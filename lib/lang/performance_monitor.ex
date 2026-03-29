defmodule Lang.PerformanceMonitor do
  @moduledoc """
  Comprehensive performance monitoring system for LANG Universal Text Intelligence Platform.

  Integrates with ash_profiler to provide real-time performance insights, automated
  optimization recommendations, and detailed profiling for:

  - Ash Framework queries and operations
  - Native Rust NIF performance
  - Oban background job processing
  - Phoenix LiveView rendering
  - Authentication and authorization flows
  - Billing and usage tracking operations

  Features:
  - Real-time performance metrics collection
  - Automated slow query detection and optimization
  - Memory usage tracking for native operations
  - Background job performance analysis
  - Performance regression detection
  - Actionable optimization recommendations
  """

  use GenServer
  require Logger

  alias Lang.Events
  alias __MODULE__.{Collector, Analyzer, Reporter}

  # Performance thresholds (in milliseconds)
  @default_thresholds %{
    ash_query: 100,
    nif_operation: 50,
    oban_job: 5000,
    liveview_mount: 200,
    auth_operation: 100,
    billing_check: 150
  }

  # Telemetry events we monitor
  @monitored_events [
    # Ash Framework events
    [:ash, :query, :start],
    [:ash, :query, :stop],
    [:ash, :changeset, :validate],
    [:ash, :create, :stop],
    [:ash, :update, :stop],
    [:ash, :destroy, :stop],

    # Native NIF events
    [:lang, :native, :fs_scanner, :start],
    [:lang, :native, :fs_scanner, :stop],
    [:lang, :native, :text_analysis, :start],
    [:lang, :native, :text_analysis, :stop],
    [:lang, :native, :graph_reasoner, :start],
    [:lang, :native, :graph_reasoner, :stop],

    # Oban events
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception],

    # Phoenix/LiveView events
    [:phoenix, :live_view, :mount, :start],
    [:phoenix, :live_view, :mount, :stop],
    [:phoenix, :live_view, :handle_params, :start],
    [:phoenix, :live_view, :handle_params, :stop],

    # Authentication events
    [:lang, :auth, :login, :start],
    [:lang, :auth, :login, :stop],
    [:lang, :auth, :api_key_validation, :start],
    [:lang, :auth, :api_key_validation, :stop],

    # Billing events
    [:lang, :billing, :usage_check, :start],
    [:lang, :billing, :usage_check, :stop],
    [:lang, :billing, :stripe_webhook, :start],
    [:lang, :billing, :stripe_webhook, :stop],

    # Provider credentials resolution
    [:lang, :providers, :credentials, :resolve, :start],
    [:lang, :providers, :credentials, :resolve, :stop]
  ]

  ## Public API

  @doc """
  Starts the performance monitor with optional configuration.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets current performance metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Gets performance report for a specific time period.
  """
  def get_report(start_time, end_time, opts \\ []) do
    GenServer.call(__MODULE__, {:get_report, start_time, end_time, opts})
  end

  @doc """
  Gets slow query analysis and optimization recommendations.
  """
  def analyze_slow_queries(limit \\ 50) do
    GenServer.call(__MODULE__, {:analyze_slow_queries, limit})
  end

  @doc """
  Gets native NIF performance statistics.
  """
  def get_native_stats do
    GenServer.call(__MODULE__, :get_native_stats)
  end

  @doc """
  Manually records a performance event.
  """
  def record_event(event_name, metadata \\ %{}, duration_ms \\ nil) do
    GenServer.cast(__MODULE__, {:record_event, event_name, metadata, duration_ms})
  end

  @doc """
  Updates performance thresholds for different operation types.
  """
  def update_thresholds(new_thresholds) do
    GenServer.call(__MODULE__, {:update_thresholds, new_thresholds})
  end

  @doc """
  Enables or disables ash_profiler integration.
  """
  def configure_ash_profiler(enabled \\ true) do
    GenServer.call(__MODULE__, {:configure_ash_profiler, enabled})
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    state = %{
      thresholds: Keyword.get(opts, :thresholds, @default_thresholds),
      metrics: %{},
      slow_queries: [],
      native_stats: %{},
      ash_profiler_enabled: Keyword.get(opts, :ash_profiler_enabled, true),
      collection_interval: Keyword.get(opts, :collection_interval, 5000),
      max_slow_queries: Keyword.get(opts, :max_slow_queries, 1000)
    }

    # Initialize telemetry handlers
    setup_telemetry_handlers()

    # Initialize ash_profiler if enabled
    if state.ash_profiler_enabled do
      setup_ash_profiler()
    end

    # Schedule periodic collection
    schedule_collection(state.collection_interval)

    Logger.info("LANG Performance Monitor started with thresholds: #{inspect(state.thresholds)}")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = build_current_metrics(state)
    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_call({:get_report, start_time, end_time, opts}, _from, state) do
    report = Reporter.generate_report(state, start_time, end_time, opts)
    {:reply, {:ok, report}, state}
  end

  @impl true
  def handle_call({:analyze_slow_queries, limit}, _from, state) do
    analysis = Analyzer.analyze_slow_queries(state.slow_queries, limit)
    {:reply, {:ok, analysis}, state}
  end

  @impl true
  def handle_call(:get_native_stats, _from, state) do
    {:reply, {:ok, state.native_stats}, state}
  end

  @impl true
  def handle_call({:update_thresholds, new_thresholds}, _from, state) do
    updated_thresholds = Map.merge(state.thresholds, new_thresholds)
    new_state = %{state | thresholds: updated_thresholds}

    Logger.info("Updated performance thresholds: #{inspect(new_thresholds)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:configure_ash_profiler, enabled}, _from, state) do
    if enabled != state.ash_profiler_enabled do
      if enabled do
        setup_ash_profiler()
      else
        teardown_ash_profiler()
      end

      new_state = %{state | ash_profiler_enabled: enabled}
      Logger.info("Ash profiler #{if enabled, do: "enabled", else: "disabled"}")
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:record_event, event_name, metadata, duration_ms}, state) do
    timestamp = DateTime.utc_now()

    new_state =
      state
      |> record_metric(event_name, duration_ms, metadata, timestamp)
      |> check_slow_operation(event_name, duration_ms, metadata, timestamp)
      |> update_native_stats(event_name, metadata)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    new_state =
      state
      |> collect_system_metrics()
      |> prune_old_data()

    schedule_collection(state.collection_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:telemetry, event_name, measurements, metadata}, state) do
    new_state = handle_telemetry_event(state, event_name, measurements, metadata)
    {:noreply, new_state}
  end

  ## Private Functions

  defp setup_telemetry_handlers do
    for event <- @monitored_events do
      :telemetry.attach(
        {__MODULE__, event},
        event,
        &handle_telemetry_event/4,
        %{}
      )
    end

    # Attach provider credentials telemetry logger/auditor
    Lang.Providers.CredentialsTelemetry.attach()
  end

  defp setup_ash_profiler do
    # Configure ash_profiler for optimal LANG performance monitoring
    Application.put_env(:ash_profiler, :enabled, true)
    Application.put_env(:ash_profiler, :report_threshold_ms, 50)
    Application.put_env(:ash_profiler, :log_slow_queries, true)
    Application.put_env(:ash_profiler, :track_memory_usage, true)

    # Start ash_profiler if not already running
    case AshProfiler.start_link() do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      error ->
        Logger.warning("Failed to start ash_profiler: #{inspect(error)}")
        :error
    end
  end

  defp teardown_ash_profiler do
    Application.put_env(:ash_profiler, :enabled, false)
    AshProfiler.stop()
  end

  defp handle_telemetry_event(event_name, measurements, metadata, _config) do
    duration =
      case measurements do
        # Convert to milliseconds
        %{duration: duration} -> duration / 1_000_000
        %{stop: stop, start: start} -> (stop - start) / 1_000_000
        _ -> nil
      end

    send(__MODULE__, {:telemetry, event_name, duration, metadata})
  end

  defp handle_telemetry_event(state, event_name, duration, metadata) do
    timestamp = DateTime.utc_now()

    state
    |> record_metric(event_name, duration, metadata, timestamp)
    |> check_slow_operation(event_name, duration, metadata, timestamp)
    |> update_native_stats(event_name, metadata)
  end

  defp record_metric(state, event_name, duration, metadata, timestamp) do
    metric_key = get_metric_key(event_name)

    current_metrics =
      Map.get(state.metrics, metric_key, %{
        count: 0,
        total_duration: 0,
        avg_duration: 0,
        min_duration: nil,
        max_duration: nil,
        last_update: timestamp
      })

    updated_metrics = %{
      count: current_metrics.count + 1,
      total_duration: current_metrics.total_duration + (duration || 0),
      avg_duration: calculate_avg_duration(current_metrics, duration),
      min_duration: update_min_duration(current_metrics.min_duration, duration),
      max_duration: update_max_duration(current_metrics.max_duration, duration),
      last_update: timestamp
    }

    %{state | metrics: Map.put(state.metrics, metric_key, updated_metrics)}
  end

  defp check_slow_operation(state, event_name, duration, metadata, timestamp) do
    if duration && is_slow_operation?(event_name, duration, state.thresholds) do
      slow_query = %{
        event: event_name,
        duration: duration,
        metadata: metadata,
        timestamp: timestamp,
        optimization_hints: generate_optimization_hints(event_name, duration, metadata)
      }

      # Limit the number of stored slow queries
      updated_slow_queries =
        [slow_query | state.slow_queries]
        |> Enum.take(state.max_slow_queries)

      # Log slow operation
      Logger.warning("Slow operation detected: #{inspect(event_name)} (#{duration}ms)")

      # Track as an event for analytics
      Events.track_event(%{
        event_type: "performance_slow_operation",
        metadata: %{
          operation: event_name,
          duration_ms: duration,
          threshold_ms: get_threshold(event_name, state.thresholds)
        }
      })

      %{state | slow_queries: updated_slow_queries}
    else
      state
    end
  end

  defp update_native_stats(state, event_name, metadata) do
    if is_native_event?(event_name) do
      nif_name = extract_nif_name(event_name)

      current_stats =
        Map.get(state.native_stats, nif_name, %{
          calls: 0,
          memory_usage: 0,
          last_call: nil
        })

      updated_stats = %{
        calls: current_stats.calls + 1,
        memory_usage: metadata[:memory_usage] || current_stats.memory_usage,
        last_call: DateTime.utc_now()
      }

      %{state | native_stats: Map.put(state.native_stats, nif_name, updated_stats)}
    else
      state
    end
  end

  defp collect_system_metrics(state) do
    # Collect VM metrics
    vm_metrics = %{
      memory: :erlang.memory(),
      process_count: :erlang.system_info(:process_count),
      atom_count: :erlang.system_info(:atom_count),
      port_count: :erlang.system_info(:port_count),
      run_queue: :erlang.statistics(:run_queue)
    }

    # Store system metrics
    timestamp = DateTime.utc_now()
    system_key = {:system, :vm_stats}

    %{
      state
      | metrics:
          Map.put(state.metrics, system_key, %{
            data: vm_metrics,
            timestamp: timestamp
          })
    }
  end

  defp prune_old_data(state) do
    # Keep only data from the last 24 hours
    cutoff_time = DateTime.utc_now() |> DateTime.add(-24 * 60 * 60, :second)

    pruned_slow_queries =
      Enum.filter(state.slow_queries, fn query ->
        DateTime.compare(query.timestamp, cutoff_time) == :gt
      end)

    %{state | slow_queries: pruned_slow_queries}
  end

  defp build_current_metrics(state) do
    %{
      operations: state.metrics,
      slow_queries_count: length(state.slow_queries),
      native_stats: state.native_stats,
      thresholds: state.thresholds,
      ash_profiler_enabled: state.ash_profiler_enabled,
      collected_at: DateTime.utc_now()
    }
  end

  defp schedule_collection(interval) do
    Process.send_after(self(), :collect_metrics, interval)
  end

  defp get_metric_key(event_name) when is_list(event_name) do
    event_name |> Enum.join("_") |> String.to_atom()
  end

  defp get_metric_key(event_name), do: event_name

  defp is_slow_operation?(event_name, duration, thresholds) do
    threshold = get_threshold(event_name, thresholds)
    duration > threshold
  end

  defp get_threshold(event_name, thresholds) do
    cond do
      event_name |> Enum.join("_") |> String.contains?("ash") ->
        thresholds.ash_query

      event_name |> Enum.join("_") |> String.contains?("native") ->
        thresholds.nif_operation

      event_name |> Enum.join("_") |> String.contains?("oban") ->
        thresholds.oban_job

      event_name |> Enum.join("_") |> String.contains?("live_view") ->
        thresholds.liveview_mount

      event_name |> Enum.join("_") |> String.contains?("auth") ->
        thresholds.auth_operation

      event_name |> Enum.join("_") |> String.contains?("billing") ->
        thresholds.billing_check

      true ->
        # Default threshold
        100
    end
  end

  defp is_native_event?(event_name) do
    event_name |> Enum.join("_") |> String.contains?("native")
  end

  defp extract_nif_name(event_name) do
    event_name
    |> Enum.join("_")
    |> String.split("_")
    |> Enum.drop_while(&(&1 != "native"))
    |> Enum.drop(1)
    |> Enum.take(1)
    |> List.first()
    |> case do
      nil -> :unknown
      name -> String.to_atom(name)
    end
  end

  defp calculate_avg_duration(%{count: 0}, _duration), do: 0

  defp calculate_avg_duration(%{total_duration: total, count: count}, duration) do
    (total + (duration || 0)) / (count + 1)
  end

  defp update_min_duration(nil, duration), do: duration
  defp update_min_duration(current_min, nil), do: current_min
  defp update_min_duration(current_min, duration), do: min(current_min, duration)

  defp update_max_duration(nil, duration), do: duration
  defp update_max_duration(current_max, nil), do: current_max
  defp update_max_duration(current_max, duration), do: max(current_max, duration)

  defp generate_optimization_hints(event_name, duration, metadata) do
    cond do
      event_name |> Enum.join("_") |> String.contains?("ash") ->
        generate_ash_optimization_hints(event_name, duration, metadata)

      event_name |> Enum.join("_") |> String.contains?("native") ->
        generate_native_optimization_hints(event_name, duration, metadata)

      event_name |> Enum.join("_") |> String.contains?("oban") ->
        generate_oban_optimization_hints(event_name, duration, metadata)

      true ->
        ["Consider adding caching", "Review algorithm complexity", "Check for N+1 queries"]
    end
  end

  defp generate_ash_optimization_hints(_event_name, duration, metadata) do
    hints = ["Consider using ash_profiler for detailed query analysis"]

    hints =
      if duration > 500 do
        ["Add database indexes for frequently queried fields" | hints]
      else
        hints
      end

    hints =
      if Map.get(metadata, :query_count, 1) > 10 do
        ["Potential N+1 query detected - consider using load/2 or batch operations" | hints]
      else
        hints
      end

    hints
  end

  defp generate_native_optimization_hints(_event_name, duration, metadata) do
    hints = ["Consider increasing NIF timeout if operations are timing out"]

    hints =
      if duration > 1000 do
        ["Large NIF operation detected - consider chunking data" | hints]
      else
        hints
      end

    hints =
      if Map.get(metadata, :memory_usage, 0) > 100_000_000 do
        ["High memory usage detected - consider streaming or pagination" | hints]
      else
        hints
      end

    hints
  end

  defp generate_oban_optimization_hints(_event_name, duration, metadata) do
    hints = ["Consider adjusting queue concurrency for better throughput"]

    hints =
      if duration > 30_000 do
        ["Very long-running job - consider breaking into smaller jobs" | hints]
      else
        hints
      end

    hints =
      if Map.get(metadata, :attempt, 1) > 1 do
        ["Job is retrying - check for intermittent failures" | hints]
      else
        hints
      end

    hints
  end
end
