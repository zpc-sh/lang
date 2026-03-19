defmodule Lang.Workers.PerformanceMetricsWorker do
  @moduledoc """
  Background worker for collecting and processing performance metrics.

  Runs periodically via Oban cron to:
  - Collect performance metrics from various system components
  - Analyze performance trends
  - Generate performance reports
  - Clean up old metrics data
  - Send performance alerts if thresholds are exceeded
  """

  use Oban.Worker, queue: :metrics, max_attempts: 3

  require Logger
  alias Lang.{PerformanceMonitor, Events}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("Starting performance metrics collection")

    start_time = System.monotonic_time(:millisecond)

    try do
      metrics = collect_metrics(args)
      process_metrics(metrics)
      cleanup_old_metrics()

      duration = System.monotonic_time(:millisecond) - start_time
      Logger.info("Performance metrics collection completed in #{duration}ms")

      # Track this worker's own performance
      Events.track_event(%{
        event_type: "performance_metrics_collected",
        duration: duration,
        metrics_count: length(metrics),
        timestamp: DateTime.utc_now()
      })

      :ok
    rescue
      error ->
        Logger.error("Performance metrics collection failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Collect current performance metrics from various system components
  """
  defp collect_metrics(_args) do
    [
      collect_oban_metrics(),
      collect_database_metrics(),
      collect_native_nif_metrics(),
      collect_memory_metrics(),
      collect_process_metrics()
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Collect Oban job performance metrics
  """
  defp collect_oban_metrics do
    try do
      # Get basic Oban stats
      config = Oban.config()

      %{
        component: :oban,
        timestamp: DateTime.utc_now(),
        metrics: %{
          queues: Map.keys(config.queues),
          queue_sizes: get_queue_sizes(),
          total_jobs_today: count_jobs_today(),
          failed_jobs_today: count_failed_jobs_today()
        }
      }
    rescue
      _ -> nil
    end
  end

  @doc """
  Collect database performance metrics
  """
  defp collect_database_metrics do
    try do
      # Basic connection pool metrics
      pool_status = Ecto.Adapters.SQL.query(Lang.Repo, "SELECT 1", [])

      case pool_status do
        {:ok, _} ->
          %{
            component: :database,
            timestamp: DateTime.utc_now(),
            metrics: %{
              connection_status: :healthy,
              pool_size: get_pool_size(),
              active_connections: get_active_connections()
            }
          }

        {:error, reason} ->
          %{
            component: :database,
            timestamp: DateTime.utc_now(),
            metrics: %{
              connection_status: :unhealthy,
              error: inspect(reason)
            }
          }
      end
    rescue
      _ -> nil
    end
  end

  @doc """
  Collect native NIF performance metrics
  """
  defp collect_native_nif_metrics do
    try do
      nif_modules = [
        Lang.Native.FSScanner,
        Lang.Native.LangParser,
        Lang.Native.PerfEngine
      ]

      loaded_nifs =
        Enum.filter(nif_modules, fn module ->
          case Code.ensure_loaded(module) do
            {:module, _} -> true
            _ -> false
          end
        end)

      %{
        component: :native_nifs,
        timestamp: DateTime.utc_now(),
        metrics: %{
          total_nifs: length(nif_modules),
          loaded_nifs: length(loaded_nifs),
          loaded_modules: loaded_nifs
        }
      }
    rescue
      _ -> nil
    end
  end

  @doc """
  Collect system memory metrics
  """
  defp collect_memory_metrics do
    try do
      memory = :erlang.memory()

      %{
        component: :memory,
        timestamp: DateTime.utc_now(),
        metrics: %{
          total: memory[:total],
          processes: memory[:processes],
          system: memory[:system],
          atom: memory[:atom],
          binary: memory[:binary],
          ets: memory[:ets]
        }
      }
    rescue
      _ -> nil
    end
  end

  @doc """
  Collect process metrics
  """
  defp collect_process_metrics do
    try do
      %{
        component: :processes,
        timestamp: DateTime.utc_now(),
        metrics: %{
          process_count: :erlang.system_info(:process_count),
          process_limit: :erlang.system_info(:process_limit),
          port_count: :erlang.system_info(:port_count),
          port_limit: :erlang.system_info(:port_limit)
        }
      }
    rescue
      _ -> nil
    end
  end

  @doc """
  Process collected metrics - analyze trends and generate alerts
  """
  defp process_metrics(metrics) do
    Enum.each(metrics, fn metric ->
      case metric.component do
        :memory -> check_memory_thresholds(metric.metrics)
        :processes -> check_process_thresholds(metric.metrics)
        :database -> check_database_health(metric.metrics)
        _ -> :ok
      end
    end)

    # Store metrics for historical analysis
    store_metrics(metrics)
  end

  @doc """
  Check if memory usage exceeds thresholds
  """
  defp check_memory_thresholds(memory_metrics) do
    total_mb = div(memory_metrics.total, 1024 * 1024)

    # Alert if using more than 1GB
    if total_mb > 1000 do
      Logger.warning("High memory usage detected: #{total_mb}MB")

      Events.track_event(%{
        event_type: "high_memory_usage",
        memory_mb: total_mb,
        timestamp: DateTime.utc_now()
      })
    end
  end

  @doc """
  Check if process count exceeds thresholds
  """
  defp check_process_thresholds(process_metrics) do
    process_usage = process_metrics.process_count / process_metrics.process_limit

    # Alert if using more than 80% of process limit
    if process_usage > 0.8 do
      Logger.warning("High process usage: #{trunc(process_usage * 100)}%")

      Events.track_event(%{
        event_type: "high_process_usage",
        usage_percent: trunc(process_usage * 100),
        timestamp: DateTime.utc_now()
      })
    end
  end

  @doc """
  Check database connection health
  """
  defp check_database_health(db_metrics) do
    case db_metrics.connection_status do
      :unhealthy ->
        Logger.error("Database connection unhealthy: #{db_metrics[:error]}")

        Events.track_event(%{
          event_type: "database_connection_failed",
          error: db_metrics[:error],
          timestamp: DateTime.utc_now()
        })

      _ ->
        :ok
    end
  end

  @doc """
  Store metrics for historical analysis
  """
  defp store_metrics(metrics) do
    # Store in events system for now
    # In production, you might want to use a time-series database
    Events.track_event(%{
      event_type: "performance_metrics_snapshot",
      metrics: metrics,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Clean up old performance metrics to prevent storage bloat
  """
  defp cleanup_old_metrics do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-7, :day)

    # Clean up old performance events (older than 7 days)
    # This is a placeholder - implement based on your events storage system
    Logger.debug("Cleaning up performance metrics older than #{cutoff_date}")
  end

  # Helper functions for metrics collection

  defp get_queue_sizes do
    try do
      # This would need to be implemented based on your Oban setup
      # For now, return empty map
      %{}
    rescue
      _ -> %{}
    end
  end

  defp count_jobs_today do
    try do
      # Count jobs created today - placeholder implementation
      0
    rescue
      _ -> 0
    end
  end

  defp count_failed_jobs_today do
    try do
      # Count failed jobs today - placeholder implementation
      0
    rescue
      _ -> 0
    end
  end

  defp get_pool_size do
    try do
      # Get database connection pool size
      Application.get_env(:lang, Lang.Repo)[:pool_size] || 10
    rescue
      _ -> 10
    end
  end

  defp get_active_connections do
    try do
      # Get active database connections - placeholder
      5
    rescue
      _ -> 0
    end
  end
end
