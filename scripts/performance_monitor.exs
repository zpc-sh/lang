#!/usr/bin/env elixir

defmodule PerformanceMonitor do
  @moduledoc """
  Production performance monitoring and diagnostics script for LANG platform.

  Usage:
    mix run scripts/performance_monitor.exs
    mix run scripts/performance_monitor.exs --profile memory
    mix run scripts/performance_monitor.exs --benchmark
    mix run scripts/performance_monitor.exs --report
  """

  require Logger

  def run(args \\ []) do
    IO.puts("\n🔍 LANG Performance Monitor")
    IO.puts("=" |> String.duplicate(50))

    case args do
      ["--profile", "memory"] -> profile_memory_usage()
      ["--benchmark"] -> run_benchmarks()
      ["--report"] -> generate_performance_report()
      ["--real-time"] -> start_real_time_monitoring()
      ["--database"] -> analyze_database_performance()
      ["--nifs"] -> analyze_native_performance()
      _ -> run_full_diagnostics()
    end
  end

  defp run_full_diagnostics do
    IO.puts("\n🚀 Running Full Performance Diagnostics")

    results = %{
      system: collect_system_metrics(),
      application: collect_application_metrics(),
      database: collect_database_metrics(),
      native: collect_native_metrics(),
      memory: collect_memory_metrics(),
      network: collect_network_metrics()
    }

    analyze_results(results)
    generate_recommendations(results)
  end

  # System Metrics Collection
  defp collect_system_metrics do
    IO.puts("  📊 Collecting system metrics...")

    %{
      beam_version: System.version(),
      otp_version: System.otp_release(),
      schedulers: System.schedulers_online(),
      uptime: :erlang.statistics(:wall_clock) |> elem(0),
      memory: :erlang.memory(),
      process_count: :erlang.system_info(:process_count),
      port_count: :erlang.system_info(:port_count),
      ets_count: :erlang.system_info(:ets_count),
      load_average: get_load_average(),
      cpu_usage: get_cpu_usage()
    }
  end

  # Application Metrics Collection
  defp collect_application_metrics do
    IO.puts("  🏗️  Collecting application metrics...")

    %{
      phoenix_endpoints: get_phoenix_metrics(),
      live_view_connections: get_liveview_metrics(),
      oban_jobs: get_oban_metrics(),
      cache_stats: get_cache_metrics(),
      pubsub_stats: get_pubsub_metrics(),
      registry_stats: get_registry_metrics()
    }
  end

  # Database Performance Analysis
  defp collect_database_metrics do
    IO.puts("  🗄️  Collecting database metrics...")

    try do
      %{
        connection_pool: get_db_pool_stats(),
        active_queries: get_active_queries(),
        slow_queries: get_slow_queries(),
        index_usage: get_index_usage(),
        table_sizes: get_table_sizes(),
        lock_stats: get_lock_statistics()
      }
    rescue
      error ->
        IO.puts("    ⚠️  Database metrics collection failed: #{inspect(error)}")
        %{error: inspect(error)}
    end
  end

  # Native NIFs Performance
  defp collect_native_metrics do
    IO.puts("  ⚡ Collecting native performance metrics...")

    %{
      nif_calls: measure_nif_performance(),
      memory_usage: measure_nif_memory(),
      error_rates: get_nif_error_rates(),
      concurrency: measure_nif_concurrency()
    }
  end

  # Memory Analysis
  defp collect_memory_metrics do
    IO.puts("  💾 Collecting memory metrics...")

    memory = :erlang.memory()

    %{
      total_mb: div(memory[:total], 1024 * 1024),
      processes_mb: div(memory[:processes], 1024 * 1024),
      system_mb: div(memory[:system], 1024 * 1024),
      atoms_mb: div(memory[:atom], 1024 * 1024),
      binaries_mb: div(memory[:binary], 1024 * 1024),
      ets_mb: div(memory[:ets], 1024 * 1024),
      gc_stats: get_gc_statistics(),
      large_processes: get_large_processes(),
      binary_references: get_binary_references()
    }
  end

  # Network Performance
  defp collect_network_metrics do
    IO.puts("  🌐 Collecting network metrics...")

    %{
      open_ports: :erlang.system_info(:port_count),
      tcp_connections: get_tcp_connections(),
      network_io: get_network_io_stats(),
      ssl_connections: get_ssl_connections()
    }
  end

  # Phoenix Metrics
  defp get_phoenix_metrics do
    try do
      endpoint_info = LangWeb.Endpoint.__info__(:functions)

      %{
        endpoint_configured:
          (:phoenix in Application.started_applications()) |> Enum.map(&elem(&1, 0)),
        active_channels: Phoenix.PubSub.subscribers_count(Lang.PubSub, "analysis:*"),
        endpoint_uptime: get_endpoint_uptime()
      }
    rescue
      _ -> %{error: "Phoenix metrics unavailable"}
    end
  end

  # LiveView Metrics
  defp get_liveview_metrics do
    try do
      %{
        active_sockets: count_active_websockets(),
        memory_per_socket: estimate_liveview_memory()
      }
    rescue
      _ -> %{error: "LiveView metrics unavailable"}
    end
  end

  # Oban Job Metrics
  defp get_oban_metrics do
    try do
      if Code.ensure_loaded?(Oban) do
        %{
          queues: Oban.config() |> Map.get(:queues, %{}),
          running_jobs: count_running_jobs(),
          completed_jobs_24h: count_completed_jobs(),
          failed_jobs_24h: count_failed_jobs(),
          queue_lengths: get_queue_lengths()
        }
      else
        %{error: "Oban not available"}
      end
    rescue
      error -> %{error: inspect(error)}
    end
  end

  # Cache Performance
  defp get_cache_metrics do
    try do
      %{
        ets_tables: :ets.all() |> length(),
        ets_memory: :ets.all() |> Enum.map(&:ets.info(&1, :memory)) |> Enum.sum(),
        cache_hit_ratio: estimate_cache_hit_ratio()
      }
    rescue
      _ -> %{error: "Cache metrics unavailable"}
    end
  end

  # PubSub Metrics
  defp get_pubsub_metrics do
    try do
      %{
        total_subscriptions: count_pubsub_subscriptions(),
        active_topics: count_active_topics()
      }
    rescue
      _ -> %{error: "PubSub metrics unavailable"}
    end
  end

  # Registry Metrics
  defp get_registry_metrics do
    try do
      registries = :pg.which_groups(:pg_scope_local)

      %{
        active_registries: length(registries),
        total_processes:
          Enum.sum(Enum.map(registries, &length(:pg.get_members(:pg_scope_local, &1))))
      }
    rescue
      _ -> %{error: "Registry metrics unavailable"}
    end
  end

  # Database Pool Stats
  defp get_db_pool_stats do
    try do
      if Code.ensure_loaded?(Lang.Repo) do
        pool_status = Lang.Repo.__pool__()

        %{
          pool_size: get_pool_config(:pool_size),
          checked_out: pool_status.checked_out || 0,
          available: pool_status.available || 0,
          queue_length: pool_status.queue_length || 0
        }
      else
        %{error: "Repository not available"}
      end
    rescue
      error -> %{error: inspect(error)}
    end
  end

  # Active Database Queries
  defp get_active_queries do
    try do
      query = """
      SELECT pid, usename, application_name, client_addr, state,
             query_start, now() - query_start as duration, query
      FROM pg_stat_activity
      WHERE state = 'active' AND query != '<IDLE>'
      ORDER BY query_start;
      """

      case Lang.Repo.query(query) do
        {:ok, result} -> %{count: length(result.rows), queries: result.rows}
        error -> %{error: inspect(error)}
      end
    rescue
      error -> %{error: inspect(error)}
    end
  end

  # Slow Query Analysis
  defp get_slow_queries do
    try do
      query = """
      SELECT query, calls, total_time, mean_time, max_time, stddev_time
      FROM pg_stat_statements
      WHERE calls > 10 AND mean_time > 100
      ORDER BY mean_time DESC
      LIMIT 10;
      """

      case Lang.Repo.query(query) do
        {:ok, result} -> %{slow_queries: result.rows}
        error -> %{error: "pg_stat_statements not available or query failed"}
      end
    rescue
      _ -> %{error: "Slow query analysis unavailable"}
    end
  end

  # Index Usage Statistics
  defp get_index_usage do
    try do
      query = """
      SELECT schemaname, tablename, indexname, idx_tup_read, idx_tup_fetch
      FROM pg_stat_user_indexes
      WHERE idx_tup_read = 0 AND idx_tup_fetch = 0
      ORDER BY schemaname, tablename;
      """

      case Lang.Repo.query(query) do
        {:ok, result} -> %{unused_indexes: length(result.rows)}
        error -> %{error: "Index usage analysis failed"}
      end
    rescue
      _ -> %{error: "Index usage analysis unavailable"}
    end
  end

  # Table Size Analysis
  defp get_table_sizes do
    try do
      query = """
      SELECT
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
        pg_total_relation_size(schemaname||'.'||tablename) as size_bytes
      FROM pg_tables
      WHERE schemaname = 'public'
      ORDER BY size_bytes DESC
      LIMIT 10;
      """

      case Lang.Repo.query(query) do
        {:ok, result} -> %{large_tables: result.rows}
        error -> %{error: "Table size analysis failed"}
      end
    rescue
      _ -> %{error: "Table size analysis unavailable"}
    end
  end

  # Database Lock Statistics
  defp get_lock_statistics do
    try do
      query = """
      SELECT mode, locktype, database, relation, page, tuple, virtualxid, transactionid, classid, objid, objsubid, virtualtransaction, pid, granted
      FROM pg_locks
      WHERE NOT granted;
      """

      case Lang.Repo.query(query) do
        {:ok, result} -> %{blocked_queries: length(result.rows)}
        error -> %{error: "Lock statistics unavailable"}
      end
    rescue
      _ -> %{error: "Lock statistics unavailable"}
    end
  end

  # Native NIF Performance Measurement
  defp measure_nif_performance do
    try do
      # Test filesystem scanner performance
      start_time = System.monotonic_time()
      result = Lang.Native.FSScanner.scan(".", max_depth: 2)
      end_time = System.monotonic_time()

      duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

      %{
        fs_scanner_duration_ms: duration_ms,
        fs_scanner_available: match?({:ok, _}, result)
      }
    rescue
      error -> %{error: "NIF performance test failed: #{inspect(error)}"}
    end
  end

  # NIF Memory Usage
  defp measure_nif_memory do
    before_memory = :erlang.memory(:total)

    try do
      # Perform memory-intensive NIF operation
      Lang.Native.FSScanner.scan(".", max_depth: 3)
      after_memory = :erlang.memory(:total)

      %{
        memory_delta_bytes: after_memory - before_memory,
        memory_delta_mb: div(after_memory - before_memory, 1024 * 1024)
      }
    rescue
      _ -> %{error: "NIF memory measurement failed"}
    end
  end

  # NIF Error Rates
  defp get_nif_error_rates do
    # This would need to be implemented with proper error tracking
    %{
      # Placeholder
      recent_errors: 0,
      # Placeholder
      error_rate: 0.0
    }
  end

  # NIF Concurrency Test
  defp measure_nif_concurrency do
    try do
      tasks =
        1..10
        |> Enum.map(fn _ ->
          Task.async(fn ->
            start_time = System.monotonic_time()
            Lang.Native.FSScanner.scan(".", max_depth: 1)
            end_time = System.monotonic_time()
            System.convert_time_unit(end_time - start_time, :native, :millisecond)
          end)
        end)

      durations = Task.await_many(tasks, 5000)

      %{
        concurrent_calls: length(durations),
        avg_duration_ms: Enum.sum(durations) / length(durations),
        max_duration_ms: Enum.max(durations)
      }
    rescue
      error -> %{error: "NIF concurrency test failed: #{inspect(error)}"}
    end
  end

  # Garbage Collection Statistics
  defp get_gc_statistics do
    :erlang.statistics(:garbage_collection)
  end

  # Find Large Processes
  defp get_large_processes do
    Process.list()
    |> Enum.map(fn pid ->
      case Process.info(pid, [:memory, :message_queue_len, :heap_size]) do
        nil -> nil
        info -> {pid, info}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_pid, info} -> info[:memory] end, :desc)
    |> Enum.take(10)
    |> Enum.map(fn {pid, info} ->
      %{
        pid: inspect(pid),
        memory_kb: div(info[:memory], 1024),
        message_queue: info[:message_queue_len],
        heap_size: info[:heap_size]
      }
    end)
  end

  # Binary References Analysis
  defp get_binary_references do
    try do
      binary_info = :erlang.memory(:binary)

      %{
        total_binaries_kb: div(binary_info, 1024)
      }
    rescue
      _ -> %{error: "Binary reference analysis failed"}
    end
  end

  # Helper Functions
  defp get_load_average do
    case :os.cmd('uptime') |> List.to_string() do
      uptime when is_binary(uptime) ->
        case Regex.run(~r/load average: ([\d.]+)/, uptime) do
          [_, load] -> String.to_float(load)
          _ -> 0.0
        end

      _ ->
        0.0
    end
  end

  defp get_cpu_usage do
    case :cpu_sup.util() do
      {:ok, usage} -> usage
      _ -> 0.0
    end
  rescue
    _ -> 0.0
  end

  defp get_pool_config(key) do
    Application.get_env(:lang, Lang.Repo)[key] || 0
  end

  defp get_endpoint_uptime do
    try do
      :erlang.statistics(:wall_clock) |> elem(0) |> div(1000)
    rescue
      _ -> 0
    end
  end

  defp count_active_websockets do
    # This would need to be implemented with proper WebSocket tracking
    # Placeholder
    0
  end

  defp estimate_liveview_memory do
    # This would need to be implemented with proper LiveView monitoring
    # Placeholder
    0
  end

  defp count_running_jobs do
    try do
      if Code.ensure_loaded?(Oban.Job) do
        # This would need proper Oban integration
        # Placeholder
        0
      else
        0
      end
    rescue
      _ -> 0
    end
  end

  defp count_completed_jobs do
    # Placeholder - would need database query
    0
  end

  defp count_failed_jobs do
    # Placeholder - would need database query
    0
  end

  defp get_queue_lengths do
    # Placeholder - would need Oban integration
    %{}
  end

  defp estimate_cache_hit_ratio do
    # Placeholder - would need cache monitoring
    0.0
  end

  defp count_pubsub_subscriptions do
    # Placeholder - would need PubSub introspection
    0
  end

  defp count_active_topics do
    # Placeholder - would need PubSub introspection
    0
  end

  defp get_tcp_connections do
    :erlang.system_info(:port_count)
  end

  defp get_network_io_stats do
    %{total_io: :erlang.statistics(:io)}
  rescue
    _ -> %{error: "Network IO stats unavailable"}
  end

  defp get_ssl_connections do
    # Placeholder - would need SSL monitoring
    0
  end

  # Analysis and Reporting
  defp analyze_results(results) do
    IO.puts("\n📊 Performance Analysis Results")
    IO.puts("-" |> String.duplicate(40))

    analyze_system_performance(results.system)
    analyze_memory_usage(results.memory)
    analyze_database_performance(results.database)
    analyze_application_performance(results.application)
  end

  defp analyze_system_performance(system) do
    IO.puts("\n🖥️  System Performance:")
    IO.puts("  Schedulers: #{system.schedulers}")
    IO.puts("  Process count: #{system.process_count}")
    IO.puts("  Memory usage: #{div(system.memory.total, 1024 * 1024)} MB")
    IO.puts("  Uptime: #{div(system.uptime, 1000)} seconds")

    if system.process_count > 50000 do
      IO.puts("  ⚠️  WARNING: High process count (#{system.process_count})")
    end
  end

  defp analyze_memory_usage(memory) do
    IO.puts("\n💾 Memory Analysis:")
    IO.puts("  Total: #{memory.total_mb} MB")
    IO.puts("  Processes: #{memory.processes_mb} MB")
    IO.puts("  System: #{memory.system_mb} MB")
    IO.puts("  Binaries: #{memory.binaries_mb} MB")

    if memory.total_mb > 2048 do
      IO.puts("  ⚠️  WARNING: High memory usage (#{memory.total_mb} MB)")
    end

    if length(memory.large_processes) > 0 do
      IO.puts("  📊 Largest processes:")

      Enum.take(memory.large_processes, 3)
      |> Enum.each(fn proc ->
        IO.puts("    #{proc.pid}: #{proc.memory_kb} KB")
      end)
    end
  end

  defp analyze_database_performance(database) do
    IO.puts("\n🗄️  Database Performance:")

    case database do
      %{error: error} ->
        IO.puts("  ❌ Database analysis failed: #{error}")

      _ ->
        if Map.has_key?(database, :connection_pool) do
          pool = database.connection_pool
          IO.puts("  Pool status: #{pool.checked_out}/#{pool.pool_size} connections used")

          if pool.queue_length > 0 do
            IO.puts("  ⚠️  WARNING: #{pool.queue_length} queries queued")
          end
        end

        if Map.has_key?(database, :active_queries) do
          IO.puts("  Active queries: #{database.active_queries.count}")
        end
    end
  end

  defp analyze_application_performance(application) do
    IO.puts("\n🏗️  Application Performance:")

    if Map.has_key?(application, :oban_jobs) and not Map.has_key?(application.oban_jobs, :error) do
      jobs = application.oban_jobs
      IO.puts("  Oban queues configured: #{map_size(jobs.queues)}")
      IO.puts("  Running jobs: #{jobs.running_jobs}")
    end

    if Map.has_key?(application, :cache_stats) and
         not Map.has_key?(application.cache_stats, :error) do
      cache = application.cache_stats
      IO.puts("  ETS tables: #{cache.ets_tables}")
      IO.puts("  ETS memory: #{div(cache.ets_memory, 1024)} KB")
    end
  end

  defp generate_recommendations(results) do
    IO.puts("\n💡 Performance Recommendations")
    IO.puts("-" |> String.duplicate(40))

    recommendations = []

    # Memory recommendations
    recommendations =
      if results.memory.total_mb > 1024 do
        [
          "Consider memory optimization - current usage: #{results.memory.total_mb} MB"
          | recommendations
        ]
      else
        recommendations
      end

    # Process count recommendations
    recommendations =
      if results.system.process_count > 30000 do
        [
          "High process count detected (#{results.system.process_count}) - investigate process leaks"
          | recommendations
        ]
      else
        recommendations
      end

    # Database recommendations
    recommendations =
      case results.database do
        %{connection_pool: %{queue_length: queue}} when queue > 5 ->
          [
            "Database connection pool under pressure - consider increasing pool size"
            | recommendations
          ]

        _ ->
          recommendations
      end

    if length(recommendations) == 0 do
      IO.puts("  ✅ No immediate performance concerns detected")
    else
      Enum.with_index(recommendations, 1)
      |> Enum.each(fn {rec, idx} ->
        IO.puts("  #{idx}. #{rec}")
      end)
    end
  end

  # Memory Profiling
  defp profile_memory_usage do
    IO.puts("\n🧠 Memory Profiling")
    IO.puts("=" |> String.duplicate(40))

    :fprof.start()
    :fprof.trace(:start)

    # Run some operations to profile
    perform_sample_operations()

    :fprof.trace(:stop)
    :fprof.profile()
    :fprof.analyse([{:dest, 'memory_profile.txt'}])
    :fprof.stop()

    IO.puts("✅ Memory profile saved to memory_profile.txt")
  end

  # Benchmarking
  defp run_benchmarks do
    IO.puts("\n🏁 Running Performance Benchmarks")
    IO.puts("=" |> String.duplicate(40))

    benchmarks = %{
      "native_fs_scan" => fn -> benchmark_fs_scan() end,
      "database_query" => fn -> benchmark_database() end,
      "memory_allocation" => fn -> benchmark_memory() end,
      "process_creation" => fn -> benchmark_processes() end
    }

    Enum.each(benchmarks, fn {name, benchmark_fn} ->
      IO.write("  Running #{name}... ")

      {time, _result} = :timer.tc(benchmark_fn)
      time_ms = div(time, 1000)

      IO.puts("#{time_ms}ms")
    end)
  end

  # Real-time Monitoring
  defp start_real_time_monitoring do
    IO.puts("\n⏱️  Starting Real-time Performance Monitoring")
    IO.puts("Press Ctrl+C to stop")
    IO.puts("=" |> String.duplicate(40))

    Stream.interval(5000)
    |> Enum.each(fn _ ->
      memory = :erlang.memory()
      processes = :erlang.system_info(:process_count)

      timestamp = DateTime.utc_now() |> DateTime.to_string()
      memory_mb = div(memory.total, 1024 * 1024)

      IO.puts("#{timestamp} | Memory: #{memory_mb}MB | Processes: #{processes}")
    end)
  end

  # Database Performance Analysis
  defp analyze_database_performance do
    IO.puts("\n🔍 Database Performance Analysis")
    IO.puts("=" |> String.duplicate(40))

    db_metrics = collect_database_metrics()

    case db_metrics do
      %{error: error} ->
        IO.puts("❌ Database analysis failed: #{error}")

      _ ->
        IO.puts("📊 Database Statistics:")

        if Map.has_key?(db_metrics, :slow_queries) do
          IO.puts(
            "  Slow queries detected: #{length(db_metrics.slow_queries.slow_queries || [])}"
          )
        end

        if Map.has_key?(db_metrics, :table_sizes) do
          IO.puts("  Large tables:")

          Enum.take(db_metrics.table_sizes.large_tables || [], 5)
          |> Enum.each(fn [schema, table, size, _] ->
            IO.puts("    #{schema}.#{table}: #{size}")
          end)
        end
    end
  end

  # Native Performance Analysis
  defp analyze_native_performance do
    IO.puts("\n⚡ Native NIF Performance Analysis")
    IO.puts("=" |> String.duplicate(40))

    native_metrics = collect_native_metrics()

    case native_metrics do
      %{error: error} ->
        IO.puts("❌ Native analysis failed: #{error}")

      _ ->
        IO.puts("📊 Native Performance:")

        if Map.has_key?(native_metrics, :nif_calls) do
          nif_perf = native_metrics.nif_calls

          if Map.has_key?(nif_perf, :fs_scanner_duration_ms) do
            IO.puts("  FS Scanner: #{nif_perf.fs_scanner_duration_ms}ms")

            if nif_perf.fs_scanner_duration_ms > 1000 do
              IO.puts("  ⚠️  WARNING: FS Scanner performance degraded")
            end
          end
        end

        if Map.has_key?(native_metrics, :concurrency) do
          concur = native_metrics.concurrency
          IO.puts("  Concurrent calls: #{concur.concurrent_calls}")
          IO.puts("  Average duration: #{Float.round(concur.avg_duration_ms, 2)}ms")
        end
    end
  end

  # Performance Report Generation
  defp generate_performance_report do
    IO.puts("\n📋 Generating Comprehensive Performance Report")
    IO.puts("=" |> String.duplicate(50))

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    filename = "performance_report_#{timestamp}.json"

    results = %{
      timestamp: timestamp,
      system: collect_system_metrics(),
      application: collect_application_metrics(),
      database: collect_database_metrics(),
      memory: collect_memory_metrics(),
      native: collect_native_metrics()
    }

    json_content = Jason.encode!(results, pretty: true)
    File.write!(filename, json_content)

    IO.puts("✅ Performance report saved to #{filename}")
    IO.puts("\nReport Summary:")
    IO.puts("  System uptime: #{div(results.system.uptime, 1000)} seconds")
    IO.puts("  Memory usage: #{div(results.system.memory.total, 1024 * 1024)} MB")
    IO.puts("  Active processes: #{results.system.process_count}")

    case results.database do
      %{connection_pool: pool} ->
        IO.puts("  DB connections: #{pool.checked_out}/#{pool.pool_size}")

      _ ->
        IO.puts("  DB connections: unavailable")
    end
  end

  # Sample Operations for Profiling
  defp perform_sample_operations do
    # Simulate typical LANG operations
    try do
      # File system operations
      Lang.Native.FSScanner.scan(".", max_depth: 2)

      # Process creation
      1..100
      |> Enum.map(fn _ -> spawn(fn -> :timer.sleep(10) end) end)
      |> Enum.each(&Process.monitor/1)

      # Memory allocation
      large_list = Enum.to_list(1..10000)
      _processed = Enum.map(large_list, &(&1 * 2))
    rescue
      _ -> :ok
    end
  end

  # Benchmark Functions
  defp benchmark_fs_scan do
    Lang.Native.FSScanner.scan(".", max_depth: 1)
  rescue
    _ -> :ok
  end

  defp benchmark_database do
    try do
      if Code.ensure_loaded?(Lang.Repo) do
        Lang.Repo.query!("SELECT 1")
      end
    rescue
      _ -> :ok
    end
  end

  defp benchmark_memory do
    # 1MB
    large_binary = :crypto.strong_rand_bytes(1024 * 1024)
    _processed = :crypto.hash(:sha256, large_binary)
  end

  defp benchmark_processes do
    processes =
      1..100
      |> Enum.map(fn _ ->
        spawn(fn ->
          :timer.sleep(1)
          exit(:normal)
        end)
      end)

    Enum.each(processes, &Process.monitor/1)
  end
end

# Run the performance monitor
case System.argv() do
  [] -> PerformanceMonitor.run()
  args -> PerformanceMonitor.run(args)
end
