defmodule LangWeb.KGBuildIndexLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"stream_id" => ""}, as: :kg)

    {:ok,
     socket
     |> assign(:form, form)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("go", %{"kg" => %{"stream_id" => id}}, socket) do
    id = String.trim(to_string(id))
    if id == "" do
      {:noreply, assign(socket, :error, "Please enter a stream_id")}
    else
      {:noreply, push_navigate(socket, to: "/lsp/kg_build/" <> id)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="max-w-md mx-auto py-8">
        <h1 class="text-xl font-semibold mb-4">Knowledge Graph Build Viewer</h1>
        <p class="text-sm text-gray-400 mb-6">Paste a <code>stream_id</code> returned by <code>lang.graph.build</code> with <code>"stream": true</code>.</p>
        <.form for={@form} id="kg-form" phx-submit="go" class="space-y-3">
          <.input field={@form[:stream_id]} type="text" placeholder="kg_..." />
          <div class="flex items-center gap-3">
            <button class="btn btn-primary" type="submit">Open Stream</button>
            <%= if @error do %>
              <span class="text-red-400 text-sm"><%= @error %></span>
            <% end %>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end

