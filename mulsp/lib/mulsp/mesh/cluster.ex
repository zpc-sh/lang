defmodule Mulsp.Mesh.Cluster do
  @moduledoc """
  Mesh clustering via distributed Erlang.

  Erlang IS inherently distributed. Every VM has the architecture.
  AtomVM now supports `Node.connect/1` — mulsp instances can cluster
  natively using Erlang distribution protocol.

  For cross-network or when distributed Erlang isn't available:
  falls back to TCP peer connections via finger/gopher queries.

  This GenServer tracks:
  - Known peers and their capabilities (from finger .plan)
  - Cluster membership state
  - Forwarding table for proxied methods
  """
  use GenServer

  require Logger

  defmodule PeerInfo do
    @moduledoc false
    defstruct [
      :node_id,
      :node_name,
      :status,
      :capabilities,
      :gopher_port,
      :finger_port,
      :dc_port,
      last_seen: nil
    ]
  end

  def start_link(opts) do
    partition = Keyword.get(opts, :partition, Mulsp.Partition.load())
    GenServer.start_link(__MODULE__, partition, name: __MODULE__)
  end

  # --- Client API ---

  @doc "Get list of known peers."
  def peers do
    case GenServer.whereis(__MODULE__) do
      nil -> []
      _pid -> GenServer.call(__MODULE__, :peers)
    end
  end

  @doc "Trigger peer discovery."
  def discover do
    GenServer.cast(__MODULE__, :discover)
  end

  @doc "Announce shutdown to all peers."
  def announce_shutdown do
    GenServer.cast(__MODULE__, :announce_shutdown)
  end

  @doc "Forward a request to a specific peer."
  def forward(target, request) do
    GenServer.call(__MODULE__, {:forward, target, request}, 10_000)
  end

  @doc "Broadcast a request to all peers, return first response."
  def broadcast(request) do
    GenServer.call(__MODULE__, {:broadcast, request}, 10_000)
  end

  # --- Server ---

  @impl true
  def init(partition) do
    state = %{
      partition: partition,
      peers: %{},
      connected_nodes: []
    }

    # Set the distributed Erlang cookie if configured
    if partition.cookie do
      try do
        Node.set_cookie(String.to_atom(partition.cookie))
      rescue
        _ -> :ok
      end
    end

    # Connect to seed peers
    for seed <- partition.peer_seeds do
      spawn(fn -> connect_seed(seed) end)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:peers, _from, state) do
    peer_list =
      state.peers
      |> Enum.map(fn {id, info} ->
        {id, %{status: info.status, capabilities: info.capabilities}}
      end)

    {:reply, peer_list, state}
  end

  def handle_call({:forward, target, request}, _from, state) do
    result =
      case Map.get(state.peers, target) do
        nil ->
          {:error, "peer not found: #{target}"}

        peer ->
          try do
            # Try distributed Erlang first
            if peer.node_name do
              :rpc.call(String.to_atom(peer.node_name), Mulsp.Dispatch, :dispatch, [
                request.method,
                request.params,
                request.id
              ])
            else
              {:error, "no route to peer"}
            end
          rescue
            e -> {:error, Exception.message(e)}
          end
      end

    {:reply, result, state}
  end

  def handle_call({:broadcast, request}, _from, state) do
    # Fan out to all peers, take first success
    results =
      state.peers
      |> Enum.map(fn {_id, peer} ->
        if peer.node_name do
          try do
            :rpc.call(
              String.to_atom(peer.node_name),
              Mulsp.Dispatch,
              :dispatch,
              [request.method, request.params, request.id],
              5_000
            )
          rescue
            _ -> {:error, :unreachable}
          end
        else
          {:error, :no_route}
        end
      end)

    result =
      Enum.find(results, {:error, :no_responder}, fn
        {:ok, _} -> true
        _ -> false
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_cast(:discover, state) do
    # Try to discover peers via Erlang distribution
    nodes = Node.list()

    new_peers =
      for node <- nodes, into: state.peers do
        id = to_string(node)

        info = %PeerInfo{
          node_id: id,
          node_name: id,
          status: :connected,
          last_seen: System.system_time(:second)
        }

        {id, info}
      end

    {:noreply, %{state | peers: new_peers}}
  end

  def handle_cast(:announce_shutdown, state) do
    # Notify distributed peers
    for node <- Node.list() do
      try do
        :rpc.cast(node, Logger, :info, ["[mulsp] peer shutting down: #{Node.self()}"])
      rescue
        _ -> :ok
      end
    end

    {:noreply, state}
  end

  defp connect_seed(seed) when is_binary(seed) do
    try do
      Node.connect(String.to_atom(seed))
    rescue
      _ -> :ok
    end
  end

  defp connect_seed(seed) when is_atom(seed) do
    try do
      Node.connect(seed)
    rescue
      _ -> :ok
    end
  end
end
