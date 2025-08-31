defmodule LangWeb.DevModelsLive do
  use LangWeb, :live_view
  import Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Lang.PubSub, "dev:models")
    _ = Lang.Dev.TelemetryHandler.attach()
    models = list_models()
    events = recent_events()

     {:ok,
      socket
      |> assign(:page_title, "Models Pipeline")
      |> assign(:models, models)
      |> assign(:selected, nil)
      |> assign(:with_diff, true)
      |> assign(:history, [])
      |> assign(:expanded, MapSet.new())
      |> assign(:telemetry, [])
      |> assign(:compare_sel, [])
      |> assign(:pair_diff, nil)
      |> assign(:compare_loading, false)
      |> assign(:errors, [])
      |> assign(:lazy_diffs, %{})
      |> stream(:events, events)}
  end

  @impl true
  def handle_info({:telemetry, stage, phase, meta, ms}, socket) do
    entry = %{stage: stage, phase: phase, id: meta[:id], ms: ms}
    tel = [entry | socket.assigns.telemetry] |> Enum.take(50)
    {:noreply, assign(socket, :telemetry, tel)}
  end

  def handle_info(_msg, socket) do
    # On any event, refresh models, recent events, and selected history
    socket =
      socket
      |> assign(:models, list_models())
      |> stream(:events, recent_events(), reset: true)
      |> load_selected_history()

    {:noreply, socket}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:selected, id) |> load_selected_history()}
  end

  def handle_event("toggle_diff", _params, socket) do
    socket = assign(socket, :with_diff, !socket.assigns.with_diff) |> load_selected_history()
    {:noreply, socket}
  end

  def handle_event("toggle_entry", %{"id" => id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, id) do
        MapSet.delete(socket.assigns.expanded, id)
      else
        MapSet.put(socket.assigns.expanded, id)
      end
    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("load_diff_prev", %{"entry_id" => eid}, %{assigns: %{selected: model_id}} = socket) do
    base = LangWeb.Endpoint.url()
    url = base <> "/dev/api/models/" <> model_id <> "/history/diff?entry_id=" <> eid
    case Req.get(url: url, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        diff = body[:diff] || body["diff"] || body
        {:noreply, socket |> assign(:lazy_diffs, Map.put(socket.assigns.lazy_diffs, eid, diff)) |> put_flash(:info, "Loaded diff vs prev") |> add_toast(:info, "Loaded diff vs prev")}
      {:ok, %Req.Response{status: code}} -> {:noreply, socket |> put_flash(:error, "Diff prev failed: #{code}") |> add_toast(:error, "Diff prev failed: #{code}")}
      {:error, reason} -> {:noreply, socket |> put_flash(:error, "Diff prev failed: #{inspect(reason)}") |> add_toast(:error, "Diff prev failed")}
    end
  end

  def handle_event("toggle_compare", %{"id" => id}, socket) do
    sel = socket.assigns.compare_sel
    sel =
      if Enum.member?(sel, id) do
        Enum.reject(sel, & &1 == id)
      else
        (sel ++ [id]) |> Enum.take(-2)
      end
    {:noreply, assign(socket, compare_sel: sel)}
  end

  def handle_event("run_compare", _params, %{assigns: %{selected: model_id, compare_sel: [a, b]}} = socket) do
    base = LangWeb.Endpoint.url()
    url = base <> "/dev/api/models/" <> model_id <> "/history/diff?from_id=" <> a <> "&to_id=" <> b
    case Req.get(url: url, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:noreply, socket |> assign(:pair_diff, body) |> put_flash(:info, "Compared #{a} → #{b}") |> add_toast(:info, "Compared #{a} → #{b}")}
      {:ok, %Req.Response{status: code}} ->
        {:noreply, socket |> put_flash(:error, "Compare failed: #{code}") |> add_toast(:error, "Compare failed: #{code}")}
      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Compare failed: #{inspect(reason)}") |> add_toast(:error, "Compare failed")}
    end
  end
  def handle_event("run_compare", _params, socket), do: {:noreply, socket}

  def handle_event("swap_compare", _params, %{assigns: %{compare_sel: [a, b]}} = socket) do
    {:noreply, assign(socket, compare_sel: [b, a])}
  end
  def handle_event("swap_compare", _params, socket), do: {:noreply, socket}

  def handle_event("clear_compare", _params, socket) do
    {:noreply, assign(socket, compare_sel: []) |> assign(:pair_diff, nil)}
  end

  def handle_event("load_diff_next", %{"entry_id" => eid}, %{assigns: %{selected: model_id, history: history}} = socket) do
    ids = Enum.map(history, & &1.id)
    case Enum.find_index(ids, & &1 == eid) do
      nil -> {:noreply, put_flash(socket, :error, "Entry not found")}
      idx when idx == length(ids) - 1 -> {:noreply, put_flash(socket, :error, "No next entry")}
      idx ->
        next_id = Enum.at(ids, idx + 1)
        base = LangWeb.Endpoint.url()
        url = base <> "/dev/api/models/" <> model_id <> "/history/diff?from_id=" <> eid <> "&to_id=" <> next_id
        case Req.get(url: url, retry: false) do
          {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
            diff = body[:diff] || body["diff"] || body
            {:noreply, socket |> assign(:lazy_diffs, Map.put(socket.assigns.lazy_diffs, eid, diff)) |> put_flash(:info, "Loaded diff #{eid} → #{next_id}") |> add_toast(:info, "Loaded diff next")}
          {:ok, %Req.Response{status: code}} -> {:noreply, socket |> put_flash(:error, "Diff next failed: #{code}") |> add_toast(:error, "Diff next failed: #{code}")}
          {:error, reason} -> {:noreply, socket |> put_flash(:error, "Diff next failed: #{inspect(reason)}") |> add_toast(:error, "Diff next failed")}
        end
    end
  end

  def handle_event("rerender", %{"id" => id}, socket) do
    _ = Lang.Dev.Workers.DocRenderWorker.new(%{"id" => id}, queue: :analysis) |> Oban.insert()
    {:noreply, socket}
  end

  def handle_event("set_status", %{"id" => id, "status" => new_status} = params, socket) do
    case Lang.Dev.ModelRegistry |> Ash.Query.filter(model_id == ^id) |> Ash.read() do
      {:ok, [%{status: curr, version: ver, hash: hash, path: path}]} ->
        if valid_status?(curr, new_status) do
          now = DateTime.utc_now()
          attrs = %{model_id: id, version: ver, hash: hash, path: path, status: new_status, status_changed_at: now, changed_by: Map.get(params, "changed_by")}
          case Lang.Dev.ModelRegistry.upsert(attrs) do
            {:ok, _} ->
              _ = Lang.Events.emit_dev_model_event(%{event_type: "status_updated", model_id: id, status: new_status})
              _ =
                case Lang.Dev.Config.fs_adapter().preview(path, max_lines: 1_000_000) do
                  {:ok, lines} ->
                    with {:ok, map} <- Lang.Dev.JSONLDHelper.parse(Enum.join(lines, "\n")) do
                      _ = Lang.Dev.ModelState.record(%{model_id: id, version: ver, hash: hash, status: new_status, path: path, event_type: "status_updated", snapshot: map, actor: Map.get(params, "changed_by")})
                      :ok
                    else
                      _ -> :ok
                    end
                  _ -> :ok
                end
              {:noreply, socket |> load_selected_history()}
            _ -> {:noreply, socket}
          end
        else
          {:noreply, socket}
        end
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dev_app flash={@flash}>
      <div class="p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">Model Pipeline</h1>
          <a href="/dev/test" class="px-2 py-1 text-xs rounded bg-zinc-800 text-white hover:bg-zinc-700">Back to Dev Hub</a>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="border rounded p-3">
            <div class="font-medium mb-2">Models</div>
            <div class="space-y-1 text-sm">
              <div :for={m <- @models} class={["flex items-center justify-between cursor-pointer", @selected == m.model_id && "bg-zinc-50"]} phx-click="select" phx-value-id={m.model_id}>
                <div class="font-mono">{m.model_id}</div>
                <div class="text-right">
                  <div class="text-xs text-zinc-600">v{m.version} · {m.status || "draft"}</div>
                  <div :if={m.changed_by || m.status_changed_at} class="text-[10px] text-zinc-400">{m.changed_by} {m.changed_by && m.status_changed_at && "·"} {format_time(m.status_changed_at)}</div>
                </div>
              </div>
              <div :if={@models == []} class="text-xs text-zinc-500">No models registered.</div>
            </div>
          </div>

          <div class="border rounded p-3">
            <div class="font-medium mb-2">Recent Events</div>
            <div id="events" phx-update="stream" class="text-sm max-h-[50vh] overflow-auto space-y-1">
              <div :for={{id, e} <- @streams.events} id={id} class="font-mono text-xs">
                <span class="text-zinc-500">{format_time(e.at)}:</span> {e.event_type} · {e.model_id}
                <span :if={e.path} class="text-zinc-500"> → {Path.basename(e.path)}</span>
                <span :if={e.reason} class="text-red-600"> ({e.reason})</span>
              </div>
            </div>
          </div>
        </div>

        <div :if={@selected} class="border rounded p-3">
          <div class="flex items-center justify-between gap-2">
            <div class="font-medium">History — {@selected}</div>
            <div class="flex items-center gap-2">
              <button phx-click="rerender" phx-value-id={@selected} class="text-xs px-2 py-0.5 rounded bg-zinc-800 text-white">Re-render</button>
              <button phx-click="toggle_diff" class="text-xs px-2 py-0.5 rounded border">{@with_diff && "Hide" || "Show"} Diffs</button>
            </div>
          </div>

          <div class="mt-2 flex items-center gap-2 text-xs">
            <div class="text-zinc-500">Status:</div>
            <form phx-submit="set_status" class="flex items-center gap-2">
              <input type="hidden" name="id" value={@selected} />
              <select name="status" class="border rounded px-1 py-0.5 text-xs">
                <option value="draft">draft</option>
                <option value="ready">ready</option>
                <option value="implemented">implemented</option>
                <option value="deprecated">deprecated</option>
              </select>
              <input type="text" name="changed_by" placeholder="actor" class="border rounded px-1 py-0.5 text-xs" />
              <button type="submit" class="px-2 py-0.5 rounded border">Update</button>
            </form>
          </div>

          <div class="mt-2 space-y-2 text-sm font-mono">
            <div class="text-xs text-zinc-500">Status timeline:</div>
            <div class="flex items-center gap-2 flex-wrap">
              <span :for={h <- Enum.filter(@history, &(&1.event_type == "status_updated"))} class="px-2 py-0.5 rounded border text-xs">{h.status || "?"} · {format_time(h.at)}<span :if={h.actor} class="text-zinc-400"> · {h.actor}</span></span>
            </div>

            <div class="mt-2 flex items-center gap-2 text-xs">
              <div class="text-zinc-500">Compare:</div>
              <div class="text-zinc-600">Selected {length(@compare_sel)}/2</div>
              <button phx-click="run_compare" class="px-2 py-0.5 rounded border" disabled={length(@compare_sel) != 2 || @compare_loading}>
                <span :if={!@compare_loading}>Compare selected</span>
                <span :if={@compare_loading}>Comparing…</span>
              </button>
              <button phx-click="swap_compare" class="px-2 py-0.5 rounded border" disabled={length(@compare_sel) != 2}>Swap</button>
              <button phx-click="clear_compare" class="px-2 py-0.5 rounded border">Clear</button>
              <a :if={length(@compare_sel) == 2} href={"/dev/api/models/" <> @selected <> "/history/diff?from_id=" <> Enum.at(@compare_sel, 0) <> "&to_id=" <> Enum.at(@compare_sel, 1)} target="_blank" class="text-[10px] underline text-zinc-600">open</a>
            </div>

            <div :if={@pair_diff} class="mt-2">
              <div class="text-xs text-zinc-600">Pair diff</div>
              <pre phx-no-curly-interpolation class="mt-1 whitespace-pre-wrap text-xs bg-zinc-50 p-2 rounded overflow-auto max-h-[40vh]">{pretty_diff(@pair_diff)}</pre>
            </div>

            <div :for={h <- @history} class="border rounded p-2">
              <div>
                <span class="text-zinc-500">{format_time(h.at)}:</span> {h.event_type}
                · v{h.version} · {String.slice(h.hash, 0, 7)}
                <span :if={h.status} class="text-zinc-500"> · {h.status}</span>
                <button :if={h.diff} phx-click="toggle_entry" phx-value-id={h.id} class="ml-2 text-[10px] px-1 py-0.5 rounded border align-middle">{MapSet.member?(@expanded, h.id) && "Hide" || "Show"} Diff</button>
                <button phx-click="load_diff_prev" phx-value-entry_id={h.id} class="ml-2 text-[10px] px-1 py-0.5 rounded border align-middle">Diff prev (on-demand)</button>
                <button phx-click="load_diff_next" phx-value-entry_id={h.id} class="ml-1 text-[10px] px-1 py-0.5 rounded border align-middle">Diff next</button>
                <a href={"/dev/api/models/" <> @selected <> "/history/diff?entry_id=" <> h.id} target="_blank" class="ml-1 text-[10px] underline text-zinc-600">open</a>
                <label class="ml-2 align-middle text-[10px]">
                  <input type="checkbox" phx-click="toggle_compare" phx-value-id={h.id} checked={Enum.member?(@compare_sel, h.id)} /> select
                </label>
              </div>
              <pre :if={show_any_diff?(@with_diff, @expanded, h.id, h.diff, @lazy_diffs)} phx-no-curly-interpolation class="mt-1 whitespace-pre-wrap text-xs bg-zinc-50 p-2 rounded overflow-auto max-h-[30vh]">{pretty_diff(diff_for_entry(h, @lazy_diffs))}</pre>
            </div>
            <div :if={@history == []} class="text-xs text-zinc-500">No history yet.</div>
          </div>
        </div>

        <div class="border rounded p-3">
          <div class="font-medium mb-2">Telemetry</div>
          <div class="text-xs font-mono max-h-[25vh] overflow-auto space-y-1">
            <div :for={t <- @telemetry}>
              {to_string(t.stage)} {to_string(t.phase)} {t.id} {t.ms}ms
            </div>
            <div :if={@telemetry == []} class="text-xs text-zinc-500">No telemetry yet.</div>
          </div>
        </div>

        <div id="toasts" class="fixed top-2 right-2 space-y-2 z-50">
          <div :for={{tid, {kind, msg}} <- @toasts} id={"toast-" <> to_string(tid)}
               class={["px-3 py-2 rounded shadow text-xs transition-opacity duration-300 hover:opacity-90", kind == :error && "bg-red-600 text-white", kind == :info && "bg-zinc-800 text-white"]}>
            <span>{msg}</span>
            <button phx-click="dismiss_toast" phx-value-id={tid} class="ml-2 text-[10px] underline">dismiss</button>
          </div>
        </div>
      </div>
    </Layouts.dev_app>
    """
  end

  defp list_models do
    case Lang.Dev.ModelRegistry |> Ash.read() do
      {:ok, list} -> Enum.sort_by(list, & &1.model_id)
      _ -> []
    end
  end

  defp recent_events do
    case Lang.Dev.ModelEvent |> Ash.read() do
      {:ok, list} ->
        list
        |> Enum.sort_by(& &1.at, {:desc, DateTime})
        |> Enum.take(50)
      _ -> []
    end
  end

  defp load_selected_history(%{assigns: %{selected: nil}} = socket), do: socket
  defp load_selected_history(%{assigns: %{selected: id, with_diff: with_diff}} = socket) do
    items = Lang.Dev.History.history(id, with_diff: with_diff)
    assign(socket, :history, items)
  end

  defp format_time(nil), do: ""
  defp format_time(dt) do
    try do
      Calendar.strftime(dt, "%H:%M:%S")
    rescue
      _ -> to_string(dt)
    end
  end

  defp pretty_diff(%{native: native}), do: Jason.encode!(native, pretty: true)
  defp pretty_diff(%{json: json}), do: Jason.encode!(json, pretty: true)
  defp pretty_diff(other) when is_map(other), do: Jason.encode!(other, pretty: true)
  defp pretty_diff(other), do: to_string(other)

  defp show_any_diff?(with_diff, expanded, id, precomputed, lazy_map) do
    (with_diff || MapSet.member?(expanded, id)) && (precomputed || Map.has_key?(lazy_map, id))
  end

  defp diff_for_entry(h, lazy_map) do
    Map.get(lazy_map, h.id) || h.diff
  end

  defp to_meta(entry) do
    %{
      id: entry.id,
      version: entry.version,
      hash: entry.hash,
      status: entry.status,
      at: entry.at
    }
  end

  def handle_event("dismiss_toast", %{"id" => id}, socket) do
    {:noreply, assign(socket, :toasts, remove_toast(socket.assigns.toasts, String.to_integer(id)))}
  end

  def handle_info({:dismiss_toast, id}, socket) do
    {:noreply, assign(socket, :toasts, remove_toast(socket.assigns.toasts, id))}
  end

  defp add_toast(socket, kind, msg) do
    id = System.unique_integer([:positive])
    :erlang.send_after(4_000, self(), {:dismiss_toast, id})
    assign(socket, :toasts, socket.assigns.toasts ++ [{id, {kind, to_string(msg)}}])
  end

  defp remove_toast(toasts, id), do: Enum.reject(toasts, fn {tid, _} -> tid == id end)

  defp valid_status?(from, to) do
    allowed = %{
      nil => ["draft", "ready", "implemented", "deprecated"],
      "draft" => ["ready", "deprecated"],
      "ready" => ["implemented", "deprecated"],
      "implemented" => ["deprecated"],
      "deprecated" => []
    }
    Enum.member?(Map.get(allowed, from, []), to)
  end
end
