defmodule Lang.Proxy.Unix do
  @moduledoc """
  Simple Unix domain socket proxy for WebSocket sessions.

  Connects to a server-local Unix socket and proxies bytes.
  """

  use GenServer

  @type state :: %{
          ws: pid(),
          path: String.t(),
          sock: port() | nil
        }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def init(opts) do
    ws = Keyword.fetch!(opts, :ws)
    path = Keyword.fetch!(opts, :path)
    state = %{ws: ws, path: path, sock: nil}
    send(self(), :connect)
    {:ok, state}
  end

  def handle_info(:connect, %{path: path} = state) do
    case :gen_tcp.connect({:local, String.to_charlist(path)}, 0, [:binary, {:active, true}], 3_000) do
      {:ok, sock} ->
        send(state.ws, {:proxy_stdout, "[unix] connected to #{path}\r\n"})
        {:noreply, %{state | sock: sock}}

      {:error, reason} ->
        send(state.ws, {:proxy_stdout, "[unix] connect error: #{inspect(reason)}\r\n"})
        {:stop, reason, state}
    end
  end

  def handle_info({:tcp, sock, data}, %{ws: ws, sock: sock} = state) do
    send(ws, {:proxy_stdout, data})
    {:noreply, state}
  end

  def handle_info({:tcp_closed, sock}, %{ws: ws, sock: sock} = state) do
    send(ws, {:proxy_exit, 0})
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def handle_cast({:stdin, data}, %{sock: sock} = state) when is_binary(data) and not is_nil(sock) do
    :gen_tcp.send(sock, data)
    {:noreply, state}
  end

  def handle_cast(_other, state), do: {:noreply, state}

  def terminate(_reason, %{sock: sock}) when not is_nil(sock) do
    try do
      :gen_tcp.close(sock)
    catch
      _, _ -> :ok
    end
    :ok
  end

  def terminate(_reason, _state), do: :ok
end

