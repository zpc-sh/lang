defmodule Lang.LSP.PhoenixIntegration do
  @moduledoc """
  Integration layer between LSP Server and Phoenix features.

  This module demonstrates how the LSP server leverages Phoenix:
  - PubSub for internal message routing and diagnostics distribution
  - Task.Supervisor for concurrent processing
  - Process registry for connection management
  - Telemetry for monitoring and metrics
  """

  alias Phoenix.PubSub
  require Logger

  @pubsub Lang.PubSub

  @doc """
  Broadcasts diagnostics to all interested subscribers (e.g., web UI).
  This allows real-time display of diagnostics in Phoenix LiveView.
  """
  def broadcast_diagnostics(uri, diagnostics) do
    _ =
      try do
        Lang.LSP.Events.DiagnosticEvent
        |> Ash.Changeset.for_create(:emit, %{
          uri: uri,
          diagnostics: diagnostics,
          at: DateTime.utc_now()
        })
        |> Ash.create()
      rescue
        _ -> :ok
      end
    :ok
  end

  @doc """
  Broadcasts completion results for caching and analysis.
  """
  def broadcast_completions(uri, position, completions) do
    _ =
      try do
        Lang.LSP.Events.CompletionEvent
        |> Ash.Changeset.for_create(:emit, %{
          uri: uri,
          position: position,
          completions: completions,
          at: DateTime.utc_now()
        })
        |> Ash.create()
      rescue
        _ -> :ok
      end
    :ok
  end

  @doc """
  Broadcast client lifecycle/activity events for real-time dashboards.

  Types:
  - :connected | :disconnected | :initialized | :activity | :stats
  """
  def broadcast_client_event(type, payload) when type in [:connected, :disconnected, :initialized, :activity, :stats] do
    _ =
      try do
        Lang.LSP.Events.ClientEvent
        |> Ash.Changeset.for_create(:emit, %{
          event_type: type,
          payload: payload,
          at: DateTime.utc_now()
        })
        |> Ash.create()
      rescue
        _ -> :ok
      end
    :ok
  end

  @doc """
  Starts an async analysis task using Phoenix's Task.Supervisor.
  """
  def async_analyze(uri, content, callback) do
    Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
      format = extract_format_from_uri(uri)

      result = Lang.TextIntelligence.AnalysisEngine.analyze_content(content, format)
      callback.(result)
    end)
  end

  @doc """
  Register a client connection in Phoenix's Registry.
  """
  def register_client(socket, client_info) do
    Registry.register(Lang.LSP.Registry, socket, client_info)
  end

  @doc """
  Get all active LSP client connections.
  """
  def list_clients do
    Registry.select(Lang.LSP.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
  end

  @doc """
  Stream large analysis results using Phoenix PubSub.
  """
  def stream_analysis_results(uri, analysis_stream) do
    stream_id = "analysis_#{:erlang.unique_integer([:positive])}"

    Task.start_link(fn ->
      analysis_stream
      |> Stream.chunk_every(10)
      |> Stream.with_index()
      |> Enum.each(fn {chunk, index} ->
        _ =
          try do
            Lang.LSP.Events.AnalysisStreamEvent
            |> Ash.Changeset.for_create(:emit, %{
              stream_id: stream_id,
              chunk: %{items: chunk},
              index: index,
              uri: uri
            })
            |> Ash.create()
          rescue
            _ -> :ok
          end

        # Rate limiting
        Process.sleep(50)
      end)

      _ =
        try do
          Lang.LSP.Events.AnalysisStreamEvent
          |> Ash.Changeset.for_create(:emit, %{
            stream_id: stream_id,
            complete: true,
            uri: uri
          })
          |> Ash.create()
        rescue
          _ -> :ok
        end
    end)

    {:ok, stream_id}
  end

  @doc """
  Monitor LSP server health using Telemetry.
  """
  def report_metrics(event, measurements, metadata \\ %{}) do
    # Emit telemetry for observability tools
    :telemetry.execute([:lang, :lsp, event], measurements, metadata)

    # Publish to Ash PubSub for the dashboard
    _ =
      try do
        Lang.LSP.Events.MetricEvent
        |> Ash.Changeset.for_create(:emit, %{
          event: event,
          measurements: measurements,
          metadata: metadata,
          at: DateTime.utc_now()
        })
        |> Ash.create()
      rescue
        _ -> :ok
      end
  end

  @doc """
  Broadcasts a security event to subscribed clients.
  """
  def broadcast_security_event(event_type, event_data) do
    message = %{
      type: event_type,
      data: sanitize_for_broadcast(event_data),
      timestamp: DateTime.utc_now()
    }
    
    PubSub.broadcast(@pubsub, "security_events", {:security_event, message})
  end
  
  @doc """
  Broadcasts a security alert to admin clients.
  """
  def broadcast_security_alert(alert) do
    sanitized_alert = sanitize_alert_for_broadcast(alert)
    
    PubSub.broadcast(@pubsub, "security_alerts", {:security_alert, sanitized_alert})
  end
  
  @doc """
  Subscribes the current process to security events.
  """
  def subscribe_to_security_events do
    PubSub.subscribe(@pubsub, "security_events")
  end
  
  @doc """
  Subscribes the current process to security alerts.
  """
  def subscribe_to_security_alerts do
    PubSub.subscribe(@pubsub, "security_alerts")
  end
  
  @doc """
  Gets real-time security dashboard data for LiveView.
  """
  def get_dashboard_data do
    case Process.whereis(Lang.Monitoring.SecurityMonitor) do
      nil -> %{metrics: %{}, alerts: []}
      pid when is_pid(pid) ->
        %{
          metrics: Lang.Monitoring.SecurityMonitor.get_metrics(),
          alerts: Lang.Monitoring.SecurityMonitor.get_recent_alerts(10)
        }
    end
  end

  @doc """
  Setup telemetry handlers for LSP metrics.
  """
  def setup_telemetry do
    events = [
      [:lang, :lsp, :request],
      [:lang, :lsp, :response],
      [:lang, :lsp, :connection],
      [:lang, :lsp, :error],
      [:lang, :lsp, :security],
      [:lang, :mcp, :session],
      [:lang, :security, :alert]
    ]

    :telemetry.attach_many(
      "lang-lsp-metrics",
      events,
      &handle_telemetry_event/4,
      %{}
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :request], measurements, metadata, _config) do
    Logger.info("LSP Request",
      method: metadata.method,
      duration: measurements.duration
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :response], measurements, metadata, _config) do
    Logger.info("LSP Response",
      method: metadata.method,
      size: measurements.size,
      duration: measurements.duration
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :connection], measurements, metadata, _config) do
    Logger.info("LSP Connection",
      action: metadata.action,
      client_count: measurements.client_count
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :error], _measurements, metadata, _config) do
    Logger.error("LSP Error",
      error: metadata.error,
      method: metadata.method
    )
  end

  defp handle_telemetry_event([:lang, :lsp, :security, event_type], measurements, metadata, _config) do
    Logger.info("LSP Security Event",
      type: event_type,
      measurements: measurements,
      metadata: metadata
    )
  end

  defp handle_telemetry_event([:lang, :mcp, :session, event_type], measurements, metadata, _config) do
    Logger.info("MCP Session Event",
      type: event_type,
      measurements: measurements,
      metadata: metadata
    )
  end

  defp handle_telemetry_event([:lang, :security, :alert], measurements, metadata, _config) do
    Logger.warn("Security Alert",
      measurements: measurements,
      metadata: metadata
    )
  end

  ## Security Event Sanitization
  
  defp sanitize_for_broadcast(event_data) do
    event_data
    |> Map.drop([:raw_request, :internal_state, :credentials])
    |> sanitize_client_info()
  end
  
  defp sanitize_client_info(data) when is_map(data) do
    case data do
      %{client_id: client_id} = data when is_binary(client_id) ->
        masked_id = mask_client_id(client_id)
        %{data | client_id: masked_id}
      
      _ -> data
    end
  end
  
  defp sanitize_alert_for_broadcast(alert) do
    sanitized_metadata = case alert.metadata do
      %{client_id: client_id} = metadata when is_binary(client_id) ->
        %{metadata | client_id: mask_client_id(client_id)}
      
      metadata -> metadata
    end
    
    %{alert | metadata: sanitized_metadata}
  end
  
  defp mask_client_id(client_id) when is_binary(client_id) and byte_size(client_id) > 8 do
    prefix = String.slice(client_id, 0, 4)
    suffix = String.slice(client_id, -4, 4)
    "#{prefix}****#{suffix}"
  end
  
  defp mask_client_id(_client_id), do: "****"

  defp extract_format_from_uri(uri) do
    case Path.extname(uri) do
      ".md" -> "markdown"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      ".py" -> "python"
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      _ -> "text"
    end
  end
end
