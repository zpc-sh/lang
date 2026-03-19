defmodule Lang.Workers.AgentSwarmWorker do
  @moduledoc """
  Background worker to provision or coordinate an agent swarm.

  Keep it lightweight; escalate long operations to downstream jobs.
  """

  use Oban.Worker, queue: :orchestration, max_attempts: 5
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    swarm_id = Map.get(args, "swarm_id")
    agent_ids = Map.get(args, "agent_ids", [])
    goals = Map.get(args, "goals", [])
    coordinator_id = Map.get(args, "coordinator_id")
    session_id = Map.get(args, "session_id") || "swarm:" <> (swarm_id || "unknown")

    Logger.metadata(swarm_id: swarm_id)
    Logger.info("Provisioning agent swarm", agent_count: length(agent_ids))

    Lang.Events.track_event(%{
      event_type: "agent_swarm_provision",
      metadata: %{
        swarm_id: swarm_id,
        agent_ids: agent_ids,
        goals: goals,
        coordinator_id: coordinator_id
      }
    })

    # Ensure we have a Swarm record and get its DB id
    {swarm_db_id, swarm_record} =
      case ensure_swarm_record(swarm_id, goals, agent_ids, coordinator_id) do
        {:ok, swarm} -> {swarm.id, swarm}
        _ -> {nil, nil}
      end

    # Create agents best-effort and link to swarm
    created_agents =
      Enum.reduce(agent_ids, [], fn external_id, acc ->
        meta = %{"swarm_id" => swarm_id, "external_id" => external_id, "coordinator_id" => coordinator_id}
        args = %{
          capabilities: derive_capabilities(goals),
          constraints: %{},
          session_id: session_id,
          spawned_by: "swarm_worker",
          sandbox_config: %{},
          metadata: meta,
          swarm_id: swarm_db_id
        }

        case safe_spawn_agent(args) do
          {:ok, agent} -> [agent | acc]
          _ -> acc
        end
      end)

    # Best-effort: update swarm status via Ash and store created agent ids mapping
    _ =
      try do
        case swarm_record do
          %Lang.Agent.Swarm{} = swarm ->
            mapping = Enum.map(created_agents, fn a -> %{"external_id" => a.metadata["external_id"], "id" => a.id} end)
            _ = Ash.update(swarm, %{metadata: Map.put(swarm.metadata || %{}, "agent_map", mapping)}, action: :update)
            {:ok, swarm} = Ash.update(swarm, %{}, action: :mark_provisioning)
            {:ok, swarm} = Ash.update(swarm, %{}, action: :mark_active)
            {:ok, _} = Ash.update(swarm, %{}, action: :mark_completed)
            :ok
          _ -> :ok
        end
      rescue
        _ -> :ok
      end

    :ok
  end

  defp safe_spawn_agent(args) do
    try do
      Ash.create(Lang.Agent.Agent, args, action: :spawn)
    rescue
      _ -> {:error, :spawn_failed}
    end
  end

  defp derive_capabilities(goals) when is_list(goals) do
    base = [:analysis]

    addl =
      goals
      |> Enum.map(&String.downcase/1)
      |> Enum.reduce([], fn g, acc ->
        acc ++
          (cond do
             String.contains?(g, "security") -> [:security]
             String.contains?(g, "search") or String.contains?(g, "index") -> [:search]
             String.contains?(g, "parse") or String.contains?(g, "analy") -> [:nlp]
             true -> []
           end)
      end)

    (base ++ addl)
    |> Enum.uniq()
  end
  defp derive_capabilities(_), do: [:analysis]

  defp ensure_swarm_record(swarm_id, goals, agent_ids, coordinator_id) do
    try do
      query = Lang.Agent.Swarm |> Ash.Query.for_read(:by_swarm_id, %{swarm_id: swarm_id})
      case Ash.read(query) do
        {:ok, [swarm]} -> {:ok, swarm}
        {:ok, []} -> Ash.create(Lang.Agent.Swarm, %{swarm_id: swarm_id, goals: goals, agent_ids: agent_ids, coordinator_id: coordinator_id, status: :created})
        other -> other
      end
    rescue
      _ -> {:error, :unavailable}
    end
  end
end
