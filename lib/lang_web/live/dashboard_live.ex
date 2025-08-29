defmodule LangWeb.DashboardLive do
  use LangWeb, :live_view

  alias Lang.Analysis
  alias Lang.Analyses.Run

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id

    # Get user's analysis statistics
    user_stats = Analysis.get_user_analysis_stats(user_id)

    # Get recent projects
    recent_projects = Analysis.list_projects(user_id, limit: 5, order_by: :updated_at)

    # Get recent analysis sessions across all projects
    recent_sessions = get_recent_sessions(user_id)

    # Get pending/processing sessions
    active_sessions = get_active_sessions(user_id)

    {:ok,
     assign(socket,
       user_stats: user_stats,
       recent_projects: recent_projects,
       recent_sessions: recent_sessions,
       active_sessions: active_sessions,
       page_title: "Dashboard"
     )}
  end

  @impl true
  def handle_event("refresh_stats", _params, socket) do
    user_id = socket.assigns.current_user.id
    user_stats = Analysis.get_user_analysis_stats(user_id)

    {:noreply, assign(socket, user_stats: user_stats)}
  end

  @impl true
  def handle_event("cancel_session", %{"session_id" => session_id}, socket) do
    try do
      session = Analysis.get_analysis_session!(session_id)

      if Run.in_progress?(session) do
        case Analysis.cancel_analysis_session(session) do
          {:ok, _session} ->
            # Refresh active sessions
            user_id = socket.assigns.current_user.id
            active_sessions = get_active_sessions(user_id)

            {:noreply,
             socket
             |> assign(active_sessions: active_sessions)
             |> put_flash(:info, "Analysis session cancelled successfully")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to cancel session")}
        end
      else
        {:noreply, put_flash(socket, :error, "Session is not in progress")}
      end
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Session not found")}
    end
  end

  defp get_recent_sessions(user_id) do
    # Get all user projects
    project_ids =
      Analysis.list_projects(user_id)
      |> Enum.map(& &1.id)

    # Get recent sessions from all projects
    project_ids
    |> Enum.flat_map(fn project_id ->
      Analysis.list_analysis_sessions(project_id, limit: 20)
    end)
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
    |> Enum.take(10)
  end

  defp get_active_sessions(user_id) do
    # Get all user projects
    project_ids =
      Analysis.list_projects(user_id)
      |> Enum.map(& &1.id)

    # Get active sessions from all projects
    project_ids
    |> Enum.flat_map(fn project_id ->
      Analysis.list_analysis_sessions(project_id, status: "processing") ++
        Analysis.list_analysis_sessions(project_id, status: "pending")
    end)
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <div class="min-h-screen bg-base-100">
        <!-- Header -->
        <div class="bg-white shadow">
          <div class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
            <div class="flex justify-between items-center">
              <div>
                <h1 class="text-3xl font-bold text-gray-900">Analysis Dashboard</h1>
                <p class="mt-1 text-sm text-gray-500">
                  Monitor your code analysis progress and results
                </p>
              </div>
              <div class="flex gap-3">
                <%= if Application.get_env(:lang, :env) == :dev do %>
                  <.link href="/oban" class="btn btn-outline btn-sm">
                    <.icon name="hero-chart-bar" class="w-4 h-4 mr-2" /> Oban
                  </.link>
                <% end %>
                <button
                  class="btn btn-outline btn-sm"
                  phx-click="refresh_stats"
                >
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                    >
                    </path>
                  </svg>
                  Refresh
                </button>
                <.link href={~p"/analyze"} class="btn btn-primary btn-sm">
                  <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                    >
                    </path>
                  </svg>
                  New Analysis
                </.link>
              </div>
            </div>
          </div>
        </div>

        <div class="max-w-7xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
          <!-- Statistics Cards -->
          <div class="mb-6">
            <.link href="/fs/watch" class="btn btn-outline btn-sm">
              <.icon name="hero-eye" class="w-4 h-4 mr-2" /> Filesystem Watch Demo
            </.link>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
            <div class="stats shadow bg-white">
              <div class="stat">
                <div class="stat-figure text-primary">
                  <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                    >
                    </path>
                  </svg>
                </div>
                <div class="stat-title">Projects</div>
                <div class="stat-value text-primary">{@user_stats.total_projects}</div>
              </div>
            </div>

            <div class="stats shadow bg-white">
              <div class="stat">
                <div class="stat-figure text-secondary">
                  <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                    >
                    </path>
                  </svg>
                </div>
                <div class="stat-title">Files Analyzed</div>
                <div class="stat-value text-secondary">
                  {@user_stats.total_files |> Number.Delimit.number_to_delimited()}
                </div>
              </div>
            </div>

            <div class="stats shadow bg-white">
              <div class="stat">
                <div class="stat-figure text-warning">
                  <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
                    >
                    </path>
                  </svg>
                </div>
                <div class="stat-title">Issues Found</div>
                <div class="stat-value text-warning">
                  {@user_stats.total_violations |> Number.Delimit.number_to_delimited()}
                </div>
                <div class="stat-desc">{@user_stats.critical_violations} critical</div>
              </div>
            </div>

            <div class="stats shadow bg-white">
              <div class="stat">
                <div class="stat-figure text-success">
                  <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 10V3L4 14h7v7l9-11h-7z"
                    >
                    </path>
                  </svg>
                </div>
                <div class="stat-title">Recent Sessions</div>
                <div class="stat-value text-success">{@user_stats.recent_sessions}</div>
                <div class="stat-desc">Last 30 days</div>
              </div>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
            <!-- Recent Projects -->
            <div class="card bg-white shadow">
              <div class="card-header">
                <h2 class="card-title">Recent Projects</h2>
                <.link href={~p"/projects"} class="text-sm text-blue-600 hover:text-blue-500">
                  View all →
                </.link>
              </div>
              <div class="card-body">
                <%= if @recent_projects == [] do %>
                  <div class="text-center py-8">
                    <svg
                      class="w-12 h-12 mx-auto text-gray-400 mb-4"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                      >
                      </path>
                    </svg>
                    <h3 class="text-sm font-medium text-gray-900 mb-1">No projects yet</h3>
                    <p class="text-sm text-gray-500 mb-4">
                      Get started by creating your first project
                    </p>
                    <.link href={~p"/analyze"} class="btn btn-primary btn-sm">
                      Create Project
                    </.link>
                  </div>
                <% else %>
                  <div class="space-y-3">
                    <%= for project <- @recent_projects do %>
                      <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                        <div class="flex-1">
                          <div class="flex items-center gap-2">
                            <h3 class="font-medium text-gray-900">{project.name}</h3>
                            <span class={"badge badge-xs #{if project.status == "active", do: "badge-success", else: "badge-warning"}"}>
                              {project.status}
                            </span>
                          </div>
                          <%= if project.description do %>
                            <p class="text-sm text-gray-500 mt-1">{project.description}</p>
                          <% end %>
                          <div class="flex items-center gap-4 mt-2 text-xs text-gray-500">
                            <%= if project.language do %>
                              <span>{project.language}</span>
                            <% end %>
                            <span>Updated {relative_time(project.updated_at)}</span>
                          </div>
                        </div>
                        <div class="text-right">
                          <.link href={~p"/projects/#{project.id}"} class="btn btn-ghost btn-xs">
                            View →
                          </.link>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
            
    <!-- Active Sessions -->
            <div class="card bg-white shadow">
              <div class="card-header">
                <h2 class="card-title">Active Analysis Sessions</h2>
              </div>
              <div class="card-body">
                <%= if @active_sessions == [] do %>
                  <div class="text-center py-8">
                    <svg
                      class="w-12 h-12 mx-auto text-gray-400 mb-4"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M13 10V3L4 14h7v7l9-11h-7z"
                      >
                      </path>
                    </svg>
                    <h3 class="text-sm font-medium text-gray-900 mb-1">No active sessions</h3>
                    <p class="text-sm text-gray-500">All analysis sessions are completed</p>
                  </div>
                <% else %>
                  <div class="space-y-3">
                    <%= for session <- @active_sessions do %>
                      <div class="flex items-center justify-between p-3 bg-blue-50 rounded-lg border border-blue-200">
                        <div class="flex-1">
                          <div class="flex items-center gap-2">
                            <div class="flex items-center gap-2">
                              <%= if session.status == "processing" do %>
                                <div class="loading loading-spinner loading-xs text-blue-600"></div>
                              <% else %>
                                <div class="w-2 h-2 bg-yellow-400 rounded-full"></div>
                              <% end %>
                              <span class="font-medium text-gray-900">
                                {Run.status_description(session)}
                              </span>
                            </div>
                          </div>
                          <div class="text-sm text-gray-600 mt-1">
                            {session.file_count} files • Started {relative_time(session.started_at)}
                          </div>
                          <%= if session.status == "processing" and session.processing_time_ms do %>
                            <div class="text-xs text-gray-500 mt-1">
                              Processing for {duration_in_words(Run.duration(session))}
                            </div>
                          <% end %>
                        </div>
                        <div class="flex items-center gap-2">
                          <.link href={~p"/sessions/#{session.id}"} class="btn btn-ghost btn-xs">
                            View
                          </.link>
                          <%= if Run.in_progress?(session) do %>
                            <button
                              class="btn btn-outline btn-error btn-xs"
                              phx-click="cancel_session"
                              phx-value-session_id={session.id}
                              data-confirm="Are you sure you want to cancel this analysis?"
                            >
                              Cancel
                            </button>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Recent Sessions -->
          <div class="card bg-white shadow mt-8">
            <div class="card-header">
              <h2 class="card-title">Recent Analysis Sessions</h2>
            </div>
            <div class="card-body">
              <%= if @recent_sessions == [] do %>
                <div class="text-center py-8">
                  <svg
                    class="w-12 h-12 mx-auto text-gray-400 mb-4"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                    >
                    </path>
                  </svg>
                  <h3 class="text-sm font-medium text-gray-900 mb-1">No analysis sessions yet</h3>
                  <p class="text-sm text-gray-500">Start analyzing your code to see results here</p>
                </div>
              <% else %>
                <div class="overflow-x-auto">
                  <table class="table table-zebra w-full">
                    <thead>
                      <tr>
                        <th>Status</th>
                        <th>Started</th>
                        <th>Files</th>
                        <th>Issues</th>
                        <th>Duration</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for session <- @recent_sessions do %>
                        <tr>
                          <td>
                            <div class="flex items-center gap-2">
                              <div class={"w-2 h-2 rounded-full #{status_color(session.status)}"}>
                              </div>
                              <span class="capitalize">{session.status}</span>
                            </div>
                          </td>
                          <td>{relative_time(session.started_at)}</td>
                          <td>{session.file_count || 0}</td>
                          <td>
                            <div class="flex items-center gap-1">
                              <span>{session.violations_count || 0}</span>
                              <%= if session.critical_issues_count && session.critical_issues_count > 0 do %>
                                <span class="badge badge-error badge-xs">
                                  {session.critical_issues_count}
                                </span>
                              <% end %>
                            </div>
                          </td>
                          <td>
                            <%= if session.processing_time_ms do %>
                              {duration_in_words(session.processing_time_ms)}
                            <% else %>
                              <%= if Run.in_progress?(session) do %>
                                {duration_in_words(Run.duration(session))}
                              <% else %>
                                -
                              <% end %>
                            <% end %>
                          </td>
                          <td>
                            <.link href={~p"/sessions/#{session.id}"} class="btn btn-ghost btn-xs">
                              View
                            </.link>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Helper functions

  defp relative_time(datetime) when is_nil(datetime), do: "Unknown"

  defp relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 ->
        "#{diff}s ago"

      diff < 3600 ->
        minutes = div(diff, 60)
        "#{minutes}m ago"

      diff < 86400 ->
        hours = div(diff, 3600)
        "#{hours}h ago"

      diff < 604_800 ->
        days = div(diff, 86400)
        "#{days}d ago"

      true ->
        Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  defp duration_in_words(nil), do: "-"

  defp duration_in_words(ms) when is_integer(ms) do
    cond do
      ms < 1000 ->
        "#{ms}ms"

      ms < 60_000 ->
        seconds = div(ms, 1000)
        "#{seconds}s"

      ms < 3_600_000 ->
        minutes = div(ms, 60_000)
        seconds = div(rem(ms, 60_000), 1000)
        if seconds > 0, do: "#{minutes}m #{seconds}s", else: "#{minutes}m"

      true ->
        hours = div(ms, 3_600_000)
        minutes = div(rem(ms, 3_600_000), 60_000)
        if minutes > 0, do: "#{hours}h #{minutes}m", else: "#{hours}h"
    end
  end

  defp status_color("completed"), do: "bg-green-400"
  defp status_color("processing"), do: "bg-blue-400"
  defp status_color("pending"), do: "bg-yellow-400"
  defp status_color("failed"), do: "bg-red-400"
  defp status_color("cancelled"), do: "bg-gray-400"
  defp status_color(_), do: "bg-gray-300"
end
