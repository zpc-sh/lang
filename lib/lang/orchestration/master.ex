defmodule Lang.Orchestration.Master do
  @moduledoc """
  Central orchestration controller for LANG.

  - Exposes `orchestrate_all/0`, `orchestrate_environment/1`, and `get_status/0` for dashboard/workers
  - Provides LSP-facing workflow helpers: `start_workflow/2`, `get_status/1`, `cancel_workflow/1`
  - Tracks job lifecycle via `notify_job_completed/1` and `notify_job_failed/2`
  - Uses Oban workers for execution; broadcasts updates via `Phoenix.PubSub`
  """

  use GenServer
  require Logger

  alias Lang.Workers.{OrchestratorWorker, OrchestrationMonitor}

  # Public API -----------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Dashboard APIs
  def orchestrate_all do
    GenServer.call(__MODULE__, :orchestrate_all)
  end

  def orchestrate_environment(env) when is_atom(env) do
    GenServer.call(__MODULE__, {:orchestrate_env, env})
  end

  def get_status do
    GenServer.call(__MODULE__, :status)
  end

  # LSP Workflow APIs (ids are simple UUIDs)
  def start_workflow(workflow, params \\ %{}) do
    GenServer.call(__MODULE__, {:start_workflow, workflow, params})
  end

  def get_status(workflow_id) when is_binary(workflow_id) do
    GenServer.call(__MODULE__, {:workflow_status, workflow_id})
  end

  def cancel_workflow(workflow_id) when is_binary(workflow_id) do
    GenServer.call(__MODULE__, {:cancel_workflow, workflow_id})
  end

  # Workers notify completion/failure
  def notify_job_completed(job_id) when is_binary(job_id) do
    GenServer.cast(__MODULE__, {:job_completed, job_id})
  end

  def notify_job_failed(job_id, error) when is_binary(job_id) do
    GenServer.cast(__MODULE__, {:job_failed, job_id, error})
  end

  # GenServer ------------------------------------------------------------------

  @impl true
  def init(_opts) do
    state = %{
      started_at: DateTime.utc_now(),
      last_orchestration: nil,
      total_orchestrations: 0,
      successful_orchestrations: 0,
      failed_orchestrations: 0,
      active_jobs: %{},         # job_id => %{env, task, inserted_at}
      completed_jobs: MapSet.new(),
      failed_jobs: %{},         # job_id => reason
      workflows: %{}            # workflow_id => %{status, started_at, jobs: [job_id], metadata: %{}}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:orchestrate_all, _from, state) do
    envs = [:text, :filesystem, :cloud, :systems]
    {job_ids, state} = enqueue_env_sets(envs, state)

    # Kick off a progress monitor
    _ = schedule_progress_check(job_ids)

    {:reply, {:ok, %{job_ids: job_ids, started_at: DateTime.utc_now()}},
     bump_orchestration(state)}
  end

  @impl true
  def handle_call({:orchestrate_env, env}, _from, state) do
    {job_ids, state} = enqueue_env_sets([env], state)
    _ = schedule_progress_check(job_ids)
    {:reply, {:ok, %{job_ids: job_ids, started_at: DateTime.utc_now()}},
     bump_orchestration(state)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      active_jobs: map_size(state.active_jobs),
      completed_jobs: MapSet.size(state.completed_jobs),
      failed_jobs: map_size(state.failed_jobs),
      total_orchestrations: state.total_orchestrations,
      successful_orchestrations: state.successful_orchestrations,
      failed_orchestrations: state.failed_orchestrations,
      last_orchestration: state.last_orchestration
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:start_workflow, workflow, params}, _from, state) do
    workflow_id = Ecto.UUID.generate()
    jobs = enqueue_workflow_jobs(workflow, params)

    workflows =
      Map.put(state.workflows, workflow_id, %{
        status: :running,
        started_at: DateTime.utc_now(),
        jobs: jobs,
        metadata: %{requested_by: Map.get(params, "user_id")}
      })

    Phoenix.PubSub.broadcast(Lang.PubSub, "orchestration:updates", {:workflow_started, workflow_id})
    {:reply, {:ok, workflow_id}, %{state | workflows: workflows}}
  end

  @impl true
  def handle_call({:workflow_status, workflow_id}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      nil -> {:reply, {:error, :not_found}, state}
      wf -> {:reply, {:ok, normalize_workflow_status(wf)}, state}
    end
  end

  @impl true
  def handle_call({:cancel_workflow, workflow_id}, _from, state) do
    case Map.get(state.workflows, workflow_id) do
      nil -> {:reply, {:error, :not_found}, state}
      wf ->
        # Best-effort: mark cancelled; any running jobs will complete/fail on their own
        workflows = Map.put(state.workflows, workflow_id, Map.put(wf, :status, :cancelled))
        Phoenix.PubSub.broadcast(Lang.PubSub, "orchestration:updates", {:workflow_cancelled, workflow_id})
        {:reply, :ok, %{state | workflows: workflows}}
    end
  end

  @impl true
  def handle_cast({:job_completed, job_id}, state) do
    active = Map.delete(state.active_jobs, job_id)
    completed = MapSet.put(state.completed_jobs, job_id)

    Phoenix.PubSub.broadcast(Lang.PubSub, "orchestration:updates", {:job_completed, job_id})
    {:noreply, %{state | active_jobs: active, completed_jobs: completed}}
  end

  @impl true
  def handle_cast({:job_failed, job_id, error}, state) do
    active = Map.delete(state.active_jobs, job_id)
    failed = Map.put(state.failed_jobs, job_id, inspect(error))

    Phoenix.PubSub.broadcast(Lang.PubSub, "orchestration:updates", {:job_failed, job_id, error})
    {:noreply, %{state | active_jobs: active, failed_jobs: failed}}
  end

  # Internal -------------------------------------------------------------------

  defp enqueue_env_sets(envs, state) do
    {job_ids, new_active} =
      envs
      |> Enum.flat_map(&jobs_for_env/1)
      |> Enum.map(&enqueue_job/1)
      |> Enum.reduce({[], %{}}, fn {job_id, meta}, {ids, acc} ->
        {[job_id | ids], Map.put(acc, job_id, meta)}
      end)

    Phoenix.PubSub.broadcast(Lang.PubSub, "orchestration:updates", {:jobs_enqueued, Enum.reverse(job_ids)})
    {Enum.reverse(job_ids), %{state | active_jobs: Map.merge(state.active_jobs, new_active)}}
  end

  defp jobs_for_env(:text) do
    [
      {:text, :generate_spec},
      {:text, :build_documentation},
      {:text, :create_examples},
      {:text, :generate_clients},
      {:text, :produce_marketing},
      {:text, :publish}
    ]
  end

  defp jobs_for_env(env) when env in [:filesystem, :cloud, :systems] do
    [
      {env, :generate_spec},
      {env, :build_documentation},
      {env, :create_examples},
      {env, :publish}
    ]
  end

  defp enqueue_job({env, task}) do
    job_id = Ecto.UUID.generate()
    args = %{environment: env, task: task, job_id: job_id}

    args
    |> OrchestratorWorker.new(queue: :orchestration)
    |> Oban.insert!()

    {job_id, %{env: env, task: task, inserted_at: DateTime.utc_now()}}
  end

  defp schedule_progress_check(job_ids) do
    %{"action" => "progress_check", "job_ids" => job_ids, "started_at" => DateTime.utc_now()}
    |> OrchestrationMonitor.new(queue: :metrics, scheduled_at: DateTime.add(DateTime.utc_now(), 30, :second))
    |> Oban.insert()
  end

  defp bump_orchestration(state) do
    %{state | total_orchestrations: state.total_orchestrations + 1, last_orchestration: DateTime.utc_now()}
  end

  defp enqueue_workflow_jobs(_workflow, _params) do
    # Minimal viable workflow: kick off a text spec gen and docs build
    [{:text, :generate_spec}, {:text, :build_documentation}]
    |> Enum.map(&enqueue_job/1)
    |> Enum.map(&elem(&1, 0))
  end

  defp normalize_workflow_status(%{status: status, jobs: jobs, started_at: started_at} = wf) do
    %{
      status: status,
      started_at: started_at,
      active_jobs: Enum.count(jobs, &(&1 in Map.keys(Process.get(:active_jobs, %{})))),
      total_jobs: length(jobs),
      jobs: jobs
    }
  end
end
