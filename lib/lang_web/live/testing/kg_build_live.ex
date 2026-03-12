defmodule LangWeb.KGBuildLive do
  use LangWeb, :live_view

  @impl true
  def mount(%{"stream_id" => stream_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(LangWeb.Endpoint, "lsp:kg_build:" <> stream_id)
    end

    {:ok,
     socket
     |> assign(:stream_id, stream_id)
     |> assign(:events, [])
     |> assign(:progress, 0.0)
     |> assign(:done, false)}
  end

  @impl true
  def handle_info(%{stream_id: _id} = evt, socket) do
    prog = Map.get(evt, :progress) || Map.get(evt, "progress") || socket.assigns.progress
    complete = Map.get(evt, :complete) || Map.get(evt, "complete") || false

    socket =
      socket
      |> assign(:progress, prog)
      |> assign(:done, !!complete)
      |> update(:events, fn items -> [Map.put(evt, :at, DateTime.utc_now()) | Enum.take(items, 99)] end)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto space-y-4 py-6">
        <h1 class="text-xl font-semibold">KG Build Stream {@stream_id}</h1>
        <div class="w-full bg-gray-800 rounded h-3 overflow-hidden">
          <div class="bg-blue-500 h-3" style={"width: #{Float.round(@progress*100, 1)}%"}></div>
        </div>
        <div :if={@done} class="text-green-400 text-sm">Build complete</div>
        <pre class="bg-gray-900 p-3 rounded text-xs overflow-auto h-80">
        <%= for evt <- @events do %>
          <%= inspect(evt) %>\n
        <% end %>
        </pre>
      </div>
    </Layouts.app>
    """
  end
end

