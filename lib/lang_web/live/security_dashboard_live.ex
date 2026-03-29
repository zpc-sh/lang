defmodule LangWeb.SecurityDashboardLive do
  @moduledoc """
  Real-time security dashboard for monitoring LSP and MCP security events.
  
  Provides live updates of:
  - Security alerts and violations
  - Client activity and blocking status  
  - Rate limiting statistics
  - Session management metrics
  - Threat analysis and patterns
  """
  
  use LangWeb, :live_view
  require Logger
  
  alias Lang.Monitoring.SecurityMonitor
  alias Lang.MCP.{SessionManager, SecurityBridge}
  alias Lang.LSP.PhoenixIntegration
  alias Phoenix.PubSub
  
  @update_interval 5_000  # 5 seconds
  @chart_data_points 20   # Last 20 data points for charts
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to security events
      PhoenixIntegration.subscribe_to_security_events()
      PhoenixIntegration.subscribe_to_security_alerts()
      
      # Schedule periodic updates
      Process.send_after(self(), :update_dashboard, @update_interval)
    end
    
    initial_data = load_dashboard_data()
    
    socket = 
      socket
      |> assign(:page_title, "Security Dashboard")
      |> assign(:security_metrics, initial_data.metrics)
      |> assign(:recent_alerts, initial_data.alerts)
      |> assign(:blocked_clients, [])
      |> assign(:active_sessions, 0)
      |> assign(:threat_level, calculate_threat_level(initial_data))
      |> assign(:chart_data, initialize_chart_data())
      |> assign(:filter_level, :all)
      |> assign(:auto_refresh, true)
    
    {:ok, socket}
  end
  
  @impl true
  def handle_params(params, _uri, socket) do
    filter_level = case Map.get(params, "filter") do
      level when level in ["critical", "warning", "info"] -> String.to_atom(level)
      _ -> :all
    end
    
    socket = assign(socket, :filter_level, filter_level)
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(:update_dashboard, socket) do
    # Schedule next update
    Process.send_after(self(), :update_dashboard, @update_interval)
    
    if socket.assigns.auto_refresh do
      updated_data = load_dashboard_data()
      
      socket = 
        socket
        |> assign(:security_metrics, updated_data.metrics)
        |> assign(:recent_alerts, filter_alerts(updated_data.alerts, socket.assigns.filter_level))
        |> assign(:threat_level, calculate_threat_level(updated_data))
        |> update(:chart_data, &update_chart_data(&1, updated_data.metrics))
      
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_info({:security_event, event}, socket) do
    # Handle real-time security events
    Logger.debug("Received security event", event: event)
    
    # Update relevant metrics based on event type
    socket = case event.type do
      :client_blocked ->
        update_blocked_clients(socket, event.data)
      
      :rate_limited ->
        increment_rate_limit_violations(socket)
      
      :session_created ->
        increment_active_sessions(socket)
        
      :session_terminated ->
        decrement_active_sessions(socket)
      
      _ ->
        socket
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:security_alert, alert}, socket) do
    # Handle real-time security alerts
    Logger.info("Received security alert", alert: alert)
    
    # Add alert to the list if it passes the filter
    if alert_passes_filter?(alert, socket.assigns.filter_level) do
      updated_alerts = [alert | socket.assigns.recent_alerts] |> Enum.take(50)
      socket = assign(socket, :recent_alerts, updated_alerts)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("toggle_refresh", _params, socket) do
    socket = assign(socket, :auto_refresh, not socket.assigns.auto_refresh)
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("set_filter", %{"level" => level}, socket) do
    filter_level = String.to_atom(level)
    
    # Update URL without navigation
    {:noreply, 
     socket 
     |> assign(:filter_level, filter_level)
     |> push_patch(to: ~p"/security?filter=#{level}")
    }
  end
  
  @impl true
  def handle_event("acknowledge_alert", %{"alert_id" => alert_id}, socket) do
    # Mark alert as acknowledged
    updated_alerts = Enum.map(socket.assigns.recent_alerts, fn alert ->
      if alert.id == alert_id do
        Map.put(alert, :acknowledged, true)
      else
        alert
      end
    end)
    
    socket = assign(socket, :recent_alerts, updated_alerts)
    {:noreply, socket}
  end
  
  @impl true
  def handle_event("refresh_now", _params, socket) do
    updated_data = load_dashboard_data()
    
    socket = 
      socket
      |> assign(:security_metrics, updated_data.metrics)
      |> assign(:recent_alerts, filter_alerts(updated_data.alerts, socket.assigns.filter_level))
      |> assign(:threat_level, calculate_threat_level(updated_data))
    
    {:noreply, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="security-dashboard">
      <div class="dashboard-header">
        <h1>Security Dashboard</h1>
        <div class="dashboard-controls">
          <button 
            phx-click="toggle_refresh" 
            class={["btn", if(@auto_refresh, do: "btn-success", else: "btn-secondary")]}
          >
            <%= if @auto_refresh, do: "Auto Refresh ON", else: "Auto Refresh OFF" %>
          </button>
          <button phx-click="refresh_now" class="btn btn-primary">
            Refresh Now
          </button>
        </div>
      </div>
      
      <!-- Threat Level Indicator -->
      <div class={"threat-level threat-level-#{@threat_level}"}>
        <div class="threat-indicator">
          <span class="threat-label">Threat Level</span>
          <span class="threat-value"><%= String.upcase(to_string(@threat_level)) %></span>
        </div>
      </div>
      
      <!-- Key Metrics -->
      <div class="metrics-grid">
        <div class="metric-card">
          <h3>Total Events</h3>
          <div class="metric-value"><%= @security_metrics.total_events || 0 %></div>
        </div>
        
        <div class="metric-card">
          <h3>Active Sessions</h3>
          <div class="metric-value"><%= @active_sessions %></div>
        </div>
        
        <div class="metric-card">
          <h3>Blocked Clients</h3>
          <div class="metric-value"><%= length(@blocked_clients) %></div>
        </div>
        
        <div class="metric-card">
          <h3>Rate Limit Violations</h3>
          <div class="metric-value"><%= @security_metrics.rate_limit_violations || 0 %></div>
        </div>
        
        <div class="metric-card">
          <h3>Failed Auth</h3>
          <div class="metric-value"><%= @security_metrics.failed_auth_count || 0 %></div>
        </div>
        
        <div class="metric-card">
          <h3>Suspicious Requests</h3>
          <div class="metric-value"><%= @security_metrics.suspicious_requests || 0 %></div>
        </div>
      </div>
      
      <!-- Activity Chart -->
      <div class="chart-section">
        <h2>Security Events Over Time</h2>
        <div class="chart-container">
          <svg class="activity-chart" width="800" height="200">
            <%= render_activity_chart(@chart_data) %>
          </svg>
        </div>
      </div>
      
      <!-- Alert Filters -->
      <div class="alert-filters">
        <h2>Recent Security Alerts</h2>
        <div class="filter-buttons">
          <button 
            phx-click="set_filter" 
            phx-value-level="all"
            class={["btn", if(@filter_level == :all, do: "btn-active", else: "btn-secondary")]}
          >
            All
          </button>
          <button 
            phx-click="set_filter" 
            phx-value-level="critical"
            class={["btn", if(@filter_level == :critical, do: "btn-active", else: "btn-secondary")]}
          >
            Critical
          </button>
          <button 
            phx-click="set_filter" 
            phx-value-level="warning"
            class={["btn", if(@filter_level == :warning, do: "btn-active", else: "btn-secondary")]}
          >
            Warning
          </button>
          <button 
            phx-click="set_filter" 
            phx-value-level="info"
            class={["btn", if(@filter_level == :info, do: "btn-active", else: "btn-secondary")]}
          >
            Info
          </button>
        </div>
      </div>
      
      <!-- Alerts List -->
      <div class="alerts-section">
        <div class="alerts-list">
          <%= for alert <- @recent_alerts do %>
            <div class={"alert-item alert-#{alert.level} #{if alert.acknowledged, do: "acknowledged", else: ""}"}>
              <div class="alert-header">
                <span class="alert-level"><%= String.upcase(to_string(alert.level)) %></span>
                <span class="alert-time"><%= format_timestamp(alert.timestamp) %></span>
                <%= unless alert.acknowledged do %>
                  <button 
                    phx-click="acknowledge_alert" 
                    phx-value-alert_id={alert.id}
                    class="btn btn-xs"
                  >
                    Acknowledge
                  </button>
                <% end %>
              </div>
              <div class="alert-message"><%= alert.message %></div>
              <%= if alert.metadata != %{} do %>
                <div class="alert-metadata">
                  <%= render_metadata(alert.metadata) %>
                </div>
              <% end %>
            </div>
          <% end %>
          
          <%= if @recent_alerts == [] do %>
            <div class="no-alerts">
              <p>No alerts matching current filter criteria.</p>
            </div>
          <% end %>
        </div>
      </div>
      
      <!-- Client Activity -->
      <div class="client-section">
        <h2>Client Activity</h2>
        <div class="client-stats">
          <%= if @security_metrics.events_by_client do %>
            <%= for {client_id, count} <- Enum.take(@security_metrics.events_by_client, 10) do %>
              <div class="client-stat">
                <span class="client-id"><%= mask_client_id(client_id) %></span>
                <span class="client-count"><%= count %> events</span>
                <%= if client_id in @blocked_clients do %>
                  <span class="client-status blocked">BLOCKED</span>
                <% else %>
                  <span class="client-status active">ACTIVE</span>
                <% end %>
              </div>
            <% end %>
          <% else %>
            <p>No client activity data available.</p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
  
  ## Helper Functions
  
  defp load_dashboard_data do
    case PhoenixIntegration.get_dashboard_data() do
      %{metrics: metrics, alerts: alerts} ->
        %{metrics: metrics, alerts: alerts}
      
      _ ->
        %{metrics: %{}, alerts: []}
    end
  end
  
  defp calculate_threat_level(data) do
    metrics = data.metrics
    alerts = data.alerts
    
    # Calculate threat level based on recent activity
    critical_alerts = Enum.count(alerts, &(&1.level in [:critical, :emergency]))
    recent_violations = (metrics.rate_limit_violations || 0) + (metrics.suspicious_requests || 0)
    
    cond do
      critical_alerts > 0 or recent_violations > 10 -> :high
      recent_violations > 5 -> :medium  
      recent_violations > 0 -> :low
      true -> :normal
    end
  end
  
  defp initialize_chart_data do
    # Initialize with empty data points
    Enum.map(1..@chart_data_points, fn i ->
      %{
        timestamp: DateTime.add(DateTime.utc_now(), -i * 60),
        events: 0,
        alerts: 0
      }
    end)
  end
  
  defp update_chart_data(chart_data, metrics) do
    new_point = %{
      timestamp: DateTime.utc_now(),
      events: metrics.total_events || 0,
      alerts: length(metrics.recent_alerts || [])
    }
    
    [new_point | Enum.take(chart_data, @chart_data_points - 1)]
  end
  
  defp filter_alerts(alerts, :all), do: alerts
  defp filter_alerts(alerts, level) do
    Enum.filter(alerts, fn alert -> 
      alert.level == level or (level == :critical and alert.level == :emergency)
    end)
  end
  
  defp alert_passes_filter?(_alert, :all), do: true
  defp alert_passes_filter?(alert, level) do
    alert.level == level or (level == :critical and alert.level == :emergency)
  end
  
  defp update_blocked_clients(socket, event_data) do
    client_id = event_data[:client_id]
    if client_id do
      updated_clients = [client_id | socket.assigns.blocked_clients] |> Enum.uniq()
      assign(socket, :blocked_clients, updated_clients)
    else
      socket
    end
  end
  
  defp increment_rate_limit_violations(socket) do
    current_metrics = socket.assigns.security_metrics
    updated_metrics = Map.update(current_metrics, :rate_limit_violations, 1, &(&1 + 1))
    assign(socket, :security_metrics, updated_metrics)
  end
  
  defp increment_active_sessions(socket) do
    assign(socket, :active_sessions, socket.assigns.active_sessions + 1)
  end
  
  defp decrement_active_sessions(socket) do
    assign(socket, :active_sessions, max(0, socket.assigns.active_sessions - 1))
  end
  
  defp format_timestamp(timestamp) do
    timestamp
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 8)  # HH:MM:SS format
  end
  
  defp mask_client_id(nil), do: "unknown"
  defp mask_client_id(client_id) when is_binary(client_id) and byte_size(client_id) > 8 do
    prefix = String.slice(client_id, 0, 4)
    suffix = String.slice(client_id, -4, 4)
    "#{prefix}****#{suffix}"
  end
  defp mask_client_id(client_id), do: "****"
  
  defp render_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {key, value} ->
      "#{key}: #{inspect(value)}"
    end)
    |> Enum.join(", ")
  end
  defp render_metadata(_), do: ""
  
  defp render_activity_chart(chart_data) do
    # Simple SVG line chart
    max_events = chart_data |> Enum.map(& &1.events) |> Enum.max(fn -> 1 end)
    
    points = chart_data
    |> Enum.with_index()
    |> Enum.map(fn {point, index} ->
      x = index * (800 / (@chart_data_points - 1))
      y = 180 - (point.events / max_events * 160)
      "#{x},#{y}"
    end)
    |> Enum.join(" ")
    
    assigns = %{points: points}
    
    ~H"""
    <!-- Chart grid -->
    <%= for i <- 0..4 do %>
      <line x1="0" y1={i * 40} x2="800" y2={i * 40} stroke="#e5e5e5" stroke-width="1"/>
    <% end %>
    <%= for i <- 0..(@chart_data_points - 1) do %>
      <line x1={i * (800 / (@chart_data_points - 1))} y1="0" x2={i * (800 / (@chart_data_points - 1))} y2="200" stroke="#e5e5e5" stroke-width="1"/>
    <% end %>
    
    <!-- Data line -->
    <polyline points={@points} fill="none" stroke="#3b82f6" stroke-width="2"/>
    
    <!-- Data points -->
    <%= for {point, index} <- Enum.with_index(@chart_data) do %>
      <circle 
        cx={index * (800 / (@chart_data_points - 1))} 
        cy={180 - (point.events / max(1, Enum.max(Enum.map(@chart_data, & &1.events))) * 160)}
        r="3" 
        fill="#3b82f6"
      />
    <% end %>
    """
  end
end