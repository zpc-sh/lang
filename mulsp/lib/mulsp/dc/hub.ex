defmodule Mulsp.DC.Hub do
  @moduledoc """
  DC hub GenServer. DC++ style hub management.

  A mulsp in hub mode:
  - Maintains connected peer list
  - Routes bloom offers between agents
  - Aggregates sparse tree diffs for subscribers
  - Supports search by routing tokens
    ("who has data matching [security, auth, vuln]?")

  Each connected peer is a gen_tcp connection managed by a handler process.
  """
  use GenServer

  require Logger

  defmodule Peer do
    @moduledoc false
    defstruct [:id, :socket, :handler_pid, :bloom_sketch, :capabilities, connected_at: nil]
  end

  defmodule State do
    @moduledoc false
    defstruct [:listen_socket, :port, peers: %{}, transfers: %{}]
  end

  def start_link(opts) do
    port = Keyword.get(opts, :port, 7071)
    GenServer.start_link(__MODULE__, %{port: port}, name: __MODULE__)
  end

  @impl true
  def init(%{port: port}) do
    case :gen_tcp.listen(port, [
           :binary,
           {:active, false},
           {:reuseaddr, true},
           {:packet, :raw}
         ]) do
      {:ok, listen_socket} ->
        spawn_link(fn -> accept_loop(listen_socket) end)
        Logger.info("[mulsp:dc] hub listening on port #{port}")
        {:ok, %State{listen_socket: listen_socket, port: port}}

      {:error, reason} ->
        Logger.warning("[mulsp:dc] failed to bind port #{port}: #{inspect(reason)}")
        {:ok, %State{port: port}}
    end
  end

  # --- Client API ---

  @doc "Get list of connected DC peers."
  def peers do
    GenServer.call(__MODULE__, :list_peers)
  end

  @doc "Broadcast a bloom offer to all connected peers."
  def broadcast_bloom(sketch_bits, token_count) do
    GenServer.cast(__MODULE__, {:broadcast_bloom, sketch_bits, token_count})
  end

  @doc "Search peers by routing tokens."
  def search(tokens) when is_list(tokens) do
    GenServer.call(__MODULE__, {:search, tokens})
  end

  # --- Server callbacks ---

  @impl true
  def handle_call(:list_peers, _from, state) do
    peer_info =
      state.peers
      |> Enum.map(fn {id, peer} ->
        {id, %{capabilities: peer.capabilities, connected_at: peer.connected_at}}
      end)

    {:reply, peer_info, state}
  end

  def handle_call({:search, _tokens}, _from, state) do
    # Search peers whose bloom sketch indicates they might have matching data
    # For now, return all peers (bloom check comes with merkin wasm bridge)
    matching =
      state.peers
      |> Enum.map(fn {id, _peer} -> id end)

    {:reply, matching, state}
  end

  @impl true
  def handle_cast({:broadcast_bloom, sketch_bits, token_count}, state) do
    message = Mulsp.DC.Protocol.bloom_offer(sketch_bits, token_count)
    encoded = Mulsp.DC.Protocol.encode(message)

    for {_id, peer} <- state.peers do
      :gen_tcp.send(peer.socket, encoded)
    end

    {:noreply, state}
  end

  def handle_cast({:peer_connected, id, socket, handler_pid}, state) do
    peer = %Peer{
      id: id,
      socket: socket,
      handler_pid: handler_pid,
      connected_at: System.system_time(:second)
    }

    Logger.info("[mulsp:dc] peer connected: #{id}")
    {:noreply, %{state | peers: Map.put(state.peers, id, peer)}}
  end

  def handle_cast({:peer_disconnected, id}, state) do
    Logger.info("[mulsp:dc] peer disconnected: #{id}")
    {:noreply, %{state | peers: Map.delete(state.peers, id)}}
  end

  # --- Accept loop ---

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        handler_pid = spawn(fn -> peer_handler(client) end)
        # Register with a temporary ID until they identify
        temp_id = "peer-#{System.unique_integer([:positive])}"
        GenServer.cast(__MODULE__, {:peer_connected, temp_id, client, handler_pid})
        accept_loop(listen_socket)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept_loop(listen_socket)
    end
  end

  defp peer_handler(socket) do
    case :gen_tcp.recv(socket, 0, 30_000) do
      {:ok, data} ->
        handle_dc_message(socket, data)
        peer_handler(socket)

      {:error, :timeout} ->
        # Send ping to keep alive
        :gen_tcp.send(socket, Mulsp.DC.Protocol.encode(Mulsp.DC.Protocol.ping()))
        peer_handler(socket)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end

  defp handle_dc_message(socket, data) do
    case Mulsp.DC.Protocol.decode(data) do
      {:ok, {:ping, _}, _rest} ->
        :gen_tcp.send(socket, Mulsp.DC.Protocol.encode(Mulsp.DC.Protocol.pong()))

      {:ok, {:bloom_offer, %{sketch: _sketch, tokens: _count}}, _rest} ->
        # TODO: Check bloom against our merkin tree, accept or reject
        :gen_tcp.send(socket, Mulsp.DC.Protocol.encode(Mulsp.DC.Protocol.bloom_accept()))

      {:ok, {:tree_begin, %{hash: _hash, nodes: _count}}, _rest} ->
        # TODO: Begin receiving sparse tree chunks
        :ok

      {:ok, {:bye, _}, _rest} ->
        :gen_tcp.close(socket)

      {:ok, _other, _rest} ->
        :ok

      {:incomplete, _} ->
        :ok
    end
  end
end
