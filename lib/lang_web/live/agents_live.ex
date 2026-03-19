defmodule LangWeb.AgentsLive do
  use LangWeb, :live_view
  require Logger

  alias Phoenix.PubSub
  alias Lang.LSP.PhoenixIntegration

  @topics [
    "agent:qwen",
    "agent:tasks:qwen",
    "agent:claude",
    "agent:tasks:claude",
    "agent:openai",
    "agent:tasks:openai",
    "orchestration:responses",
    "orchestration:updates",
    "lsp:diagnostics:global",
    "lsp:completions:global",
    "lsp:metrics:global",
    "lsp:clients:global"
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Agents Dashboard")
      |> assign(:lsp_clients, %{})
      |> assign(:agents, %{})
      |> assign(:events_buffer, [])
      |> assign(:filter, %{agent: "all", session_id: "", workspace_id: ""})
      |> assign(:form, to_form(%{agent: "all", session_id: "", workspace_id: ""}, as: :filter))
      |> assign(:subscribed_streams, MapSet.new())
      |> assign(:stream_buffers, %{})
      |> assign(:stream_form, to_form(%{stream_id: ""}, as: :stream))
      |> assign(:stats, %{events: 0, tasks: 0, responses: 0})
      |> stream_configure(:events, dom_id: &event_dom_id/1)
      |> stream(:events, [])

    if connected?(socket) do
      Enum.each(@topics, &safe_subscribe/1)
      # Prime with current LSP clients
      {:ok, _} = schedule_refresh()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, socket}

  # Orchestration updates
  @impl true
  def handle_info({:job_completed, job_id}, socket) do
    {:noreply,
     socket
     |> bump(:events)
     |> stream_insert(:events, %{type: :orchestration, event: :job_completed, id: job_id, at: now()})}
  end

  def handle_info({:job_failed, job_id, error}, socket) do
    {:noreply,
     socket
     |> bump(:events)
     |> stream_insert(:events, %{type: :orchestration, event: :job_failed, id: job_id, error: inspect(error), at: now()})}
  end

  # Qwen task assignment
  def handle_info({:task_assignment, msg}, socket) do
    {session_id, workspace_id} = get_tags(msg)
    {:noreply,
     socket
     |> bump(:events)
     |> bump(:tasks)
     |> put_agent(agent_name(msg), :active)
     |> insert_event(%{type: :agent, agent: agent_name(msg), event: :task_assignment, session_id: session_id, workspace_id: workspace_id, msg: redact(msg), at: now()})}
  end

  # Generic agent responses
  def handle_info({:agent_response, message_id, result}, socket) do
    {session_id, workspace_id} = get_tags(result[:ctx] || %{})
    agent = result[:agent] || :qwen
    {:noreply,
     socket
     |> bump(:events)
     |> bump(:responses)
     |> insert_event(%{type: :agent, agent: agent, event: :response, id: message_id, session_id: session_id, workspace_id: workspace_id, result: redact(result), at: now()})}
  end

  # LSP diagnostics & completions
  def handle_info(%{uri: uri, diagnostics: diags} = _evt, socket) do
    {:noreply,
     socket
     |> bump(:events)
     |> insert_event(%{type: :lsp, event: :diagnostics, uri: uri, count: length(diags), at: now()})}
  end

  def handle_info(%{uri: uri, position: pos, completions: list} = _evt, socket) do
    {:noreply,
     socket
     |> bump(:events)
     |> insert_event(%{type: :lsp, event: :completions, uri: uri, at: now(), count: length(list), position: pos})}
  end

  # LSP client lifecycle/activity (via Ash PubSub transform)
  def handle_info(%{type: type, payload: payload, at: at}, socket)
      when type in [:connected, :initialized, :disconnected, :activity] do
    {clients, ev} = update_clients(socket.assigns.lsp_clients, type, payload, at)
    {:noreply, socket |> assign(:lsp_clients, clients) |> insert_event(ev)}
  end

  # LSP metrics (request/response/connection) via Ash PubSub transform
  def handle_info(%{event: event} = evt, socket) do
    formatted =
      case event do
        :request -> %{type: :lsp, event: :request, method: get_in(evt, [:metadata, :method]), duration: get_in(evt, [:measurements, :duration]), at: evt.at}
        :response -> %{type: :lsp, event: :response, method: get_in(evt, [:metadata, :method]), duration: get_in(evt, [:measurements, :duration]), at: evt.at}
        :connection -> %{type: :lsp, event: :connection, action: get_in(evt, [:metadata, :action]), count: get_in(evt, [:measurements, :client_count]), at: evt.at}
        _ -> nil
      end

    if formatted do
      {:noreply, socket |> bump(:events) |> insert_event(formatted)}
    else
      {:noreply, socket}
    end
  end

  # Analysis stream events (dynamic topics)
  def handle_info(%{stream_id: sid, complete: true} = evt, socket) do
    socket = append_stream_event(socket, sid, %{type: :stream_complete, uri: evt[:uri], at: now()})
    {:noreply, socket}
  end

  def handle_info(%{stream_id: sid, chunk: chunk, index: idx} = evt, socket) do
    socket = append_stream_event(socket, sid, %{type: :stream_chunk, index: idx, count: (chunk[:items] || []) |> length(), uri: evt[:uri], at: now()})
    {:noreply, socket}
  end

  # Subscribe to analysis stream
  @impl true
  def handle_event("stream_subscribe", %{"stream" => %{"stream_id" => sid}}, socket) do
    sid = String.trim(to_string(sid))
    socket =
      if sid != "" do
        topic = "lsp:analysis_stream:" <> sid
        _ = safe_subscribe(topic)
        assign(socket, :subscribed_streams, MapSet.put(socket.assigns.subscribed_streams, sid))
      else
        socket
      end

    {:noreply, socket}
  end

  # Filtering controls --------------------------------------------------------
  @impl true
  def handle_event("filter_change", %{"filter" => params}, socket) do
    filt = %{
      agent: Map.get(params, "agent", "all"),
      session_id: Map.get(params, "session_id", ""),
      workspace_id: Map.get(params, "workspace_id", "")
    }

    socket = assign(socket, filter: filt, form: to_form(params, as: :filter))
    {:noreply, refresh_stream(socket)}
  end

  # Default catch-all
  def handle_info(_msg, socket), do: {:noreply, socket}

  # Helpers ------------------------------------------------------------------
  defp safe_subscribe(topic) do
    # Try both Ash (Endpoint) and direct PubSub buses
    _ = try do PubSub.subscribe(LangWeb.Endpoint, topic) rescue _ -> :ok end
    _ = try do PubSub.subscribe(Lang.PubSub, topic) rescue _ -> :ok end
    :ok
  end

  defp schedule_refresh do
    {:ok, Process.send_after(self(), :refresh, 2_000)}
  end

  defp safe_list_clients do
    try do
      PhoenixIntegration.list_clients()
      |> Enum.map(fn {socket, pid, info} -> %{sock: inspect(socket), pid: inspect(pid), info: info} end)
    rescue
      _ -> []
    end
  end

  defp bump(socket, key) do
    update(socket, :stats, fn s -> Map.update!(s, key, &(&1 + 1)) end)
  end

  defp put_agent(socket, name, status) do
    update(socket, :agents, fn agents -> Map.put(agents, name, %{status: status, updated_at: now()}) end)
  end

  defp now, do: DateTime.utc_now()
  defp redact(data), do: data
  defp event_dom_id(e), do: "evt-" <> :erlang.phash2(e) |> Integer.to_string()

  defp agent_name(%{to_agent: name}) when is_binary(name), do: String.to_atom(name)
  defp agent_name(%{"to_agent" => name}) when is_binary(name), do: String.to_atom(name)
  defp agent_name(_), do: :agent

  defp get_tags(map) when is_map(map) do
    session_id = Map.get(map, :session_id) || Map.get(map, "session_id")
    workspace_id = Map.get(map, :workspace_id) || Map.get(map, "workspace_id")
    {session_id, workspace_id}
  end

  defp update_clients(clients, :connected, %{client_id: id, connected_at: ts, label: label}, at) do
    meta = %{
      client_id: id,
      label: label,
      connected_at: ts,
      request_count: 0,
      methods: %{},
      last_seen: at
    }

    {Map.put(clients, id, meta), %{type: :lsp, event: :client_connected, client_id: id, label: label, at: at}}
  end

  defp update_clients(clients, :initialized, %{client_id: id}, at) do
    meta = Map.update(clients[id] || %{}, :initialized, true, fn _ -> true end)
    {Map.put(clients, id, Map.merge(clients[id] || %{}, %{initialized: true, last_seen: at})), %{type: :lsp, event: :client_initialized, client_id: id, at: at}}
  end

  defp update_clients(clients, :activity, %{client_id: id, method: method} = payload, at) do
    meta = clients[id] || %{client_id: id, methods: %{}, request_count: 0}
    methods = Map.update(meta[:methods] || %{}, method, 1, &(&1 + 1))
    meta = meta |> Map.put(:methods, methods) |> Map.put(:request_count, (meta[:request_count] || 0) + 1) |> Map.put(:last_seen, at)
    {Map.put(clients, id, meta), %{type: :lsp, event: :client_activity, client_id: id, method: method, duration_ms: payload[:duration_ms], at: at}}
  end

  defp update_clients(clients, :activity, %{client_id: id, activity: :identify, label: label}, at) do
    meta = Map.merge(clients[id] || %{}, %{label: label, last_seen: at})
    {Map.put(clients, id, meta), %{type: :lsp, event: :client_identify, client_id: id, label: label, at: at}}
  end

  defp update_clients(clients, :disconnected, %{client_id: id, duration_s: dur, request_count: cnt, methods: methods}, at) do
    {Map.delete(clients, id), %{type: :lsp, event: :client_disconnected, client_id: id, duration_s: dur, request_count: cnt, methods: methods, at: at}}
  end

  # Buffer + streaming helpers ----------------------------------------------
  defp insert_event(socket, evt) do
    buf = [evt | (socket.assigns.events_buffer || [])] |> Enum.take(300)
    socket = assign(socket, :events_buffer, buf)
    refresh_stream(socket)
  end

  defp refresh_stream(%{assigns: %{events_buffer: buf, filter: filt}} = socket) do
    filtered =
      buf
      |> Enum.filter(&matches_filter?(&1, filt))

    socket
    |> stream(:events, filtered, reset: true)
  end

  defp matches_filter?(evt, %{agent: agent, session_id: sid, workspace_id: wid}) do
    agent_ok =
      case agent do
        "all" -> true
        a when is_binary(a) -> to_string(Map.get(evt, :agent, "")) == a
        _ -> true
      end

    sid_ok = sid in [nil, ""] or (to_string(Map.get(evt, :session_id, "")) == sid)
    wid_ok = wid in [nil, ""] or (to_string(Map.get(evt, :workspace_id, "")) == wid)

    agent_ok and sid_ok and wid_ok
  end

  defp append_stream_event(socket, sid, event) do
    buf = socket.assigns.stream_buffers || %{}
    list = [event | Map.get(buf, sid, [])] |> Enum.take(100)
    assign(socket, :stream_buffers, Map.put(buf, sid, list))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dev_app flash={@flash}>
      <div id="agents-dashboard" class="p-4 space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">Agents Dashboard</h1>
          <div class="flex items-center gap-3">
            <a href="/dev/auth/impersonate/dev@lang.test?name=Dev%20User&return_to=/dev/agents"
               class="px-2 py-1 text-xs rounded bg-zinc-800 text-white hover:bg-zinc-700">Impersonate dev@lang.test</a>
            <div class="text-sm text-zinc-500">Events: {@stats.events} · Tasks: {@stats.tasks} · Responses: {@stats.responses}</div>
          </div>
        </div>

        <div class="border rounded p-3">
          <h2 class="font-medium mb-2">Filters</h2>
          <.form for={@form} id="agents-filter" phx-change="filter_change">
            <div class="grid grid-cols-1 md:grid-cols-4 gap-3">
              <div>
                <label class="text-xs text-zinc-600">Agent</label>
                <select name="filter[agent]" class="w-full border rounded px-2 py-1 text-sm">
                  <option value="all" selected={@filter.agent == "all"}>All</option>
                  <option value="qwen" selected={@filter.agent == "qwen"}>Qwen</option>
                  <option value="claude" selected={@filter.agent == "claude"}>Claude</option>
                  <option value="openai" selected={@filter.agent == "openai"}>OpenAI</option>
                </select>
              </div>
              <div>
                <label class="text-xs text-zinc-600">Session ID</label>
                <input type="text" name="filter[session_id]" value={@filter.session_id} class="w-full border rounded px-2 py-1 text-sm" placeholder="optional" />
              </div>
              <div>
                <label class="text-xs text-zinc-600">Workspace ID</label>
                <input type="text" name="filter[workspace_id]" value={@filter.workspace_id} class="w-full border rounded px-2 py-1 text-sm" placeholder="optional" />
              </div>
            </div>
          </.form>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="border rounded p-3">
            <h2 class="font-medium mb-2">Active Agents</h2>
            <div :for={{name, info} <- @agents} id={"agent-" <> to_string(name)} class="flex items-center justify-between py-1">
              <div class="font-mono">{to_string(name)}</div>
              <div class={[
                "text-xs px-2 py-0.5 rounded",
                info.status == :active && "bg-green-100 text-green-700",
                info.status != :active && "bg-zinc-100 text-zinc-700"
              ]}>{to_string(info.status)}</div>
            </div>
            <div :if={map_size(@agents) == 0} class="text-sm text-zinc-500">No agent activity yet</div>
          </div>

          <div class="border rounded p-3">
            <h2 class="font-medium mb-2">LSP Clients</h2>
            <div class="text-sm text-zinc-500 mb-2">{map_size(@lsp_clients)} connected</div>
            <div id="lsp-clients-grid" class="grid grid-cols-1 md:grid-cols-4 gap-3">
              <div :for={{_id, c} <- @lsp_clients} class="border rounded p-2 bg-white shadow-sm">
                <div class="flex items-center justify-between">
                  <div class="font-mono text-xs truncate">{c.label || c.client_id || "client"}</div>
                  <div class="text-[10px] text-zinc-500">{time_ago(c.connected_at)}</div>
                </div>
                <div class="mt-1 text-[11px] text-zinc-600">Reqs: {c.request_count || 0}</div>
                <div class="mt-1 text-[11px] text-zinc-600">Top funcs:
                  <%= for {m, n} <- top_methods(c.methods || %{}, 3) do %>
                    <span class="inline-block mr-1">{shorten(m)}({n})</span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <div class="border rounded p-3">
            <h2 class="font-medium mb-2">Quick Actions</h2>
            <div class="text-sm text-zinc-600">Open your editor and send `lang.onboard` or start a chat session to see events stream in.</div>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="border rounded p-3">
            <h2 class="font-medium mb-2">Analysis Streams</h2>
            <.form for={@stream_form} id="stream-subscribe" phx-submit="stream_subscribe">
              <div class="flex gap-2 items-end">
                <div class="flex-1">
                  <label class="text-xs text-zinc-600">Stream ID</label>
                  <input type="text" name="stream[stream_id]" value={@stream_form[:stream_id].value || ""} class="w-full border rounded px-2 py-1 text-sm" placeholder="analysis_123" />
                </div>
                <button class="px-3 py-1 text-xs bg-zinc-800 text-white rounded">Subscribe</button>
              </div>
            </.form>

            <div class="mt-3">
              <div class="text-xs text-zinc-500 mb-1">Active Streams: {MapSet.size(@subscribed_streams)}</div>
              <div class="space-y-2">
                <div :for={sid <- @subscribed_streams} class="border rounded p-2">
                  <div class="text-xs font-mono mb-1">{sid}</div>
                  <div class="max-h-40 overflow-auto text-[11px] font-mono">
                    <div :for={e <- (@stream_buffers[sid] || [])} class="truncate">{inspect(e)}</div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="border rounded p-3">
            <h2 class="font-medium mb-2">Mock Services</h2>
            <div class="grid grid-cols-3 gap-2 text-xs">
              <div class="border rounded p-2">
                <div class="font-medium">SSH Proxy</div>
                <div class="text-zinc-600">{mock_status(:ssh)}</div>
              </div>
              <div class="border rounded p-2">
                <div class="font-medium">MCP WS</div>
                <div class="text-zinc-600">{mock_status(:mcp_ws)}</div>
              </div>
              <div class="border rounded p-2">
                <div class="font-medium">Other</div>
                <div class="text-zinc-600">{mock_status(:other)}</div>
              </div>
            </div>
          </div>
        </div>

        <div class="border rounded p-3">
          <h2 class="font-medium mb-2">Recent Events</h2>
          <div id="events" phx-update="stream" class="space-y-1 text-xs">
            <div :for={{id, e} <- @streams.events} id={id} class="font-mono truncate">
              {format_event(e)}
            </div>
          </div>
          <div class="text-xs text-zinc-500">Most recent on top</div>
        </div>
      </div>
    </Layouts.dev_app>
    """
  end

  defp format_event(%{type: :agent, agent: who, event: :task_assignment} = _e), do: "agent:" <> to_string(who) <> " assigned task"
  defp format_event(%{type: :agent, agent: who, event: :response}), do: "agent:" <> to_string(who) <> " response"
  defp format_event(%{type: :lsp, event: :diagnostics, uri: uri, count: n}), do: "lsp:diagnostics #{n} for #{uri}"
  defp format_event(%{type: :lsp, event: :completions, uri: uri, count: n}), do: "lsp:completions #{n} for #{uri}"
  defp format_event(%{type: :lsp, event: :client_connected, client_id: id}), do: "lsp:client connected #{id}"
  defp format_event(%{type: :lsp, event: :client_initialized, client_id: id}), do: "lsp:client initialized #{id}"
  defp format_event(%{type: :lsp, event: :client_activity, client_id: id, method: m}), do: "lsp:client #{id} #{shorten(m)}"
  defp format_event(%{type: :lsp, event: :client_disconnected, client_id: id}), do: "lsp:client disconnected #{id}"
  defp format_event(%{type: :orchestration, event: :job_completed, id: id}), do: "job completed #{id}"
  defp format_event(%{type: :orchestration, event: :job_failed, id: id}), do: "job failed #{id}"
  defp format_event(_), do: "event"

  defp top_methods(methods, k) do
    methods
    |> Enum.sort_by(fn {_m, n} -> -n end)
    |> Enum.take(k)
  end

  defp time_ago(nil), do: ""
  defp time_ago(%DateTime{} = dt) do
    sec = DateTime.diff(DateTime.utc_now(), dt)
    format_secs(sec)
  end
  defp time_ago(_iso) do
    ""
  end

  defp format_secs(s) when s < 60, do: "#{s}s"
  defp format_secs(s) when s < 3600, do: "#{div(s,60)}m"
  defp format_secs(s), do: "#{div(s,3600)}h"

  defp shorten(nil), do: ""
  defp shorten(m) when is_binary(m) do
    case String.split(m, "/") do
      [a, b] -> a <> "/" <> String.slice(b, 0, 8)
      _ -> String.slice(m, 0, 16)
    end
  end

  defp mock_status(_), do: "mocked"
end
