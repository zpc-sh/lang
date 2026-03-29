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
            emit_stream_chunks(session_id, stream_id, summary)
            complete_stream(session_id, stream_id, result)

          {:ok, other} ->
            # Fallback: stringify result
            text = inspect(other)
            emit_stream_chunks(session_id, stream_id, text)
            complete_stream(session_id, stream_id, other)

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
    total = byte_size(text)

    text
    |> chunk_binary(chunk_bytes)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, idx} ->
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "mcp_stream:session:#{session_id}",
        {:mcp_stream_chunk, stream_id, %{index: idx, total_bytes: total, chunk: chunk}}
      )
    end)
  end

  defp complete_stream(session_id, stream_id, final_payload) do
    Phoenix.PubSub.broadcast(Lang.PubSub, "mcp_stream:session:#{session_id}", {:mcp_stream_complete, stream_id, final_payload})
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

