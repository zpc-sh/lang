defmodule Muyata.Conduit.Listener do
  @moduledoc """
  TCP listener on the target port. The front door.

  Accepts client connections and for each one, opens a connection to
  the real upstream service, then spawns a Relay to shuttle bytes
  bidirectionally. The Tap gets a copy of every byte in both directions.

  muyata never modifies traffic — the conduit is transparent.
  """
  use GenServer

  require Logger

  def start_link(opts) do
    listen_port = Keyword.get(opts, :listen_port, 5432)
    upstream_host = Keyword.get(opts, :upstream_host, "127.0.0.1")
    upstream_port = Keyword.get(opts, :upstream_port, 5433)

    GenServer.start_link(
      __MODULE__,
      %{listen_port: listen_port, upstream_host: upstream_host, upstream_port: upstream_port},
      name: __MODULE__
    )
  end

  @impl true
  def init(config) do
    case :gen_tcp.listen(config.listen_port, [
           :binary,
           {:active, false},
           {:reuseaddr, true},
           {:packet, :raw}
         ]) do
      {:ok, listen_socket} ->
        spawn_link(fn -> accept_loop(listen_socket, config) end)
        Logger.info("[muyata:conduit] listening on port #{config.listen_port}")
        Logger.info("[muyata:conduit] upstream #{config.upstream_host}:#{config.upstream_port}")
        {:ok, Map.put(config, :listen_socket, listen_socket)}

      {:error, reason} ->
        Logger.warning("[muyata:conduit] failed to bind port #{config.listen_port}: #{inspect(reason)}")
        {:ok, config}
    end
  end

  @impl true
  def terminate(_reason, %{listen_socket: socket}) when not is_nil(socket) do
    :gen_tcp.close(socket)
  end

  def terminate(_reason, _state), do: :ok

  defp accept_loop(listen_socket, config) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        Muyata.Void.new_connection()
        spawn(fn -> establish_relay(client_socket, config) end)
        accept_loop(listen_socket, config)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.warning("[muyata:conduit] accept error: #{inspect(reason)}")
        accept_loop(listen_socket, config)
    end
  end

  defp establish_relay(client_socket, config) do
    host = to_charlist(config.upstream_host)

    case :gen_tcp.connect(host, config.upstream_port, [:binary, {:active, false}, {:packet, :raw}], 5_000) do
      {:ok, upstream_socket} ->
        Muyata.Conduit.Relay.start(client_socket, upstream_socket)

      {:error, reason} ->
        Logger.warning("[muyata:conduit] upstream connect failed: #{inspect(reason)}")
        :gen_tcp.close(client_socket)
    end
  end
end
