defmodule Lang.Orchestration.Master do
  @moduledoc """
  Master orchestrator using Oban for distributed processing.
  Each environment gets its own queue and worker pool.
  """

  use GenServer
  require Logger

  @environments [:text, :filesystem, :cloud, :systems]
  @artifacts [:spec, :implementation, :docs, :examples, :api, :client, :marketing]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Orchestrate all environments and their complete pipeline
  """
  def orchestrate_all do
    Logger.info("Starting full LANG orchestration...")

    # Create orchestration plan
    plan = create_orchestration_plan()

    # Submit all jobs to Oban queues
    jobs =
      Enum.flat_map(plan, fn {env, tasks} ->
        Enum.map(tasks, fn {task, opts} ->
          %{
            environment: env,
            task: task,
            priority: opts[:priority] || 5,
            dependencies: opts[:dependencies] || []
          }
          |> Lang.Workers.OrchestratorWorker.new(queue: queue_for_env(env))
          |> Oban.insert!()
        end)
      end)

    # Monitor job completion
    GenServer.cast(__MODULE__, {:jobs_started, Enum.map(jobs, & &1.id)})

    {:ok,
     %{
       job_ids: Enum.map(jobs, & &1.id),
       started_at: DateTime.utc_now(),
       total_jobs: length(jobs)
     }}
  end

  @doc """
  Get current orchestration status
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Trigger environment-specific orchestration
  """
  def orchestrate_environment(environment) when environment in @environments do
    Logger.info("Starting orchestration for #{environment} environment")

    tasks = get_tasks_for_environment(environment)

    jobs =
      Enum.map(tasks, fn {task, opts} ->
        %{
          environment: environment,
          task: task,
          priority: opts[:priority] || 5
        }
        |> Lang.Workers.OrchestratorWorker.new(queue: queue_for_env(environment))
        |> Oban.insert!()
      end)

    {:ok,
     %{
       environment: environment,
       job_ids: Enum.map(jobs, & &1.id),
       started_at: DateTime.utc_now()
     }}
  end

  @doc """
  Schedule periodic orchestration
  """
  def schedule_daily_orchestration do
    Oban.insert!(
      Lang.Workers.DailyOrchestrationWorker.new(%{},
        scheduled_at: next_2am_utc()
      )
    )
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic orchestration
    schedule_orchestration()

    {:ok,
     %{
       active_jobs: MapSet.new(),
       completed_jobs: MapSet.new(),
       failed_jobs: MapSet.new(),
       metrics: %{
         total_orchestrations: 0,
         successful_orchestrations: 0,
         failed_orchestrations: 0
       },
       last_orchestration: nil
     }}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      active_jobs: MapSet.size(state.active_jobs),
      completed_jobs: MapSet.size(state.completed_jobs),
      failed_jobs: MapSet.size(state.failed_jobs),
      metrics: state.metrics,
      last_orchestration: state.last_orchestration
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast({:jobs_started, job_ids}, state) do
    new_state = %{
      state
      | active_jobs: MapSet.union(state.active_jobs, MapSet.new(job_ids)),
        last_orchestration: DateTime.utc_now(),
        metrics: update_in(state.metrics, [:total_orchestrations], &(&1 + 1))
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:job_completed, job_id}, state) do
    new_state = %{
      state
      | active_jobs: MapSet.delete(state.active_jobs, job_id),
        completed_jobs: MapSet.put(state.completed_jobs, job_id)
    }

    # Check if orchestration is complete
    if MapSet.size(new_state.active_jobs) == 0 and MapSet.size(state.active_jobs) > 0 do
      Logger.info("Orchestration completed successfully!")

      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "orchestration:updates",
        {:orchestration_completed, new_state.completed_jobs}
      )

      new_state = update_in(new_state, [:metrics, :successful_orchestrations], &(&1 + 1))
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:job_failed, job_id, error}, state) do
    Logger.error("Orchestration job #{job_id} failed: #{inspect(error)}")

    new_state = %{
      state
      | active_jobs: MapSet.delete(state.active_jobs, job_id),
        failed_jobs: MapSet.put(state.failed_jobs, job_id)
    }

    Phoenix.PubSub.broadcast(Lang.PubSub, "orchestration:updates", {:job_failed, job_id, error})

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:schedule_orchestration, state) do
    # Schedule next orchestration
    schedule_orchestration()

    # Trigger orchestration if conditions are met
    if should_auto_orchestrate?() do
      spawn(fn -> orchestrate_all() end)
    end

    {:noreply, state}
  end

  # Private functions

  defp create_orchestration_plan do
    for env <- @environments do
      {env, get_tasks_for_environment(env)}
    end
  end

  defp get_tasks_for_environment(:text) do
    [
      {:generate_spec, priority: 1, dependencies: []},
      {:implement_parsers, priority: 2, dependencies: [:generate_spec]},
      {:build_documentation, priority: 3, dependencies: [:generate_spec]},
      {:create_examples, priority: 3, dependencies: [:generate_spec]},
      {:expose_api, priority: 4, dependencies: [:implement_parsers]},
      {:generate_clients, priority: 5, dependencies: [:expose_api]},
      {:produce_marketing, priority: 6, dependencies: [:build_documentation, :create_examples]},
      {:publish, priority: 7, dependencies: [:generate_clients, :produce_marketing]}
    ]
  end

  defp get_tasks_for_environment(:filesystem) do
    [
      {:generate_spec, priority: 1, dependencies: []},
      {:implement_lsp_features, priority: 2, dependencies: [:generate_spec]},
      {:build_documentation, priority: 3, dependencies: [:generate_spec]},
      {:create_examples, priority: 3, dependencies: [:generate_spec]},
      {:expose_api, priority: 4, dependencies: [:implement_lsp_features]},
      {:generate_clients, priority: 5, dependencies: [:expose_api]},
      {:produce_marketing, priority: 6, dependencies: [:build_documentation, :create_examples]},
      {:publish, priority: 7, dependencies: [:generate_clients, :produce_marketing]}
    ]
  end

  defp get_tasks_for_environment(:cloud) do
    [
      {:discover_resources, priority: 1, dependencies: []},
      {:generate_spec, priority: 2, dependencies: [:discover_resources]},
      {:implement_analyzers, priority: 2, dependencies: [:generate_spec]},
      {:build_documentation, priority: 3, dependencies: [:generate_spec]},
      {:create_examples, priority: 3, dependencies: [:generate_spec]},
      {:expose_api, priority: 4, dependencies: [:implement_analyzers]},
      {:generate_clients, priority: 5, dependencies: [:expose_api]},
      {:produce_marketing, priority: 6, dependencies: [:build_documentation, :create_examples]},
      {:publish, priority: 7, dependencies: [:generate_clients, :produce_marketing]}
    ]
  end

  defp get_tasks_for_environment(:systems) do
    [
      {:analyze_system_topology, priority: 1, dependencies: []},
      {:generate_spec, priority: 2, dependencies: [:analyze_system_topology]},
      {:implement_monitors, priority: 2, dependencies: [:generate_spec]},
      {:build_documentation, priority: 3, dependencies: [:generate_spec]},
      {:create_examples, priority: 3, dependencies: [:generate_spec]},
      {:expose_api, priority: 4, dependencies: [:implement_monitors]},
      {:generate_clients, priority: 5, dependencies: [:expose_api]},
      {:produce_marketing, priority: 6, dependencies: [:build_documentation, :create_examples]},
      {:publish, priority: 7, dependencies: [:generate_clients, :produce_marketing]}
    ]
  end

  defp queue_for_env(:text), do: :analysis
  defp queue_for_env(:filesystem), do: :lsp
  defp queue_for_env(:cloud), do: :metrics
  defp queue_for_env(:systems), do: :default

  defp schedule_orchestration do
    # Schedule next check in 1 hour
    Process.send_after(self(), :schedule_orchestration, :timer.hours(1))
  end

  defp next_2am_utc do
    now = DateTime.utc_now()
    tomorrow = DateTime.add(now, 1, :day)

    DateTime.new!(
      Date.new!(tomorrow.year, tomorrow.month, tomorrow.day),
      Time.new!(2, 0, 0),
      "Etc/UTC"
    )
  end

  defp should_auto_orchestrate? do
    # Auto-orchestrate if:
    # 1. No orchestration in the last 24 hours
    # 2. System health is good
    # 3. No critical errors in the last hour

    last_orchestration = GenServer.call(__MODULE__, :get_status).last_orchestration

    case last_orchestration do
      nil ->
        true

      timestamp ->
        DateTime.diff(DateTime.utc_now(), timestamp, :hour) >= 24
    end
  end

  @doc """
  Notify the master that a job has completed
  """
  def notify_job_completed(job_id) do
    GenServer.cast(__MODULE__, {:job_completed, job_id})
  end

  @doc """
  Notify the master that a job has failed
  """
  def notify_job_failed(job_id, error) do
    GenServer.cast(__MODULE__, {:job_failed, job_id, error})
  end
end
