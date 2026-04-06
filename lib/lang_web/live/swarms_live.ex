defmodule LangWeb.SwarmsLive do
  use LangWeb, :live_view
  alias Lang.Agent.Swarm

  @impl true
  def mount(_params, _session, socket) do
    # Ensure AuthOnMount set these assigns
    filters = %{"swarm_id" => "", "coordinator_id" => "", "session_id" => ""}
    paging = %{page: 1, page_size: 20, sort: :inserted_at, dir: :desc}
    socket =
      socket
      |> assign(:page_title, "Agent Swarms")
      |> assign(:filters, filters)
      |> assign(:paging, paging)
      |> assign(:empty?, false)
      |> assign(:export_ready, nil)
      |> assign(:signed_link, nil)
      |> stream(:swarms, [])
      |> assign(:form, to_form(filters, as: :filters))

    {:ok, load_swarms(socket)}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = %{
      "swarm_id" => Map.get(params, "swarm_id", ""),
      "coordinator_id" => Map.get(params, "coordinator_id", ""),
      "session_id" => Map.get(params, "session_id", "")
    }

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:form, to_form(filters, as: :filters))
      |> put_flash(:info, "Filters applied")
      |> load_swarms()

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_swarms_csv", _params, socket) do
    data = current_swarms(socket)
    csv = build_swarms_csv(data)
    {:noreply, Phoenix.LiveView.send_download(socket, {:binary, csv}, filename: "swarms.csv", content_type: "text/csv")}
  end

  @impl true
  def handle_event("export_swarms_json", _params, socket) do
    data = current_swarms(socket)
    json = Jason.encode_to_iodata!(Enum.map(data, &swarms_json_map/1))
    {:noreply, Phoenix.LiveView.send_download(socket, {:binary, IO.iodata_to_binary(json)}, filename: "swarms.json", content_type: "application/json")}
  end

  @impl true
  def handle_event("export_swarms_ndjson_bg", _params, socket) do
    export_id = new_export_id()
    if connected?(socket), do: Phoenix.PubSub.subscribe(Lang.PubSub, "exports:#{export_id}")

    filters = socket.assigns.filters
    _ =
      if Code.ensure_loaded?(Oban) do
        args = %{"kind" => "swarms", "format" => "ndjson", "export_id" => export_id, "filters" => filters}
        job = %{args: args}
        try do
          Oban.insert(Lang.Repo, Oban.Job.new(job, queue: :metrics, worker: Lang.Workers.SwarmExportWorker))
        rescue
          _ -> :ok
        end
      end

    {:noreply, socket |> put_flash(:info, "Export started")}
  end

  @impl true
  def handle_info({:export_ready, export_id}, socket) do
    {:noreply, assign(socket, :export_ready, export_id) |> put_flash(:info, "Export ready to download")}
  end

  @impl true
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

  @impl true
  def handle_event("set_page", %{"dir" => dir}, socket) when dir in ["prev", "next"] do
    %{page: page} = socket.assigns.paging
    new_page = max(1, page + if(dir == "next", do: 1, else: -1))
    {:noreply, socket |> update(:paging, &Map.put(&1, :page, new_page)) |> load_swarms()}
  end

  def handle_event("set_page_size", %{"size" => size}, socket) do
    size = parse_int(size, 20) |> clamp(5, 100)
    {:noreply, socket |> assign(:paging, %{socket.assigns.paging | page_size: size, page: 1}) |> load_swarms()}
  end

  def handle_event("set_sort", %{"sort" => sort, "dir" => dir}, socket) do
    sort = to_sort_atom(sort)
    dir = to_dir_atom(dir)
    {:noreply, socket |> assign(:paging, %{socket.assigns.paging | sort: sort, dir: dir, page: 1}) |> load_swarms()}
  end

  defp load_swarms(%{assigns: %{filters: f, paging: p}} = socket) do
    swarms =
      cond do
        present?(f["swarm_id"]) -> read_by_swarm_id(f["swarm_id"]) |> apply_sort(p) 
        present?(f["coordinator_id"]) -> read_by_coordinator(f["coordinator_id"]) |> apply_sort(p)
        present?(f["session_id"]) -> read_by_session(f["session_id"]) |> apply_sort(p)
        true -> read_recent(p)
      end

    socket
    |> assign(:empty?, Enum.empty?(swarms))
    |> stream(:swarms, swarms, reset: true)
  end

  defp present?(val) when is_binary(val), do: String.trim(val) != ""
  defp present?(_), do: false

  defp read_by_swarm_id(swarm_id) do
    case Swarm |> Ash.Query.for_read(:by_swarm_id, %{swarm_id: swarm_id}) |> Ash.Query.load(:agents) |> Ash.read() do
      {:ok, [swarm]} -> [swarm]
      _ -> []
    end
  end

  defp read_by_coordinator(coord) do
    case Swarm |> Ash.Query.for_read(:by_coordinator, %{coordinator_id: coord}) |> Ash.Query.load(:agents) |> Ash.read() do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp read_by_session(session_id) do
    case Swarm |> Ash.Query.for_read(:by_session, %{session_id: session_id}) |> Ash.Query.load(:agents) |> Ash.read() do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp read_recent(%{page: page, page_size: size, sort: sort, dir: dir}) do
    offset = (page - 1) * size
    case Swarm
         |> Ash.Query.sort([{dir, sort}])
         |> Ash.Query.limit(size)
         |> Ash.Query.offset(offset)
         |> Ash.Query.load(:agents)
         |> Ash.read() do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp current_swarms(socket) do
    # Use what is currently shown (streams) for exact WYSIWYG export
    socket.assigns.streams.swarms
    |> Enum.map(fn {_id, s} -> s end)
  end

  defp build_swarms_csv(list) do
    header = "swarm_id,status,goals,agent_count,coordinator_id,inserted_at\n"
    rows =
      Enum.map(list, fn s ->
        goals = s.goals || [] |> Enum.join("; ") |> escape_csv()
        swarm_id = escape_csv(s.swarm_id)
        status = escape_csv(to_string(s.status))
        agent_count = Integer.to_string(length(s.agent_ids || []))
        coord = escape_csv(s.coordinator_id || "")
        inserted = escape_csv(to_string(s.inserted_at))
        Enum.join([swarm_id, status, goals, agent_count, coord, inserted], ",") <> "\n"
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

  defp swarms_json_map(s) do
    %{
      swarm_id: s.swarm_id,
      status: s.status,
      goals: s.goals,
      agent_count: length(s.agent_ids || []),
      coordinator_id: s.coordinator_id,
      inserted_at: s.inserted_at
    }
  end

  defp apply_sort(list, %{page: page, page_size: size, sort: sort, dir: dir}) when is_list(list) do
    sorter =
      case {sort, dir} do
        {:inserted_at, :asc} -> &(&1.inserted_at <= &2.inserted_at)
        {:inserted_at, :desc} -> &(&1.inserted_at >= &2.inserted_at)
        {:status, :asc} -> &(&1.status <= &2.status)
        {:status, :desc} -> &(&1.status >= &2.status)
        _ -> &(&1.inserted_at >= &2.inserted_at)
      end

    list
    |> Enum.sort(sorter)
    |> Enum.drop((page - 1) * size)
    |> Enum.take(size)
  end

  defp parse_int(v, default) do
    case Integer.parse(to_string(v)) do
      {n, _} -> n
      _ -> default
    end
  end

  defp clamp(n, min, max), do: max(min, min(max, n))
  defp to_sort_atom("inserted_at"), do: :inserted_at
  defp to_sort_atom("status"), do: :status
  defp to_sort_atom(_), do: :inserted_at
  defp to_dir_atom("asc"), do: :asc
  defp to_dir_atom(_), do: :desc

  defp new_export_id do
    "exp_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-semibold">Agent Swarms</h1>
        </div>

        <.form for={@form} id="swarm-filter-form" phx-change="filter" phx-submit="filter" class="grid grid-cols-1 md:grid-cols-6 gap-4">
          <.input field={@form[:swarm_id]} type="text" placeholder="swarm_id" label="Swarm ID" />
          <.input field={@form[:coordinator_id]} type="text" placeholder="coordinator_id" label="Coordinator ID" />
          <.input field={@form[:session_id]} type="text" placeholder="session_id" label="Session ID" />
          <div>
            <label class="block text-sm font-medium text-slate-700">Sort</label>
            <div class="flex gap-2">
              <select phx-change="set_sort" name="sort" class="px-2 py-1 border rounded">
                <option value="inserted_at" selected={@paging.sort == :inserted_at}>Inserted</option>
                <option value="status" selected={@paging.sort == :status}>Status</option>
              </select>
              <select phx-change="set_sort" name="dir" class="px-2 py-1 border rounded">
                <option value="desc" selected={@paging.dir == :desc}>Desc</option>
                <option value="asc" selected={@paging.dir == :asc}>Asc</option>
              </select>
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-700">Page Size</label>
            <select phx-change="set_page_size" name="size" class="px-2 py-1 border rounded">
              <option value="10" selected={@paging.page_size == 10}>10</option>
              <option value="20" selected={@paging.page_size == 20}>20</option>
              <option value="50" selected={@paging.page_size == 50}>50</option>
              <option value="100" selected={@paging.page_size == 100}>100</option>
            </select>
          </div>
          <div class="flex items-end">
            <button type="submit" class="btn btn-primary px-4 py-2 rounded bg-blue-600 text-white">Filter</button>
          </div>
        </.form>

        <div class="flex items-center justify-end gap-2">
          <button phx-click="export_swarms_csv" class="px-3 py-1 rounded border text-xs">Export CSV</button>
          <button phx-click="export_swarms_json" class="px-3 py-1 rounded border text-xs">Export JSON</button>
          <button phx-click="export_swarms_ndjson_bg" class="px-3 py-1 rounded border text-xs">Export NDJSON (bg)</button>
        </div>
        <div id="swarms" phx-update="stream" class="divide-y divide-slate-200 rounded border">
          <div class={[@empty? && "hidden", "only:block px-4 py-8 text-center text-slate-500"]}>No swarms yet</div>
          <div :for={{id, swarm} <- @streams.swarms} id={id} class="px-4 py-3 grid grid-cols-1 md:grid-cols-6 gap-2 items-center">
            <div class="font-mono text-xs truncate" title={swarm.swarm_id}>
              <.link navigate={~p"/agents/swarms/#{swarm.swarm_id}"} class="hover:underline">
                <span class="text-slate-500">swarm</span>/<%= swarm.swarm_id %>
              </.link>
            </div>
            <div>
              <span class="text-xs px-2 py-0.5 rounded border">
                <%= swarm.status %>
              </span>
            </div>
            <div class="col-span-2 truncate" title={Enum.join(swarm.goals || [], ", ")}>Goals: <%= Enum.join(swarm.goals || [], ", ") %></div>
            <div class="text-sm">Agents: <%= length(swarm.agent_ids || []) %></div>
            <div class="text-xs text-slate-500 truncate" title={swarm.coordinator_id || "-"}>Coord: <%= swarm.coordinator_id || "-" %></div>
          </div>
        </div>

        <div class="flex items-center justify-between">
          <button phx-click="set_page" phx-value-dir="prev" class="px-3 py-1 rounded border disabled:opacity-50" disabled={@paging.page <= 1}>Previous</button>
          <div class="text-sm">Page <%= @paging.page %></div>
          <button phx-click="set_page" phx-value-dir="next" class="px-3 py-1 rounded border disabled:opacity-50" disabled={@empty? or length(current_swarms(%{assigns: assigns})) < @paging.page_size}>Next</button>
        </div>
      </div>
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
    </Layouts.app>
    """
  end
end
