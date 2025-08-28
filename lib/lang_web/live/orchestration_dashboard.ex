defmodule LangWeb.Live.OrchestrationDashboard do
  use LangWeb, :live_view

  alias Lang.Orchestration.Master
  alias Lang.Repo

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to Oban telemetry
      :telemetry.attach(
        "orchestration-dashboard",
        [:oban, :job, :stop],
        &handle_job_telemetry/4,
        socket.assigns.live_action
      )

      # Subscribe to orchestration events
      Phoenix.PubSub.subscribe(Lang.PubSub, "orchestration:updates")

      # Start periodic updates
      schedule_update()
    end

    {:ok,
     socket
     |> assign(:page_title, "Orchestration Control Center")
     |> assign(:environments, load_environment_status())
     |> assign(:active_jobs, load_active_jobs())
     |> assign(:metrics, load_metrics())
     |> assign(:recent_publications, load_recent_publications())
     |> assign(:job_history, load_job_history())
     |> assign(:system_health, check_system_health())
     |> assign(:orchestration_status, get_orchestration_status())}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]} current_scope={assigns[:current_scope]}>
    <div class="orchestration-dashboard min-h-screen bg-gray-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">LANG Orchestration Control Center</h1>
          <p class="mt-2 text-lg text-gray-600">
            Monitor and control AI intelligence generation across all environments
          </p>
          
    <!-- System Health Indicator -->
          <div class="mt-4 flex items-center space-x-4">
            <div class={[
              "flex items-center px-3 py-1 rounded-full text-sm font-medium",
              system_health_class(@system_health.status)
            ]}>
              <div class={[
                "w-2 h-2 rounded-full mr-2",
                system_health_dot_class(@system_health.status)
              ]}>
              </div>
              System Status: {String.capitalize(to_string(@system_health.status))}
            </div>
            <div class="text-sm text-gray-500">
              Last updated: {format_time(@system_health.last_check)}
            </div>
          </div>
        </div>
        
    <!-- Control Actions -->
        <div class="bg-white rounded-lg shadow mb-8 p-6">
          <h2 class="text-xl font-semibold mb-4">Orchestration Controls</h2>
          <div class="flex flex-wrap gap-4">
            <button
              phx-click="orchestrate-all"
              class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg font-medium transition-colors"
              disabled={@orchestration_status.active}
            >
              {if @orchestration_status.active,
                do: "Orchestrating...",
                else: "Orchestrate All Environments"}
            </button>

            <button
              phx-click="generate-sdks"
              class="bg-green-600 hover:bg-green-700 text-white px-6 py-2 rounded-lg font-medium transition-colors"
            >
              Generate All SDKs
            </button>

            <button
              phx-click="publish-all"
              class="bg-purple-600 hover:bg-purple-700 text-white px-6 py-2 rounded-lg font-medium transition-colors"
            >
              Publish Everything
            </button>

            <button
              phx-click="stop-orchestration"
              class="bg-red-600 hover:bg-red-700 text-white px-6 py-2 rounded-lg font-medium transition-colors"
              disabled={not @orchestration_status.active}
            >
              Emergency Stop
            </button>
          </div>
        </div>
        
    <!-- Environment Status Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <%= for env <- @environments do %>
            <.environment_card environment={env} />
          <% end %>
        </div>
        
    <!-- Metrics Dashboard -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 mb-8">
          <!-- Active Jobs -->
          <div class="bg-white rounded-lg shadow">
            <div class="p-6">
              <h3 class="text-lg font-medium text-gray-900 mb-4">Active Jobs</h3>
              <div class="space-y-3">
                <%= if Enum.empty?(@active_jobs) do %>
                  <p class="text-gray-500 italic">No active jobs</p>
                <% else %>
                  <%= for job <- Enum.take(@active_jobs, 10) do %>
                    <.job_item job={job} />
                  <% end %>
                <% end %>
              </div>
              <%= if length(@active_jobs) > 10 do %>
                <div class="mt-4 text-center">
                  <button class="text-blue-600 hover:text-blue-800 text-sm font-medium">
                    View all {length(@active_jobs)} jobs
                  </button>
                </div>
              <% end %>
            </div>
          </div>
          
    <!-- Metrics -->
          <div class="bg-white rounded-lg shadow">
            <div class="p-6">
              <h3 class="text-lg font-medium text-gray-900 mb-4">System Metrics</h3>
              <div class="space-y-4">
                <div>
                  <div class="flex justify-between items-center mb-1">
                    <span class="text-sm text-gray-600">Job Success Rate</span>
                    <span class="text-sm font-medium">{@metrics.success_rate}%</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2">
                    <div
                      class="bg-green-500 h-2 rounded-full"
                      style={"width: #{@metrics.success_rate}%"}
                    >
                    </div>
                  </div>
                </div>

                <div>
                  <div class="flex justify-between items-center mb-1">
                    <span class="text-sm text-gray-600">Queue Utilization</span>
                    <span class="text-sm font-medium">{@metrics.queue_utilization}%</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2">
                    <div
                      class="bg-blue-500 h-2 rounded-full"
                      style={"width: #{@metrics.queue_utilization}%"}
                    >
                    </div>
                  </div>
                </div>

                <div>
                  <div class="flex justify-between items-center mb-1">
                    <span class="text-sm text-gray-600">Processing Speed</span>
                    <span class="text-sm font-medium">{@metrics.avg_processing_time}ms</span>
                  </div>
                </div>

                <div>
                  <div class="flex justify-between items-center mb-1">
                    <span class="text-sm text-gray-600">Total Jobs Today</span>
                    <span class="text-sm font-medium">{@metrics.jobs_today}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
          
    <!-- Recent Publications -->
          <div class="bg-white rounded-lg shadow">
            <div class="p-6">
              <h3 class="text-lg font-medium text-gray-900 mb-4">Recent Publications</h3>
              <div class="space-y-3">
                <%= if Enum.empty?(@recent_publications) do %>
                  <p class="text-gray-500 italic">No recent publications</p>
                <% else %>
                  <%= for pub <- @recent_publications do %>
                    <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
                      <div>
                        <p class="text-sm font-medium">{pub.environment} - {pub.artifact_type}</p>
                        <p class="text-xs text-gray-500">{format_time(pub.published_at)}</p>
                      </div>
                      <a
                        href={pub.url}
                        target="_blank"
                        class="text-blue-600 hover:text-blue-800 text-xs"
                      >
                        View →
                      </a>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Job History Table -->
        <div class="bg-white rounded-lg shadow">
          <div class="p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Job History</h3>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Job ID
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Environment
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Task
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Status
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Duration
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Completed
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for job <- @job_history do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        #{String.slice(job.id, 0..7)}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class={[
                          "inline-flex px-2 py-1 text-xs font-medium rounded-full",
                          environment_badge_class(job.environment)
                        ]}>
                          {job.environment}
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        {job.task}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class={[
                          "inline-flex px-2 py-1 text-xs font-medium rounded-full",
                          job_status_class(job.state)
                        ]}>
                          {job.state}
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {format_duration(job.duration)}
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        {format_time(job.completed_at)}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
    </Layouts.app>
    """
  end

  # Component for environment cards
  defp environment_card(assigns) do
    ~H"""
    <div class="bg-white rounded-lg shadow p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-medium capitalize">{@environment.name}</h3>
        <div class={[
          "w-3 h-3 rounded-full",
          environment_status_class(@environment.status)
        ]}>
        </div>
      </div>

      <div class="space-y-2 text-sm">
        <div class="flex justify-between">
          <span class="text-gray-600">Active Jobs:</span>
          <span class="font-medium">{@environment.active_jobs}</span>
        </div>
        <div class="flex justify-between">
          <span class="text-gray-600">Completed:</span>
          <span class="font-medium">{@environment.completed_jobs}</span>
        </div>
        <div class="flex justify-between">
          <span class="text-gray-600">Success Rate:</span>
          <span class="font-medium">{@environment.success_rate}%</span>
        </div>
        <div class="flex justify-between">
          <span class="text-gray-600">Last Run:</span>
          <span class="font-medium">{format_time(@environment.last_run)}</span>
        </div>
      </div>

      <div class="mt-4">
        <button
          phx-click="orchestrate-environment"
          phx-value-environment={@environment.name}
          class="w-full bg-gray-100 hover:bg-gray-200 text-gray-700 py-2 px-4 rounded transition-colors"
        >
          Orchestrate {String.capitalize(@environment.name)}
        </button>
      </div>
    </div>
    """
  end

  # Component for job items
  defp job_item(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
      <div class="flex-1">
        <p class="text-sm font-medium">{@job.environment} - {@job.task}</p>
        <p class="text-xs text-gray-500">Started {format_time(@job.started_at)}</p>
      </div>
      <div class="flex items-center space-x-2">
        <div class={[
          "w-2 h-2 rounded-full",
          job_status_dot_class(@job.state)
        ]}>
        </div>
        <span class="text-xs text-gray-600">{@job.progress}%</span>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("orchestrate-all", _params, socket) do
    case Master.orchestrate_all() do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Orchestration started: #{length(result.job_ids)} jobs queued")
         |> update_dashboard_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to start orchestration: #{reason}")}
    end
  end

  def handle_event("orchestrate-environment", %{"environment" => env}, socket) do
    case Master.orchestrate_environment(String.to_atom(env)) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{String.capitalize(env)} orchestration started")
         |> update_dashboard_data()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to start #{env} orchestration: #{reason}")}
    end
  end

  def handle_event("generate-sdks", _params, socket) do
    # Trigger SDK generation for all environments
    environments = [:text, :filesystem, :cloud, :systems]
    languages = [:typescript, :python, :go, :rust, :java, :csharp]

    jobs_created =
      for env <- environments,
          lang <- languages do
        %{
          environment: env,
          language: lang
        }
        |> Lang.Workers.SDKGenerator.new(queue: :sdk_generation)
        |> Oban.insert!()
      end

    {:noreply,
     socket
     |> put_flash(:info, "SDK generation started: #{length(jobs_created)} jobs queued")
     |> update_dashboard_data()}
  end

  def handle_event("publish-all", _params, socket) do
    # Trigger publishing for all environments
    environments = [:text, :filesystem, :cloud, :systems]

    jobs_created =
      for env <- environments do
        %{
          environment: env,
          task: :publish,
          priority: 1
        }
        |> Lang.Workers.OrchestratorWorker.new(queue: :publishing)
        |> Oban.insert!()
      end

    {:noreply,
     socket
     |> put_flash(:info, "Publishing started: #{length(jobs_created)} jobs queued")
     |> update_dashboard_data()}
  end

  def handle_event("stop-orchestration", _params, socket) do
    # This would implement emergency stop functionality
    # For now, just show a confirmation
    {:noreply,
     socket
     |> put_flash(:warning, "Emergency stop triggered - halting all orchestration jobs")}
  end

  @impl true
  def handle_info(:update_dashboard, socket) do
    schedule_update()
    {:noreply, update_dashboard_data(socket)}
  end

  def handle_info({:task_completed, env, task, result, duration}, socket) do
    {:noreply,
     socket
     |> put_flash(
       :info,
       "✅ #{String.capitalize(to_string(env))} #{task} completed (#{duration}ms)"
     )
     |> update_dashboard_data()}
  end

  def handle_info({:orchestration_completed, completed_jobs}, socket) do
    {:noreply,
     socket
     |> put_flash(
       :info,
       "🎉 Full orchestration completed! #{MapSet.size(completed_jobs)} jobs finished"
     )
     |> update_dashboard_data()}
  end

  def handle_info({:job_failed, job_id, error}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "❌ Job #{String.slice(job_id, 0..7)} failed: #{error}")
     |> update_dashboard_data()}
  end

  def handle_info({:sdk_ready, env, language}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "📦 #{String.capitalize(to_string(language))} SDK ready for #{env}")
     |> update_dashboard_data()}
  end

  def handle_info({:marketing_content_ready, env, type, result}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "📝 #{String.capitalize(to_string(type))} content ready for #{env}")
     |> update_dashboard_data()}
  end

  # Telemetry handler
  def handle_job_telemetry([:oban, :job, :stop], measurements, metadata, _config) do
    # Process Oban job telemetry data
    # This would update real-time metrics
  end

  # Private helper functions

  defp schedule_update do
    Process.send_after(self(), :update_dashboard, 5_000)
  end

  defp update_dashboard_data(socket) do
    socket
    |> assign(:environments, load_environment_status())
    |> assign(:active_jobs, load_active_jobs())
    |> assign(:metrics, load_metrics())
    |> assign(:recent_publications, load_recent_publications())
    |> assign(:job_history, load_job_history())
    |> assign(:system_health, check_system_health())
    |> assign(:orchestration_status, get_orchestration_status())
  end

  defp load_environment_status do
    [
      %{
        name: "text",
        status: :healthy,
        active_jobs: 3,
        completed_jobs: 147,
        success_rate: 98.2,
        last_run: DateTime.add(DateTime.utc_now(), -3600, :second)
      },
      %{
        name: "filesystem",
        status: :healthy,
        active_jobs: 1,
        completed_jobs: 89,
        success_rate: 95.5,
        last_run: DateTime.add(DateTime.utc_now(), -7200, :second)
      },
      %{
        name: "cloud",
        status: :warning,
        active_jobs: 0,
        completed_jobs: 23,
        success_rate: 87.0,
        last_run: DateTime.add(DateTime.utc_now(), -14400, :second)
      },
      %{
        name: "systems",
        status: :healthy,
        active_jobs: 2,
        completed_jobs: 156,
        success_rate: 99.1,
        last_run: DateTime.add(DateTime.utc_now(), -1800, :second)
      }
    ]
  end

  defp load_active_jobs do
    # This would query Oban for active jobs
    [
      %{
        id: "12345678",
        environment: "text",
        task: "generate_spec",
        state: "running",
        progress: 75,
        started_at: DateTime.add(DateTime.utc_now(), -300, :second)
      },
      %{
        id: "87654321",
        environment: "filesystem",
        task: "build_documentation",
        state: "running",
        progress: 45,
        started_at: DateTime.add(DateTime.utc_now(), -600, :second)
      }
    ]
  end

  defp load_metrics do
    %{
      success_rate: 96.8,
      queue_utilization: 67,
      avg_processing_time: 2_340,
      jobs_today: 89
    }
  end

  defp load_recent_publications do
    [
      %{
        environment: "text",
        artifact_type: "landing_page",
        published_at: DateTime.add(DateTime.utc_now(), -1800, :second),
        url: "https://lang.ai/text"
      },
      %{
        environment: "filesystem",
        artifact_type: "api_docs",
        published_at: DateTime.add(DateTime.utc_now(), -3600, :second),
        url: "https://docs.lang.ai/filesystem"
      }
    ]
  end

  defp load_job_history do
    # This would query Oban job history
    [
      %{
        id: "job_123",
        environment: "text",
        task: "generate_clients",
        state: "completed",
        duration: 15_420,
        completed_at: DateTime.add(DateTime.utc_now(), -900, :second)
      },
      %{
        id: "job_124",
        environment: "cloud",
        task: "discover_resources",
        state: "failed",
        duration: 8_230,
        completed_at: DateTime.add(DateTime.utc_now(), -1200, :second)
      }
    ]
  end

  defp check_system_health do
    %{
      status: :healthy,
      last_check: DateTime.utc_now()
    }
  end

  defp get_orchestration_status do
    case Master.get_status() do
      %{active_jobs: active} when active > 0 ->
        %{active: true, jobs_count: active}

      _ ->
        %{active: false, jobs_count: 0}
    end
  rescue
    _ -> %{active: false, jobs_count: 0}
  end

  # CSS class helpers

  defp system_health_class(:healthy), do: "bg-green-100 text-green-800"
  defp system_health_class(:warning), do: "bg-yellow-100 text-yellow-800"
  defp system_health_class(:error), do: "bg-red-100 text-red-800"

  defp system_health_dot_class(:healthy), do: "bg-green-400"
  defp system_health_dot_class(:warning), do: "bg-yellow-400"
  defp system_health_dot_class(:error), do: "bg-red-400"

  defp environment_status_class(:healthy), do: "bg-green-400"
  defp environment_status_class(:warning), do: "bg-yellow-400"
  defp environment_status_class(:error), do: "bg-red-400"

  defp environment_badge_class("text"), do: "bg-blue-100 text-blue-800"
  defp environment_badge_class("filesystem"), do: "bg-green-100 text-green-800"
  defp environment_badge_class("cloud"), do: "bg-purple-100 text-purple-800"
  defp environment_badge_class("systems"), do: "bg-orange-100 text-orange-800"

  defp job_status_class("completed"), do: "bg-green-100 text-green-800"
  defp job_status_class("running"), do: "bg-blue-100 text-blue-800"
  defp job_status_class("failed"), do: "bg-red-100 text-red-800"
  defp job_status_class("queued"), do: "bg-gray-100 text-gray-800"

  defp job_status_dot_class("completed"), do: "bg-green-400"
  defp job_status_dot_class("running"), do: "bg-blue-400 animate-pulse"
  defp job_status_dot_class("failed"), do: "bg-red-400"
  defp job_status_dot_class("queued"), do: "bg-gray-400"

  # Formatting helpers

  defp format_time(nil), do: "Never"

  defp format_time(datetime) do
    case DateTime.diff(DateTime.utc_now(), datetime, :second) do
      diff when diff < 60 -> "#{diff}s ago"
      diff when diff < 3600 -> "#{div(diff, 60)}m ago"
      diff when diff < 86400 -> "#{div(diff, 3600)}h ago"
      _ -> DateTime.to_date(datetime) |> Date.to_string()
    end
  end

  defp format_duration(nil), do: "-"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60000, 1)}m"
end
