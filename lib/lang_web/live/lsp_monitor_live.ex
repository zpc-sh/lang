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
        total_requests: 0,
        lsp_caps: nil,
        lsp_caps_error: nil,
        lsp_ping_ms: nil,
        lsp_ping_error: nil,
        lsp_methods: [],
        analysis_form: to_form(%{"content" => "", "format" => "text"}, as: :analysis),
        analysis_stream_id: nil,
        analysis_events: [],
        scan_form: to_form(%{"path" => "", "max_depth" => "3"}, as: :scan),
        scan_result: nil,
        scan_error: nil
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
  def handle_event("fetch_caps", _params, socket) do
    case Lang.lsp_capabilities() do
      {:ok, caps} ->
        methods = (caps["methods"] || []) |> Enum.map(&to_string/1)
        {:noreply, assign(socket, lsp_caps: caps, lsp_caps_error: nil, lsp_methods: methods)}

      {:error, reason} ->
        {:noreply, assign(socket, lsp_caps: nil, lsp_caps_error: inspect(reason))}
    end
  end

  @impl true
  def handle_event("ping", _params, socket) do
    t0 = System.monotonic_time(:millisecond)
    case Lang.LSP.Client.ping() do
      {:ok, %{"status" => "pong"}} ->
        ms = System.monotonic_time(:millisecond) - t0
        {:noreply, assign(socket, lsp_ping_ms: ms, lsp_ping_error: nil)}
      {:ok, _other} ->
        {:noreply, assign(socket, lsp_ping_ms: nil, lsp_ping_error: "Unexpected response")}
      {:error, reason} ->
        {:noreply, assign(socket, lsp_ping_ms: nil, lsp_ping_error: inspect(reason))}
    end
  end

  @impl true
  def handle_event("start_stream", %{"analysis" => %{"content" => content, "format" => format}}, socket) do
    case Lang.LSP.Client.request("lang.analyze.stream", %{content: content, format: format}) do
      {:ok, %{"stream_id" => stream_id}} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Lang.PubSub, "lsp:analysis:#{stream_id}")
        {:noreply,
         assign(socket,
           analysis_stream_id: stream_id,
           analysis_events: cap_events(["started"]),
           analysis_form: to_form(%{"content" => content, "format" => format}, as: :analysis)
         )}

      {:ok, other} ->
        {:noreply, assign(socket, analysis_events: cap_events([inspect(other)]))}

      {:error, reason} ->
        {:noreply, assign(socket, analysis_events: cap_events(["error: #{inspect(reason)}"]))}
    end
  end

  @impl true
  def handle_event("fs_scan", %{"scan" => %{"path" => path, "max_depth" => md}}, socket) do
    max_depth = parse_int(md, 3)
    case Lang.LSP.Client.request("lang.fs.scan", %{path: path, max_depth: max_depth}) do
      {:ok, %{"stats" => stats} = res} ->
        {:noreply, assign(socket, scan_result: %{stats: stats}, scan_error: nil)}
      {:ok, other} ->
        {:noreply, assign(socket, scan_result: %{raw: other}, scan_error: nil)}
      {:error, reason} ->
        {:noreply, assign(socket, scan_result: nil, scan_error: inspect(reason))}
    end
  end

  @impl true
  def handle_info({:started, data}, socket) do
    {:noreply, update(socket, :analysis_events, fn ev -> cap_events(ev ++ ["started: #{inspect(data)}"]) end)}
  end

  @impl true
  def handle_info({:progress, data}, socket) do
    pct = :erlang.float_to_binary((data[:progress] || 0.0) * 100.0, decimals: 1)
    {:noreply, update(socket, :analysis_events, fn ev -> cap_events(ev ++ ["progress: #{pct}%"]) end)}
  end

  @impl true
  def handle_info({:completed, data}, socket) do
    {:noreply, update(socket, :analysis_events, fn ev -> cap_events(ev ++ ["completed"]) end)}
  end

  @impl true
  def handle_info({:error, data}, socket) do
    {:noreply, update(socket, :analysis_events, fn ev -> cap_events(ev ++ ["error: #{inspect(data)}"]) end)}
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
          <div class="mt-4 flex items-center gap-3">
            <button id="fetch-caps" phx-click="fetch_caps" class="px-3 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700">
              Fetch from LSP (localhost:4001)
            </button>
            <%= if @lsp_caps_error do %>
              <span class="text-sm text-red-600">{@lsp_caps_error}</span>
            <% end %>
          </div>
          <div class="mt-2 flex items-center gap-3">
            <button id="ping-lsp" phx-click="ping" class="px-3 py-2 bg-gray-800 text-white rounded-md hover:bg-gray-900">
              Ping LSP
            </button>
            <%= if not is_nil(@lsp_ping_ms) do %>
              <span class="text-sm text-gray-700">Latency: {@lsp_ping_ms} ms</span>
            <% end %>
            <%= if @lsp_ping_error do %>
              <span class="text-sm text-red-600">{@lsp_ping_error}</span>
            <% end %>
          </div>
          <%= if @lsp_caps do %>
            <div id="lsp-caps" class="mt-4 p-3 rounded border border-gray-200 bg-gray-50">
              <div class="text-sm text-gray-700">Methods available: {(@lsp_caps["methods"] || []) |> Enum.count()}</div>
            </div>
          <% end %>
          <%= if @lsp_methods != [] do %>
            <div id="lsp-methods" class="mt-4 max-h-48 overflow-auto border border-gray-200 rounded">
              <ul class="divide-y divide-gray-100">
                <%= for m <- @lsp_methods do %>
                  <li class="px-3 py-1 text-sm font-mono text-gray-700">{m}</li>
                <% end %>
              </ul>
            </div>
          <% end %>
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

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Analyze Stream (LSP)</h2>
          <.form for={@analysis_form} id="analysis-form" phx-submit="start_stream">
            <div class="space-y-3">
              <.input field={@analysis_form[:format]} type="text" label="Format" />
              <.input field={@analysis_form[:content]} type="textarea" label="Content" />
              <button id="start-stream" type="submit" class="px-3 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700">
                Start Streaming Analysis
              </button>
            </div>
          </.form>
          <div id="analysis-events" class="mt-4 max-h-40 overflow-auto text-sm font-mono bg-gray-50 p-2 rounded border border-gray-200">
            <%= if @analysis_events == [] do %>
              <div class="text-gray-500">No events yet</div>
            <% else %>
              <%= for e <- @analysis_events do %>
                <div class="text-gray-700">{e}</div>
              <% end %>
            <% end %>
          </div>
        </div>
        <div class="bg-white shadow rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Filesystem Scan (LSP)</h2>
          <.form for={@scan_form} id="scan-form" phx-submit="fs_scan">
            <div class="grid grid-cols-1 md:grid-cols-6 gap-3 items-end">
              <div class="md:col-span-4">
                <.input field={@scan_form[:path]} type="text" label="Path" />
              </div>
              <div class="md:col-span-1">
                <.input field={@scan_form[:max_depth]} type="number" label="Depth" />
              </div>
              <div class="md:col-span-1">
                <button id="scan" type="submit" class="w-full px-3 py-2 bg-emerald-600 text-white rounded-md hover:bg-emerald-700">Scan</button>
              </div>
            </div>
          </.form>
          <div class="mt-4 text-sm">
            <%= if @scan_error do %>
              <div class="text-red-600">{@scan_error}</div>
            <% end %>
            <%= if @scan_result do %>
              <pre phx-no-curly-interpolation class="p-2 bg-gray-50 rounded border border-gray-200 overflow-auto">{inspect(@scan_result, pretty: true, limit: 50)}</pre>
            <% else %>
              <div class="text-gray-500">No results yet</div>
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

  defp cap_events(list) do
    max = 200
    if length(list) > max, do: Enum.take(list, -max), else: list
  end

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
end
