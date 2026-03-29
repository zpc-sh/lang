defmodule Lang.Monitoring.SecurityMonitor do
  @moduledoc """
  Real-time security monitoring and alerting for the LANG platform.
  
  Monitors security events from LSP, MCP, and other components, providing
  real-time alerts, threat detection, and automated response capabilities.
  """
  
  use GenServer
  require Logger
  
  alias Lang.LSP.PhoenixIntegration
  alias Lang.Redis
  
  @alert_thresholds %{
    rate_limit_violations: 10,  # per minute
    failed_auth_attempts: 5,    # per minute
    suspicious_requests: 3,     # per minute
    session_anomalies: 2,       # per minute
    critical_errors: 1          # immediate alert
  }
  
  @monitoring_window 60_000  # 1 minute
  @cleanup_interval 300_000  # 5 minutes
  
  @type alert_level :: :info | :warning | :critical | :emergency
  @type security_event :: %{
    type: atom(),
    timestamp: DateTime.t(),
    client_id: String.t() | nil,
    method: String.t() | nil,
    metadata: map()
  }
  
  ## Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records a security event for monitoring and analysis.
  """
  @spec record_event(security_event()) :: :ok
  def record_event(event) do
    GenServer.cast(__MODULE__, {:record_event, event})
  end
  
  @doc """
  Gets current security metrics and statistics.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  @doc """
  Gets recent security alerts.
  """
  @spec get_recent_alerts(non_neg_integer()) :: [map()]
  def get_recent_alerts(limit \\ 50) do
    GenServer.call(__MODULE__, {:get_recent_alerts, limit})
  end
  
  @doc """
  Manually triggers an alert for testing purposes.
  """
  @spec trigger_test_alert(atom(), map()) :: :ok
  def trigger_test_alert(alert_type, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:trigger_test_alert, alert_type, metadata})
  end
  
  ## GenServer Implementation
  
  def init(_opts) do
    # Schedule periodic cleanup and analysis
    Process.send_after(self(), :analyze_security_trends, @monitoring_window)
    Process.send_after(self(), :cleanup_old_events, @cleanup_interval)
    
    # Subscribe to Phoenix security events
    PhoenixIntegration.subscribe_to_security_events()
    
    state = %{
      events: [],  # Recent security events
      metrics: init_metrics(),
      alerts: [],  # Recent alerts
      patterns: %{},  # Detected threat patterns
      blocked_clients: MapSet.new()  # Temporarily blocked clients
    }
    
    Logger.info("Security monitor started")
    {:ok, state}
  end
  
  def handle_cast({:record_event, event}, state) do
    # Add timestamp if not present
    enriched_event = Map.put_new(event, :timestamp, DateTime.utc_now())
    
    # Update events list (keep recent events only)
    new_events = [enriched_event | state.events] |> Enum.take(1000)
    
    # Update metrics
    new_metrics = update_metrics(state.metrics, enriched_event)
    
    # Check for immediate alerts
    alerts_to_send = check_for_alerts(enriched_event, new_metrics)
    
    # Send alerts if any
    Enum.each(alerts_to_send, &send_alert/1)
    
    # Update alerts list
    new_alerts = alerts_to_send ++ state.alerts |> Enum.take(200)
    
    # Check for client blocking
    new_blocked_clients = maybe_block_client(enriched_event, new_metrics, state.blocked_clients)
    
    new_state = %{
      events: new_events,
      metrics: new_metrics,
      alerts: new_alerts,
      patterns: state.patterns,
      blocked_clients: new_blocked_clients
    }
    
    {:noreply, new_state}
  end
  
  def handle_cast({:trigger_test_alert, alert_type, metadata}, state) do
    alert = create_alert(:warning, alert_type, "Test alert triggered manually", metadata)
    send_alert(alert)
    
    new_alerts = [alert | state.alerts] |> Enum.take(200)
    new_state = %{state | alerts: new_alerts}
    
    {:noreply, new_state}
  end
  
  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end
  
  def handle_call({:get_recent_alerts, limit}, _from, state) do
    recent_alerts = Enum.take(state.alerts, limit)
    {:reply, recent_alerts, state}
  end
  
  def handle_info(:analyze_security_trends, state) do
    # Schedule next analysis
    Process.send_after(self(), :analyze_security_trends, @monitoring_window)
    
    # Analyze trends and patterns
    new_patterns = analyze_threat_patterns(state.events)
    trend_alerts = detect_trend_anomalies(state.events, new_patterns)
    
    # Send trend-based alerts
    Enum.each(trend_alerts, &send_alert/1)
    
    new_alerts = trend_alerts ++ state.alerts |> Enum.take(200)
    new_state = %{state | patterns: new_patterns, alerts: new_alerts}
    
    {:noreply, new_state}
  end
  
  def handle_info(:cleanup_old_events, state) do
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_old_events, @cleanup_interval)
    
    # Remove events older than 1 hour
    cutoff_time = DateTime.add(DateTime.utc_now(), -3600)
    
    new_events = Enum.filter(state.events, fn event ->
      DateTime.compare(event.timestamp, cutoff_time) == :gt
    end)
    
    # Clean up metrics for expired time windows
    new_metrics = cleanup_metrics(state.metrics, cutoff_time)
    
    new_state = %{state | events: new_events, metrics: new_metrics}
    {:noreply, new_state}
  end
  
  def handle_info({:security_event, event_data}, state) do
    # Handle events from Phoenix integration
    handle_cast({:record_event, event_data}, state)
  end
  
  ## Private Functions
  
  defp init_metrics do
    %{
      total_events: 0,
      events_by_type: %{},
      events_by_client: %{},
      events_per_minute: [],
      failed_auth_count: 0,
      rate_limit_violations: 0,
      suspicious_requests: 0,
      blocked_clients_count: 0,
      last_reset: DateTime.utc_now()
    }
  end
  
  defp update_metrics(metrics, event) do
    %{
      total_events: metrics.total_events + 1,
      events_by_type: increment_counter(metrics.events_by_type, event.type),
      events_by_client: increment_counter(metrics.events_by_client, event.client_id),
      events_per_minute: add_to_time_series(metrics.events_per_minute, event.timestamp),
      failed_auth_count: metrics.failed_auth_count + (if event.type in [:auth_failed, :unauthorized], do: 1, else: 0),
      rate_limit_violations: metrics.rate_limit_violations + (if event.type == :rate_limited, do: 1, else: 0),
      suspicious_requests: metrics.suspicious_requests + (if is_suspicious_event?(event), do: 1, else: 0),
      blocked_clients_count: metrics.blocked_clients_count,
      last_reset: metrics.last_reset
    }
  end
  
  defp increment_counter(counter_map, key) when is_nil(key), do: counter_map
  defp increment_counter(counter_map, key) do
    Map.update(counter_map, key, 1, &(&1 + 1))
  end
  
  defp add_to_time_series(time_series, timestamp) do
    minute_bucket = div(DateTime.to_unix(timestamp), 60)
    
    # Keep only last hour of data
    cutoff = div(DateTime.to_unix(DateTime.utc_now()), 60) - 60
    
    updated_series = [{minute_bucket, 1} | time_series]
    |> Enum.reduce(%{}, fn {bucket, count}, acc ->
      if bucket >= cutoff do
        Map.update(acc, bucket, count, &(&1 + count))
      else
        acc
      end
    end)
    |> Enum.to_list()
    
    updated_series
  end
  
  defp is_suspicious_event?(event) do
    case event do
      %{type: :request_blocked} -> true
      %{type: :invalid_params, metadata: %{reason: reason}} ->
        suspicious_patterns = ["script", "exec", "../", "eval", "system"]
        reason_str = to_string(reason)
        Enum.any?(suspicious_patterns, &String.contains?(String.downcase(reason_str), &1))
      
      %{method: method} when is_binary(method) ->
        String.contains?(method, "..") or String.length(method) > 100
      
      _ -> false
    end
  end
  
  defp check_for_alerts(event, metrics) do
    alerts = []
    
    # Check immediate critical alerts
    alerts = case event.type do
      :critical_error -> 
        [create_alert(:emergency, :critical_error, "Critical system error detected", event.metadata) | alerts]
      
      :security_breach ->
        [create_alert(:emergency, :security_breach, "Potential security breach detected", event.metadata) | alerts]
      
      _ -> alerts
    end
    
    # Check threshold-based alerts
    alerts = check_threshold_alerts(metrics, alerts)
    
    alerts
  end
  
  defp check_threshold_alerts(metrics, alerts) do
    current_minute = div(DateTime.to_unix(DateTime.utc_now()), 60)
    events_this_minute = metrics.events_per_minute
                        |> Enum.find({current_minute, 0}, fn {bucket, _count} -> bucket == current_minute end)
                        |> elem(1)
    
    alerts = if metrics.failed_auth_count >= @alert_thresholds.failed_auth_attempts do
      [create_alert(:critical, :auth_failures, "High number of authentication failures", %{count: metrics.failed_auth_count}) | alerts]
    else
      alerts
    end
    
    alerts = if metrics.rate_limit_violations >= @alert_thresholds.rate_limit_violations do
      [create_alert(:warning, :rate_limiting, "High rate limit violations", %{count: metrics.rate_limit_violations}) | alerts]
    else
      alerts
    end
    
    alerts = if metrics.suspicious_requests >= @alert_thresholds.suspicious_requests do
      [create_alert(:critical, :suspicious_activity, "Suspicious request patterns detected", %{count: metrics.suspicious_requests}) | alerts]
    else
      alerts
    end
    
    alerts
  end
  
  defp analyze_threat_patterns(events) do
    # Analyze recent events for patterns
    recent_events = Enum.take(events, 100)
    
    %{
      ip_patterns: analyze_ip_patterns(recent_events),
      method_patterns: analyze_method_patterns(recent_events),
      timing_patterns: analyze_timing_patterns(recent_events),
      client_behavior: analyze_client_behavior(recent_events)
    }
  end
  
  defp analyze_ip_patterns(events) do
    # Group events by IP and look for suspicious patterns
    events
    |> Enum.group_by(fn event -> get_in(event, [:metadata, :ip_address]) end)
    |> Enum.filter(fn {ip, ip_events} -> ip && length(ip_events) > 10 end)
    |> Enum.map(fn {ip, ip_events} ->
      {ip, %{
        event_count: length(ip_events),
        unique_methods: ip_events |> Enum.map(& &1.method) |> Enum.uniq() |> length(),
        failed_requests: Enum.count(ip_events, &(&1.type in [:request_blocked, :unauthorized]))
      }}
    end)
    |> Enum.into(%{})
  end
  
  defp analyze_method_patterns(events) do
    # Look for unusual method usage patterns
    events
    |> Enum.group_by(& &1.method)
    |> Enum.map(fn {method, method_events} ->
      {method, %{
        count: length(method_events),
        unique_clients: method_events |> Enum.map(& &1.client_id) |> Enum.uniq() |> length(),
        error_rate: Enum.count(method_events, &(&1.type in [:request_blocked, :invalid_params])) / length(method_events)
      }}
    end)
    |> Enum.into(%{})
  end
  
  defp analyze_timing_patterns(events) do
    # Detect rapid-fire requests (potential DoS)
    events
    |> Enum.group_by(& &1.client_id)
    |> Enum.map(fn {client_id, client_events} ->
      if length(client_events) > 5 do
        sorted_events = Enum.sort_by(client_events, & &1.timestamp)
        time_diffs = Enum.zip(sorted_events, tl(sorted_events))
                    |> Enum.map(fn {e1, e2} -> 
                      DateTime.diff(e2.timestamp, e1.timestamp, :millisecond)
                    end)
        
        avg_interval = Enum.sum(time_diffs) / length(time_diffs)
        {client_id, %{avg_interval: avg_interval, burst_detected: avg_interval < 100}}
      else
        {client_id, %{avg_interval: nil, burst_detected: false}}
      end
    end)
    |> Enum.into(%{})
  end
  
  defp analyze_client_behavior(events) do
    # Analyze client behavior patterns
    events
    |> Enum.group_by(& &1.client_id)
    |> Enum.map(fn {client_id, client_events} ->
      {client_id, %{
        total_requests: length(client_events),
        error_count: Enum.count(client_events, &(&1.type in [:request_blocked, :invalid_params, :unauthorized])),
        unique_methods: client_events |> Enum.map(& &1.method) |> Enum.uniq() |> length(),
        suspicious_score: calculate_suspicion_score(client_events)
      }}
    end)
    |> Enum.into(%{})
  end
  
  defp calculate_suspicion_score(client_events) do
    # Calculate a suspicion score based on various factors
    base_score = 0
    
    # High error rate
    error_rate = Enum.count(client_events, &(&1.type in [:request_blocked, :invalid_params, :unauthorized])) / length(client_events)
    base_score = base_score + (error_rate * 30)
    
    # Rapid requests
    if length(client_events) > 50 do
      base_score = base_score + 20
    end
    
    # Suspicious methods
    suspicious_methods = Enum.count(client_events, fn event ->
      method = event.method || ""
      String.contains?(method, "..") or String.contains?(method, "admin") or String.length(method) > 50
    end)
    base_score = base_score + (suspicious_methods * 10)
    
    min(100, round(base_score))
  end
  
  defp detect_trend_anomalies(events, patterns) do
    alerts = []
    
    # Check for clients with high suspicion scores
    high_suspicion_clients = patterns.client_behavior
                           |> Enum.filter(fn {_client, data} -> data.suspicious_score > 70 end)
    
    alerts = Enum.reduce(high_suspicion_clients, alerts, fn {client_id, data}, acc ->
      alert = create_alert(:warning, :suspicious_client, "Client exhibiting suspicious behavior", %{
        client_id: client_id,
        suspicion_score: data.suspicious_score,
        total_requests: data.total_requests,
        error_count: data.error_count
      })
      [alert | acc]
    end)
    
    # Check for DoS patterns
    burst_clients = patterns.timing_patterns
                   |> Enum.filter(fn {_client, data} -> data.burst_detected end)
    
    alerts = Enum.reduce(burst_clients, alerts, fn {client_id, data}, acc ->
      alert = create_alert(:critical, :potential_dos, "Potential DoS attack detected", %{
        client_id: client_id,
        avg_interval: data.avg_interval
      })
      [alert | acc]
    end)
    
    alerts
  end
  
  defp maybe_block_client(event, metrics, blocked_clients) do
    client_id = event.client_id

    client_errors = Map.get(metrics.events_by_client, client_id, 0)

    cond do
      # Already blocked
      MapSet.member?(blocked_clients, client_id) ->
        blocked_clients

      # High error rate from this client
      client_errors >= 20 ->
        Logger.warning("Temporarily blocking client due to high error rate",
          client_id: client_id,
          errors: client_errors
        )

        send_alert(
          create_alert(:critical, :client_blocked, "Client temporarily blocked", %{
            client_id: client_id,
            reason: "high_error_rate"
          })
        )

        store_blocked_client(client_id, "high_error_rate")
        MapSet.put(blocked_clients, client_id)

      # Suspicious activity
      is_suspicious_event?(event) and event.type == :request_blocked ->
        Logger.warning("Temporarily blocking client due to suspicious activity",
          client_id: client_id
        )

        send_alert(
          create_alert(:critical, :client_blocked, "Client temporarily blocked", %{
            client_id: client_id,
            reason: "suspicious_activity"
          })
        )

        store_blocked_client(client_id, "suspicious_activity")
        MapSet.put(blocked_clients, client_id)

      true ->
        blocked_clients
    end
  end
  
  defp create_alert(level, type, message, metadata) do
    %{
      id: generate_alert_id(),
      level: level,
      type: type,
      message: message,
      timestamp: DateTime.utc_now(),
      metadata: metadata,
      acknowledged: false
    }
  end
  
  defp send_alert(alert) do
    # Log the alert
    Logger.warning("Security alert: #{alert.message}", 
      level: alert.level,
      type: alert.type,
      metadata: alert.metadata
    )
    
    # Send to Phoenix for real-time notifications
    PhoenixIntegration.broadcast_security_alert(alert)
    
    # Send telemetry
    :telemetry.execute([:lang, :security, :alert], %{count: 1}, alert)
    
    # For critical/emergency alerts, also send notifications
    if alert.level in [:critical, :emergency] do
      send_notification(alert)
    end
  end
  
  defp send_notification(alert) do
    # In a real implementation, this would integrate with:
    # - Email notifications
    # - Slack/Discord webhooks  
    # - PagerDuty or similar
    # - SMS alerts for emergencies
    
    Logger.info("Would send notification for #{alert.level} alert: #{alert.message}")
  end
  
  defp store_blocked_client(client_id, reason) do
    # Store blocked client in Redis with TTL
    key = "blocked_client:#{client_id}"
    data = %{blocked_at: DateTime.utc_now(), reason: reason}
    
    Redis.setex(key, 3600, Jason.encode!(data))  # Block for 1 hour
  end
  
  defp cleanup_metrics(metrics, cutoff_time) do
    cutoff_minute = div(DateTime.to_unix(cutoff_time), 60)
    
    cleaned_time_series = metrics.events_per_minute
                         |> Enum.filter(fn {bucket, _count} -> bucket >= cutoff_minute end)
    
    %{metrics | events_per_minute: cleaned_time_series}
  end
  
  defp generate_alert_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end