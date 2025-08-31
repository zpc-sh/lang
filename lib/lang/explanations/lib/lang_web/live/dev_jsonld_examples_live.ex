defmodule LangWeb.DevJsonldExamplesLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    dir = examples_dir()
    {:ok,
     socket
     |> assign(:page_title, "JSON‑LD Examples")
     |> assign(:dir, dir)
     |> assign(:files, list_files(dir))
     |> assign(:selected, nil)
     |> assign(:content, nil)
     |> assign(:error, nil)
     |> then(fn s ->
       if connected?(s) do
         Phoenix.PubSub.subscribe(Lang.PubSub, "dev:fs:jsonld")
       end
       s
     end)}
  end

  @impl true
  def handle_event("view_example", %{"file" => file}, socket) do
    path = Path.join(socket.assigns.dir, file)
    case Lang.Native.FSScanner.preview(path, max_lines: 5000) do
      {:ok, lines} -> {:noreply, assign(socket, selected: file, content: Enum.join(lines, "
"), error: nil)}
      {:error, reason} -> {:noreply, assign(socket, error: inspect(reason), selected: file, content: nil)}
    end
  end

  def handle_event("copy_example", %{"file" => file}, socket) do
    path = Path.join(socket.assigns.dir, file)
    case Lang.Native.FSScanner.preview(path, max_lines: 5000) do
      {:ok, lines} -> {:noreply, push_event(socket, "copy-to-clipboard", %{text: Enum.join(lines, "
")})}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dev_app flash={@flash}>
      <div class="p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">JSON‑LD Examples</h1>
          <a href="/dev/test" class="px-2 py-1 text-xs rounded bg-zinc-800 text-white hover:bg-zinc-700">Back to Dev Hub</a>
        </div>
        <div class="text-xs text-zinc-600">Directory: {@dir}</div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="border rounded p-3">
            <div class="font-medium mb-2">Files</div>
            <div class="space-y-1">
              <div :for={f <- @files} class="flex items-center justify-between gap-2">
                <div class="text-sm font-mono">{f}</div>
                <div class="flex items-center gap-2">
                  <button phx-click="view_example" phx-value-file={f} class="px-2 py-0.5 text-xs rounded border">View</button>
                  <button phx-click="copy_example" phx-value-file={f} class="px-2 py-0.5 text-xs rounded bg-zinc-800 text-white">Copy</button>
                </div>
              </div>
              <div :if={@files == []} class="text-xs text-zinc-500">No examples found.</div>
            </div>
          </div>

          <div class="border rounded p-3">
            <div class="font-medium mb-2">Preview</div>
            <div :if={@selected} class="text-xs text-zinc-600 mb-1">{@selected}</div>
            <pre :if={@content} phx-no-curly-interpolation class="text-sm whitespace-pre-wrap bg-white border rounded p-2 max-h-[65vh] overflow-auto">{@content}</pre>
            <div :if={@content} class="mt-2">
              <a href={"/dev/jsonld?" <> URI.encode_query(%{"input" => @content})} class="px-2 py-0.5 text-xs rounded bg-green-700 text-white">Open in Runner</a>
            </div>
            <div :if={@error} class="text-xs text-red-600 bg-red-50 border rounded p-2">{@error}</div>
          </div>
        </div>
      </div>
    </Layouts.dev_app>
    """
  end

  @impl true
  def handle_info({:changed, _files}, socket) do
    {:noreply, assign(socket, :files, list_files(socket.assigns.dir))}
  end

  defp examples_dir do
    priv = :code.priv_dir(:lang) |> to_string()
    Path.join([priv, "dev", "jsonld"]) |> Path.expand()
  end

  defp list_files(dir) do
    case Lang.Native.FSScanner.scan(dir, max_depth: 1) do
      {:ok, %{tree: tree}} -> extract_json_files(tree)
      _ -> default_examples()
    end
  end

  defp extract_json_files(tree) when is_list(tree) do
    tree
    |> Enum.flat_map(fn
      %{"name" => name, "type" => "file"} -> [name]
      %{name: name, type: "file"} -> [name]
      %{name: name, type: :file} -> [name]
      _ -> []
    end)
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.sort()
  end
  defp extract_json_files(_), do: default_examples()

  defp default_examples do
    [
      "echo.json",
      "broadcast.json",
      "proxy_ssh.json",
      "emit_diagnostics.json",
      "scan_fs.json"
    ]
  end
end
