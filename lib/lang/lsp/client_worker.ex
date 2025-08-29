defmodule Lang.LSP.ClientWorker do
  @moduledoc """
  Single persistent JSON-RPC TCP client to the LSP server.

  Maintains one TCP connection and serves synchronous requests sequentially.
  Intended to be started in a small pool for concurrency.
  """

  use GenServer
  require Logger

  @default_host ~c"127.0.0.1"
  @default_port 4001
  @default_timeout 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @doc false
  def call(pid, method, params \\ %{}, opts \\ []) do
    GenServer.call(
      pid,
      {:call, method, params, opts},
      Keyword.get(opts, :timeout, @default_timeout) + 1_000
    )
  end

  @impl true
  def init(opts) do
    state = %{
      host: Keyword.get(opts, :host, @default_host),
      port: Keyword.get(opts, :port, @default_port),
      root_path: Keyword.get(opts, :root_path, System.cwd!()),
      socket: nil,
      next_id: 1,
      initialized?: false,
      client_id: "worker_#{System.unique_integer([:positive])}_#{:os.getpid()}",
      recv_task: nil,
      inflight: %{},
      max_inflight: Keyword.get(opts, :max_inflight, get_in(Application.get_env(:lang, :lsp_client) || %{}, [:max_inflight]) || 32)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:call, method, params, opts}, _from, state) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Backpressure: refuse when inflight exceeds max
    if map_size(state.inflight) >= state.max_inflight do
      {:reply, {:error, :backpressure}, state}
    else
      case ensure_connected(state, timeout) do
      {:ok, socket, state} ->
        {id, state} = next_id(state)
        start_mono = System.monotonic_time(:millisecond)
        :telemetry.execute([:lang, :lsp, :client, :request, :start], %{}, %{id: id, method: method})

        # register inflight and timeout
        tref = Process.send_after(self(), {:inflight_timeout, id}, timeout + 1000)
        state = put_inflight(state, id, {_from, tref, method, start_mono})

        case send_jsonrpc(socket, id, method, params) do
          :ok -> {:noreply, state}
          {:error, reason} ->
            cancel_inflight(id, state)
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:metrics, _from, state) do
    {:reply, %{inflight: map_size(state.inflight), initialized: state.initialized?, max_inflight: state.max_inflight}, state}
  end

  @impl true
  def terminate(_reason, state) do
    close_socket(state.socket)
    :ok
  end

  # Internal helpers
  defp ensure_connected(%{socket: socket, initialized?: true, recv_task: recv} = state, _timeout)
       when is_port(socket) and is_pid(recv), do: {:ok, socket, state}

  defp ensure_connected(state, timeout) do
    case :gen_tcp.connect(state.host, state.port, [:binary, packet: :raw, active: false, nodelay: true], timeout) do
      {:ok, socket} ->
        case initialize_lsp(socket, state.client_id, state.root_path, timeout) do
          {:ok, _} ->
            :ok = send_initialized_notification(socket)
            {:ok, task} = Task.start_link(fn -> recv_loop(self(), socket) end)
            {:ok, socket, %{state | socket: socket, initialized?: true, recv_task: task}}

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp next_id(state) do
    id = state.next_id
    new_state = %{state | next_id: id + 1}
    {id, new_state}
  end

  defp close_socket(nil), do: :ok

  defp close_socket(socket) do
    try do
      :gen_tcp.close(socket)
    rescue
      _ -> :ok
    end
  end

  defp send_jsonrpc(socket, id, method, params) do
    payload = %{"jsonrpc" => "2.0", "id" => id, "method" => method}
    payload = if params in [nil, %{}], do: payload, else: Map.put(payload, "params", params)

    with {:ok, json_io} <- Jason.encode_to_iodata(payload) do
      len = :erlang.iolist_size(json_io)
      header_io = ["Content-Length: ", Integer.to_string(len), "\r\n\r\n"]
      :gen_tcp.send(socket, [header_io, json_io])
    end
  end

  # Receive loop: continuously reads frames and sends them to GenServer
  defp recv_loop(owner, socket) do
    case recv_until_header(socket, "", :infinity) do
      {:ok, content_length, rest} ->
        case recv_body(socket, content_length, rest, :infinity) do
          {:ok, %{"id" => id} = full} ->
            send(owner, {:lsp_response, id, full})
            recv_loop(owner, socket)
          {:ok, %{"method" => _m} = _notification} ->
            # ignore notifications
            recv_loop(owner, socket)
          {:ok, other} ->
            send(owner, {:lsp_response, nil, other})
            recv_loop(owner, socket)
          {:error, reason} ->
            send(owner, {:lsp_recv_error, reason})
        end
      {:error, reason} ->
        send(owner, {:lsp_recv_error, reason})
    end
  end

  defp recv_until_header(socket, acc, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        buf = acc <> data
        case :binary.match(buf, "\r\n\r\n") do
          {hdr_end, 4} ->
            headers = :binary.part(buf, 0, hdr_end)
            rest = :binary.part(buf, hdr_end + 4, byte_size(buf) - (hdr_end + 4))
            case parse_content_length(headers) do
              {:ok, len} -> {:ok, len, rest}
              {:error, _} -> recv_until_header(socket, buf, timeout)
            end
          :nomatch -> recv_until_header(socket, buf, timeout)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_content_length(headers) when is_binary(headers) do
    case :binary.match(headers, "Content-Length: ") do
      {pos, _len} ->
        start = pos + byte_size("Content-Length: ")
        suffix = :binary.part(headers, start, byte_size(headers) - start)
        case :binary.match(suffix, "\r\n") do
          {eol, _} ->
            len_bin = :binary.part(suffix, 0, eol)
            case Integer.parse(len_bin) do
              {int, _} -> {:ok, int}
              :error -> {:error, :invalid_length}
            end
          :nomatch -> {:error, :no_eol}
        end
      :nomatch -> {:error, :no_content_length}
    end
  end

  defp recv_body(_socket, 0, rest, _timeout), do: decode_json_full(rest)

  defp recv_body(socket, len, rest, timeout) do
    have = byte_size(rest)

    cond do
      have == len ->
        decode_json_full(rest)

      have > len ->
        decode_json_full(binary_part(rest, 0, len))

      true ->
        remaining = len - have

        case :gen_tcp.recv(socket, remaining, timeout) do
          {:ok, data} -> decode_json_full(rest <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp decode_json_full(binary) do
    case Jason.decode(binary) do
      {:ok, %{"error" => err} = full} -> {:ok, full}
      {:ok, %{"result" => _res} = full} -> {:ok, full}
      {:ok, other} -> {:ok, other}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  # -- inflight helpers --
  defp put_inflight(%{inflight: inflight} = state, id, from_tref_method) do
    %{state | inflight: Map.put(inflight, id, from_tref_method)}
  end

  defp pop_inflight(%{inflight: inflight} = state, id) do
    {val, rest} = Map.pop(inflight, id)
    {val, %{state | inflight: rest}}
  end

  defp cancel_inflight(id, %{inflight: inflight}) do
    case inflight[id] do
      {from, tref, _method} ->
        Process.cancel_timer(tref)
        GenServer.reply(from, {:error, :send_failed})
      _ -> :ok
    end
  end

  @impl true
  def handle_info({:lsp_response, id, %{"result" => res}}, state) when is_integer(id) do
    {{from, tref, method, start_mono}, state} = pop_inflight(state, id)
    tref && Process.cancel_timer(tref)
    duration_ms = System.monotonic_time(:millisecond) - start_mono
    :telemetry.execute([:lang, :lsp, :client, :request, :stop], %{duration_ms: duration_ms}, %{id: id, method: method})
    GenServer.reply(from, {:ok, res})
    {:noreply, state}
  end

  @impl true
  def handle_info({:lsp_response, id, %{"error" => err}}, state) when is_integer(id) do
    {{from, tref, method, start_mono}, state} = pop_inflight(state, id)
    tref && Process.cancel_timer(tref)
    duration_ms = System.monotonic_time(:millisecond) - start_mono
    :telemetry.execute([:lang, :lsp, :client, :request, :stop], %{duration_ms: duration_ms}, %{id: id, method: method})
    GenServer.reply(from, {:error, err})
    {:noreply, state}
  end

  @impl true
  def handle_info({:inflight_timeout, id}, state) do
    case pop_inflight(state, id) do
      {{from, _tref, method, start_mono}, state} ->
        duration_ms = System.monotonic_time(:millisecond) - start_mono
        :telemetry.execute([:lang, :lsp, :client, :request, :stop], %{duration_ms: duration_ms}, %{id: id, method: method, timeout: true})
        GenServer.reply(from, {:error, :timeout})
        {:noreply, state}
      {nil, state} -> {:noreply, state}
    end
  end

  @impl true
  def handle_info({:lsp_recv_error, reason}, state) do
    # Fail all inflight callers
    Enum.each(state.inflight, fn {id, {from, tref, method, start_mono}} ->
      tref && Process.cancel_timer(tref)
      duration_ms = System.monotonic_time(:millisecond) - start_mono
      :telemetry.execute([:lang, :lsp, :client, :request, :stop], %{duration_ms: duration_ms}, %{id: id, method: method, recv_error: reason})
      GenServer.reply(from, {:error, reason})
    end)
    {:noreply, %{state | socket: nil, initialized?: false, recv_task: nil, inflight: %{}}}
  end

  # --- LSP initialize helpers ---
  defp initialize_lsp(socket, client_id, root_path, timeout) do
    id = System.unique_integer([:positive])

    init_params = %{
      "processId" => :os.getpid(),
      "clientInfo" => %{"name" => "Lang LSP ClientWorker", "version" => "1.0.0"},
      "rootPath" => root_path,
      "rootUri" => "file://#{root_path}",
      "capabilities" => %{
        "workspace" => %{"workspaceFolders" => true, "didChangeConfiguration" => %{"dynamicRegistration" => true}},
        "textDocument" => %{
          "completion" => %{"dynamicRegistration" => true, "completionItem" => %{"snippetSupport" => true}},
          "hover" => %{"dynamicRegistration" => true},
          "definition" => %{"dynamicRegistration" => true},
          "references" => %{"dynamicRegistration" => true}
        }
      }
    }

    with :ok <- send_jsonrpc(socket, id, "initialize", init_params),
         {:ok, content_length, rest} <- recv_until_header(socket, "", timeout),
         {:ok, _full} <- recv_body(socket, content_length, rest, timeout) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_initialized_notification(socket) do
    notification = %{"jsonrpc" => "2.0", "method" => "initialized", "params" => %{}}
    with {:ok, json_io} <- Jason.encode_to_iodata(notification) do
      len = :erlang.iolist_size(json_io)
      header_io = ["Content-Length: ", Integer.to_string(len), "\r\n\r\n"]
      :gen_tcp.send(socket, [header_io, json_io])
    end
  end
end
