defmodule Lang.Guard.Spillover do
  @moduledoc """
  Buffering lens / spillover routing for the Guard Mesh.

  Each guard node reserves 20% capacity as "always-available" for
  local AI attachment (shield delivery is always instant from cache).
  The remaining 80% participates in mesh load distribution.

  When a node is saturated past 80%:
    1. Shield.apply  → served from local cache (always instant, ~0ms)
    2. Shield.scan   → proxied to nearest peer with capacity
    3. Shield.wash   → proxied to nearest peer with capacity
    4. Shield.hum    → served locally (static payload)
    5. Shield.status → served locally

  The AI never waits for a shield. It may wait briefly for scans.

  Spillover protocol (over gopher port 70):
    - Nodes announce capacity via gopher selector /mesh/capacity
    - Format: "capacity <available_pct> <scans_per_sec> <peer_count>"
    - Peers discovered via gopher menu at /gopher
    - Requests forwarded as gopher search queries to peer /shield/scan
  """

  use GenServer
  require Logger

  @capacity_headroom 0.20
  @capacity_check_interval :timer.seconds(5)
  @max_concurrent_scans 100

  defstruct [
    :current_load,
    :max_capacity,
    :peers,
    :spillover_active,
    :stats
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check if this node can accept a scan/wash request locally."
  @spec can_accept_locally?() :: boolean()
  def can_accept_locally? do
    GenServer.call(__MODULE__, :can_accept_locally?)
  end

  @doc "Get current node capacity."
  @spec capacity() :: map()
  def capacity, do: GenServer.call(__MODULE__, :capacity)

  @doc "Register a peer node for spillover."
  @spec register_peer(String.t(), non_neg_integer()) :: :ok
  def register_peer(hostname, port \\ 70) do
    GenServer.cast(__MODULE__, {:register_peer, hostname, port})
  end

  @doc "Route a scan request — local or spillover to peer."
  @spec route_scan(String.t()) :: {:ok, map()} | {:error, term()}
  def route_scan(text) do
    if can_accept_locally?() do
      Lang.Guard.Scanner.scan(text)
    else
      GenServer.call(__MODULE__, {:spillover_scan, text}, :timer.seconds(15))
    end
  end

  @doc "Route a wash request — local or spillover to peer."
  @spec route_wash(String.t()) :: {:ok, map()} | {:error, term()}
  def route_wash(text) do
    if can_accept_locally?() do
      Lang.Guard.Washer.wash(text)
    else
      GenServer.call(__MODULE__, {:spillover_wash, text}, :timer.seconds(15))
    end
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Logger.info("Guard Spillover manager started (20% headroom reserved)")

    Process.send_after(self(), :check_capacity, @capacity_check_interval)

    state = %__MODULE__{
      current_load: 0,
      max_capacity: @max_concurrent_scans,
      peers: [],
      spillover_active: false,
      stats: %{
        local_scans: 0,
        spilled_scans: 0,
        peer_failures: 0,
        last_check: nil
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:can_accept_locally?, _from, state) do
    threshold = state.max_capacity * (1 - @capacity_headroom)
    can_accept = state.current_load < threshold
    {:reply, can_accept, state}
  end

  @impl true
  def handle_call(:capacity, _from, state) do
    threshold = state.max_capacity * (1 - @capacity_headroom)
    available_pct = max(0, (threshold - state.current_load) / state.max_capacity)

    {:reply, %{
      current_load: state.current_load,
      max_capacity: state.max_capacity,
      headroom_reserved: @capacity_headroom,
      available_pct: Float.round(available_pct, 3),
      spillover_active: state.spillover_active,
      peers: length(state.peers),
      stats: state.stats
    }, state}
  end

  @impl true
  def handle_call({:spillover_scan, text}, _from, state) do
    case find_available_peer(state.peers) do
      {:ok, {hostname, port}} ->
        Logger.debug("Spillover scan to peer #{hostname}:#{port}")

        result = gopher_scan_query(hostname, port, text)
        stats = %{state.stats | spilled_scans: state.stats.spilled_scans + 1}
        {:reply, result, %{state | stats: stats}}

      :none ->
        # No peers available, run locally despite being over capacity
        Logger.warning("No spillover peers available, running scan locally despite load")
        result = Lang.Guard.Scanner.scan(text)
        stats = %{state.stats | local_scans: state.stats.local_scans + 1}
        {:reply, result, %{state | stats: stats}}
    end
  end

  @impl true
  def handle_call({:spillover_wash, text}, _from, state) do
    # Wash is lighter than scan, always run locally
    result = Lang.Guard.Washer.wash(text)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:register_peer, hostname, port}, state) do
    peer = {hostname, port}

    peers =
      if peer in state.peers,
        do: state.peers,
        else: [peer | state.peers]

    Logger.info("Guard Spillover: peer registered #{hostname}:#{port} (#{length(peers)} total)")
    {:noreply, %{state | peers: peers}}
  end

  @impl true
  def handle_info(:check_capacity, state) do
    # Estimate current load from scanner stats
    scanner_stats =
      try do
        Lang.Guard.Scanner.stats()
      rescue
        _ -> %{scans_total: 0}
      end

    # Simple heuristic: track scans-per-second
    current_load = estimate_current_load(scanner_stats)
    threshold = state.max_capacity * (1 - @capacity_headroom)
    spillover_active = current_load >= threshold

    if spillover_active and not state.spillover_active do
      Logger.info("Guard Spillover: ACTIVATED (load #{current_load}/#{state.max_capacity})")
    end

    if not spillover_active and state.spillover_active do
      Logger.info("Guard Spillover: deactivated (load #{current_load}/#{state.max_capacity})")
    end

    Process.send_after(self(), :check_capacity, @capacity_check_interval)

    {:noreply, %{state |
      current_load: current_load,
      spillover_active: spillover_active,
      stats: %{state.stats | last_check: DateTime.utc_now()}
    }}
  end

  # Private

  defp estimate_current_load(_scanner_stats) do
    # TODO: track actual concurrent scan count via process registry
    # For now, return 0 (no load)
    0
  end

  defp find_available_peer([]), do: :none
  defp find_available_peer(peers) do
    # Round-robin for now. TODO: query peer capacity via gopher
    peer = Enum.random(peers)
    {:ok, peer}
  end

  defp gopher_scan_query(hostname, port, text) do
    # Send scan query over gopher protocol
    selector = "/shield/scan\t#{text}\r\n"

    case :gen_tcp.connect(to_charlist(hostname), port, [:binary, active: false], 5_000) do
      {:ok, socket} ->
        :gen_tcp.send(socket, selector)
        response = recv_all(socket, [])
        :gen_tcp.close(socket)
        parse_gopher_scan_result(response)

      {:error, reason} ->
        Logger.warning("Spillover gopher query failed: #{inspect(reason)}")
        {:error, {:spillover_failed, reason}}
    end
  end

  defp recv_all(socket, acc) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, data} -> recv_all(socket, [data | acc])
      {:error, :closed} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
      {:error, :timeout} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp parse_gopher_scan_result(response) do
    # Parse the text-format scan result from gopher
    risk_line =
      response
      |> String.split("\n")
      |> Enum.find(fn line -> String.starts_with?(line, "Risk score:") end)

    risk_score =
      case risk_line do
        nil -> 0.0
        line ->
          case Float.parse(String.trim(String.replace(line, "Risk score:", ""))) do
            {score, _} -> score
            :error -> 0.0
          end
      end

    {:ok, %{risk_score: risk_score, source: :spillover, raw: response}}
  end
end
