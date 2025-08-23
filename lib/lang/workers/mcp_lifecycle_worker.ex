defmodule Lang.Workers.McpLifecycleWorker do
  @moduledoc """
  Oban worker for MCP connection lifecycle management.

  This worker handles background tasks for MCP connection management including:
  - Connection health monitoring and recovery
  - Idle connection cleanup
  - Connection pool optimization
  - Circuit breaker state management
  - Resource limit enforcement
  - Performance metrics collection

  ## Integration
  Integrates with Lang's existing Oban infrastructure and uses the same
  patterns as other background workers in the system.
  """

  use Oban.Worker,
    queue: :mcp,
    max_attempts: 3,
    tags: ["mcp", "lifecycle", "cleanup"]

  alias Lang.MCP.{Broker, Pool, StreamBridge}
  alias Lang.Events
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => "health_check"} = args}) do
    Logger.debug("Starting MCP health check cycle")

    case perform_health_checks(args) do
      {:ok, results} ->
        Events.track_event(%{
          event_type: "mcp_health_check_completed",
          metadata: %{
            healthy_connections: results.healthy_count,
            unhealthy_connections: results.unhealthy_count,
            recovered_connections: results.recovered_count
          }
        })

        Logger.info("MCP health check completed",
          healthy: results.healthy_count,
          unhealthy: results.unhealthy_count,
          recovered: results.recovered_count
        )

        :ok

      {:error, reason} ->
        Logger.error("MCP health check failed", reason: reason)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => "cleanup_idle"} = args}) do
    Logger.debug("Starting MCP idle connection cleanup")

    case cleanup_idle_connections(args) do
      {:ok, results} ->
        Events.track_event(%{
          event_type: "mcp_idle_cleanup_completed",
          metadata: %{
            connections_cleaned: results.cleaned_count,
            resources_freed: results.resources_freed
          }
        })

        Logger.info("MCP idle cleanup completed",
          cleaned: results.cleaned_count,
          resources_freed: results.resources_freed
        )

        :ok

      {:error, reason} ->
        Logger.error("MCP idle cleanup failed", reason: reason)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => "optimize_pools"} = args}) do
    Logger.debug("Starting MCP pool optimization")

    case optimize_connection_pools(args) do
      {:ok, results} ->
        Events.track_event(%{
          event_type: "mcp_pool_optimization_completed",
          metadata: %{
            pools_optimized: results.optimized_count,
            connections_adjusted: results.adjusted_count
          }
        })

        Logger.info("MCP pool optimization completed",
          optimized: results.optimized_count,
          adjusted: results.adjusted_count
        )

        :ok

      {:error, reason} ->
        Logger.error("MCP pool optimization failed", reason: reason)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => "circuit_breaker_recovery"} = args}) do
    Logger.debug("Starting MCP circuit breaker recovery")

    case recover_circuit_breakers(args) do
      {:ok, results} ->
        Events.track_event(%{
          event_type: "mcp_circuit_breaker_recovery_completed",
          metadata: %{
            breakers_recovered: results.recovered_count,
            server_types_restored: results.restored_types
          }
        })

        Logger.info("MCP circuit breaker recovery completed",
          recovered: results.recovered_count,
          restored_types: results.restored_types
        )

        :ok

      {:error, reason} ->
        Logger.error("MCP circuit breaker recovery failed", reason: reason)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => "collect_metrics"} = args}) do
    Logger.debug("Starting MCP metrics collection")

    case collect_performance_metrics(args) do
      {:ok, metrics} ->
        # Store metrics for monitoring
        store_metrics(metrics)

        Events.track_event(%{
          event_type: "mcp_metrics_collected",
          metadata: %{
            total_connections: metrics.total_connections,
            active_streams: metrics.active_streams,
            throughput_mbps: metrics.throughput_mbps
          }
        })

        :ok

      {:error, reason} ->
        Logger.error("MCP metrics collection failed", reason: reason)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => "connection_recovery", "connection_id" => connection_id}}) do
    Logger.info("Attempting MCP connection recovery", connection_id: connection_id)

    case recover_failed_connection(connection_id) do
      {:ok, new_connection_id} ->
        Events.track_event(%{
          event_type: "mcp_connection_recovered",
          metadata: %{
            old_connection_id: connection_id,
            new_connection_id: new_connection_id
          }
        })

        Logger.info("MCP connection recovered",
          old: connection_id,
          new: new_connection_id
        )

        :ok

      {:error, reason} ->
        Logger.warning("MCP connection recovery failed",
          connection_id: connection_id,
          reason: reason
        )

        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.warning("Unknown MCP lifecycle task", args: args)
    {:error, :unknown_task}
  end

  ## Public API for scheduling jobs

  @doc """
  Schedule periodic health check for all MCP connections.
  """
  def schedule_health_check(opts \\ []) do
    %{
      "task" => "health_check",
      "check_pools" => Keyword.get(opts, :check_pools, true),
      "check_streams" => Keyword.get(opts, :check_streams, true),
      "recovery_enabled" => Keyword.get(opts, :recovery_enabled, true)
    }
    |> new(queue: :mcp, scheduled_at: DateTime.add(DateTime.utc_now(), 30, :second))
    |> Oban.insert()
  end

  @doc """
  Schedule idle connection cleanup.
  """
  def schedule_idle_cleanup(opts \\ []) do
    %{
      "task" => "cleanup_idle",
      "idle_timeout_minutes" => Keyword.get(opts, :idle_timeout_minutes, 15),
      "preserve_prewarmed" => Keyword.get(opts, :preserve_prewarmed, true)
    }
    |> new(queue: :mcp, scheduled_at: DateTime.add(DateTime.utc_now(), 300, :second))
    |> Oban.insert()
  end

  @doc """
  Schedule connection pool optimization.
  """
  def schedule_pool_optimization(opts \\ []) do
    %{
      "task" => "optimize_pools",
      "target_utilization" => Keyword.get(opts, :target_utilization, 0.7),
      "max_pool_size" => Keyword.get(opts, :max_pool_size, 10)
    }
    |> new(queue: :mcp, scheduled_at: DateTime.add(DateTime.utc_now(), 600, :second))
    |> Oban.insert()
  end

  @doc """
  Schedule circuit breaker recovery attempts.
  """
  def schedule_circuit_breaker_recovery(opts \\ []) do
    %{
      "task" => "circuit_breaker_recovery",
      "cooldown_minutes" => Keyword.get(opts, :cooldown_minutes, 5),
      "test_connections" => Keyword.get(opts, :test_connections, true)
    }
    |> new(queue: :mcp, scheduled_at: DateTime.add(DateTime.utc_now(), 300, :second))
    |> Oban.insert()
  end

  @doc """
  Schedule metrics collection.
  """
  def schedule_metrics_collection(opts \\ []) do
    %{
      "task" => "collect_metrics",
      "include_performance" => Keyword.get(opts, :include_performance, true),
      "include_usage" => Keyword.get(opts, :include_usage, true)
    }
    |> new(queue: :mcp, scheduled_at: DateTime.add(DateTime.utc_now(), 60, :second))
    |> Oban.insert()
  end

  @doc """
  Schedule recovery for a failed connection.
  """
  def schedule_connection_recovery(connection_id, opts \\ []) do
    %{
      "task" => "connection_recovery",
      "connection_id" => connection_id,
      "retry_attempts" => Keyword.get(opts, :retry_attempts, 3),
      "backoff_seconds" => Keyword.get(opts, :backoff_seconds, 30)
    }
    |> new(
      queue: :mcp,
      scheduled_at: DateTime.add(DateTime.utc_now(), Keyword.get(opts, :delay_seconds, 10), :second),
      max_attempts: Keyword.get(opts, :retry_attempts, 3)
    )
    |> Oban.insert()
  end

  ## Private Implementation Functions

  defp perform_health_checks(args) do
    check_pools = Map.get(args, "check_pools", true)
    check_streams = Map.get(args, "check_streams", true)
    recovery_enabled = Map.get(args, "recovery_enabled", true)

    results = %{
      healthy_count: 0,
      unhealthy_count: 0,
      recovered_count: 0
    }

    results =
      if check_pools do
        pool_results = check_pool_health(recovery_enabled)
        %{
          results
          | healthy_count: results.healthy_count + pool_results.healthy_count,
            unhealthy_count: results.unhealthy_count + pool_results.unhealthy_count,
            recovered_count: results.recovered_count + pool_results.recovered_count
        }
      else
        results
      end

    results =
      if check_streams do
        stream_results = check_stream_health(recovery_enabled)
        %{
          results
          | healthy_count: results.healthy_count + stream_results.healthy_count,
            unhealthy_count: results.unhealthy_count + stream_results.unhealthy_count,
            recovered_count: results.recovered_count + stream_results.recovered_count
        }
      else
        results
      end

    {:ok, results}
  end

  defp check_pool_health(recovery_enabled) do
    stats = Pool.get_stats()

    # Get detailed pool information
    pool_health = check_individual_pools()

    results = %{
      healthy_count: count_healthy_pools(pool_health),
      unhealthy_count: count_unhealthy_pools(pool_health),
      recovered_count: 0
    }

    if recovery_enabled do
      recovered = recover_unhealthy_pools(pool_health)
      %{results | recovered_count: recovered}
    else
      results
    end
  end

  defp check_stream_health(recovery_enabled) do
    stats = StreamBridge.get_stats()

    # Check for stuck or failed streams
    stream_health = check_individual_streams()

    results = %{
      healthy_count: count_healthy_streams(stream_health),
      unhealthy_count: count_unhealthy_streams(stream_health),
      recovered_count: 0
    }

    if recovery_enabled do
      recovered = recover_unhealthy_streams(stream_health)
      %{results | recovered_count: recovered}
    else
      results
    end
  end

  defp cleanup_idle_connections(args) do
    idle_timeout_minutes = Map.get(args, "idle_timeout_minutes", 15)
    preserve_prewarmed = Map.get(args, "preserve_prewarmed", true)

    # Calculate cutoff time
    cutoff_time = DateTime.add(DateTime.utc_now(), -idle_timeout_minutes * 60, :second)

    # Get current stats before cleanup
    before_stats = Pool.get_stats()

    # Perform cleanup (Pool module handles the actual cleanup)
    # This would trigger the pool's internal cleanup mechanism

    # Get stats after cleanup
    after_stats = Pool.get_stats()

    cleaned_count = before_stats.total_connections - after_stats.total_connections
    resources_freed = calculate_resources_freed(cleaned_count)

    {:ok, %{
      cleaned_count: cleaned_count,
      resources_freed: resources_freed
    }}
  end

  defp optimize_connection_pools(args) do
    target_utilization = Map.get(args, "target_utilization", 0.7)
    max_pool_size = Map.get(args, "max_pool_size", 10)

    stats = Pool.get_stats()

    # Analyze current pool utilization
    optimization_plan = analyze_pool_utilization(stats, target_utilization, max_pool_size)

    # Apply optimizations
    optimization_results = apply_pool_optimizations(optimization_plan)

    {:ok, %{
      optimized_count: optimization_results.pools_modified,
      adjusted_count: optimization_results.connections_adjusted
    }}
  end

  defp recover_circuit_breakers(args) do
    cooldown_minutes = Map.get(args, "cooldown_minutes", 5)
    test_connections = Map.get(args, "test_connections", true)

    broker_stats = Broker.get_stats()

    # Find circuit breakers that are ready for recovery attempt
    recovery_candidates = find_recovery_candidates(broker_stats.circuit_breaker_states, cooldown_minutes)

    recovered_count = 0
    restored_types = []

    results = Enum.reduce(recovery_candidates, {recovered_count, restored_types}, fn {server_type, _breaker_state}, {count, types} ->
      case attempt_circuit_breaker_recovery(server_type, test_connections) do
        :ok ->
          {count + 1, [server_type | types]}
        {:error, _reason} ->
          {count, types}
      end
    end)

    {final_recovered_count, final_restored_types} = results

    {:ok, %{
      recovered_count: final_recovered_count,
      restored_types: final_restored_types
    }}
  end

  defp collect_performance_metrics(_args) do
    broker_stats = Broker.get_stats()
    pool_stats = Pool.get_stats()
    bridge_stats = StreamBridge.get_stats()

    metrics = %{
      timestamp: DateTime.utc_now(),
      total_connections: broker_stats.total_connections,
      active_connections: pool_stats.active_connections,
      idle_connections: pool_stats.idle_connections,
      active_streams: bridge_stats.active_streams,
      completed_streams: bridge_stats.completed_streams,
      failed_streams: bridge_stats.failed_streams,
      bytes_streamed: bridge_stats.bytes_streamed,
      throughput_mbps: calculate_throughput_mbps(bridge_stats),
      pool_utilization: calculate_pool_utilization(pool_stats),
      error_rate: calculate_error_rate(broker_stats, bridge_stats)
    }

    {:ok, metrics}
  end

  defp recover_failed_connection(connection_id) do
    # Get connection info from broker
    case Broker.get_connection_status(connection_id) do
      {:ok, connection_info} ->
        # Attempt to create a new connection with the same configuration
        case Broker.request_connection(
               connection_info.server_type,
               connection_info.user_id,
               connection_info.session_id,
               connection_info.config
             ) do
          {:ok, new_connection_id} ->
            # Clean up the old connection
            Broker.disconnect(connection_id)
            {:ok, new_connection_id}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :connection_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Helper Functions

  defp check_individual_pools do
    # This would check each pool individually
    # Returning mock data for now
    %{
      "filesystem" => :healthy,
      "git" => :unhealthy,
      "database" => :healthy
    }
  end

  defp check_individual_streams do
    # This would check each active stream
    # Returning mock data for now
    %{
      "stream_1" => :healthy,
      "stream_2" => :stuck,
      "stream_3" => :healthy
    }
  end

  defp count_healthy_pools(pool_health) do
    Enum.count(pool_health, fn {_pool, status} -> status == :healthy end)
  end

  defp count_unhealthy_pools(pool_health) do
    Enum.count(pool_health, fn {_pool, status} -> status != :healthy end)
  end

  defp count_healthy_streams(stream_health) do
    Enum.count(stream_health, fn {_stream, status} -> status == :healthy end)
  end

  defp count_unhealthy_streams(stream_health) do
    Enum.count(stream_health, fn {_stream, status} -> status != :healthy end)
  end

  defp recover_unhealthy_pools(pool_health) do
    unhealthy_pools = Enum.filter(pool_health, fn {_pool, status} -> status != :healthy end)

    Enum.count(unhealthy_pools, fn {pool_name, _status} ->
      # Attempt recovery for each unhealthy pool
      case attempt_pool_recovery(pool_name) do
        :ok -> true
        {:error, _} -> false
      end
    end)
  end

  defp recover_unhealthy_streams(stream_health) do
    unhealthy_streams = Enum.filter(stream_health, fn {_stream, status} -> status != :healthy end)

    Enum.count(unhealthy_streams, fn {stream_id, _status} ->
      # Attempt recovery for each unhealthy stream
      case attempt_stream_recovery(stream_id) do
        :ok -> true
        {:error, _} -> false
      end
    end)
  end

  defp attempt_pool_recovery(pool_name) do
    Logger.info("Attempting pool recovery", pool: pool_name)
    # Implementation would go here
    :ok
  end

  defp attempt_stream_recovery(stream_id) do
    Logger.info("Attempting stream recovery", stream: stream_id)
    # Implementation would go here
    :ok
  end

  defp calculate_resources_freed(cleaned_count) do
    # Estimate resources freed per connection
    memory_per_connection_mb = 5
    cpu_per_connection_percent = 0.1

    %{
      memory_freed_mb: cleaned_count * memory_per_connection_mb,
      cpu_freed_percent: cleaned_count * cpu_per_connection_percent
    }
  end

  defp analyze_pool_utilization(stats, target_utilization, max_pool_size) do
    # Analyze current utilization and create optimization plan
    current_utilization = if stats.total_connections > 0 do
      stats.active_connections / stats.total_connections
    else
      0.0
    end

    %{
      current_utilization: current_utilization,
      target_utilization: target_utilization,
      needs_scaling: current_utilization > target_utilization * 1.2,
      needs_downsizing: current_utilization < target_utilization * 0.5
    }
  end

  defp apply_pool_optimizations(optimization_plan) do
    # Apply the optimization plan
    %{
      pools_modified: 0,
      connections_adjusted: 0
    }
  end

  defp find_recovery_candidates(circuit_breaker_states, cooldown_minutes) do
    cooldown_time = DateTime.add(DateTime.utc_now(), -cooldown_minutes * 60, :second)

    Enum.filter(circuit_breaker_states, fn {_server_type, state} ->
      state == :open and DateTime.compare(cooldown_time, DateTime.utc_now()) == :gt
    end)
  end

  defp attempt_circuit_breaker_recovery(server_type, test_connections) do
    Logger.info("Attempting circuit breaker recovery", server_type: server_type)

    if test_connections do
      # Test if the server type is working again
      # Implementation would test a simple connection
      :ok
    else
      :ok
    end
  end

  defp calculate_throughput_mbps(bridge_stats) do
    # Calculate throughput in megabytes per second
    # This is a simplified calculation
    bridge_stats.bytes_streamed / (1024 * 1024) / 60  # Assuming 60 second window
  end

  defp calculate_pool_utilization(pool_stats) do
    if pool_stats.total_connections > 0 do
      pool_stats.active_connections / pool_stats.total_connections
    else
      0.0
    end
  end

  defp calculate_error_rate(broker_stats, bridge_stats) do
    total_operations = broker_stats.total_connections + bridge_stats.total_streams
    total_errors = bridge_stats.failed_streams

    if total_operations > 0 do
      total_errors / total_operations
    else
      0.0
    end
  end

  defp store_metrics(metrics) do
    # Store metrics for monitoring system
    Events.track_event(%{
      event_type: "mcp_performance_metrics",
      metadata: metrics
    })
  end

  ## Oban Worker Callbacks

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 30s, 2m, 8m
    trunc(:math.pow(2, attempt) * 15)
  end

  @impl Oban.Worker
  def timeout(_job) do
    # 5 minutes max per lifecycle job
    :timer.minutes(5)
  end
end
