defmodule LangWeb.LspStatusLive do
  use LangWeb, :live_view

  alias Lang.LSP.API

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"path" => ".", "max_depth" => "8"}, as: :scan)
    search_form = to_form(%{"path" => ".", "query" => "TODO|FIXME", "max_results" => "100"}, as: :search)
    code_form =
      to_form(
        %{"path" => ".", "language" => "elixir", "pattern" => "(call target: (identifier) @fn)", "max_results" => "100", "max_depth" => "15"},
        as: :code
      )

    {:ok,
     socket
     |> assign(:page_title, "LSP Status")
     |> assign(:ping_result, nil)
     |> assign(:ping_error, nil)
     |> assign(:last_ping_at, nil)
     |> assign(:loading?, false)
     |> assign(:scan_loading?, false)
     |> assign(:scan_error, nil)
     |> assign(:scan_stats, nil)
     |> assign(:scan_files, [])
     |> assign(:form, form)
     |> assign(:search_form, search_form)
     |> assign(:search_loading?, false)
     |> assign(:search_error, nil)
     |> assign(:search_stats, nil)
     |> assign(:search_items, [])
     |> assign(:code_form, code_form)
     |> assign(:code_presets, code_presets_for("elixir"))
     |> assign(:code_loading?, false)
     |> assign(:code_error, nil)
     |> assign(:code_stats, nil)
     |> assign(:code_items, [])
     |> assign(:active_tab, "scan")
     |> stream(:files, [])
     |> stream(:search_results, [])
     |> stream(:code_results, [])}
  end

  @impl true
  def handle_event("ping", _params, socket) do
    socket = assign(socket, :loading?, true)

    result = API.ping()

    socket =
      case result do
        {:ok, res} ->
          socket
          |> assign(:ping_result, res)
          |> assign(:ping_error, nil)
          |> assign(:last_ping_at, DateTime.utc_now())

        {:error, reason} ->
          socket
          |> assign(:ping_result, nil)
          |> assign(:ping_error, inspect(reason))
          |> assign(:last_ping_at, DateTime.utc_now())
      end

    {:noreply, assign(socket, :loading?, false)}
  end

  # -- code form change (update presets and optionally apply selected preset) --
  @impl true
  def handle_event("code_change", %{"code" => params}, socket) do
    lang = Map.get(params, "language", "elixir")
    presets = code_presets_for(lang)

    params =
      case Map.get(params, "preset") do
        nil -> params
        "" -> params
        preset_key ->
          case Enum.find(presets, fn {k, _label, _pattern} -> k == preset_key end) do
            {^preset_key, _label, pattern} -> Map.put(params, "pattern", pattern)
            _ -> params
          end
      end

    {:noreply,
     socket
     |> assign(:code_presets, presets)
     |> assign(:code_form, to_form(params, as: :code))}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("download", %{"type" => type}, socket) do
    {filename, payload} =
      case type do
        "scan" ->
          {"lsp_scan.json",
           %{
             stats: socket.assigns.scan_stats,
             files: socket.assigns.scan_files
           }}

        "search" ->
          {"lsp_search.json",
           %{
             stats: socket.assigns.search_stats,
             results: socket.assigns.search_items
           }}

        "code" ->
          {"lsp_code_search.json",
           %{
             stats: socket.assigns.code_stats,
             results: socket.assigns.code_items
           }}

        _ -> {"lsp_export.json", %{}}
      end

    json = Jason.encode!(payload, pretty: true)
    {:noreply, Phoenix.LiveView.send_download(socket, {:binary, json}, filename: filename, content_type: "application/json")}
  end

  @impl true
  def handle_event("scan", %{"scan" => %{"path" => path} = params}, socket) do
    max_depth = parse_int(Map.get(params, "max_depth", "8"), 8)

    # Kick off async scan via LSP API
    Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
      send(self(), {:scan_started, path})
      res = API.fs_scan(path, %{"max_depth" => max_depth})
      send(self(), {:scan_finished, path, res})
    end)

    {:noreply, socket |> assign(:scan_loading?, true) |> assign(:scan_error, nil)}
  end

  @impl true
  def handle_info({:scan_started, _path}, socket) do
    {:noreply, socket |> assign(:scan_loading?, true) |> assign(:scan_error, nil)}
  end

  @impl true
  def handle_info({:scan_finished, path, {:ok, result}}, socket) do
    {files, stats} = normalize_scan_result(result)

    socket =
      socket
      |> assign(:scan_loading?, false)
      |> assign(:scan_error, nil)
      |> assign(:scan_stats, Map.put(stats, :path, path))
      |> assign(:scan_files, files)
      |> stream(:files, files, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:scan_finished, _path, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:scan_loading?, false) |> assign(:scan_error, inspect(reason))}
  end

  # -- search --
  @impl true
  def handle_event("search", %{"search" => %{"path" => path, "query" => query} = params}, socket) do
    max_results = parse_int(Map.get(params, "max_results", "100"), 100)

    Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
      send(self(), {:search_started, path, query})
      res = API.fs_search(path, query, %{"max_results" => max_results})
      send(self(), {:search_finished, path, query, res})
    end)

    {:noreply, socket |> assign(:search_loading?, true) |> assign(:search_error, nil) |> stream(:search_results, [], reset: true)}
  end

  @impl true
  def handle_info({:search_started, _path, _query}, socket) do
    {:noreply, assign(socket, :search_loading?, true)}
  end

  @impl true
  def handle_info({:search_finished, path, query, {:ok, results}}, socket) do
    {items, stats} = normalize_search_results(results)

    socket =
      socket
      |> assign(:search_loading?, false)
      |> assign(:search_error, nil)
      |> assign(:search_stats, stats |> Map.merge(%{path: path, query: query}))
      |> assign(:search_items, items)
      |> stream(:search_results, items, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:search_finished, _path, _query, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:search_loading?, false) |> assign(:search_error, inspect(reason))}
  end

  # -- code search --
  @impl true
  def handle_event(
        "search_code",
        %{"code" => %{"path" => path, "language" => lang, "pattern" => pat} = params},
        socket
      ) do
    max_results = parse_int(Map.get(params, "max_results", "100"), 100)
    max_depth = parse_int(Map.get(params, "max_depth", "15"), 15)

    Task.Supervisor.start_child(Lang.LSP.TaskSupervisor, fn ->
      send(self(), {:code_started, path, lang})
      res = API.fs_search_code(path, lang, pat, %{"max_results" => max_results, "max_depth" => max_depth})
      send(self(), {:code_finished, path, lang, pat, res})
    end)

    {:noreply,
     socket
     |> assign(:code_loading?, true)
     |> assign(:code_error, nil)
     |> stream(:code_results, [], reset: true)}
  end

  @impl true
  def handle_info({:code_started, _path, _lang}, socket) do
    {:noreply, assign(socket, :code_loading?, true)}
  end

  @impl true
  def handle_info({:code_finished, path, lang, pat, {:ok, results}}, socket) do
    {items, stats} = normalize_code_results(results)

    socket =
      socket
      |> assign(:code_loading?, false)
      |> assign(:code_error, nil)
      |> assign(:code_stats, stats |> Map.merge(%{path: path, language: lang, pattern: pat}))
      |> assign(:code_items, items)
      |> stream(:code_results, items, reset: true)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:code_finished, _path, _lang, _pat, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:code_loading?, false) |> assign(:code_error, inspect(reason))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div id="lsp-status" class="container mx-auto px-4 py-6">
        <div class="flex items-center justify-between mb-4">
          <h1 class="text-2xl font-semibold">LSP Connectivity</h1>
          <.button id="ping-btn" phx-click="ping" disabled={@loading?}>
            <.icon name="hero-arrow-path" class={["size-4 mr-2", @loading? && "animate-spin"]} />
            {@loading? && "Pinging..." || "Ping LSP"}
          </.button>
        </div>

        <div class="card bg-base-100 shadow p-4">
          <div class="text-sm opacity-70">Last ping:</div>
          <div id="last-ping" class="mb-3">
            {if @last_ping_at, do: Calendar.strftime(@last_ping_at, "%Y-%m-%d %H:%M:%S UTC"), else: "never"}
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <div class="font-medium mb-2">Result</div>
              <pre id="ping-result" class="p-3 rounded bg-base-200 overflow-auto min-h-24" phx-no-curly-interpolation>
                <%= @ping_result && (Jason.encode!(@ping_result, pretty: true)) || "(no result)" %>
              </pre>
            </div>

            <div>
              <div class="font-medium mb-2">Error</div>
              <pre id="ping-error" class="p-3 rounded bg-base-200 overflow-auto min-h-24 text-red-500" phx-no-curly-interpolation>
                <%= @ping_error && @ping_error || "(no error)" %>
              </pre>
            </div>
          </div>
        </div>

        <div class="mt-8">
          <div class="tabs tabs-boxed mb-3">
            <button class={["tab", @active_tab == "scan" && "tab-active"]} phx-click="switch_tab" phx-value-tab="scan">Scan</button>
            <button class={["tab", @active_tab == "search" && "tab-active"]} phx-click="switch_tab" phx-value-tab="search">Search</button>
            <button class={["tab", @active_tab == "code" && "tab-active"]} phx-click="switch_tab" phx-value-tab="code">Code Search</button>
          </div>

          <%= if @active_tab == "scan" do %>
            <div class="flex items-center justify-between mb-3">
              <div class="flex items-center justify-between">
                <h2 class="text-xl font-semibold">Filesystem Scan (via LSP)</h2>
                <.link href={~p"/fs/watch"} class="text-sm text-blue-600 hover:text-blue-500">Open Watch Demo</.link>
              </div>
              <.button id="scan-download" phx-click="download" phx-value-type="scan" class="btn btn-sm">Download JSON</.button>
            </div>

          <.form for={@form} id="scan-form" phx-submit="scan" class="grid grid-cols-1 md:grid-cols-4 gap-3 mb-4">
            <.input field={@form[:path]} type="text" label="Path" />
            <.input field={@form[:max_depth]} type="number" label="Max depth" />
            <div class="flex items-end">
              <.button id="scan-submit" type="submit" disabled={@scan_loading?}>
                <.icon name="hero-magnifying-glass" class={["size-4 mr-2", @scan_loading? && "animate-spin"]} />
                {@scan_loading? && "Scanning..." || "Scan"}
              </.button>
            </div>
          </.form>

          <div class="mb-3 text-sm opacity-70" id="scan-meta">
            {if @scan_stats do
              ~H"<span>Path: {@scan_stats.path}</span> · <span>Files: {@scan_stats.total_files || @scan_stats[:total_files]}</span> · <span>Dirs: {@scan_stats.total_dirs || @scan_stats[:total_dirs]}</span>"
            else
              ~H"<span>Run a scan to see results.</span>"
            end}
            <span :if={@scan_error} class="text-red-500">Error: {@scan_error}</span>
          </div>

          <div id="files" phx-update="stream" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
            <div class="hidden only:block text-sm opacity-70">No files yet</div>
            <div :for={{id, file} <- @streams.files} id={id} class="card bg-base-100 p-3 shadow">
              <div class="font-mono text-xs break-all">
                {file.path}
              </div>
              <div class="text-xs opacity-70">{file.type} · {file.size} bytes</div>
            </div>
          </div>
          <% else %>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-xl font-semibold">Filesystem Search (via LSP)</h2>
              <.button id="search-download" phx-click="download" phx-value-type="search" class="btn btn-sm">Download JSON</.button>
            </div>

            <.form for={@search_form} id="search-form" phx-submit="search" class="grid grid-cols-1 md:grid-cols-6 gap-3 mb-4">
              <.input field={@search_form[:path]} type="text" label="Path" />
              <.input field={@search_form[:query]} type="text" label="Regex Query" />
              <.input field={@search_form[:max_results]} type="number" label="Max results" />
              <div class="md:col-span-2 flex items-end">
                <.button id="search-submit" type="submit" disabled={@search_loading?}>
                  <.icon name="hero-magnifying-glass" class={["size-4 mr-2", @search_loading? && "animate-spin"]} />
                  {@search_loading? && "Searching..." || "Search"}
                </.button>
              </div>
            </.form>

            <div class="mb-3 text-sm opacity-70" id="search-meta">
              {if @search_stats do
                ~H"<span>Path: {@search_stats.path}</span> · <span>Query: {@search_stats.query}</span> · <span>Matches: {@search_stats.matches}</span>"
              else
                ~H"<span>Run a search to see results.</span>"
              end}
              <span :if={@search_error} class="text-red-500">Error: {@search_error}</span>
            </div>

            <div id="search-results" phx-update="stream" class="grid grid-cols-1 md:grid-cols-2 gap-2">
              <div class="hidden only:block text-sm opacity-70">No matches yet</div>
              <div :for={{id, item} <- @streams.search_results} id={id} class="card bg-base-100 p-3 shadow">
                <div class="font-mono text-xs break-all">{item.path}:{item.line}</div>
                <pre class="text-xs whitespace-pre-wrap" phx-no-curly-interpolation><%= item.preview %></pre>
              </div>
            </div>
          <% end %>

          <%= if @active_tab == "code" do %>
            <div class="flex items-center justify-between mb-3">
              <h2 class="text-xl font-semibold">Tree-sitter Code Search (via LSP)</h2>
              <.button id="code-download" phx-click="download" phx-value-type="code" class="btn btn-sm">Download JSON</.button>
            </div>

            <.form for={@code_form} id="code-form" phx-submit="search_code" phx-change="code_change" class="grid grid-cols-1 md:grid-cols-6 gap-3 mb-4">
              <.input field={@code_form[:path]} type="text" label="Path" />
              <.input field={@code_form[:language]} type="text" label="Language" />
              <.input field={@code_form[:pattern]} type="text" label="Tree-sitter Pattern" />
              <.input field={@code_form[:preset]} type="select" label="Preset Pattern" prompt="Choose preset" options={for {k, label, _pat} <- @code_presets, do: {label, k}} />
              <.input field={@code_form[:max_results]} type="number" label="Max results" />
              <.input field={@code_form[:max_depth]} type="number" label="Max depth" />
              <div class="md:col-span-1 flex items-end">
                <.button id="code-submit" type="submit" disabled={@code_loading?}>
                  <.icon name="hero-magnifying-glass" class={["size-4 mr-2", @code_loading? && "animate-spin"]} />
                  {@code_loading? && "Searching..." || "Search"}
                </.button>
              </div>
            </.form>

            <div class="mb-3 text-sm opacity-70" id="code-meta">
              {if @code_stats do
                ~H"<span>Path: {@code_stats.path}</span> · <span>Lang: {@code_stats.language}</span> · <span>Pattern: {@code_stats.pattern}</span> · <span>Matches: {@code_stats.matches}</span>"
              else
                ~H"<span>Run a code search to see results.</span>"
              end}
              <span :if={@code_error} class="text-red-500">Error: {@code_error}</span>
            </div>

            <div id="code-results" phx-update="stream" class="grid grid-cols-1 md:grid-cols-2 gap-2">
              <div class="hidden only:block text-sm opacity-70">No matches yet</div>
              <div :for={{id, item} <- @streams.code_results} id={id} class="card bg-base-100 p-3 shadow">
                <div class="font-mono text-xs break-all">{item.path}:{item.line}</div>
                <div class="text-xs opacity-70">{item.language}</div>
                <pre class="text-xs whitespace-pre-wrap" phx-no-curly-interpolation><%= item.preview %></pre>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # -- helpers --
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_, default), do: default

  defp normalize_scan_result(result) when is_map(result) do
    # Accept atom or string keyed maps
    tree = Map.get(result, :tree) || Map.get(result, "tree") || %{}
    stats = Map.get(result, :stats) || Map.get(result, "stats") || %{}

    files =
      tree
      |> flatten_tree()
      |> Enum.take(500)

    {files, symbolize_keys(stats)}
  end

  defp normalize_scan_result(_), do: {[], %{}}

  defp flatten_tree(%{} = node) do
    type = Map.get(node, :type) || Map.get(node, "type")
    path = Map.get(node, :path) || Map.get(node, "path")
    size = Map.get(node, :size) || Map.get(node, "size") || 0
    children = Map.get(node, :children) || Map.get(node, "children") || []

    me = if path, do: [%{path: path, type: type || "file", size: size}], else: []
    me ++ Enum.flat_map(List.wrap(children), &flatten_tree/1)
  end

  defp flatten_tree(list) when is_list(list), do: Enum.flat_map(list, &flatten_tree/1)
  defp flatten_tree(_), do: []

  defp symbolize_keys(map) when is_map(map) do
    for {k, v} <- map, into: %{} do
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, v}
    end
  end
  defp symbolize_keys(other), do: other

  defp normalize_search_results(results) when is_list(results) do
    items =
      results
      |> Enum.map(fn r ->
        %{
          path: Map.get(r, :path) || Map.get(r, "path"),
          line: Map.get(r, :line) || Map.get(r, "line") || 0,
          preview: Map.get(r, :preview) || Map.get(r, "preview") || ""
        }
      end)
      |> Enum.take(500)

    stats = %{matches: length(items)}
    {items, stats}
  end

  defp normalize_search_results(_), do: {[], %{matches: 0}}

  defp normalize_code_results(results) when is_list(results) do
    items =
      results
      |> Enum.map(fn r ->
        %{
          path: Map.get(r, :path) || Map.get(r, "path"),
          line:
            Map.get(r, :line) || Map.get(r, "line") ||
              Map.get(r, :row) || Map.get(r, "row") || 0,
          language: Map.get(r, :language) || Map.get(r, "language") || "",
          preview:
            Map.get(r, :preview) || Map.get(r, "preview") ||
              Map.get(r, :text) || Map.get(r, "text") ||
              Map.get(r, :source) || Map.get(r, "source") ||
              Map.get(r, :snippet) || Map.get(r, "snippet") || ""
        }
      end)
      |> Enum.take(500)

    stats = %{matches: length(items)}
    {items, stats}
  end

  defp normalize_code_results(_), do: {[], %{matches: 0}}

  # -- presets --
  defp code_presets_for(lang) when is_binary(lang) do
    case String.downcase(lang) do
      "elixir" ->
        [
          {"calls", "Function calls", "(call target: (identifier) @fn)"},
          {"defmodule", "Module definitions", "(call target: (identifier) @name (#match? @name \"defmodule\"))"},
          {"attribute", "Module attributes", "(attribute) @attr"}
        ]

      "rust" ->
        [
          {"fn", "Function items", "(function_item name: (identifier) @function)"},
          {"impl", "Impl blocks", "(impl_item type: (type_identifier) @type)"},
          {"call", "Call expressions", "(call_expression function: (identifier) @fn)"}
        ]

      "python" ->
        [
          {"def", "Function defs", "(function_definition name: (identifier) @name)"},
          {"class", "Class defs", "(class_definition name: (identifier) @name)"},
          {"call", "Call expressions", "(call function: (identifier) @fn)"}
        ]

      "javascript" ->
        [
          {"func_decl", "Function declarations", "(function_declaration name: (identifier) @name)"},
          {"call", "Call expressions", "(call_expression function: (identifier) @fn)"},
          {"class", "Class declarations", "(class_declaration name: (identifier) @name)"}
        ]

      "typescript" ->
        [
          {"func_decl", "Function declarations", "(function_declaration name: (identifier) @name)"},
          {"method", "Method signatures", "(method_signature name: (property_identifier) @name)"},
          {"call", "Call expressions", "(call_expression function: (identifier) @fn)"}
        ]

      _ ->
        [
          {"calls", "Generic call expressions", "(call_expression function: (identifier) @fn)"}
        ]
    end
  end
end
