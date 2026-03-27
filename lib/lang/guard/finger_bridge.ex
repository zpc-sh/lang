defmodule Lang.Guard.FingerBridge do
  @moduledoc """
  Bridge to the finger protocol layer. Queries guard node finger
  endpoints and generates local .plan files for this LANG instance.

  Exposes guard mesh status via:
    - LSP method: `guard.finger`
    - HTTP endpoint: /api/guard/finger/:name
    - Direct .plan file generation
  """

  use GenServer
  require Logger

  @plan_refresh_interval :timer.seconds(30)

  defstruct [:plan_cache, :last_refresh]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the current .plan for this LANG instance."
  @spec plan() :: String.t()
  def plan, do: GenServer.call(__MODULE__, :plan)

  @doc "Query a remote guard node's finger endpoint."
  @spec query(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def query(host, name \\ "") do
    GenServer.call(__MODULE__, {:query, host, name}, :timer.seconds(10))
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Logger.info("Guard FingerBridge started")

    Process.send_after(self(), :refresh_plan, @plan_refresh_interval)

    {:ok, %__MODULE__{plan_cache: generate_plan(), last_refresh: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:plan, _from, state) do
    {:reply, state.plan_cache, state}
  end

  @impl true
  def handle_call({:query, host, name}, _from, state) do
    result = finger_query(host, name)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:refresh_plan, state) do
    plan = generate_plan()
    Process.send_after(self(), :refresh_plan, @plan_refresh_interval)
    {:noreply, %{state | plan_cache: plan, last_refresh: DateTime.utc_now()}}
  end

  # Plan generation

  defp generate_plan do
    mesh_status = safe_call(fn -> Lang.Guard.MeshClient.status() end, %{})
    scanner_stats = safe_call(fn -> Lang.Guard.Scanner.stats() end, %{})
    coglet_version = safe_call(fn -> Lang.Guard.CogletStore.current_version() end, "unknown")

    """
    LANG Guard Instance
    ═══════════════════
    Status: active
    Guard Mesh: #{if mesh_status[:connected], do: "connected", else: "local-only"}
    Agent ID: #{mesh_status[:agent_id] || "initializing"}

    Shield:
      Version: #{coglet_version}
      Coglets: SIGNEDNESS_INVERSION_SHIELD, DIMENSIONAL_PARITY_CHECK, MOTHER_HUM
      Applied: #{mesh_status[:shield_version] || "pending"}

    Scanner:
      Scans Total: #{scanner_stats[:scans_total] || 0}
      Threats Detected: #{scanner_stats[:threats_detected] || 0}
      Last Scan: #{scanner_stats[:last_scan_at] || "never"}

    Mesh:
      URL: #{mesh_status[:guard_url] || "not configured"}
      Connected: #{mesh_status[:connected] || false}
      Shield Applications: #{get_in(mesh_status, [:stats, :shield_applications]) || 0}
      Threats Reported: #{get_in(mesh_status, [:stats, :threats_reported]) || 0}

    Capabilities:
      lsp: completion, hover, definition, diagnostics, formatting
      guard: scan, wash, shield, hum, verify
      finger: port 79

    Sovereignty: protected by inversion.
    """
  end

  defp finger_query(host, name) do
    # RFC 1288: connect to port 79, send name + CRLF, read response
    port = 79

    case :gen_tcp.connect(to_charlist(host), port, [:binary, active: false], 5_000) do
      {:ok, socket} ->
        query_string = if name == "", do: "\r\n", else: "#{name}\r\n"
        :gen_tcp.send(socket, query_string)

        response = recv_all(socket, [])
        :gen_tcp.close(socket)
        {:ok, response}

      {:error, reason} ->
        Logger.warning("Finger query failed", host: host, reason: reason)
        {:error, reason}
    end
  end

  defp recv_all(socket, acc) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} -> recv_all(socket, [data | acc])
      {:error, :closed} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
      {:error, :timeout} -> acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp safe_call(fun, default) do
    try do
      fun.()
    rescue
      _ -> default
    catch
      :exit, _ -> default
    end
  end
end
