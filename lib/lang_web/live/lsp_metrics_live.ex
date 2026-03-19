defmodule LangWeb.LspMetricsLive do
  use LangWeb, :live_view

  @topic "lsp:measurements:global"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lang.PubSub, @topic)
    end

    {:ok,
     socket
     |> assign(:events, [])
     |> assign(:limit, 200)
     |> assign(:title, "LSP Metrics")}
  end

  @impl true
  def handle_info(%{} = evt, socket) do
    events =
      [normalize(evt) | socket.assigns.events]
      |> Enum.take(socket.assigns.limit)

    {:noreply, assign(socket, :events, events)}
  end

  defp normalize(%{id: id, client_id: cid, method: m, duration_ms: d, at: at} = m1) do
    %{id: id, client_id: cid, method: m, duration_ms: d, at: at, provider: Map.get(m1, :provider), model: Map.get(m1, :model)}
  end

  defp normalize(%{"id" => id, "client_id" => cid, "method" => m, "duration_ms" => d, "at" => at} = m1) do
    %{id: id, client_id: cid, method: m, duration_ms: d, at: at, provider: Map.get(m1, "provider"), model: Map.get(m1, "model")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="max-w-5xl mx-auto space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold">LSP Metrics</h1>
          <div class="text-xs text-zinc-500">Streaming from {@topic}</div>
        </div>

        <div class="overflow-x-auto border rounded">
          <table class="min-w-full text-sm">
            <thead>
              <tr class="bg-zinc-50 text-left">
                <th class="px-3 py-2">Method</th>
                <th class="px-3 py-2">Client</th>
                <th class="px-3 py-2">Duration (ms)</th>
                <th class="px-3 py-2">Provider</th>
                <th class="px-3 py-2">Model</th>
                <th class="px-3 py-2">At</th>
              </tr>
            </thead>
            <tbody id="rows">
              <tr :for={e <- @events} class="border-t">
                <td class="px-3 py-1">{e.method}</td>
                <td class="px-3 py-1 text-zinc-600">{e.client_id}</td>
                <td class="px-3 py-1">{e.duration_ms}</td>
                <td class="px-3 py-1 text-zinc-600">{e.provider}</td>
                <td class="px-3 py-1 text-zinc-600">{e.model}</td>
                <td class="px-3 py-1 text-zinc-600">{format_at(e.at)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_at(nil), do: ""
  defp format_at(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_at(s) when is_binary(s), do: s
  defp format_at(_), do: ""
end

