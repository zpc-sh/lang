defmodule Lang.Proxy.WSUpstream do
  @moduledoc """
  WebSocket upstream proxy using Mint and mint_web_socket.

  Bridges between the SessionWebSocket process (`ws` pid) and an upstream
  WebSocket URL. Forwards upstream frames as stdout to the `ws` process and
  sends stdin frames from `ws` to the upstream.
  """

  use GenServer
  require Logger

  alias Mint.HTTP
  alias Mint.WebSocket, as: MWS

  @type state :: %{
          ws: pid(),
          url: String.t(),
          conn: HTTP.t() | nil,
          ref: reference() | nil,
          socket: term() | nil,
          websocket: MWS.t() | nil,
          scheme: :http | :https,
          host: String.t(),
          port: pos_integer(),
          path: String.t()
        }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    ws = Keyword.fetch!(opts, :ws)
    url = Keyword.fetch!(opts, :url)

    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = u when scheme in ["ws", "wss"] and is_binary(host) ->
        path = (u.path || "/") <> if u.query, do: "?" <> u.query, else: ""
        scheme_atom = if scheme == "wss", do: :https, else: :http
        port = u.port || (scheme_atom == :https && 443 || 80)

        state = %{
          ws: ws,
          url: url,
          conn: nil,
          ref: nil,
          socket: nil,
          websocket: nil,
          scheme: scheme_atom,
          host: host,
          port: port,
          path: path
        }

        {:ok, state, {:continue, :connect}}

      _ ->
        send(ws, {:proxy_stdout, "[ws] invalid url: #{inspect(url)}\r\n"})
        {:stop, :invalid_url}
    end
  end

  @impl true
  def handle_continue(:connect, %{scheme: scheme, host: host, port: port, path: path} = state) do
    headers = [{"sec-websocket-protocol", "mdld"}]
    transport_opts = [alpn_advertised_protocols: ["h2", "http/1.1"]]
    with {:ok, conn} <- HTTP.connect(scheme, host, port, transport_opts: transport_opts),
         {:ok, conn, ref} <- MWS.upgrade(conn, path, headers) do
      {:noreply, %{state | conn: conn, ref: ref}}
    else
      {:error, reason} ->
        send(state.ws, {:proxy_stdout, "[ws] connect error: #{inspect(reason)}\r\n"})
        {:stop, reason, state}
      other ->
        send(state.ws, {:proxy_stdout, "[ws] unexpected connect error: #{inspect(other)}\r\n"})
        {:stop, :connect_failed, state}
    end
  end

  @impl true
  def handle_info(message, %{conn: conn} = state) do
    case HTTP.stream(conn, message) do
      {:ok, conn, responses} ->
        handle_responses(responses, %{state | conn: conn})

      {:error, conn, reason, _responses} ->
        send(state.ws, {:proxy_stdout, "[ws] stream error: #{inspect(reason)}\r\n"})
        send(state.ws, {:proxy_exit, :error})
        {:stop, reason, %{state | conn: conn}}

      :unknown ->
        {:noreply, state}
    end
  end

  defp handle_responses(responses, state) do
    Enum.reduce(responses, {:noreply, state}, fn resp, {_, st} ->
      do_handle_response(resp, st)
    end)
  end

  defp do_handle_response({:status, ref, 101}, %{ref: ref} = state), do: {:noreply, state}
  defp do_handle_response({:headers, ref, headers}, %{ref: ref, conn: conn} = state) do
    case MWS.new(conn, ref, headers) do
      {:ok, conn, websocket} ->
        send(state.ws, {:proxy_stdout, "[ws] connected to #{state.url}\r\n"})
        {:noreply, %{state | conn: conn, websocket: websocket}}
      {:error, reason} ->
        send(state.ws, {:proxy_stdout, "[ws] upgrade failed: #{inspect(reason)}\r\n"})
        send(state.ws, {:proxy_exit, :upgrade_failed})
        {:stop, reason, state}
    end
  end

  defp do_handle_response({:data, ref, data}, %{ref: ref, websocket: ws, conn: conn} = state) when not is_nil(ws) do
    case MWS.decode(ws, data) do
      {:ok, frames, ws2} ->
        Enum.each(frames, fn
          {:text, text} -> send(state.ws, {:proxy_stdout, text})
          {:ping, data} -> send_upstream({:pong, data}, %{state | websocket: ws2})
          {:close, _code, _reason} -> send(state.ws, {:proxy_exit, 0})
          _ -> :ok
        end)
        {:noreply, %{state | websocket: ws2, conn: conn}}
      {:error, reason} ->
        send(state.ws, {:proxy_stdout, "[ws] decode error: #{inspect(reason)}\r\n"})
        {:stop, reason, state}
    end
  end

  defp do_handle_response(_other, state), do: {:noreply, state}

  @impl true
  def handle_cast({:stdin, data}, state) when is_binary(data) do
    {:noreply, send_upstream({:text, data}, state)}
  end

  def handle_cast(_other, state), do: {:noreply, state}

  defp send_upstream(_frame, %{websocket: nil} = state), do: state

  defp send_upstream(frame, %{websocket: ws, conn: conn, ref: ref} = state) do
    case MWS.encode(ws, frame) do
      {:ok, iodata, ws2} ->
        case HTTP.stream_request_body(conn, ref, iodata) do
          {:ok, conn} -> %{state | conn: conn, websocket: ws2}
          {:error, conn, reason} ->
            send(state.ws, {:proxy_stdout, "[ws] send error: #{inspect(reason)}\r\n"})
            %{state | conn: conn, websocket: ws2}
        end

      {:error, reason} ->
        send(state.ws, {:proxy_stdout, "[ws] encode error: #{inspect(reason)}\r\n"})
        state
    end
  end
end

