defmodule LangWeb.LSPMonitorLive do
  @moduledoc """
  LiveView for monitoring LSP server status and connections.
  Demonstrates Phoenix integration with the LSP server.
  """
  use LangWeb, :live_view
  alias Phoenix.PubSub
  alias Lang.LSP.Server

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to LSP events
      PubSub.subscribe(Lang.PubSub, "lsp:diagnostics")
      PubSub.subscribe(Lang.PubSub, "lsp:completions")
      PubSub.subscribe(Lang.PubSub, "lsp:connections")

      # Schedule periodic updates
      :timer.send_interval(5000, self(), :update_stats)
    end

    {:ok,
     assign(socket,
       server_info: get_server_info(),
       recent_diagnostics: [],
       recent_completions: [],
       active_connections: 0,
       total_requests: 0
     )}
  end

  @impl true
  def handle_info({:diagnostics, uri, diagnostics}, socket) do
    recent =
      [{uri, diagnostics, DateTime.utc_now()} | socket.assigns.recent_diagnostics]
      |> Enum.take(10)

    {:noreply, assign(socket, recent_diagnostics: recent)}
  end

  @impl true
  def handle_info({:completions, uri, position, completions}, socket) do
    recent =
      [
        {uri, position, length(completions), DateTime.utc_now()}
        | socket.assigns.recent_completions
      ]
      |> Enum.take(10)

    {:noreply, assign(socket, recent_completions: recent)}
  end

  @impl true
  def handle_info(:update_stats, socket) do
    {:noreply, assign(socket, server_info: get_server_info())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]} current_scope={assigns[:current_scope]}>
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 class="text-3xl font-bold text-gray-900 mb-8">LSP Server Monitor</h1>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Server Status</h2>
          <dl class="space-y-2">
            <div class="flex justify-between">
              <dt class="text-gray-600">Status:</dt>
              <dd class="font-medium text-green-600">Active</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Port:</dt>
              <dd class="font-mono">{@server_info[:port] || "N/A"}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Active Documents:</dt>
              <dd class="font-medium">{@server_info[:active_documents] || 0}</dd>
            </div>
            <div class="flex justify-between">
              <dt class="text-gray-600">Version:</dt>
              <dd class="font-mono">{@server_info[:version] || "1.0.0"}</dd>
            </div>
          </dl>
        </div>

        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Server Capabilities</h2>
          <div class="space-y-2">
            <%= for {capability, enabled} <- [
              {"Text Sync", true},
              {"Completions", true},
              {"Hover", true},
              {"Diagnostics", true},
              {"Formatting", true},
              {"Symbols", true}
            ] do %>
              <div class="flex items-center justify-between">
                <span class="text-gray-600">{capability}</span>
                <span class={[
                  "px-2 py-1 text-xs rounded-full",
                  enabled && "bg-green-100 text-green-800",
                  !enabled && "bg-gray-100 text-gray-600"
                ]}>
                  {if enabled, do: "Enabled", else: "Disabled"}
                </span>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Recent Diagnostics</h2>
          <div class="space-y-3">
            <%= if @recent_diagnostics == [] do %>
              <p class="text-gray-500 text-sm">No recent diagnostics</p>
            <% else %>
              <%= for {uri, diagnostics, timestamp} <- @recent_diagnostics do %>
                <div class="border-l-4 border-blue-500 pl-4 py-2">
                  <div class="text-sm font-mono text-gray-700 truncate">
                    {Path.basename(uri)}
                  </div>
                  <div class="text-xs text-gray-500">
                    {length(diagnostics)} diagnostics • {Calendar.strftime(timestamp, "%H:%M:%S")}
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Recent Completions</h2>
          <div class="space-y-3">
            <%= if @recent_completions == [] do %>
              <p class="text-gray-500 text-sm">No recent completions</p>
            <% else %>
              <%= for {uri, position, count, timestamp} <- @recent_completions do %>
                <div class="border-l-4 border-green-500 pl-4 py-2">
                  <div class="text-sm font-mono text-gray-700 truncate">
                    {Path.basename(uri)}
                  </div>
                  <div class="text-xs text-gray-500">
                    Line {position["line"]} • {count} items • {Calendar.strftime(
                      timestamp,
                      "%H:%M:%S"
                    )}
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <div class="mt-8 bg-blue-50 border border-blue-200 rounded-lg p-6">
        <h3 class="text-lg font-semibold text-blue-900 mb-2">Phoenix Integration</h3>
        <p class="text-blue-800">
          The LSP server leverages Phoenix for:
        </p>
        <ul class="mt-2 space-y-1 text-blue-700">
          <li class="flex items-start">
            <span class="mr-2">•</span>
            <span>PubSub for real-time diagnostics and event distribution</span>
          </li>
          <li class="flex items-start">
            <span class="mr-2">•</span>
            <span>Task.Supervisor for concurrent analysis processing</span>
          </li>
          <li class="flex items-start">
            <span class="mr-2">•</span>
            <span>Process Registry for connection management</span>
          </li>
          <li class="flex items-start">
            <span class="mr-2">•</span>
            <span>Telemetry for performance monitoring</span>
          </li>
        </ul>
      </div>
    </div>
    </Layouts.app>
    """
  end

  defp get_server_info do
    case Server.get_server_info() do
      %{} = info -> info
      _ -> %{}
    end
  rescue
    _ -> %{}
  end
end
