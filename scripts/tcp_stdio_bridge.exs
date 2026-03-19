#!/usr/bin/env elixir
# TCP <-> STDIO bridge for LSP
#
# Purpose: let stdio-only clients talk to a TCP LSP server by proxying
# bytes between this process' STDIN/STDOUT and a TCP socket.
#
# Usage:
#   LSP_HOST=127.0.0.1 LSP_PORT=4001 scripts/tcp_stdio_bridge.exs
#   (then point your stdio client at this process)

defmodule TcpStdioBridge do
  @moduledoc false

  def main do
    host = System.get_env("LSP_HOST") || "127.0.0.1"
    port = System.get_env("LSP_PORT") |> to_int(4001)

    IO.puts(:stderr, "[bridge] Connecting to #{host}:#{port} …")

    {:ok, socket} =
      :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false, packet: :raw])

    IO.puts(:stderr, "[bridge] Connected. Proxying STDIO <-> TCP.")

    # Set stdio to binary/raw
    IO.setopts(:stdio, encoding: :latin1)

    # Forward STDIN -> TCP
    stdin_task =
      Task.async(fn ->
        forward_stdin_to_tcp(socket)
      end)

    # Forward TCP -> STDOUT
    tcp_task =
      Task.async(fn ->
        forward_tcp_to_stdout(socket)
      end)

    # Wait on either side to finish, then shut down the other
    wait_any(stdin_task, tcp_task, socket)
  end

  defp forward_stdin_to_tcp(socket) do
    # Read by lines; LSP frames are text (headers + JSON body). Partial sends are fine.
    case IO.binread(:stdio, :line) do
      data when is_binary(data) ->
        :ok = :gen_tcp.send(socket, data)
        forward_stdin_to_tcp(socket)

      :eof ->
        # Graceful shutdown of write side
        :gen_tcp.shutdown(socket, :write)
        :ok

      {:error, _} ->
        :gen_tcp.shutdown(socket, :write)
        :ok
    end
  end

  defp forward_tcp_to_stdout(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, data} ->
        :ok = IO.binwrite(:stdio, data)
        forward_tcp_to_stdout(socket)

      {:error, :closed} ->
        # Peer closed: close stdout write side (nothing to do) and exit
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp wait_any(stdin_task, tcp_task, socket) do
    receive do
      {:DOWN, _ref, :process, ^stdin_task.pid, _} ->
        :gen_tcp.close(socket)
        Task.shutdown(tcp_task, :brutal_kill)

      {:DOWN, _ref, :process, ^tcp_task.pid, _} ->
        :gen_tcp.close(socket)
        Task.shutdown(stdin_task, :brutal_kill)
    after
      10 ->
        # Convert tasks to monitored processes on first pass
        Process.monitor(stdin_task.pid)
        Process.monitor(tcp_task.pid)
        wait_any(stdin_task, tcp_task, socket)
    end
  end

  defp to_int(nil, default), do: default
  defp to_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      _ -> default
    end
  end
  defp to_int(val, _default) when is_integer(val), do: val
end

TcpStdioBridge.main()

