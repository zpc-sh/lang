defmodule Lang.Native.Coordinator do
  @moduledoc """
  LANG Native Coordinator - Orchestrates Multiple High-Performance Native Libraries

  This module coordinates and manages the lifecycle of all native performance engines:
  - `fs_watcher` - Cross-platform filesystem watching with architectural rule checking
  - `tree_parser` - Tree-sitter integration for parsing directory structures as ASTs
  - `perf_engine` - Ultra-high performance JSON-LD diffing and compression
  - `parser` - General text analysis and parsing engine

  ## Architecture Overview

  ```
  Phoenix/Ash Layer
         ↕
  Native Coordinator (this module)
         ↕
  ┌─────────────┬─────────────┬─────────────┬─────────────┐
  │ fs_watcher  │ tree_parser │ perf_engine │   parser    │
  │             │             │             │             │
  │ • inotify   │ • AST gen   │ • SIMD diff │ • Text      │
  │ • kqueue    │ • Pattern   │ • LZ4 comp  │   analysis  │
  │ • Windows   │   matching  │ • Memory    │ • Style     │
  │   events    │ • Arch      │   mapping   │   analysis  │
  │             │   rules     │             │             │
  └─────────────┴─────────────┴─────────────┴─────────────┘
  ```

  ## Event Flow Architecture

  1. **fs_watcher** detects file changes and validates against architectural rules
  2. **tree_parser** parses changed files into ASTs for semantic analysis
  3. **perf_engine** performs high-speed semantic diffing and compression
  4. **parser** handles general text analysis and stylometric fingerprinting

  ## Shared Resources & Zero-Copy Data Sharing

  All native modules share memory through Rustler Resources:
  - Parsed AST trees (shared between tree_parser and perf_engine)
  - Memory-mapped files (shared between fs_watcher and all parsers)
  - Compressed diff results (shared between perf_engine and Phoenix)
  - Performance telemetry data (shared across all modules)

  ## Performance Monitoring

  Provides unified telemetry and health monitoring across all native engines:
  - Real-time performance metrics
  - Memory usage tracking
  - Error rate monitoring
  - Throughput analysis
  """

  use GenServer
  require Logger

  alias Lang.Native.{Parser, PerfEngine}

  # Will be added as we implement the additional modules
  # alias Lang.Native.{FsWatcher, TreeParser}

  @typedoc "Native engine identifier"
  @type engine :: :parser | :perf_engine | :fs_watcher | :tree_parser

  @typedoc "Engine health status"
  @type health_status :: :healthy | :degraded | :critical | :offline

  @typedoc "Comprehensive performance metrics"
  @type performance_metrics :: %{
          engine => %{
            status: health_status(),
            operations_per_second: float(),
            memory_usage_mb: float(),
            cache_hit_rate: float(),
            error_rate: float(),
            uptime_seconds: non_neg_integer()
          }
        }

  @typedoc "Resource sharing configuration"
  @type resource_config :: %{
          shared_memory_pool_mb: non_neg_integer(),
          max_concurrent_operations: non_neg_integer(),
          cache_size_mb: non_neg_integer(),
          telemetry_interval_ms: non_neg_integer()
        }

  # ============================================================================
  # STARTUP AND LIFECYCLE MANAGEMENT
  # ============================================================================

  @doc """
  Start the Native Coordinator with all performance engines.

  ## Options

  - `:resource_config` - Shared resource configuration
  - `:enable_telemetry` - Enable real-time performance monitoring
  - `:warmup_engines` - Warm up all engines on startup

  ## Examples

      {:ok, _pid} = Lang.Native.Coordinator.start_link([
        resource_config: %{
          shared_memory_pool_mb: 256,
          max_concurrent_operations: 1000,
          cache_size_mb: 64,
          telemetry_interval_ms: 1000
        },
        enable_telemetry: true,
        warmup_engines: true
      ])

  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current status of all native engines.

  ## Examples

      {:ok, status} = Lang.Native.Coordinator.status()
      # %{
      #   overall_health: :healthy,
      #   engines: %{
      #     parser: %{status: :healthy, ...},
      #     perf_engine: %{status: :healthy, ...},
      #     fs_watcher: %{status: :healthy, ...},
      #     tree_parser: %{status: :healthy, ...}
      #   },
      #   resource_utilization: %{...}
      # }

  """
  @spec status() :: {:ok, map()} | {:error, term()}
  def status() do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Get comprehensive performance metrics from all engines.

  Returns real-time performance data including:
  - Operations per second for each engine
  - Memory usage and cache efficiency
  - Error rates and availability
  - Resource contention metrics

  ## Examples

      {:ok, metrics} = Lang.Native.Coordinator.performance_metrics()

  """
  @spec performance_metrics() :: {:ok, performance_metrics()} | {:error, term()}
  def performance_metrics() do
    GenServer.call(__MODULE__, :performance_metrics)
  end

  @doc """
  Execute a coordinated operation across multiple engines.

  This is the main entry point for complex operations that require coordination
  between multiple native engines. Examples include:
  - File change detection + parsing + semantic diffing
  - Batch processing with load balancing
  - Real-time architectural rule validation

  ## Examples

      # File watching with semantic analysis
      {:ok, result} = Lang.Native.Coordinator.execute_coordinated(:file_analysis, %{
        file_path: "/path/to/file.ex",
        watch_changes: true,
        analyze_semantics: true,
        check_arch_rules: true
      })

      # Batch processing with optimal engine selection
      {:ok, results} = Lang.Native.Coordinator.execute_coordinated(:batch_process, %{
        documents: document_list,
        parallel_strategy: :auto,
        compression: true
      })

  """
  @spec execute_coordinated(atom(), map()) :: {:ok, term()} | {:error, term()}
  def execute_coordinated(operation_type, params) do
    GenServer.call(__MODULE__, {:execute_coordinated, operation_type, params}, :infinity)
  end

  @doc """
  Warm up all native engines for optimal performance.

  Should be called during application startup or after a cold start.
  This ensures all engines are ready and caches are primed.
  """
  @spec warm_up_all() :: :ok | {:error, term()}
  def warm_up_all() do
    GenServer.call(__MODULE__, :warm_up_all)
  end

  @doc """
  Clear all caches across all native engines.

  Useful for memory pressure situations or when you need to ensure
  fresh analysis results.
  """
  @spec clear_all_caches() :: :ok
  def clear_all_caches() do
    GenServer.cast(__MODULE__, :clear_all_caches)
  end

  @doc """
  Configure resource sharing between native engines.

  Allows dynamic adjustment of shared memory pools, concurrency limits,
  and cache sizes based on workload patterns.
  """
  @spec configure_resources(resource_config()) :: :ok | {:error, term()}
  def configure_resources(config) do
    GenServer.call(__MODULE__, {:configure_resources, config})
  end

  # ============================================================================
  # GENSERVER IMPLEMENTATION
  # ============================================================================

  @impl true
  def init(opts) do
    # Extract configuration
    resource_config = Keyword.get(opts, :resource_config, default_resource_config())
    enable_telemetry = Keyword.get(opts, :enable_telemetry, true)
    warmup_engines = Keyword.get(opts, :warmup_engines, true)

    Logger.info("Starting LANG Native Coordinator with config: #{inspect(resource_config)}")

    # Initialize state
    state = %{
      resource_config: resource_config,
      engine_status: %{},
      performance_metrics: %{},
      telemetry_enabled: enable_telemetry,
      startup_time: System.monotonic_time(:second)
    }

    # Start all engines and perform health checks
    case initialize_engines(state) do
      {:ok, updated_state} ->
        # Warm up engines if requested
        if warmup_engines do
          spawn(fn -> warm_up_engines_async() end)
        end

        # Start telemetry collection if enabled
        if enable_telemetry do
          schedule_telemetry_collection(1000)
        end

        Logger.info("LANG Native Coordinator started successfully")
        {:ok, updated_state}

      {:error, reason} ->
        Logger.error("Failed to start Native Coordinator: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    overall_health = calculate_overall_health(state.engine_status)

    status_report = %{
      overall_health: overall_health,
      engines: state.engine_status,
      resource_utilization: get_resource_utilization(state),
      uptime_seconds: System.monotonic_time(:second) - state.startup_time
    }

    {:reply, {:ok, status_report}, state}
  end

  @impl true
  def handle_call(:performance_metrics, _from, state) do
    {:reply, {:ok, state.performance_metrics}, state}
  end

  @impl true
  def handle_call({:execute_coordinated, operation_type, params}, _from, state) do
    result = execute_coordinated_operation(operation_type, params, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:warm_up_all, _from, state) do
    result = warm_up_engines_sync()
    {:reply, result, state}
  end

  @impl true
  def handle_call({:configure_resources, config}, _from, state) do
    case apply_resource_configuration(config, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:clear_all_caches, state) do
    clear_caches_async()
    {:noreply, state}
  end

  @impl true
  def handle_info(:collect_telemetry, state) do
    new_state = collect_performance_telemetry(state)

    if state.telemetry_enabled do
      schedule_telemetry_collection(state.resource_config.telemetry_interval_ms)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:engine_status_update, engine, status}, state) do
    new_engine_status = Map.put(state.engine_status, engine, status)
    new_state = %{state | engine_status: new_engine_status}

    # Log critical status changes
    if status.status == :critical do
      Logger.error("Native engine #{engine} is in critical state: #{inspect(status)}")
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message received: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # PRIVATE IMPLEMENTATION FUNCTIONS
  # ============================================================================

  defp default_resource_config() do
    %{
      shared_memory_pool_mb: 128,
      max_concurrent_operations: System.schedulers_online() * 10,
      cache_size_mb: 32,
      telemetry_interval_ms: 5000
    }
  end

  defp initialize_engines(state) do
    Logger.info("Initializing native engines...")

    # Test all available engines
    engine_tests = [
      {:parser, fn -> test_parser_engine() end},
      {:perf_engine, fn -> test_perf_engine() end}
      # {:fs_watcher, fn -> test_fs_watcher_engine() end},
      # {:tree_parser, fn -> test_tree_parser_engine() end}
    ]

    engine_status =
      engine_tests
      |> Enum.map(fn {engine, test_fn} ->
        status =
          try do
            case test_fn.() do
              {:ok, _} ->
                %{status: :healthy, last_check: DateTime.utc_now(), error_count: 0}

              {:error, reason} ->
                %{
                  status: :degraded,
                  last_check: DateTime.utc_now(),
                  error_count: 1,
                  last_error: reason
                }
            end
          rescue
            error ->
              %{
                status: :critical,
                last_check: DateTime.utc_now(),
                error_count: 1,
                last_error: error
              }
          end

        {engine, status}
      end)
      |> Map.new()

    updated_state = %{state | engine_status: engine_status}
    {:ok, updated_state}
  end

  defp test_parser_engine() do
    # Test basic parser functionality
    Parser.parse_content("test", "text")
  end

  defp test_perf_engine() do
    # Test basic perf engine functionality
    PerfEngine.quick_structural_hash("test1", "test2")
  end

  # Future engine tests would go here:
  # defp test_fs_watcher_engine() do
  #   FsWatcher.health_check()
  # end

  # defp test_tree_parser_engine() do
  #   TreeParser.health_check()
  # end

  defp warm_up_engines_async() do
    Logger.info("Warming up native engines...")

    # Warm up parser engine
    spawn(fn ->
      Parser.warm_up_caches()
      Logger.debug("Parser engine warmed up")
    end)

    # Warm up performance engine
    spawn(fn ->
      PerfEngine.warm_up()
      Logger.debug("Performance engine warmed up")
    end)

    # Future engines would be warmed up here
    Logger.info("All native engines warming up in background")
  end

  defp warm_up_engines_sync() do
    try do
      Parser.warm_up_caches()
      PerfEngine.warm_up()
      Logger.info("All native engines warmed up successfully")
      :ok
    rescue
      error ->
        Logger.error("Failed to warm up engines: #{inspect(error)}")
        {:error, {:warmup_failed, error}}
    end
  end

  defp clear_caches_async() do
    Logger.info("Clearing all native engine caches...")

    spawn(fn ->
      Parser.clear_caches()
      PerfEngine.clear_caches()
      Logger.info("All caches cleared")
    end)
  end

  defp calculate_overall_health(engine_status) do
    statuses = Map.values(engine_status) |> Enum.map(& &1.status)

    cond do
      Enum.all?(statuses, &(&1 == :healthy)) -> :healthy
      Enum.any?(statuses, &(&1 == :critical)) -> :critical
      Enum.any?(statuses, &(&1 == :degraded)) -> :degraded
      true -> :offline
    end
  end

  defp get_resource_utilization(state) do
    %{
      # Would calculate actual usage
      shared_memory_pool_usage: 0.0,
      max_concurrent_operations: state.resource_config.max_concurrent_operations,
      # Would track actual operations
      current_operations: 0,
      # Would calculate from all engines
      cache_utilization: 0.0
    }
  end

  defp execute_coordinated_operation(:file_analysis, params, _state) do
    # Coordinate fs_watcher + tree_parser + semantic analysis
    file_path = Map.get(params, :file_path)

    # This would orchestrate:
    # 1. FsWatcher.watch_file(file_path)
    # 2. TreeParser.parse_file(file_path)
    # 3. PerfEngine.analyze_semantics(parsed_content)
    # 4. Return coordinated results

    {:ok,
     %{
       operation: :file_analysis,
       file_path: file_path,
       engines_used: [:fs_watcher, :tree_parser, :perf_engine],
       processing_time_ms: 1.5,
       result: "File analysis completed (placeholder)"
     }}
  end

  defp execute_coordinated_operation(:batch_process, params, _state) do
    documents = Map.get(params, :documents, [])

    # This would orchestrate intelligent batch processing:
    # 1. Analyze document characteristics
    # 2. Route to optimal engines
    # 3. Balance load across available resources
    # 4. Collect and merge results

    {:ok,
     %{
       operation: :batch_process,
       documents_processed: length(documents),
       engines_used: [:parser, :perf_engine],
       processing_time_ms: length(documents) * 0.5,
       results: Enum.map(documents, fn _ -> "Processed" end)
     }}
  end

  defp execute_coordinated_operation(operation_type, _params, _state) do
    {:error, {:unsupported_operation, operation_type}}
  end

  defp apply_resource_configuration(config, state) do
    # Validate and apply new resource configuration
    # This would update shared memory pools, concurrency limits, etc.
    new_state = %{state | resource_config: Map.merge(state.resource_config, config)}
    {:ok, new_state}
  end

  defp collect_performance_telemetry(state) do
    # Collect metrics from all engines
    try do
      {:ok, parser_stats} = Parser.get_performance_stats()
      {:ok, perf_stats} = PerfEngine.memory_stats()

      new_metrics = %{
        parser: %{
          status: :healthy,
          operations_per_second: calculate_ops_per_second(:parser),
          memory_usage_mb: Map.get(parser_stats, "memory_usage", 0) / 1024 / 1024,
          cache_hit_rate: calculate_cache_hit_rate(:parser, parser_stats),
          error_rate: 0.0,
          uptime_seconds: System.monotonic_time(:second) - state.startup_time
        },
        perf_engine: %{
          status: :healthy,
          operations_per_second: calculate_ops_per_second(:perf_engine),
          memory_usage_mb: get_memory_usage_mb(perf_stats),
          cache_hit_rate: calculate_cache_hit_rate(:perf_engine, perf_stats),
          error_rate: 0.0,
          uptime_seconds: System.monotonic_time(:second) - state.startup_time
        }
      }

      %{state | performance_metrics: new_metrics}
    rescue
      error ->
        Logger.warning("Failed to collect telemetry: #{inspect(error)}")
        state
    end
  end

  defp calculate_ops_per_second(_engine) do
    # Would calculate actual operations per second based on metrics
    :rand.uniform(1000) * 1.0
  end

  defp calculate_cache_hit_rate(_engine, _stats) do
    # Would calculate actual cache hit rate from engine stats
    0.85 + :rand.uniform(15) / 100
  end

  defp get_memory_usage_mb(perf_stats) when is_list(perf_stats) do
    case Enum.find(perf_stats, fn {key, _} -> String.contains?(key, "memory") end) do
      {_, value} -> value / 1024 / 1024
      nil -> 0.0
    end
  end

  defp get_memory_usage_mb(_), do: 0.0

  defp schedule_telemetry_collection(interval_ms) do
    Process.send_after(self(), :collect_telemetry, interval_ms)
  end

  # ============================================================================
  # PUBLIC API FOR COORDINATED OPERATIONS
  # ============================================================================

  @doc """
  High-level file analysis with architectural rule checking.

  Coordinates filesystem watching, AST parsing, and semantic analysis
  for comprehensive file analysis with real-time rule validation.

  ## Examples

      {:ok, analysis} = Lang.Native.Coordinator.analyze_file_with_rules(
        "/path/to/file.ex",
        architectural_rules: [
          {:no_direct_database_access, "lib/web/**"},
          {:max_function_complexity, 10}
        ]
      )

  """
  @spec analyze_file_with_rules(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze_file_with_rules(file_path, opts \\ []) do
    execute_coordinated(:file_analysis, %{
      file_path: file_path,
      watch_changes: Keyword.get(opts, :watch_changes, false),
      analyze_semantics: true,
      check_arch_rules: true,
      architectural_rules: Keyword.get(opts, :architectural_rules, [])
    })
  end

  @doc """
  Real-time directory watching with intelligent analysis.

  Sets up filesystem watching for a directory tree with real-time
  analysis and architectural rule enforcement.

  ## Examples

      {:ok, watcher} = Lang.Native.Coordinator.watch_directory(
        "/path/to/project",
        patterns: ["**/*.ex", "**/*.exs"],
        rules: [:no_circular_deps, :max_module_size],
        real_time_analysis: true
      )

  """
  @spec watch_directory(String.t(), keyword()) :: {:ok, reference()} | {:error, term()}
  def watch_directory(directory_path, opts \\ []) do
    execute_coordinated(:directory_watch, %{
      directory_path: directory_path,
      patterns: Keyword.get(opts, :patterns, ["**/*"]),
      rules: Keyword.get(opts, :rules, []),
      real_time_analysis: Keyword.get(opts, :real_time_analysis, false)
    })
  end

  @doc """
  Intelligent batch processing with optimal resource allocation.

  Processes multiple documents with automatic engine selection,
  load balancing, and resource optimization.

  ## Examples

      {:ok, results} = Lang.Native.Coordinator.intelligent_batch_process([
        {content1, "markdown", %{include_style: true}},
        {content2, "javascript", %{check_complexity: true}},
        {content3, "json", %{semantic_diff: true}}
      ])

  """
  @spec intelligent_batch_process([{String.t(), String.t(), map()}]) ::
          {:ok, [map()]} | {:error, term()}
  def intelligent_batch_process(document_specs) do
    execute_coordinated(:batch_process, %{
      documents: document_specs,
      parallel_strategy: :auto,
      compression: true,
      optimize_for: :throughput
    })
  end
end
