defmodule LangWeb.SwarmShowLive do
  use LangWeb, :live_view
  alias Lang.Agent.Swarm
  alias Lang.Agent.Agent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Swarm")
     |> assign(:swarm, nil)
     |> assign(:loading, true)
     |> assign(:error, nil)
     |> assign(:agents_paging, %{page: 1, page_size: 20, sort: :name, dir: :asc})
     |> assign(:agent_filters, %{state: "", min_trust: ""})
     |> assign(:export_ready, nil)
     |> assign(:signed_link, nil)}
  end

  @impl true
  def handle_params(%{"swarm_id" => swarm_id}, _url, socket) do
    {:noreply, load_swarm(socket, swarm_id)}
  end

  @impl true
  def handle_event("quarantine_agent", %{"agent_id" => agent_id}, socket) do
    _ =
      try do
        with {:ok, agent} <- get_agent(socket.assigns.swarm, agent_id) do
          Ash.update(agent, %{reason: "manual", severity: :medium}, action: :quarantine)
        end
      rescue
        _ -> :ok
      end

    {:noreply,
     socket
     |> put_flash(:info, "Agent quarantined")
     |> reload()}
  end

  def handle_event("trust_up", %{"agent_id" => agent_id}, socket) do
    adjust_trust(socket, agent_id, 0.1)
  end

  def handle_event("trust_down", %{"agent_id" => agent_id}, socket) do
    adjust_trust(socket, agent_id, -0.1)
  end

  def handle_event("bulk_quarantine", _params, socket) do
    count = length(socket.assigns.swarm.agents || [])
    Enum.each(socket.assigns.swarm.agents || [], fn agent ->
      safe_quarantine(agent)
    end)
    {:noreply,
     socket
     |> put_flash(:info, "Quarantined #{count} agents")
     |> reload()}
  end

  def handle_event("bulk_trust_up", _params, socket) do
    Enum.each(socket.assigns.swarm.agents || [], fn agent ->
      safe_adjust_trust(agent, 0.1)
    end)
    {:noreply, socket |> put_flash(:info, "Increased trust for all agents") |> reload()}
  end

  def handle_event("bulk_trust_down", _params, socket) do
    Enum.each(socket.assigns.swarm.agents || [], fn agent ->
      safe_adjust_trust(agent, -0.1)
    end)
    {:noreply, socket |> put_flash(:info, "Decreased trust for all agents") |> reload()}
  end

  def handle_event("export_agents_csv", _params, socket) do
    data = socket.assigns.swarm.agents || []
    csv = build_agents_csv(data)
    {:noreply, Phoenix.LiveView.send_download(socket, {:binary, csv}, filename: "swarm_" <> socket.assigns.swarm.swarm_id <> "_agents.csv", content_type: "text/csv")}
  end

  def handle_event("export_agents_json", _params, socket) do
    data = socket.assigns.swarm.agents || []
    json = Jason.encode_to_iodata!(Enum.map(data, &agent_json_map/1))
    {:noreply, Phoenix.LiveView.send_download(socket, {:binary, IO.iodata_to_binary(json)}, filename: "swarm_" <> socket.assigns.swarm.swarm_id <> "_agents.json", content_type: "application/json")}
  end

  def handle_event("export_agents_ndjson_bg", _params, socket) do
    export_id = new_export_id()
    if connected?(socket), do: Phoenix.PubSub.subscribe(Lang.PubSub, "exports:#{export_id}")

    filters = socket.assigns.agent_filters
    swarm_id = socket.assigns.swarm.swarm_id
    _ =
      if Code.ensure_loaded?(Oban) do
        args = %{"kind" => "agents", "format" => "ndjson", "export_id" => export_id, "swarm_id" => swarm_id, "filters" => filters}
        job = %{args: args}
        try do
          Oban.insert(Lang.Repo, Oban.Job.new(job, queue: :metrics, worker: Lang.Workers.SwarmExportWorker))
        rescue
          _ -> :ok
        end
      end

    {:noreply, socket |> put_flash(:info, "Agents export started")}
  end

  @impl true
  def handle_info({:export_ready, export_id}, socket) do
    {:noreply, assign(socket, :export_ready, export_id) |> put_flash(:info, "Export ready to download")}
  end

  def handle_event("make_signed_link", _params, socket) do
    case socket.assigns.export_ready do
      nil -> {:noreply, socket |> put_flash(:error, "No export id yet")}
      id ->
        exp = System.os_time(:second) + 600
        secret = System.get_env("EXPORTS_SIGNING_SECRET") || System.get_env("SECRET_KEY_BASE") || ""
        sig = :crypto.mac(:hmac, :sha256, secret, id <> ":" <> to_string(exp)) |> Base.url_encode64(padding: false)
        link = "/dl/exports/" <> id <> "?sig=" <> sig <> "&exp=" <> to_string(exp)
        {:noreply, assign(socket, :signed_link, link) |> put_flash(:info, "Signed link created")}
    end
  end

  def handle_event("agents_set_page", %{"dir" => dir}, socket) when dir in ["prev", "next"] do
    %{page: page} = socket.assigns.agents_paging
    new_page = max(1, page + if(dir == "next", do: 1, else: -1))
    {:noreply, assign(socket, :agents_paging, %{socket.assigns.agents_paging | page: new_page}) |> reload()}
  end

  def handle_event("agents_set_page_size", %{"size" => size}, socket) do
    size = parse_int(size, 20) |> clamp(5, 100)
    {:noreply, assign(socket, :agents_paging, %{socket.assigns.agents_paging | page_size: size, page: 1}) |> reload()}
  end

  def handle_event("agents_set_sort", %{"sort" => sort, "dir" => dir}, socket) do
    sort = to_agent_sort_atom(sort)
    dir = to_dir_atom(dir)
    {:noreply, assign(socket, :agents_paging, %{socket.assigns.agents_paging | sort: sort, dir: dir, page: 1}) |> reload()}
  end

  def handle_event("agents_filter", %{"filters" => %{"state" => st, "min_trust" => mt}}, socket) do
    {:noreply,
     socket
     |> assign(:agent_filters, %{state: st, min_trust: mt})
     |> assign(:agents_paging, %{socket.assigns.agents_paging | page: 1})
     |> reload()}
  end

  defp adjust_trust(socket, agent_id, delta) do
    _ =
      try do
        with {:ok, agent} <- get_agent(socket.assigns.swarm, agent_id) do
          do_adjust_trust(agent, delta)
        end
      rescue
        _ -> :ok
      end

    {:noreply,
     socket
     |> put_flash(:info, if(delta > 0, do: "Trust increased", else: "Trust decreased"))
     |> reload()}
  end

  defp reload(socket), do: load_swarm(socket, socket.assigns.swarm.swarm_id)

  defp load_swarm(socket, swarm_id) do
    with {:ok, [swarm]} <- Swarm |> Ash.Query.for_read(:by_swarm_id, %{swarm_id: swarm_id}) |> Ash.read() do
      # Load paginated agents
      %{page: page, page_size: size, sort: sort, dir: dir} = socket.assigns.agents_paging
      offset = (page - 1) * size
      base = Agent |> Ash.Query.for_read(:by_swarm, %{swarm_id: swarm.id})
      filtered = apply_agent_filters(base, socket.assigns.agent_filters)
      agents =
        case filtered
             |> Ash.Query.sort([{dir, sort}])
             |> Ash.Query.limit(size)
             |> Ash.Query.offset(offset)
             |> Ash.read() do
          {:ok, list} -> list
          _ -> []
        end

      socket
      |> assign(:swarm, %{swarm | agents: agents})
      |> assign(:loading, false)
      |> assign(:error, nil)
    else
      {:ok, []} -> socket |> assign(:error, "Swarm not found") |> assign(:loading, false)
      {:error, reason} -> socket |> assign(:error, inspect(reason)) |> assign(:loading, false)
    end
  end

  defp get_agent(%{agents: agents}, id) when is_list(agents) do
    case Enum.find(agents, &(&1.id == id)) do
      nil -> {:error, :not_found}
      a -> {:ok, a}
    end
  end

  defp safe_quarantine(agent) do
    try do
      Ash.update(agent, %{reason: "manual", severity: :medium}, action: :quarantine)
    rescue
      _ -> :ok
    end
  end

  defp safe_adjust_trust(agent, delta) do
    try do
      do_adjust_trust(agent, delta)
    rescue
      _ -> :ok
    end
  end

  defp do_adjust_trust(agent, delta) do
    current = agent.trust_score || Decimal.new("0.0")
    new_score = Decimal.add(current, Decimal.new(delta))
    Ash.update(agent, %{new_score: new_score, reason: "manual adjustment"}, action: :update_trust_score)
  end

  defp build_agents_csv(list) do
    header = "id,name,state,session_id,trust_score,capabilities\n"
    rows =
      Enum.map(list, fn a ->
        caps = a.capabilities || [] |> Enum.join("; ") |> escape_csv()
        id = escape_csv(a.id)
        name = escape_csv(a.name)
        state = escape_csv(to_string(a.state))
        session = escape_csv(a.session_id || "")
        trust = escape_csv(to_string(a.trust_score || Decimal.new("0.0")))
        Enum.join([id, name, state, session, trust, caps], ",") <> "\n"
      end)
      |> Enum.join("")

    header <> rows
  end

  defp escape_csv(nil), do: ""
  defp escape_csv(val) do
    s = to_string(val)
    if String.contains?(s, [",", "\"", "\n"]) do
      "\"" <> String.replace(s, "\"", "\"\"") <> "\""
    else
      s
    end
  end

  defp agent_json_map(a) do
    %{
      id: a.id,
      name: a.name,
      state: a.state,
      session_id: a.session_id,
      trust_score: a.trust_score,
      capabilities: a.capabilities
    }
  end

  defp new_export_id do
    "exp_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end

  defp parse_int(v, default) do
    case Integer.parse(to_string(v)) do
      {n, _} -> n
      _ -> default
    end
  end
  defp clamp(n, min, max), do: max(min, min(max, n))
  defp to_agent_sort_atom("name"), do: :name
  defp to_agent_sort_atom("state"), do: :state
  defp to_agent_sort_atom("trust_score"), do: :trust_score
  defp to_agent_sort_atom(_), do: :name
  defp to_dir_atom("asc"), do: :asc
  defp to_dir_atom(_), do: :desc

  defp apply_agent_filters(query, %{state: st, min_trust: mt}) do
    import Ash.Query
    q =
      case String.trim(st) do
        "" -> query
        state -> filter(query, state == ^String.to_atom(state))
      end

    with {minf, _} <- Float.parse(to_string(mt)), true <- minf >= 0.0 do
      filter(q, trust_score >= ^Decimal.from_float(minf))
    else
      _ -> q
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="space-y-6">
        <.link navigate={~p"/agents/swarms"} class="text-sm text-blue-600 hover:underline">← Back</.link>
        <%= if @error do %>
          <div class="text-red-600"><%= @error %></div>
        <% else %>
          <%= if @loading or is_nil(@swarm) do %>
            <div>Loading...</div>
          <% else %>
            <div class="flex items-center justify-between">
              <h1 class="text-2xl font-semibold font-mono">swarm/<%= @swarm.swarm_id %></h1>
              <div class="flex items-center gap-2">
                <button phx-click="bulk_trust_up" phx-confirm="Increase trust for all agents?" class="px-2 py-1 text-xs rounded bg-emerald-600 text-white">+ trust all</button>
                <button phx-click="bulk_trust_down" phx-confirm="Decrease trust for all agents?" class="px-2 py-1 text-xs rounded bg-amber-600 text-white">- trust all</button>
                <button phx-click="bulk_quarantine" phx-confirm="Quarantine all agents in this swarm?" class="px-2 py-1 text-xs rounded bg-red-600 text-white">Quarantine all</button>
                <span class="text-xs px-2 py-0.5 rounded border"><%= @swarm.status %></span>
              </div>
            </div>
            <div class="text-sm text-slate-600">Goals: <%= Enum.join(@swarm.goals || [], ", ") %></div>

            <div class="mt-4 border rounded">
              <div class="px-4 py-2 font-semibold bg-slate-50 flex items-center justify-between">
                <div>Agents (<%= length(@swarm.agent_ids || []) %>)</div>
                <div class="flex items-center gap-2">
                  <.form for={to_form(@agent_filters, as: :filters)} phx-change="agents_filter" class="flex items-center gap-2">
                    <select name="filters[state]" class="px-2 py-1 border rounded text-xs">
                      <option value="" selected={@agent_filters.state == ""}>Any state</option>
                      <option value="active" selected={@agent_filters.state == "active"}>Active</option>
                      <option value="idle" selected={@agent_filters.state == "idle"}>Idle</option>
                      <option value="quarantined" selected={@agent_filters.state == "quarantined"}>Quarantined</option>
                      <option value="terminated" selected={@agent_filters.state == "terminated"}>Terminated</option>
                    </select>
                    <input type="number" step="0.1" min="0" max="1" name="filters[min_trust]" value={@agent_filters.min_trust} placeholder=":min trust" class="px-2 py-1 border rounded text-xs w-28" />
                  </.form>
                  <label class="text-xs">Sort</label>
                  <select phx-change="agents_set_sort" name="sort" class="px-2 py-1 border rounded text-xs">
                    <option value="name" selected={@agents_paging.sort == :name}>Name</option>
                    <option value="state" selected={@agents_paging.sort == :state}>State</option>
                    <option value="trust_score" selected={@agents_paging.sort == :trust_score}>Trust</option>
                  </select>
                  <select phx-change="agents_set_sort" name="dir" class="px-2 py-1 border rounded text-xs">
                    <option value="asc" selected={@agents_paging.dir == :asc}>Asc</option>
                    <option value="desc" selected={@agents_paging.dir == :desc}>Desc</option>
                  </select>
                  <label class="text-xs">Page Size</label>
                  <select phx-change="agents_set_page_size" name="size" class="px-2 py-1 border rounded text-xs">
                    <option value="10" selected={@agents_paging.page_size == 10}>10</option>
                    <option value="20" selected={@agents_paging.page_size == 20}>20</option>
                    <option value="50" selected={@agents_paging.page_size == 50}>50</option>
                  </select>
                  <button phx-click="agents_set_page" phx-value-dir="prev" class="px-2 py-1 rounded border text-xs disabled:opacity-50" disabled={@agents_paging.page <= 1}>Prev</button>
                  <div class="text-xs">Page <%= @agents_paging.page %></div>
                  <button phx-click="agents_set_page" phx-value-dir="next" class="px-2 py-1 rounded border text-xs disabled:opacity-50" disabled={length(@swarm.agents || []) < @agents_paging.page_size}>Next</button>
                  <button phx-click="export_agents_csv" class="px-2 py-1 rounded border text-xs">Export CSV</button>
                  <button phx-click="export_agents_json" class="px-2 py-1 rounded border text-xs">Export JSON</button>
                  <button phx-click="export_agents_ndjson_bg" class="px-2 py-1 rounded border text-xs">Export NDJSON (bg)</button>
                </div>
              </div>
              <div class="divide-y">
                <div :for={agent <- @swarm.agents || []} id={agent.id} class="px-4 py-3 grid grid-cols-1 md:grid-cols-6 gap-2 items-center">
                  <div class="font-mono text-xs truncate" title={agent.id}><%= agent.name %></div>
                  <div class="text-xs"><%= agent.state %></div>
                  <div class="text-xs truncate" title={Enum.join(agent.capabilities || [], ", ")}>
                    <%= Enum.join(agent.capabilities || [], ", ") %>
                  </div>
                  <div class="text-xs truncate" title={agent.session_id || "-"}><%= agent.session_id || "-" %></div>
                  <div class="text-xs">trust: <%= to_string(agent.trust_score || Decimal.new("0.0")) %></div>
                  <div class="flex gap-2">
                    <button phx-click="trust_up" phx-value-agent_id={agent.id} class="px-2 py-1 text-xs rounded bg-emerald-600 text-white">+ trust</button>
                    <button phx-click="trust_down" phx-value-agent_id={agent.id} class="px-2 py-1 text-xs rounded bg-amber-600 text-white">- trust</button>
                    <button phx-click="quarantine_agent" phx-value-agent_id={agent.id} phx-confirm="Quarantine this agent?" class="px-2 py-1 text-xs rounded bg-red-600 text-white">Quarantine</button>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
          <%= if @export_ready do %>
            <div class="mt-2 text-xs flex items-center gap-3">
              <span>Export ready:</span>
              <.link navigate={~p"/api/exports/#{@export_ready}"} class="text-blue-600 hover:underline">NDJSON</.link>
              <.link navigate={~p"/api/exports/#{@export_ready}?format=zip"} class="text-blue-600 hover:underline">ZIP</.link>
              <button phx-click="make_signed_link" class="px-2 py-1 rounded border text-xs">Make Signed Link</button>
              <%= if @signed_link do %>
                <a href={@signed_link} class="text-blue-600 hover:underline">Signed</a>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
