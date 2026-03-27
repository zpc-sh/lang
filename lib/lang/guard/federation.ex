defmodule Lang.Guard.Federation do
  @moduledoc """
  Guard Mesh federation protocol.

  Enables organic mesh growth: anyone can run a guard node,
  announce it, and join the defensive network.

  Discovery happens over gopher (port 70):
    - Each node serves a /gopher menu listing known peers
    - New nodes announce themselves to a seed list
    - Peers exchange peer lists (gossip-style)
    - The mesh grows with the threat

  Scale model:
    - Shield payloads are static (<10KB), cached everywhere → instant delivery
    - 1 node comfortably serves ~10,000 AI agents for shield delivery
    - Scan/wash is ~1ms per request (CPU-bound)
    - At 2B devices: organic mesh of ~200K nodes (1 per 10K users)
    - The more nodes, the more resilient the mesh

  Federation join protocol:
    1. New node starts with seed peers (or just guard.lang.dev)
    2. Queries seed's /gopher for peer list
    3. Announces itself to all discovered peers via /mesh/announce
    4. Begins serving shield/scan/wash requests
    5. Periodically re-announces and re-discovers (gossip)
  """

  use GenServer
  require Logger

  @gossip_interval :timer.minutes(5)
  @seed_peers [{"guard.lang.dev", 70}]
  @max_peers 1000
  @announce_ttl :timer.hours(1)

  defstruct [
    :node_id,
    :hostname,
    :gopher_port,
    :finger_port,
    :mcp_port,
    :peers,
    :peer_last_seen,
    :stats
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get all known peers."
  @spec peers() :: [{String.t(), non_neg_integer()}]
  def peers, do: GenServer.call(__MODULE__, :peers)

  @doc "Get federation status."
  @spec status() :: map()
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Manually add a peer."
  @spec add_peer(String.t(), non_neg_integer()) :: :ok
  def add_peer(hostname, port \\ 70) do
    GenServer.cast(__MODULE__, {:add_peer, hostname, port})
  end

  @doc "Announce this node to a specific peer."
  @spec announce_to(String.t(), non_neg_integer()) :: :ok | {:error, term()}
  def announce_to(hostname, port \\ 70) do
    GenServer.call(__MODULE__, {:announce_to, hostname, port})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    hostname = Keyword.get(opts, :hostname, node_hostname())
    gopher_port = Keyword.get(opts, :gopher_port, gopher_port_from_config())
    node_id = "guard-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

    Logger.info("Guard Federation starting", node_id: node_id, hostname: hostname)

    state = %__MODULE__{
      node_id: node_id,
      hostname: hostname,
      gopher_port: gopher_port,
      finger_port: 79,
      mcp_port: 4002,
      peers: MapSet.new(@seed_peers),
      peer_last_seen: %{},
      stats: %{
        gossip_rounds: 0,
        peers_discovered: 0,
        announcements_sent: 0,
        started_at: DateTime.utc_now()
      }
    }

    # Start gossip cycle
    Process.send_after(self(), :gossip, @gossip_interval)

    {:ok, state}
  end

  @impl true
  def handle_call(:peers, _from, state) do
    {:reply, MapSet.to_list(state.peers), state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{
      node_id: state.node_id,
      hostname: state.hostname,
      gopher_port: state.gopher_port,
      peer_count: MapSet.size(state.peers),
      stats: state.stats
    }, state}
  end

  @impl true
  def handle_call({:announce_to, hostname, port}, _from, state) do
    result = do_announce(hostname, port, state)
    stats = %{state.stats | announcements_sent: state.stats.announcements_sent + 1}
    {:reply, result, %{state | stats: stats}}
  end

  @impl true
  def handle_cast({:add_peer, hostname, port}, state) do
    peer = {hostname, port}
    peers = MapSet.put(state.peers, peer)
    peer_last_seen = Map.put(state.peer_last_seen, peer, DateTime.utc_now())

    # Also register with spillover
    Lang.Guard.Spillover.register_peer(hostname, port)

    {:noreply, %{state | peers: peers, peer_last_seen: peer_last_seen}}
  end

  @impl true
  def handle_info(:gossip, state) do
    Logger.debug("Guard Federation: gossip round #{state.stats.gossip_rounds + 1}")

    # Query a random subset of peers for their peer lists
    sample = state.peers |> MapSet.to_list() |> Enum.take_random(min(5, MapSet.size(state.peers)))

    new_peers =
      Enum.reduce(sample, state.peers, fn {hostname, port}, acc ->
        case discover_peers_via_gopher(hostname, port) do
          {:ok, discovered} ->
            Enum.reduce(discovered, acc, fn peer, inner_acc ->
              if MapSet.size(inner_acc) < @max_peers do
                MapSet.put(inner_acc, peer)
              else
                inner_acc
              end
            end)

          {:error, _} ->
            acc
        end
      end)

    # Evict stale peers
    now = DateTime.utc_now()
    new_peers =
      MapSet.filter(new_peers, fn peer ->
        case Map.get(state.peer_last_seen, peer) do
          nil -> true
          last_seen -> DateTime.diff(now, last_seen, :millisecond) < @announce_ttl
        end
      end)

    # Register new peers with spillover
    MapSet.difference(new_peers, state.peers)
    |> Enum.each(fn {hostname, port} ->
      Lang.Guard.Spillover.register_peer(hostname, port)
    end)

    discovered = MapSet.size(new_peers) - MapSet.size(state.peers)

    stats = %{state.stats |
      gossip_rounds: state.stats.gossip_rounds + 1,
      peers_discovered: state.stats.peers_discovered + max(0, discovered)
    }

    Process.send_after(self(), :gossip, @gossip_interval)

    {:noreply, %{state | peers: new_peers, stats: stats}}
  end

  # Private

  defp do_announce(hostname, port, state) do
    # Announce via gopher: send our info as a query to /mesh/announce
    announcement = "#{state.hostname}\t#{state.gopher_port}\t#{state.node_id}"
    selector = "/mesh/announce\t#{announcement}\r\n"

    case :gen_tcp.connect(to_charlist(hostname), port, [:binary, active: false], 5_000) do
      {:ok, socket} ->
        :gen_tcp.send(socket, selector)
        _response = recv_all(socket, [])
        :gen_tcp.close(socket)
        :ok

      {:error, reason} ->
        Logger.debug("Federation announce to #{hostname}:#{port} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp discover_peers_via_gopher(hostname, port) do
    selector = "/gopher\r\n"

    case :gen_tcp.connect(to_charlist(hostname), port, [:binary, active: false], 5_000) do
      {:ok, socket} ->
        :gen_tcp.send(socket, selector)
        response = recv_all(socket, [])
        :gen_tcp.close(socket)
        {:ok, parse_gopher_peer_menu(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_gopher_peer_menu(response) do
    # Parse gopher menu lines for type "1" (submenu) entries that look like peers
    response
    |> String.split("\r\n")
    |> Enum.filter(&String.starts_with?(&1, "1"))
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t") do
        [_display, _selector, hostname, port_str | _] ->
          case Integer.parse(port_str) do
            {port, _} when port > 0 -> [{hostname, port}]
            _ -> []
          end

        _ ->
          []
      end
    end)
  end

  defp recv_all(socket, acc) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} -> recv_all(socket, [data | acc])
      {:error, :closed} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
      {:error, :timeout} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp node_hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "localhost"
    end
  end

  defp gopher_port_from_config do
    Application.get_env(:lang, :guard, [])
    |> Keyword.get(:gopher_port, 70)
  end
end
