defmodule Muyata.Mesh.Cluster do
  @moduledoc """
  Muyata mesh clustering — collective intelligence of sunyata.

  Clustering modes:
  1. Same-protocol swarm: multiple muyata watching the same service
     type share shapes and merge heatmaps for faster convergence.
  2. Cross-protocol mesh: muyata instances watching different services
     share bloom sketches for emergent protocol similarity detection.
  3. mulsp integration: muyata joins the mulsp DC mesh as peers.

  A single muyata is limited by Rice's theorem. A swarm of muyata
  collectively builds a probabilistic map of all communication.
  """
  use GenServer

  require Logger

  defmodule Peer do
    @moduledoc false
    defstruct [:id, :host, :port, :type, :last_seen, :bloom_bits, :shape]
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get list of known peers."
  def peers do
    GenServer.call(__MODULE__, :list_peers)
  end

  @doc "Register a peer (muyata or mulsp)."
  def register_peer(id, host, port, type \\ :muyata) do
    GenServer.cast(__MODULE__, {:register_peer, id, host, port, type})
  end

  @doc "Share our shape with all peers."
  def broadcast_shape do
    GenServer.cast(__MODULE__, :broadcast_shape)
  end

  @doc "Receive a shape from a peer."
  def receive_shape(peer_id, shape) do
    GenServer.cast(__MODULE__, {:receive_shape, peer_id, shape})
  end

  @doc "Get composite bloom (union of all peer blooms)."
  def composite_bloom do
    GenServer.call(__MODULE__, :composite_bloom)
  end

  @impl true
  def init(_opts) do
    state = %{
      peers: %{},
      received_shapes: %{},
      merge_queue: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:list_peers, _from, state) do
    info =
      Enum.map(state.peers, fn {id, peer} ->
        %{id: id, host: peer.host, port: peer.port, type: peer.type, last_seen: peer.last_seen}
      end)

    {:reply, info, state}
  end

  def handle_call(:composite_bloom, _from, state) do
    blooms =
      state.peers
      |> Enum.map(fn {_id, peer} -> peer.bloom_bits end)
      |> Enum.filter(&(&1 != nil))

    composite =
      case blooms do
        [] -> nil
        [first | rest] -> Enum.reduce(rest, first, &bloom_union/2)
      end

    {:reply, composite, state}
  end

  @impl true
  def handle_cast({:register_peer, id, host, port, type}, state) do
    peer = %Peer{
      id: id,
      host: host,
      port: port,
      type: type,
      last_seen: System.system_time(:second)
    }

    Logger.info("[muyata:mesh] peer registered: #{id} (#{type})")
    {:noreply, %{state | peers: Map.put(state.peers, id, peer)}}
  end

  def handle_cast(:broadcast_shape, state) do
    shape = Muyata.Shape.seal()
    _etf = Muyata.Shape.to_etf(shape)

    # TODO: send via DC protocol to all peers
    Logger.info("[muyata:mesh] broadcasting shape to #{map_size(state.peers)} peers")
    {:noreply, state}
  end

  def handle_cast({:receive_shape, peer_id, shape}, state) do
    Logger.info("[muyata:mesh] received shape from #{peer_id}")

    state = %{
      state
      | received_shapes: Map.put(state.received_shapes, peer_id, shape),
        merge_queue: [peer_id | state.merge_queue]
    }

    {:noreply, state}
  end

  defp bloom_union(a, b) when byte_size(a) == byte_size(b) do
    import Bitwise

    for {<<ba::8>>, <<bb::8>>} <- Enum.zip(
          for(<<byte::8 <- a>>, do: <<byte::8>>),
          for(<<byte::8 <- b>>, do: <<byte::8>>)
        ),
        into: <<>> do
      <<bor(ba, bb)::8>>
    end
  end

  defp bloom_union(a, _b), do: a
end
