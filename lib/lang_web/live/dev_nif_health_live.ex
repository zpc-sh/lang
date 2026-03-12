defmodule LangWeb.DevNifHealthLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "NIF Health")
     |> assign(:path, ".")
     |> assign(:max_lines, "20")
     |> assign(:preview_result, nil)
     |> assign(:analyze_result, nil)
     |> assign(:nif_status, nif_status())}
  end

  @impl true
  def handle_event("preview", %{"path" => path, "max_lines" => max_lines}, socket) do
    {ms, res} = :timer.tc(fn -> Lang.Native.FSScanner.preview(path, max_lines: to_int(max_lines, 20)) end)
    {:noreply, assign(socket, path: path, max_lines: max_lines, preview_result: %{duration_ms: div(ms, 1000), result: res})}
  end

  def handle_event("analyze", %{"text" => text}, socket) do
    {ms, res} = :timer.tc(fn -> Lang.Native.PerfEngine.analyze_text(text || "sample", format: :markdown) end)
    {:noreply, assign(socket, analyze_result: %{duration_ms: div(ms, 1000), result: res})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dev_app flash={@flash}>
      <div class="p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">NIF Health</h1>
          <a href="/dev/auth/impersonate/dev@lang.test?name=Dev%20User&return_to=/dev/nif" class="px-2 py-1 text-xs rounded bg-zinc-800 text-white hover:bg-zinc-700">Impersonate dev@lang.test</a>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="border rounded p-3 space-y-2">
            <div class="font-medium">FSScanner.preview</div>
            <.form for={to_form(%{path: @path, max_lines: @max_lines}, as: :f)} phx-submit="preview" class="flex gap-2 items-end">
              <div class="flex-1">
                <label class="text-xs text-zinc-600">Path</label>
                <input type="text" name="path" value={@path} class="w-full border rounded px-2 py-1 text-xs" />
              </div>
              <div>
                <label class="text-xs text-zinc-600">Max lines</label>
                <input type="number" min="1" max="200" name="max_lines" value={@max_lines} class="w-24 border rounded px-2 py-1 text-xs" />
              </div>
              <button class="px-2 py-1 text-xs rounded bg-zinc-800 text-white">Run</button>
            </.form>
            <div :if={@preview_result} class="text-xs text-zinc-600">
              <div class="mb-1">Duration: {@preview_result.duration_ms} ms</div>
              <pre class="max-h-48 overflow-auto">{inspect(@preview_result.result, pretty: true)}</pre>
            </div>
          </div>

          <div class="border rounded p-3 space-y-2">
            <div class="font-medium">PerfEngine.analyze_text</div>
            <.form for={to_form(%{text: "# Sample\n\nSome text."}, as: :g)} phx-submit="analyze" class="space-y-2">
              <textarea name="text" class="w-full h-32 border rounded p-2 font-mono text-xs"># Sample\n\nSome text.</textarea>
              <button class="px-2 py-1 text-xs rounded bg-zinc-800 text-white">Run</button>
            </.form>
            <div :if={@analyze_result} class="text-xs text-zinc-600">
              <div class="mb-1">Duration: {@analyze_result.duration_ms} ms</div>
              <pre class="max-h-48 overflow-auto">{inspect(@analyze_result.result, pretty: true)}</pre>
            </div>
          </div>
        </div>

        <div class="border rounded p-3">
          <div class="font-medium mb-1">NIF Status</div>
          <pre class="text-xs">{inspect(@nif_status, pretty: true)}</pre>
        </div>
      </div>
    </Layouts.dev_app>
    """
  end

  defp to_int(v, d) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> d
    end
  end
  defp to_int(v, _d) when is_integer(v), do: v

  defp nif_status do
    %{
      fs_scanner: loaded?(Lang.Native.FSScanner),
      perf_engine: loaded?(Lang.Native.PerfEngine),
      tree_parser: loaded?(Lang.Native.TreeParser),
      lang_parser: loaded?(Lang.Native.LangParser)
    }
  end

  defp loaded?(mod) do
    case Code.ensure_loaded(mod) do
      {:module, _} -> true
      _ -> false
    end
  end
end
