defmodule LangWeb.DevAgentsDocLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Agents Guide")
     |> assign(:doc, load_doc())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dev_app flash={@flash}>
      <div class="p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">Agents Guide</h1>
          <a href="/dev/test" class="px-2 py-1 text-xs rounded bg-zinc-800 text-white hover:bg-zinc-700">Back to Dev Hub</a>
        </div>
        <div class="text-xs text-zinc-600">This page renders lib/lang_web/AGENTS.md for quick reference in dev.</div>
        <pre class="text-sm whitespace-pre-wrap bg-white border rounded p-3 max-h-[70vh] overflow-auto">{@doc}</pre>
      </div>
    </Layouts.dev_app>
    """
  end

  defp load_doc do
    path = __DIR__ |> Path.join("../AGENTS.md") |> Path.expand()
    case Lang.Native.FSScanner.preview(path, max_lines: 5000) do
      {:ok, lines} when is_list(lines) -> Enum.join(lines, "
")
      {:error, _} -> "AGENTS.md not found or unreadable at: #{path}"
    end
  end
end
