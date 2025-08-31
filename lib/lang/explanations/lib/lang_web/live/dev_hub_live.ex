defmodule LangWeb.DevHubLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    _ = Lang.Dev.Metrics.ensure_started()
    socket = assign(socket, :page_title, "Developer Hub")
    if connected?(socket) do
      :timer.send_interval(2_000, :tick)
    end
    {:ok,
     socket
     |> assign(:metrics, fetch_metrics())
     |> assign(:method_counts, fetch_method_counts(15))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dev_app flash={@flash}>
      <div class="p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-semibold">Developer Hub</h1>
          <a href="/dev/auth/impersonate/dev@lang.test?name=Dev%20User&return_to=/dev/test" class="px-2 py-1 text-xs rounded bg-zinc-800 text-white hover:bg-zinc-700">Impersonate dev@lang.test</a>
        </div>
        <p class="text-sm text-zinc-500">DEV ONLY. Tools for rapid, contract-first testing of Codex API Blueprint flows.</p>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <a href="/dev/jsonld" class="border rounded p-4 hover:bg-zinc-50 block">
            <div class="font-medium">JSON‑LD Runner</div>
            <div class="text-sm text-zinc-500">Run whitelisted lds:actions and inspect results/events.</div>
          </a>

          <a href="/dev/agents" class="border rounded p-4 hover:bg-zinc-50 block">
            <div class="font-medium">Agents Dashboard</div>
            <div class="text-sm text-zinc-500">Stream LSP/agent events, inspect activity.</div>
          </a>

          <a href="/dev/lsp" class="border rounded p-4 hover:bg-zinc-50 block">
            <div class="font-medium">LSP Editor</div>
            <div class="text-sm text-zinc-500">Track LSP method progress and specs.</div>
          </a>

          <a href="/dev/proxy/terminal" class="border rounded p-4 hover:bg-zinc-50 block">
            <div class="font-medium">Proxy Terminal</div>
            <div class="text-sm text-zinc-500">Mint WS tickets and attach to upstream sessions.</div>
          </a>

          <a href="/dev/lsp/traces" class="border rounded p-4 hover:bg-zinc-50 block">
            <div class="font-medium">LSP Traces</div>
            <div class="text-sm text-zinc-500">Start/stop taps and inspect method traffic.</div>
          </a>
          <a href="/dev/nif" class="border rounded p-4 hover:bg-zinc-50 block">
            <div class="font-medium">NIF Health</div>
            <div class="text-sm text-zinc-500">Quick preview and analysis timings with native NIFs.</div>
          </a>
          <a href="/dev/examples" class="border rounded p-4 hover:bg-zinc-50 block">
            <div class="font-medium">JSON‑LD Examples</div>
            <div class="text-sm text-zinc-500">Browse and copy from priv/dev/jsonld</div>
          </a>
          <div class="border rounded p-4">
            <div class="font-medium mb-1">Live Metrics (2s)</div>
            <div class="text-sm text-zinc-600">
              Diagnostics: {@metrics.counts.diagnostics} · Completions: {@metrics.counts.completions}
            </div>
            <div class="text-sm text-zinc-600">
              Analysis: {@metrics.counts.analysis_scan} · LSP Client: {@metrics.counts.lsp_client} · LSP Metrics: {@metrics.counts.lsp_metrics}
            </div>
            <div class="mt-2 text-xs text-zinc-500">Up: {@metrics.uptime_seconds}s</div>
            <div class="mt-2 text-xs text-zinc-500">
              API: <code>/dev/api/metrics/summary</code>, <code>/dev/api/metrics/lsp</code>, <code>/dev/api/metrics/nif</code>
            </div>
            <div class="mt-2">
              <div class="font-medium text-sm mb-1">Top Methods (15m)</div>
              <div class="flex flex-wrap gap-2">
                <span :for={m <- @method_counts} class="text-[11px] px-2 py-0.5 rounded bg-zinc-800 text-white">{m.method} ({m.count})</span>
              </div>
              <div class="mt-1 text-xs text-zinc-500">API: <code>/dev/api/lsp/methods?minutes=15</code> · Heartbeat: <code>/dev/api/lsp/heartbeat</code></div>
            </div>
          </div>

          <a href="/dev/agents-doc" class="border rounded p-4 hover:bg-zinc-50 block">
            <div class="font-medium">Agents Guide</div>
            <div class="text-sm text-zinc-500">Open AGENTS.md (dev-only) in a convenient viewer.</div>
          </a>
        </div>
      </div>
    </Layouts.dev_app>
    """
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, socket |> assign(:metrics, fetch_metrics()) |> assign(:method_counts, fetch_method_counts(15))}
  end

  defp fetch_metrics do
    case Lang.Dev.Metrics.summary() do
      {:ok, data} -> data
      %{counts: _} = data -> data
      _ -> %{counts: %{diagnostics: 0, completions: 0, analysis_scan: 0, lsp_client: 0, lsp_metrics: 0}, uptime_seconds: 0}
    end
  end

  defp fetch_method_counts(minutes) do
    import Ash.Query
    from = DateTime.add(DateTime.utc_now(), -minutes * 60, :second)
    case Lang.LSP.Events.MetricEvent |> filter(at >= ^from) |> Ash.read() do
      {:ok, events} ->
        events
        |> Enum.filter(&match?(%{event: :request}, &1) or match?(%{event: :response}, &1))
        |> Enum.map(&get_in(&1, [:metadata, :method]))
        |> Enum.reject(&is_nil/1)
        |> Enum.group_by(& &1)
        |> Enum.map(fn {m, list} -> %{method: m, count: length(list)} end)
        |> Enum.sort_by(& &1.count, :desc)
        |> Enum.take(8)
      _ -> []
    end
  end
end
