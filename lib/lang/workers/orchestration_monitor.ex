defmodule Lang.Workers.OrchestrationMonitor do
  @moduledoc """
  Monitors orchestration job progress and provides status updates.
  This worker tracks job completion, identifies stuck jobs, and provides
  real-time progress reporting for the orchestration dashboard.
  """

  use Oban.Worker,
    queue: :metrics,
    max_attempts: 2,
    tags: ["monitoring", "orchestration"]

  require Logger
  import Ecto.Query

  alias Lang.Orchestration.Master

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "progress_check"} = args}) do
    job_ids = Map.get(args, "job_ids", [])
    started_at = Map.get(args, "started_at")

    Logger.info("Checking progress for #{length(job_ids)} orchestration jobs")

    progress_report = generate_progress_report(job_ids, started_at)

    # Broadcast progress update
    Phoenix.PubSub.broadcast(
      Lang.PubSub,
      "orchestration:updates",
      {:progress_report, progress_report}
    )

    # Check for stuck jobs
    stuck_jobs = identify_stuck_jobs(job_ids)

    if length(stuck_jobs) > 0 do
      handle_stuck_jobs(stuck_jobs)
    end

    # Schedule next progress check if jobs are still running
    if progress_report.active_jobs > 0 do
      schedule_next_progress_check(job_ids, started_at)
    else
      Logger.info("All orchestration jobs completed")
      notify_orchestration_complete(progress_report)
    end

    :ok
  end

  def perform(%Oban.Job{args: %{"action" => "health_check"}}) do
    Logger.info("Performing orchestration system health check")

    health_report = %{
      timestamp: DateTime.utc_now(),
      queue_stats: get_queue_statistics(),
      worker_stats: get_worker_statistics(),
      error_rate: calculate_error_rate(),
      performance_metrics: get_performance_metrics()
    }

    # Broadcast health report
    Phoenix.PubSub.broadcast(
      Lang.PubSub,
      "orchestration:health",
      {:health_report, health_report}
    )

    # Alert if issues detected
    if health_report.error_rate > 0.1 do
      alert_high_error_rate(health_report)
    end

    :ok
  end

  def perform(%Oban.Job{args: %{"action" => "cleanup_stale_jobs"}}) do
    Logger.info("Cleaning up stale orchestration jobs")

    cleanup_results = cleanup_stale_jobs()

    Logger.info("Cleanup completed: #{inspect(cleanup_results)}")

    :ok
  end

  defp generate_progress_report(job_ids, started_at) do
    # Query job statuses from Oban
    jobs = get_jobs_by_ids(job_ids)

    completed_jobs = Enum.filter(jobs, &(&1.state == "completed"))
    failed_jobs = Enum.filter(jobs, &(&1.state in ["cancelled", "discarded"]))
    active_jobs = Enum.filter(jobs, &(&1.state in ["available", "executing", "retryable"]))

    total_jobs = length(jobs)

    completion_percentage =
      if total_jobs > 0, do: length(completed_jobs) / total_jobs * 100, else: 0

    estimated_completion = estimate_completion_time(active_jobs, completed_jobs, started_at)

    environment_progress = calculate_environment_progress(jobs)

    %{
      timestamp: DateTime.utc_now(),
      total_jobs: total_jobs,
      completed_jobs: length(completed_jobs),
      failed_jobs: length(failed_jobs),
      active_jobs: length(active_jobs),
      completion_percentage: Float.round(completion_percentage, 1),
      estimated_completion: estimated_completion,
      environment_progress: environment_progress,
      started_at: started_at,
      duration_so_far: calculate_duration(started_at)
    }
  end

  defp get_jobs_by_ids(job_ids) do
    if length(job_ids) > 0 do
      Oban.Job
      |> where([j], j.id in ^job_ids)
      |> Lang.Repo.all()
    else
      []
    end
  end

  defp calculate_environment_progress(jobs) do
    jobs
    |> Enum.group_by(fn job ->
      get_in(job.args, ["environment"]) || "unknown"
    end)
    |> Enum.map(fn {env, env_jobs} ->
      completed = Enum.count(env_jobs, &(&1.state == "completed"))
      total = length(env_jobs)

      %{
        environment: env,
        completed: completed,
        total: total,
        percentage: if(total > 0, do: Float.round(completed / total * 100, 1), else: 0)
      }
    end)
  end

  defp estimate_completion_time(active_jobs, completed_jobs, started_at) do
    if length(active_jobs) == 0 do
      "Completed"
    else
      # Calculate average job duration from completed jobs
      avg_duration = calculate_average_duration(completed_jobs)

      if avg_duration > 0 do
        # Convert to seconds
        remaining_time = avg_duration * length(active_jobs) / 1000
        DateTime.add(DateTime.utc_now(), round(remaining_time), :second)
      else
        "Unknown"
      end
    end
  end

  defp calculate_average_duration(completed_jobs) do
    if length(completed_jobs) > 0 do
      total_duration =
        Enum.reduce(completed_jobs, 0, fn job, acc ->
          if job.completed_at && job.attempted_at do
            duration = DateTime.diff(job.completed_at, List.first(job.attempted_at), :millisecond)
            acc + duration
          else
            acc
          end
        end)

      total_duration / length(completed_jobs)
    else
      0
    end
  end

  defp calculate_duration(started_at) when is_binary(started_at) do
    case DateTime.from_iso8601(started_at) do
      {:ok, datetime, _} -> calculate_duration(datetime)
      _ -> "Unknown"
    end
  end

  defp calculate_duration(started_at) do
    DateTime.diff(DateTime.utc_now(), started_at, :second)
  end

  defp identify_stuck_jobs(job_ids) do
    # Find jobs that have been executing for too long (> 30 minutes)
    cutoff_time = DateTime.add(DateTime.utc_now(), -30, :minute)

    Oban.Job
    |> where([j], j.id in ^job_ids)
    |> where([j], j.state == "executing")
    |> where([j], j.attempted_at < ^cutoff_time)
    |> Lang.Repo.all()
  end

  defp handle_stuck_jobs(stuck_jobs) do
    Logger.warning("Found #{length(stuck_jobs)} stuck jobs")

    Enum.each(stuck_jobs, fn job ->
      Logger.warning("Stuck job detected: #{job.id} (#{job.worker})")

      # Cancel the stuck job
      Oban.cancel_job(job.id)

      # Optionally restart it
      restart_job(job)
    end)

    # Notify administrators
    notify_stuck_jobs(stuck_jobs)
  end

  defp restart_job(job) do
    # Create a new job with the same parameters
    new_args = Map.put(job.args, "restarted_from", job.id)

    worker_module = String.to_existing_atom("Elixir.#{job.worker}")

    new_args
    |> worker_module.new()
    |> Oban.insert!()

    Logger.info("Restarted stuck job #{job.id} as new job")
  end

  defp schedule_next_progress_check(job_ids, started_at) do
    check_time = DateTime.add(DateTime.utc_now(), 5, :minute)

    %{
      "action" => "progress_check",
      "job_ids" => job_ids,
      "started_at" => started_at
    }
    |> __MODULE__.new(scheduled_at: check_time)
    |> Oban.insert!()
  end

  defp notify_orchestration_complete(progress_report) do
    Logger.info("""
    Orchestration completed:
    - Total jobs: #{progress_report.total_jobs}
    - Completed: #{progress_report.completed_jobs}
    - Failed: #{progress_report.failed_jobs}
    - Duration: #{progress_report.duration_so_far} seconds
    """)

    Phoenix.PubSub.broadcast(
      Lang.PubSub,
      "orchestration:updates",
      {:orchestration_complete, progress_report}
    )
  end

  defp get_queue_statistics do
    queues = [:default, :analysis, :lsp, :metrics, :sdk_generation, :publishing, :marketing]

    Enum.map(queues, fn queue ->
      stats = Oban.check_queue(queue)

      %{
        queue: queue,
        available: Map.get(stats, :available, 0),
        executing: Map.get(stats, :executing, 0),
        scheduled: Map.get(stats, :scheduled, 0)
      }
    end)
  end

  defp get_worker_statistics do
    # Get statistics for orchestration workers
    workers = [
      "Lang.Workers.OrchestratorWorker",
      "Lang.Workers.TextEnvironment",
      "Lang.Workers.SDKGenerator",
      "Lang.Workers.MarketingGenerator",
      "Lang.Workers.DailyOrchestrationWorker"
    ]

    Enum.map(workers, fn worker ->
      recent_jobs = get_recent_jobs_for_worker(worker)

      %{
        worker: worker,
        recent_jobs: length(recent_jobs),
        success_rate: calculate_worker_success_rate(recent_jobs),
        avg_duration: calculate_worker_avg_duration(recent_jobs)
      }
    end)
  end

  defp get_recent_jobs_for_worker(worker) do
    cutoff = DateTime.add(DateTime.utc_now(), -24, :hour)

    Oban.Job
    |> where([j], j.worker == ^worker)
    |> where([j], j.inserted_at > ^cutoff)
    |> Lang.Repo.all()
  end

  defp calculate_worker_success_rate(jobs) do
    if length(jobs) > 0 do
      successful = Enum.count(jobs, &(&1.state == "completed"))
      Float.round(successful / length(jobs) * 100, 1)
    else
      0.0
    end
  end

  defp calculate_worker_avg_duration(jobs) do
    completed_jobs = Enum.filter(jobs, &(&1.state == "completed" && &1.completed_at))
    calculate_average_duration(completed_jobs)
  end

  defp calculate_error_rate do
    cutoff = DateTime.add(DateTime.utc_now(), -1, :hour)

    total_jobs =
      Oban.Job
      |> where([j], j.inserted_at > ^cutoff)
      |> where(
        [j],
        j.worker in [
          "Lang.Workers.OrchestratorWorker",
          "Lang.Workers.TextEnvironment",
          "Lang.Workers.SDKGenerator",
          "Lang.Workers.MarketingGenerator"
        ]
      )
      |> Lang.Repo.aggregate(:count)

    failed_jobs =
      Oban.Job
      |> where([j], j.inserted_at > ^cutoff)
      |> where([j], j.state in ["cancelled", "discarded"])
      |> where(
        [j],
        j.worker in [
          "Lang.Workers.OrchestratorWorker",
          "Lang.Workers.TextEnvironment",
          "Lang.Workers.SDKGenerator",
          "Lang.Workers.MarketingGenerator"
        ]
      )
      |> Lang.Repo.aggregate(:count)

    if total_jobs > 0 do
      failed_jobs / total_jobs
    else
      0.0
    end
  end

  defp get_performance_metrics do
    %{
      memory_usage: get_memory_usage(),
      queue_latency: calculate_queue_latency(),
      throughput: calculate_throughput()
    }
  end

  defp get_memory_usage do
    # MB
    :erlang.memory(:total) / (1024 * 1024)
  end

  defp calculate_queue_latency do
    # Calculate average time jobs spend in queue before execution
    cutoff = DateTime.add(DateTime.utc_now(), -1, :hour)

    jobs =
      Oban.Job
      |> where([j], j.inserted_at > ^cutoff)
      |> where([j], j.state == "completed")
      |> limit(100)
      |> Lang.Repo.all()

    if length(jobs) > 0 do
      total_latency =
        Enum.reduce(jobs, 0, fn job, acc ->
          if length(job.attempted_at) > 0 do
            first_attempt = List.first(job.attempted_at)
            latency = DateTime.diff(first_attempt, job.inserted_at, :millisecond)
            acc + latency
          else
            acc
          end
        end)

      total_latency / length(jobs)
    else
      0
    end
  end

  defp calculate_throughput do
    # Jobs completed per minute over last hour
    cutoff = DateTime.add(DateTime.utc_now(), -1, :hour)

    completed_jobs =
      Oban.Job
      |> where([j], j.completed_at > ^cutoff)
      |> where([j], j.state == "completed")
      |> Lang.Repo.aggregate(:count)

    # per minute
    completed_jobs / 60.0
  end

  defp cleanup_stale_jobs do
    # Clean up jobs older than 7 days
    cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    {deleted_count, _} =
      Oban.Job
      |> where([j], j.completed_at < ^cutoff)
      |> where([j], j.state in ["completed", "cancelled", "discarded"])
      |> Lang.Repo.delete_all()

    %{deleted_jobs: deleted_count, cutoff_date: cutoff}
  end

  defp alert_high_error_rate(health_report) do
    Logger.error("High error rate detected: #{health_report.error_rate * 100}%")

    Phoenix.PubSub.broadcast(
      Lang.PubSub,
      "orchestration:alerts",
      {:high_error_rate, health_report}
    )
  end

  defp notify_stuck_jobs(stuck_jobs) do
    Phoenix.PubSub.broadcast(
      Lang.PubSub,
      "orchestration:alerts",
      {:stuck_jobs, stuck_jobs}
    )
  end

  @doc """
  Schedule a periodic health check
  """
  def schedule_health_check do
    %{"action" => "health_check"}
    # Every 15 minutes
    |> __MODULE__.new(schedule: "*/15 * * * *")
    |> Oban.insert!()
  end

  @doc """
  Schedule stale job cleanup
  """
  def schedule_cleanup do
    %{"action" => "cleanup_stale_jobs"}
    # Daily at 3 AM
    |> __MODULE__.new(schedule: "0 3 * * *")
    |> Oban.insert!()
  end

  @doc """
  Get current orchestration system status
  """
  def get_system_status do
    %{
      queue_stats: get_queue_statistics(),
      worker_stats: get_worker_statistics(),
      error_rate: calculate_error_rate(),
      performance_metrics: get_performance_metrics(),
      timestamp: DateTime.utc_now()
    }
  end
end
