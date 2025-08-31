
defmodule LangWeb.SessionAuditLive do
  use LangWeb, :live_view
  alias Lang.Events

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Lang.PubSub, "events:all")
    end
    {:ok, assign(socket, events: load_events(100), filter: "")}
  end

  @impl true
  def handle_info({:event_tracked, event}, socket) do
    name = Map.get(event, :activity_name)
    if is_binary(name) and String.starts_with?(name, "mdld_session_") do
      {:noreply, update(socket, :events, fn evs -> [event | evs] |> Enum.take(100) end)}
    else
      {:noreply, socket}
    end
  end


  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, filter: q, events: load_events(100, q))}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    csv = to_csv(socket.assigns.events)
    {:noreply, Phoenix.LiveView.send_download(socket, {:binary, csv}, filename: "session_audit.csv", content_type: "text/csv")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto p-6">
        <h1 class="text-2xl font-semibold mb-4">Session Audit</h1>
        <.form for={%{}} phx-change="filter" class="mb-4">
          <input name="q" value={@filter} placeholder="Filter (e.g. started, ended)" class="w-full bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm"/>
        </.form>
        <button phx-click="export_csv" class="btn btn-xs mb-4">Export CSV</button>
        <div id="audit" class="space-y-2">
          <%= for ev <- @events do %>
            <div class="rounded border border-gray-800 bg-gray-900 p-3 text-sm">
              <div class="flex items-center justify-between">
                <div class="text-gray-200"><%= ev.activity_name %></div>
                <div class="text-xs text-gray-500"><%= format_time(ev.occurred_at) %></div>
              </div>
              <div class="mt-1 text-xs text-gray-400">
                <%= inspect(ev.metadata) %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_events(limit, q \\ "") do
    import Ash.Query

    case Lang.Events.UserActivityEvent
      |> Ash.Query.filter(fragment("activity_name LIKE ?", ^"mdld_session_%"))
         |> Ash.Query.sort(occurred_at: :desc)
         |> Ash.Query.limit(limit)
         |> Ash.read() do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp format_time(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_string()
  end
  defp format_time(%DateTime{} = dt), do: DateTime.to_string(dt)
  defp format_time(_), do: ""

  defp to_csv(events) do
    header = "activity_name,occurred_at,metadata\n"
    rows =
      for ev <- events do
        meta = ev.metadata |> Jason.encode!() |> String.replace("\n", " ")
        "#{ev.activity_name},#{format_time(ev.occurred_at)},#{meta}\n"
      end
      |> Enum.join("")

    header <> rows
  end
end
