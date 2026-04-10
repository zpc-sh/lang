defmodule Muyata.Conduit.Relay do
  @moduledoc """
  Bidirectional byte shuttle between client and upstream.

  Two processes: one reads client → writes upstream (and taps),
  the other reads upstream → writes client (and taps).

  muyata never modifies traffic. Bytes pass through untouched.
  The Tap receives a copy of every chunk in both directions.
  """

  require Logger

  @doc "Start relaying between client and upstream sockets."
  def start(client_socket, upstream_socket) do
    parent = self()

    # Client → Upstream
    c2u = spawn_link(fn -> relay_loop(client_socket, upstream_socket, :client, parent) end)

    # Upstream → Client
    u2c = spawn_link(fn -> relay_loop(upstream_socket, client_socket, :server, parent) end)

    # Wait for either direction to close
    receive do
      {:relay_done, _dir} ->
        cleanup(client_socket, upstream_socket, c2u, u2c)
    end
  end

  defp relay_loop(from_socket, to_socket, direction, parent) do
    case :gen_tcp.recv(from_socket, 0, 30_000) do
      {:ok, data} ->
        # Forward untouched
        :gen_tcp.send(to_socket, data)
        # Tap for observation (async, never blocks the relay)
        Muyata.Observer.Tap.observe(direction, data)
        relay_loop(from_socket, to_socket, direction, parent)

      {:error, :timeout} ->
        relay_loop(from_socket, to_socket, direction, parent)

      {:error, _reason} ->
        send(parent, {:relay_done, direction})
    end
  end

  defp cleanup(client_socket, upstream_socket, c2u, u2c) do
    Process.exit(c2u, :shutdown)
    Process.exit(u2c, :shutdown)
    :gen_tcp.close(client_socket)
    :gen_tcp.close(upstream_socket)
  rescue
    _ -> :ok
  end
end
