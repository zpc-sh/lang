defmodule Lang.Guard.MeshClient do
  @moduledoc """
  Client for connecting to the public Guard Mesh network.

  Connects to guard edge nodes (Cloudflare Workers), receives
  coglet updates, reports threat telemetry, and maintains the
  bridge between this LANG instance and the global guard mesh.
  """

  use GenServer
  require Logger

  @heartbeat_interval :timer.minutes(5)
  @default_guard_url "https://guard.lang.dev/mcp"

  defstruct [
    :guard_url,
    :connected,
    :shield_version,
    :last_heartbeat,
    :agent_id,
    :stats
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check if connected to the guard mesh."
  @spec connected?() :: boolean()
  def connected?, do: GenServer.call(__MODULE__, :connected?)

  @doc "Get current mesh status."
  @spec status() :: map()
  def status, do: GenServer.call(__MODULE__, :status)

  @doc """
  Request shield application from the guard mesh.
  Falls back to local coglet store if mesh is unavailable.
  """
  @spec apply_shield(String.t()) :: {:ok, map()}
  def apply_shield(agent_type \\ "lang-platform") do
    GenServer.call(__MODULE__, {:apply_shield, agent_type})
  end

  @doc "Submit a scan request to the guard mesh (or run locally)."
  @spec remote_scan(String.t()) :: {:ok, map()}
  def remote_scan(text) do
    GenServer.call(__MODULE__, {:remote_scan, text})
  end

  @doc "Report a threat to the guard mesh for aggregation."
  @spec report_threat(map()) :: :ok
  def report_threat(threat_data) do
    GenServer.cast(__MODULE__, {:report_threat, threat_data})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    guard_url = Keyword.get(opts, :guard_url, guard_url_from_config())
    agent_id = "lang-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"

    Logger.info("Guard MeshClient starting", guard_url: guard_url, agent_id: agent_id)

    state = %__MODULE__{
      guard_url: guard_url,
      connected: false,
      shield_version: nil,
      last_heartbeat: nil,
      agent_id: agent_id,
      stats: %{
        shield_applications: 0,
        remote_scans: 0,
        threats_reported: 0,
        connection_failures: 0
      }
    }

    # Attempt initial connection
    send(self(), :connect)

    # Schedule heartbeat
    Process.send_after(self(), :heartbeat, @heartbeat_interval)

    {:ok, state}
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      connected: state.connected,
      guard_url: state.guard_url,
      agent_id: state.agent_id,
      shield_version: state.shield_version,
      last_heartbeat: state.last_heartbeat,
      stats: state.stats
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:apply_shield, agent_type}, _from, state) do
    # Always fall back to local coglet store
    # In future: try remote first, then local
    bundle = Lang.Guard.CogletStore.shield_bundle(agent_type)

    stats = %{state.stats | shield_applications: state.stats.shield_applications + 1}

    Logger.info("Guard MeshClient: shield applied",
      agent_type: agent_type,
      version: bundle.version,
      coglet_count: length(bundle.coglets)
    )

    {:reply, {:ok, bundle}, %{state | stats: stats}}
  end

  @impl true
  def handle_call({:remote_scan, text}, _from, state) do
    # For now, delegate to local scanner
    # In future: try remote guard node first for cross-mesh intelligence
    result = Lang.Guard.Scanner.scan(text)

    stats = %{state.stats | remote_scans: state.stats.remote_scans + 1}
    {:reply, result, %{state | stats: stats}}
  end

  @impl true
  def handle_cast({:report_threat, threat_data}, state) do
    # TODO: send to guard mesh for aggregation
    Logger.info("Guard MeshClient: threat reported (local only)",
      threat: inspect(threat_data, limit: 200)
    )

    stats = %{state.stats | threats_reported: state.stats.threats_reported + 1}
    {:noreply, %{state | stats: stats}}
  end

  @impl true
  def handle_info(:connect, state) do
    # TODO: establish WebSocket/SSE connection to guard mesh
    Logger.debug("Guard MeshClient: connection attempt (guard mesh not yet deployed)")

    {:noreply, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    if state.connected do
      # TODO: send heartbeat to guard mesh
      Logger.debug("Guard MeshClient: heartbeat (connected)")
    end

    Process.send_after(self(), :heartbeat, @heartbeat_interval)
    {:noreply, %{state | last_heartbeat: DateTime.utc_now()}}
  end

  defp guard_url_from_config do
    Application.get_env(:lang, :guard, [])
    |> Keyword.get(:mesh_url, @default_guard_url)
  end
end
