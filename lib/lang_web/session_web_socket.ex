defmodule LangWeb.SessionWebSocket do
  @behaviour WebSock
  require Logger

  @impl true
  def init(state) do
    defaults = Application.get_env(:lang, :session_proxy, [])
    idle_ms = Keyword.get(defaults, :idle_timeout_ms, 10 * 60_000)
    bw_limit = Keyword.get(defaults, :bandwidth_limit_bytes, 50 * 1024 * 1024)
    base = %{
      connected_at: System.system_time(:second),
      proxy: nil,
      idle_timeout_ms: idle_ms,
      bandwidth_limit_bytes: bw_limit,
      bytes_in: 0,
      bytes_out: 0,
      idle_ref: nil
    }
    {:ok, Map.merge(base, state)}
  end

  @impl true
  def handle_in({data, _opcode}, state) when is_binary(data) do
    case safe_decode(data) do
      {:ok, %{"type" => "hello"} = msg} ->
        cols = msg["cols"] || 80
        rows = msg["rows"] || 24
        mode = msg["mode"] || "pty"
        new_state = state |> maybe_start_proxy(cols, rows, mode) |> start_idle_timer()
        track_audit(new_state, :session_started)
        reply = %{type: "hello_ack", cols: cols, rows: rows, mode: mode, proxy: !!new_state.proxy}
        {:reply, {:text, Jason.encode!(reply)}, new_state}

      {:ok, %{"type" => "resize", "cols" => cols, "rows" => rows}} ->
        # No-op in stub; would forward to PTY in real proxy
        {:reply, {:text, Jason.encode!(%{type: "resize_ack", cols: cols, rows: rows})}, state}

      {:ok, %{"type" => "stdin", "data" => input}} when is_binary(input) ->
        case state.proxy do
          nil -> {:reply, {:text, Jason.encode!(%{type: "stdout", data: input})}, state}
          pid when is_pid(pid) ->
            GenServer.cast(pid, {:stdin, input})
            {:ok, inc_in(state, byte_size(input))}
        end

      {:ok, other} ->
        {:reply, {:text, Jason.encode!(%{type: "error", error: "unknown_message", payload: other})}, state}

      {:error, :invalid_json} ->
        {:reply, {:text, Jason.encode!(%{type: "error", error: "invalid_json"})}, state}
    end
  end

  def handle_in(_other, state), do: {:ok, state}

  @impl true
  def handle_info({:proxy_stdout, data}, state) when is_binary(data) do
    state = reset_idle(state)
    state = inc_out(state, byte_size(data))
    state = maybe_enforce_bw(state)
    {:reply, {:text, Jason.encode!(%{type: "stdout", data: data})}, state}
  end

  def handle_info({:proxy_exit, status}, state) do
    track_audit(state, :session_ended)
    {:reply, {:text, Jason.encode!(%{type: "exit", status: status})}, %{state | proxy: nil} |> cancel_idle()}
  end

  def handle_info(:idle_timeout, state) do
    track_audit(state, :session_idle_timeout)
    {:reply, {:text, Jason.encode!(%{type: "exit", status: "idle_timeout"})}, %{state | proxy: nil} |> cancel_idle()}
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, _state), do: :ok

  defp safe_decode(data) do
    try do
      {:ok, Jason.decode!(data)}
    rescue
      _ -> {:error, :invalid_json}
    end
  end

  defp start_idle_timer(%{idle_ref: nil, idle_timeout_ms: ms} = state) when is_integer(ms) and ms > 0 do
    ref = Process.send_after(self(), :idle_timeout, ms)
    %{state | idle_ref: ref}
  end
  defp start_idle_timer(state), do: state

  defp reset_idle(%{idle_ref: ref, idle_timeout_ms: ms} = state) when is_reference(ref) and is_integer(ms) and ms > 0 do
    _ = Process.cancel_timer(ref)
    %{state | idle_ref: Process.send_after(self(), :idle_timeout, ms)}
  end
  defp reset_idle(state), do: state

  defp cancel_idle(%{idle_ref: ref} = state) when is_reference(ref) do
    _ = Process.cancel_timer(ref)
    %{state | idle_ref: nil}
  end
  defp cancel_idle(state), do: state

  defp inc_in(state, n), do: %{state | bytes_in: state.bytes_in + (n || 0)}
  defp inc_out(state, n), do: %{state | bytes_out: state.bytes_out + (n || 0)}

  defp maybe_enforce_bw(%{bandwidth_limit_bytes: limit, bytes_out: out} = state) when is_integer(limit) and limit > 0 do
    if out > limit do
      track_audit(state, :bandwidth_limit_exceeded)
      _ = send(self(), {:proxy_exit, :bandwidth_limit})
    end
    state
  end
  defp maybe_enforce_bw(state), do: state

  defp track_audit(%{claims: claims} = _state, event) do
    # Best-effort audit hook
    try do
      Lang.Events.track_event(%{
        event_type: "mdld_session_" <> to_string(event),
        metadata: %{
          proto: claims["proto"],
          session_id: claims["session_id"],
          host: claims["host"] || claims["lds:host"],
          path: claims["path"] || claims["lds:path"],
          url: claims["url"] || claims["lds:url"]
        }
      })
    rescue
      _ -> :ok
    end
  end
  
  defp maybe_start_proxy(%{claims: %{"proto" => "ssh"} = claims} = state, cols, rows, _mode) do
    host = claims["host"] || claims["lds:host"]
    port = claims["port"] || claims["lds:port"] || 22
    user = claims["user"] || claims["lds:user"]
    finger = claims["fingerprint"] || claims["lds:fingerprint"]
    case host do
      nil -> state
      _ ->
        {:ok, pid} = Lang.Proxy.SSH.start_link(ws: self(), host: host, port: to_int(port, 22), user: user, fingerprint: finger, cols: to_int(cols, 80), rows: to_int(rows, 24))
        Map.put(state, :proxy, pid)
    end
  end

  defp maybe_start_proxy(state, _c, _r, _m), do: state

  defp maybe_start_proxy(%{claims: %{"proto" => "unix"} = claims} = state, _c, _r, _m) do
    path = claims["path"] || claims["lds:path"]
    case path do
      nil -> state
      _ ->
        {:ok, pid} = Lang.Proxy.Unix.start_link(ws: self(), path: path)
        Map.put(state, :proxy, pid)
    end
  end

  defp maybe_start_proxy(%{claims: %{"proto" => "ws"} = claims} = state, _c, _r, _m) do
    url = claims["url"] || claims["lds:url"]
    case url do
      nil -> state
      _ ->
        {:ok, pid} = Lang.Proxy.WSUpstream.start_link(ws: self(), url: url)
        Map.put(state, :proxy, pid)
    end
  end

  defp to_int(v, d) when is_integer(v), do: v
  defp to_int(v, d) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      _ -> d
    end
  end
  defp to_int(_, d), do: d
end
