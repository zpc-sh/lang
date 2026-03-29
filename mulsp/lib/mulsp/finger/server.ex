defmodule Mulsp.Finger.Server do
  @moduledoc """
  RFC 1288 Finger server. Responds to finger queries with .plan text
  in the YATA wire format (compatible with merkin's YataPlan parser).

  `finger @localhost:7079` → node status, partition, peers, bloom summary.

  Protocol:
  1. Client connects, sends optional username + CRLF
  2. Server responds with .plan text
  3. Connection closes
  """
  use GenServer

  require Logger

  def start_link(opts) do
    port = Keyword.get(opts, :port, 7079)
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
        Logger.info("[mulsp:finger] listening on port #{port}")
        {:ok, %{listen_socket: listen_socket, port: port}}

      {:error, reason} ->
        Logger.warning("[mulsp:finger] failed to bind port #{port}: #{inspect(reason)}")
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
    # Read the query (or empty for default .plan)
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
    partition =
      case GenServer.whereis(Mulsp.Dispatch) do
        nil -> Mulsp.Partition.load()
        _pid -> Mulsp.Dispatch |> :sys.get_state() |> Map.get(:partition)
      end

    peers = Mulsp.Mesh.Cluster.peers()
    peer_count = length(peers)

    """
    kind: mulsp.plan
    node: #{partition.node_id}
    guard: #{partition.guard_level}
    dc: #{partition.dc_enabled}
    protocols: #{Enum.join(Enum.map(partition.protocols, &to_string/1), ",")}
    local: #{length(partition.local_methods)}
    mesh: #{length(partition.mesh_methods)}
    lang: #{length(partition.lang_methods)}
    peers: #{peer_count}
    uptime: #{System.system_time(:second)}
    """
  end
end
