defmodule Lang.Think.ExplainIntent do
  @moduledoc """
  LSP handler for `lang.think.explain_intent`.

  Behavior:
  - Validates billing (via organization in ctx) and required params
  - Two modes:
    - realtime/provider: routes directly to Providers for synchronous response
    - async/enqueued: enqueues `Lang.Think.Request` via Ash/Oban and returns request_id
  - Optional MCP streaming bridge: when `stream_via: "mcp"` is present with
    `mcp_connection_id` and `session_id`, creates a stream via `Lang.MCP.StreamBridge`
    and streams chunks of the explanation.

  Tracks events via `Lang.Events.track_event/1`.
  """

  @behaviour Lang.LSP.Handler
  @lsp_method "lang.think.explain_intent"

  require Logger

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    with :ok <- validate_billing(ctx),
         :ok <- validate_required(params) do
      do_handle(params, ctx)
    else
      {:error, code, msg} -> {:error, code, msg}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_handle(params, ctx) do
    mode = Map.get(params, "mode")
    provider = Map.get(params, "provider")
    user = Map.get(ctx, :user)
    org = Map.get(ctx, :organization)

    # Optional MCP streaming branch
    stream_via = Map.get(params, "stream_via")
    if stream_via in ["mcp", :mcp] do
      handle_with_mcp_stream(params, ctx)
    else
      cond do
        mode in ["realtime", "sync", true] or provider in ["xai", "openai", "anthropic"] ->
          route_to_provider(params)

        true ->
          enqueue_request(params, ctx)
      end
      |> tap(fn result ->
        _ = Lang.Events.track_event(%{
          event_type: "think_explain_intent",
          user_id: user && user.id,
          organization_id: org && org.id,
          metadata: %{
            mode: mode || "async",
            provider: provider,
            client_id: params["client_id"]
          }
        })
      end)
    end
  end

  defp handle_with_mcp_stream(params, ctx) do
    user_id = get_in(ctx, [:user, :id]) || Map.get(ctx, :user_id)
    org_id = get_in(ctx, [:organization, :id]) || Map.get(ctx, :organization_id)
    conn_id = Map.get(params, "mcp_connection_id") || Map.get(params, "connection_id")
    session_id = Map.get(params, "session_id")
    client_id = Map.get(params, "client_id")

    with true <- is_binary(conn_id) and conn_id != "",
         true <- is_binary(session_id) and session_id != "",
         {:ok, stream_id} <- Lang.MCP.StreamBridge.create_stream(conn_id, to_string(user_id), to_string(session_id), %{client_id: client_id}) do
      # Spawn a bounded async task that computes the explanation and emits chunks
      Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
        case route_to_provider(params) do
          {:ok, %{"summary" => summary} = result} ->
            trait_aggregate = emit_stream_chunks(session_id, stream_id, summary)
            complete_stream(session_id, stream_id, result, trait_aggregate)

          {:ok, other} ->
            # Fallback: stringify result
            text = inspect(other)
            trait_aggregate = emit_stream_chunks(session_id, stream_id, text)
            complete_stream(session_id, stream_id, other, trait_aggregate)

          {:error, reason} ->
            Phoenix.PubSub.broadcast(Lang.PubSub, "mcp_stream:session:#{session_id}", {:mcp_stream_error, stream_id, inspect(reason)})
        end
      end)

      {:ok, %{stream_id: stream_id, status: "streaming"}}
    else
      false -> {:error, -32602, "Missing required parameters: mcp_connection_id, session_id"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp emit_stream_chunks(session_id, stream_id, text) when is_binary(text) do
    chunk_bytes = 1024
    total_bytes = byte_size(text)
    chunks = chunk_binary(text, chunk_bytes)
    total_chunks = length(chunks)

    chunks
    |> Enum.with_index(1)
    |> Enum.reduce(%{previous_chunk: nil, chunk_count: 0, coherence_total: 0.0, entropy_total: 0.0}, fn {chunk, idx}, acc ->
      trait_update = incremental_trait_update(acc.previous_chunk, chunk)
      next_acc = %{
        previous_chunk: chunk,
        chunk_count: acc.chunk_count + 1,
        coherence_total: acc.coherence_total + trait_update.coherence,
        entropy_total: acc.entropy_total + trait_update.entropy
      }

      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "mcp_stream:session:#{session_id}",
        {:mcp_stream_chunk, stream_id,
         %{
           index: idx,
           total_bytes: total_bytes,
           total_chunks: total_chunks,
           chunk: chunk,
           trait_update: trait_update,
           audit_summary: chunk_audit_summary(idx, total_chunks, trait_update)
         }}
      )

      next_acc
    end)
    |> Map.drop([:previous_chunk])
    |> finalize_trait_aggregate(text)
  end

  defp complete_stream(session_id, stream_id, final_payload, trait_aggregate) do
    payload =
      case final_payload do
        map when is_map(map) ->
          map
          |> Map.put("trait_aggregate", trait_aggregate)
          |> Map.put("audit_summary", turn_audit_summary(trait_aggregate))

        other ->
          %{
            "result" => other,
            "trait_aggregate" => trait_aggregate,
            "audit_summary" => turn_audit_summary(trait_aggregate)
          }
      end

    Phoenix.PubSub.broadcast(Lang.PubSub, "mcp_stream:session:#{session_id}", {:mcp_stream_complete, stream_id, payload})
  end

  defp chunk_binary(<<>> = _bin, _size), do: []
    defp chunk_binary(bin, size) when is_binary(bin) and is_integer(size) and size > 0 do
    do_chunk(bin, size, []) |> Enum.reverse()
  end

  defp do_chunk(<<>>, _size, acc), do: acc
  defp do_chunk(bin, size, acc) do
    case bin do
      <<chunk::binary-size(size), rest::binary>> -> do_chunk(rest, size, [chunk | acc])
      _ -> [bin | acc]
    end
  end

  defp incremental_trait_update(previous_chunk, chunk) do
    %{coherence: coherence(previous_chunk, chunk), entropy: entropy(chunk)}
  end

  defp coherence(nil, _chunk), do: 1.0
  defp coherence(previous_chunk, chunk) do
    prev_tokens = token_set(previous_chunk)
    current_tokens = token_set(chunk)
    union_size = MapSet.union(prev_tokens, current_tokens) |> MapSet.size()

    if union_size == 0 do
      1.0
    else
      (MapSet.intersection(prev_tokens, current_tokens) |> MapSet.size()) / union_size
    end
  end

  defp token_set(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^[:alnum:]_]+/u, trim: true)
    |> MapSet.new()
  end

  defp entropy(text) when is_binary(text) do
    text
    |> String.to_charlist()
    |> Enum.frequencies()
    |> Enum.reduce(0.0, fn {_char, count}, acc ->
      probability = count / max(1, String.length(text))
      acc - probability * :math.log2(probability)
    end)
  end

  defp finalize_trait_aggregate(acc, full_text) do
    count = max(1, acc.chunk_count)

    %{
      chunk_count: acc.chunk_count,
      avg_coherence: acc.coherence_total / count,
      avg_entropy: acc.entropy_total / count,
      overall_entropy: entropy(full_text)
    }
  end

  defp chunk_audit_summary(idx, total_chunks, trait_update) do
    "chunk=#{idx}/#{total_chunks} coherence=#{fmt(trait_update.coherence)} entropy=#{fmt(trait_update.entropy)}"
  end

  defp turn_audit_summary(aggregate) do
    "turn_final chunks=#{aggregate.chunk_count} avg_coherence=#{fmt(aggregate.avg_coherence)} avg_entropy=#{fmt(aggregate.avg_entropy)} overall_entropy=#{fmt(aggregate.overall_entropy)}"
  end

  defp fmt(number) when is_number(number) do
    :erlang.float_to_binary(number * 1.0, decimals: 4)
  end

  defp enqueue_request(params, ctx) do
    content = params["content"] || params["code"] || ""
    language = params["language"] || params["lang"] || ""

    attrs = %{
      kind: :explain_intent,
      input: %{content: content, language: language, client_id: params["client_id"]},
      user_id: get_in(ctx, [:user, :id]) || Map.get(ctx, :user_id),
      project_id: Map.get(params, "project_id"),
      run_id: Map.get(params, "run_id")
    }

    case Lang.Think.Request.create_enqueued(attrs) do
      {:ok, req} -> {:ok, %{request_id: req.id, status: "queued"}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp route_to_provider(params) do
    opts =
      case params["provider"] do
        "xai" -> [provider: :xai]
        "openai" -> [provider: :openai]
        "anthropic" -> [provider: :anthropic]
        _ -> []
      end

    case Lang.Providers.Router.route_request(@lsp_method, params, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:provider_error, reason}}
      other -> {:error, {:invalid_provider_response, other}}
    end
  end

  defp validate_required(params) do
    with :ok <- require_key(params, "client_id"),
         :ok <- require_any(params, ["content", "code"]) do
      :ok
    end
  end

  defp require_key(params, key) do
    case params[key] do
      s when is_binary(s) and byte_size(s) > 0 -> :ok
      _ -> {:error, -32602, "Missing required parameter: #{key}"}
    end
  end

  defp require_any(params, keys) do
    if Enum.any?(keys, fn k -> is_binary(params[k]) and byte_size(params[k]) > 0 end) do
      :ok
    else
      {:error, -32602, "Missing one of required parameters: #{Enum.join(keys, ", ")}"}
    end
  end

  defp validate_billing(ctx) do
    org_id = get_in(ctx, [:organization, :id]) || Map.get(ctx, :organization_id)
    case org_id do
      nil -> :ok
      id ->
        case Lang.Billing.can_make_request?(id) do
          {:ok, :allowed} -> :ok
          {:error, :limit_exceeded} -> {:error, -32001, "Billing limit exceeded"}
          {:error, reason} -> {:error, {:billing_error, reason}}
          other -> {:error, {:billing_unknown, other}}
        end
    end
  end
end
