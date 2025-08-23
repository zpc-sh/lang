defmodule LangWeb.LspChannel do
  use Phoenix.Channel
  require Logger

  alias Lang.RPC.{Router, JsonLD, Errors}

  def join("lsp:" <> _session_id, _payload, socket) do
    {:ok, socket}
  end

  def handle_in("json", %{"jsonrpc" => "2.0", "id" => id, "method" => method} = req, socket) do
    params = Map.get(req, "params", %{})
    ctx = Map.get(socket.assigns, :rpc_ctx, %{}) |> Map.put(:channel_pid, self())
    api_key_id = ctx[:api_key_id] || "anon"

    with :ok <- Lang.Security.RedisLimiter.allow?(to_string(api_key_id), method) do
      case Router.dispatch(ctx, method, params) do
        {:ok, result} ->
          reply = JsonLD.wrap(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
          {:reply, {:ok, reply}, socket}

        {:error, code, message, data} ->
          reply = JsonLD.wrap(Errors.error(id, code, message, data))
          {:reply, {:ok, reply}, socket}

        {:error, :invalid_request} ->
          reply = JsonLD.wrap(Errors.error(id, -32600, "Invalid Request", nil))
          {:reply, {:ok, reply}, socket}
      end
    else
      {:error, :rate_limited} ->
        reply = JsonLD.wrap(Errors.error(id, -32001, "Rate limit exceeded", %{method: method}))
        {:reply, {:ok, reply}, socket}
    end
  end

  def handle_in("json", _payload, socket) do
    {:reply, {:ok, JsonLD.wrap(Errors.error(nil, -32600, "Invalid Request", nil))}, socket}
  end

  # Example stream notifications pushed from async tasks
  def handle_info({:rpc_stream, request_id, {:chunk, data}}, socket) do
    Phoenix.Channel.push(socket, "stream.chunk", %{
      request_id: request_id,
      data: data,
      is_last: false
    })
    {:noreply, socket}
  end

  def handle_info({:rpc_stream_completed, request_id}, socket) do
    Phoenix.Channel.push(socket, "stream.completed", %{
      request_id: request_id,
      is_last: true
    })
    {:noreply, socket}
  end
end
