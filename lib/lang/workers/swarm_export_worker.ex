defmodule Lang.Workers.SwarmExportWorker do
  @moduledoc """
  Background export worker for swarms and agents.

  Stores exported content in Redis under key "export:<export_id>" with TTL,
  and broadcasts readiness over PubSub topic "exports:<export_id>".
  """

  use Oban.Worker, queue: :metrics, max_attempts: 3
  require Logger
  alias Phoenix.PubSub

  @ttl 900
  @chunk_size 1_000_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"kind" => kind, "format" => format, "export_id" => export_id} = args}) do
    case {kind, format} do
      {"swarms", "ndjson"} -> export_swarms_ndjson(args)
      {"agents", "ndjson"} -> export_agents_ndjson(args)
      other ->
        Logger.warning("Unsupported export request", request: other)
        :discard
    end

    # Notify listeners
    PubSub.broadcast(Lang.PubSub, "exports:#{export_id}", {:export_ready, export_id})
    :ok
  end

  defp export_swarms_ndjson(%{"export_id" => id, "filters" => filters}) do
    import Ash.Query

    q = Lang.Agent.Swarm
        |> maybe_filter_swarm_id(filters["swarm_id"]) 
        |> maybe_filter_coord(filters["coordinator_id"]) 
        |> maybe_filter_session(filters["session_id"]) 
        |> sort(inserted_at: :desc)

    {:ok, list} = Ash.read(q)

    content =
      list
      |> Stream.map(fn s ->
        %{
          swarm_id: s.swarm_id,
          status: s.status,
          goals: s.goals,
          agent_ids: s.agent_ids,
          coordinator_id: s.coordinator_id,
          inserted_at: s.inserted_at
        }
        |> Jason.encode!()
      end)
      |> Enum.intersperse("\n")
      |> Enum.join("")

    store_export(id, content)
  end

  defp export_agents_ndjson(%{"export_id" => id, "swarm_id" => swarm_id, "filters" => filters}) do
    import Ash.Query

    with {:ok, [swarm]} <- Lang.Agent.Swarm |> Ash.Query.for_read(:by_swarm_id, %{swarm_id: swarm_id}) |> Ash.read() do
      base = Lang.Agent.Agent |> for_read(:by_swarm, %{swarm_id: swarm.id})
      q = apply_agent_filters(base, filters)
      {:ok, list} = Ash.read(q)

      content =
        list
        |> Stream.map(fn a ->
          %{
            id: a.id,
            name: a.name,
            state: a.state,
            session_id: a.session_id,
            trust_score: a.trust_score,
            capabilities: a.capabilities
          }
          |> Jason.encode!()
        end)
        |> Enum.intersperse("\n")
        |> Enum.join("")

      store_export(id, content)
    else
      _ -> :ok
    end
  end

  defp maybe_filter_swarm_id(q, id) do
    import Ash.Query
    filter(q, swarm_id == ^id)
  end

  defp maybe_filter_coord(q, id) do
    import Ash.Query
    filter(q, coordinator_id == ^id)
  end

  defp maybe_filter_session(q, session_id) do
    import Ash.Query
    filter(q, exists(agents, session_id == ^session_id))
  end

  defp apply_agent_filters(q, %{"state" => st, "min_trust" => mt}) do
    import Ash.Query

    q =
      case String.trim(to_string(st)) do
        "" -> q
        state -> filter(q, state == ^String.to_atom(state))
      end

    case Float.parse(to_string(mt)) do
      {minf, _} when minf >= 0.0 -> filter(q, trust_score >= ^Decimal.from_float(minf))
      _ -> q
    end
  end

  defp apply_agent_filters(q, _), do: q

  defp store_export(id, content) when is_binary(content) do
    unless Code.ensure_loaded?(Redix), do: :ok

    ttl = Integer.to_string(@ttl)
    key_base = "export:" <> id

    try do
      if byte_size(content) <= @chunk_size do
        _ = Redix.command(Lang.Redis, ["SETEX", key_base, ttl, content])
      else
        parts = chunk_binary(content, @chunk_size)
        Enum.with_index(parts, 1)
        |> Enum.each(fn {chunk, idx} ->
          _ = Redix.command(Lang.Redis, ["SETEX", "#{key_base}:part:#{idx}", ttl, chunk])
        end)
        _ = Redix.command(Lang.Redis, ["SETEX", "#{key_base}:parts", ttl, Integer.to_string(length(parts))])
      end
    rescue
      _ -> :ok
    end
  end

  defp chunk_binary(bin, size) do
    total = byte_size(bin)
    if total <= size, do: [bin], else: do_chunk(bin, size, []) |> Enum.reverse()
  end

  defp do_chunk(<<>>, _size, acc), do: acc
  defp do_chunk(bin, size, acc) do
    <<chunk::binary-size(size), rest::binary>> =
      if byte_size(bin) >= size, do: bin, else: bin <> :binary.copy(<<0>>, size - byte_size(bin))

    actual = binary_part(chunk, 0, min(size, byte_size(bin)))
    do_chunk(binary_part(bin, min(size, byte_size(bin)), byte_size(bin) - min(size, byte_size(bin))), size, [actual | acc])
  end
end
