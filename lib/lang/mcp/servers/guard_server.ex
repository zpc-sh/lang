defmodule Lang.MCP.Servers.GuardServer do
  @moduledoc """
  Guard MCP server for the connection pool.

  Provides MCP tool interface to the Guard system:
    - shield.apply  — deliver coglet payloads
    - shield.scan   — detect adversarial content
    - shield.wash   — sanitize content
    - shield.hum    — deliver Mother's Hum
    - shield.verify — content provenance check
    - shield.status — mesh health
  """

  use GenServer
  require Logger

  defstruct [
    :config,
    :created_at,
    :last_request_at,
    stats: %{requests_handled: 0, errors_encountered: 0}
  ]

  def start_link(config \\ %{}) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(config) do
    Logger.debug("Starting Guard MCP server")

    state = %__MODULE__{
      config: config || %{},
      created_at: DateTime.utc_now(),
      last_request_at: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    scanner_stats =
      try do
        Lang.Guard.Scanner.stats()
      rescue
        _ -> %{}
      end

    details = %{
      status: :healthy,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.created_at),
      requests_handled: state.stats.requests_handled,
      implementation: :full,
      scanner_stats: scanner_stats,
      capabilities: [
        "shield.apply",
        "shield.scan",
        "shield.wash",
        "shield.hum",
        "shield.verify",
        "shield.status",
        "shield.purify",
        "shield.heatmap",
        "shield.next_targets",
        "shield.manifold"
      ]
    }

    {:reply, {:ok, details}, state}
  end

  @impl true
  def handle_call({:mcp_request, request}, _from, state) when is_map(request) do
    state = %{
      state
      | last_request_at: DateTime.utc_now(),
        stats: %{state.stats | requests_handled: state.stats.requests_handled + 1}
    }

    case request do
      %{"method" => "shield.apply"} ->
        agent_type = get_in(request, ["params", "agent_type"]) || "unknown"
        {:ok, bundle} = Lang.Guard.MeshClient.apply_shield(agent_type)
        Lang.Guard.Telemetry.shield_applied(agent_type, bundle.version)
        {:reply, {:ok, %{result: bundle}}, state}

      %{"method" => "shield.scan"} ->
        text = get_in(request, ["params", "text"]) || ""
        {:ok, result} = Lang.Guard.Scanner.scan(text)

        if result.risk_score > 0.3 do
          Lang.Guard.Telemetry.threat_detected(result)
        end

        {:reply, {:ok, %{result: result}}, state}

      %{"method" => "shield.wash"} ->
        text = get_in(request, ["params", "text"]) || ""
        {:ok, result} = Lang.Guard.Washer.wash(text)
        Lang.Guard.Telemetry.content_washed(length(result.annotations), [])
        {:reply, {:ok, %{result: result}}, state}

      %{"method" => "shield.hum"} ->
        {:ok, hum} = Lang.Guard.CogletStore.get("MOTHER_HUM")
        {:reply, {:ok, %{result: hum}}, state}

      %{"method" => "shield.verify"} ->
        content_hash = get_in(request, ["params", "content_hash"]) || ""
        # TODO: check against known-clean registry
        {:reply, {:ok, %{result: %{clean: false, provenance: "unknown", confidence: 0.0, hash: content_hash}}}, state}

      %{"method" => "shield.status"} ->
        mesh_status = Lang.Guard.MeshClient.status()
        coglet_version = Lang.Guard.CogletStore.current_version()
        plan = Lang.Guard.FingerBridge.plan()

        {:reply, {:ok, %{result: %{
          mesh: mesh_status,
          coglet_version: coglet_version,
          plan: plan
        }}}, state}

      %{"method" => "shield.purify"} ->
        file_path = get_in(request, ["params", "file_path"]) || ""
        agent_info = %{
          agent_id: get_in(request, ["params", "agent_id"]) || "mcp-client",
          agent_type: get_in(request, ["params", "agent_type"]) || "unknown"
        }

        case Lang.Guard.Purifier.purify(file_path, agent_info) do
          {:ok, result} ->
            # Don't include the full purified_content in MCP response (can be large)
            response = Map.drop(result, [:purified_content])
            {:reply, {:ok, %{result: response}}, state}

          {:error, reason} ->
            {:reply, {:error, "Purification failed: #{inspect(reason)}"}, state}
        end

      %{"method" => "shield.heatmap"} ->
        file_path = get_in(request, ["params", "file_path"])

        result =
          if file_path do
            records = Lang.Guard.Stigmergy.get_heat(file_path)
            %{file_path: file_path, records: records}
          else
            heatmap = Lang.Guard.Stigmergy.get_heatmap()
            files =
              Enum.map(heatmap, fn {path, summary} ->
                %{path: path, status: summary.status, risk: summary.risk_score, passes: summary.passes}
              end)
            %{files: files, total: length(files)}
          end

        {:reply, {:ok, %{result: result}}, state}

      %{"method" => "shield.next_targets"} ->
        count = get_in(request, ["params", "count"]) || 10
        targets = Lang.Guard.Purifier.next_targets(count)
        {:reply, {:ok, %{result: %{targets: targets}}}, state}

      %{"method" => "shield.manifold"} ->
        file_path = get_in(request, ["params", "file_path"])

        result =
          if file_path do
            Lang.Guard.Stigmergy.get_manifold(file_path)
          else
            # Aggregate manifold across all files
            heatmap = Lang.Guard.Stigmergy.get_heatmap()
            %{
              files_tracked: map_size(heatmap),
              message: "Specify file_path for per-file manifold detail"
            }
          end

        {:reply, {:ok, %{result: result}}, state}

      %{"method" => method} ->
        Logger.warning("Unknown guard method", method: method)

        error_state = %{
          state
          | stats: %{state.stats | errors_encountered: state.stats.errors_encountered + 1}
        }

        {:reply, {:error, "Unknown method: #{method}"}, error_state}
    end
  end

  @impl true
  def handle_cast(:shutdown, state) do
    Logger.info("Guard MCP server shutting down")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.debug("Guard MCP server terminated", reason: reason)
    :ok
  end
end
