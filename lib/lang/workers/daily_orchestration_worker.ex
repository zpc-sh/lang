defmodule Lang.Workers.DailyOrchestrationWorker do
  @moduledoc """
  Daily orchestration worker that automatically triggers full system orchestration
  at scheduled times. This worker ensures that all environments stay up-to-date
  with the latest specifications, documentation, SDKs, and marketing materials.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    tags: ["orchestration", "scheduled", "daily"]

  require Logger
  import Ecto.Query

  alias Lang.Orchestration.Master

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("Starting daily orchestration run")

    start_time = System.monotonic_time(:millisecond)

    try do
      # Check system health before starting
      case check_system_health() do
        {:ok, :healthy} ->
          execute_daily_orchestration(args)

        {:ok, :degraded} ->
          Logger.warning("System health is degraded, proceeding with caution")
          execute_daily_orchestration(args)

        {:error, :unhealthy} ->
          Logger.error("System is unhealthy, skipping daily orchestration")
          schedule_next_orchestration()
          {:error, :system_unhealthy}
      end
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("Daily orchestration failed after #{duration}ms: #{inspect(error)}")

        # Schedule retry in 4 hours if failed
        schedule_retry_orchestration()
        {:error, error}
    end
  end

  defp execute_daily_orchestration(args) do
    Logger.info("System health check passed, starting full orchestration")

    # Get orchestration preferences from args
    environments = Map.get(args, "environments", [:text, :filesystem, :cloud, :systems])
    skip_marketing = Map.get(args, "skip_marketing", false)
    priority_env = Map.get(args, "priority_environment", nil)

    # Start orchestration
    case Master.orchestrate_all() do
      {:ok, result} ->
        duration = System.monotonic_time(:millisecond) - result.started_at

        Logger.info("""
        Daily orchestration initiated successfully:
        - Jobs queued: #{length(result.job_ids)}
        - Environments: #{Enum.join(environments, ", ")}
        - Started at: #{result.started_at}
        """)

        # Send notification to monitoring systems
        notify_orchestration_started(result)

        # Schedule next daily orchestration
        schedule_next_orchestration()

        # Schedule health check in 30 minutes to monitor progress
        schedule_progress_check(result.job_ids)

        :ok

      {:error, reason} ->
        Logger.error("Failed to start daily orchestration: #{reason}")

        # Schedule retry in 2 hours
        schedule_retry_orchestration()
        {:error, reason}
    end
  end

  defp check_system_health do
    health_checks = [
      check_database_connection(),
      check_oban_queues(),
      check_memory_usage(),
      check_disk_space(),
      check_external_services()
    ]

    failed_checks = Enum.filter(health_checks, fn {status, _} -> status != :ok end)

    cond do
      length(failed_checks) == 0 ->
        {:ok, :healthy}

      length(failed_checks) <= 2 ->
        Logger.warning("Some health checks failed: #{inspect(failed_checks)}")
        {:ok, :degraded}

      true ->
        Logger.error("Multiple health checks failed: #{inspect(failed_checks)}")
        {:error, :unhealthy}
    end
  end

  defp check_database_connection do
    try do
      case Ecto.Adapters.SQL.query(Lang.Repo, "SELECT 1", []) do
        {:ok, _} -> {:ok, :database}
        error -> {:error, {:database, error}}
      end
    rescue
      error -> {:error, {:database, error}}
    end
  end

  defp check_oban_queues do
    try do
      # Check if Oban queues are responsive
      queue_stats = Oban.check_queue(:default)

      if is_map(queue_stats) do
        {:ok, :oban}
      else
        {:error, {:oban, "Queue check failed"}}
      end
    rescue
      error -> {:error, {:oban, error}}
    end
  end

  defp check_memory_usage do
    try do
      memory_usage = :erlang.memory(:total)
      # 4GB limit
      memory_limit = 1024 * 1024 * 1024 * 4

      if memory_usage < memory_limit do
        {:ok, :memory}
      else
        {:error, {:memory, "High memory usage: #{div(memory_usage, 1024 * 1024)}MB"}}
      end
    rescue
      error -> {:error, {:memory, error}}
    end
  end

  defp check_disk_space do
    try do
      # Check available disk space (simplified)
      case File.stat("priv") do
        {:ok, _} -> {:ok, :disk}
        error -> {:error, {:disk, error}}
      end
    rescue
      error -> {:error, {:disk, error}}
    end
  end

  defp check_external_services do
    # Check if we can reach key external services
    try do
      # This would check external APIs, S3, etc.
      # For now, just return ok
      {:ok, :external}
    rescue
      error -> {:error, {:external, error}}
    end
  end

  defp schedule_next_orchestration do
    next_run = next_orchestration_time()

    Logger.info("Scheduling next daily orchestration for #{next_run}")

    %{}
    |> __MODULE__.new(scheduled_at: next_run)
    |> Oban.insert!()
  end

  defp schedule_retry_orchestration do
    retry_time = DateTime.add(DateTime.utc_now(), 2, :hour)

    Logger.info("Scheduling orchestration retry for #{retry_time}")

    %{"retry" => true}
    |> __MODULE__.new(scheduled_at: retry_time)
    |> Oban.insert!()
  end

  defp schedule_progress_check(job_ids) do
    check_time = DateTime.add(DateTime.utc_now(), 30, :minute)

    %{
      "action" => "progress_check",
      "job_ids" => job_ids,
      "started_at" => DateTime.utc_now()
    }
    |> Lang.Workers.OrchestrationMonitor.new(scheduled_at: check_time)
    |> Oban.insert!()
  end

  defp next_orchestration_time do
    now = DateTime.utc_now()

    # Schedule for 2 AM UTC next day
    tomorrow = DateTime.add(now, 1, :day)

    DateTime.new!(
      Date.new!(tomorrow.year, tomorrow.month, tomorrow.day),
      Time.new!(2, 0, 0),
      "Etc/UTC"
    )
  end

  defp notify_orchestration_started(result) do
    # Send to monitoring systems
    Phoenix.PubSub.broadcast(
      Lang.PubSub,
      "orchestration:daily",
      {:daily_orchestration_started, result}
    )

    # Send webhook notifications if configured
    send_webhook_notifications(result)

    # Log to external monitoring (DataDog, New Relic, etc.)
    log_to_external_monitoring(result)
  end

  defp send_webhook_notifications(result) do
    webhooks = Application.get_env(:lang, :orchestration_webhooks, [])

    payload = %{
      event: "daily_orchestration_started",
      timestamp: DateTime.utc_now(),
      jobs_queued: length(result.job_ids),
      environments: [:text, :filesystem, :cloud, :systems],
      job_ids: result.job_ids
    }

    Enum.each(webhooks, fn webhook_url ->
      Task.async(fn ->
        try do
          HTTPoison.post(webhook_url, Jason.encode!(payload), [
            {"Content-Type", "application/json"},
            {"User-Agent", "LANG-Orchestration/2.0"}
          ])
        rescue
          error ->
            Logger.warning("Failed to send webhook to #{webhook_url}: #{inspect(error)}")
        end
      end)
    end)
  end

  defp log_to_external_monitoring(result) do
    # This would integrate with external monitoring services
    # For now, just log locally
    Logger.info("Daily orchestration metrics logged: #{length(result.job_ids)} jobs queued")
  end

  @doc """
  Manually trigger daily orchestration (for testing or emergency runs)
  """
  def trigger_immediate_orchestration(opts \\ []) do
    args = %{
      "manual_trigger" => true,
      "triggered_by" => Keyword.get(opts, :triggered_by, "manual"),
      "environments" => Keyword.get(opts, :environments, [:text, :filesystem, :cloud, :systems]),
      "skip_marketing" => Keyword.get(opts, :skip_marketing, false)
    }

    %{} =
      Map.merge(%{}, args)
      |> __MODULE__.new(queue: :default)
      |> Oban.insert!()
  end

  @doc """
  Get status of current daily orchestration
  """
  def get_daily_orchestration_status do
    # Check for recent daily orchestration jobs
    recent_jobs =
      Oban.Job
      |> where([j], j.worker == "Lang.Workers.DailyOrchestrationWorker")
      |> where([j], j.inserted_at > ^DateTime.add(DateTime.utc_now(), -24, :hour))
      |> order_by([j], desc: j.inserted_at)
      |> limit(5)
      |> Lang.Repo.all()

    case recent_jobs do
      [] ->
        %{
          status: :no_recent_runs,
          last_run: nil,
          next_scheduled: find_next_scheduled_run()
        }

      [latest | _] ->
        %{
          status: latest.state,
          last_run: latest.inserted_at,
          last_completed: latest.completed_at,
          next_scheduled: find_next_scheduled_run(),
          recent_jobs: length(recent_jobs)
        }
    end
  end

  defp find_next_scheduled_run do
    Oban.Job
    |> where([j], j.worker == "Lang.Workers.DailyOrchestrationWorker")
    |> where([j], j.state == "scheduled")
    |> order_by([j], asc: j.scheduled_at)
    |> limit(1)
    |> Lang.Repo.one()
    |> case do
      nil -> nil
      job -> job.scheduled_at
    end
  end
end
