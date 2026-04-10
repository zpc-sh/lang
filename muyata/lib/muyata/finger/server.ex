defmodule Muyata.Finger.Server do
  @moduledoc """
  RFC 1288 Finger server. Responds with .plan text showing
  muyata's void status, framing confidence, pattern count.

  `finger @localhost:7179` → one-shot void status in YATA format.
  """
  use GenServer

  require Logger

  def start_link(opts) do
    port = Keyword.get(opts, :port, 7179)
    GenServer.start_link(__MODULE__, %{port: port}, name: __MODULE__)
  end

  @impl true
  def init(%{port: port}) do
    case :gen_tcp.listen(port, [
           :binary,
           {:active, false},
           {:reuseaddr, true},
           {:packet, :line}
         ]) do
      {:ok, listen_socket} ->
        spawn_link(fn -> accept_loop(listen_socket) end)
        Logger.info("[muyata:finger] listening on port #{port}")
        {:ok, %{listen_socket: listen_socket, port: port}}

      {:error, reason} ->
        Logger.warning("[muyata:finger] failed to bind port #{port}: #{inspect(reason)}")
        {:ok, %{port: port}}
    end
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        spawn(fn -> handle_client(client) end)
        accept_loop(listen_socket)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept_loop(listen_socket)
    end
  end

  defp handle_client(socket) do
    _query =
      case :gen_tcp.recv(socket, 0, 5_000) do
        {:ok, data} -> String.trim(data)
        {:error, _} -> ""
      end

    plan = build_plan()
    :gen_tcp.send(socket, plan)
    :gen_tcp.close(socket)
  end

  defp build_plan do
    void = Muyata.Void.state()
    framing = Muyata.Observer.Framing.status()

    framing_line =
      case framing.dominant do
        nil -> "none"
        d -> "#{d.type} @ #{d.confidence}"
      end

    coverage = Muyata.Observer.Heatmap.coverage()
    peers = Muyata.Mesh.Cluster.peers()

    """
    kind: muyata.plan
    node: #{void.node_id}
    target: #{void.upstream_host}:#{void.upstream_port}
    listen: #{void.listen_port}
    epoch: #{void.epoch}
    patterns: #{void.patterns_seen}
    bytes: #{void.bytes_observed}
    connections: #{void.connections_seen}
    framing: #{framing_line}
    framed: #{framing.framed_count}
    coverage: #{Float.round(coverage * 100, 4)}%
    peers: #{length(peers)}
    uptime: #{System.system_time(:second)}
    """
  end
end
