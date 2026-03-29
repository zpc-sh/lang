defmodule Lang.Testing.LSPComparator do
  @moduledoc """
  LSP Performance Comparator for running A/B tests measuring AI agent performance
  with and without LSP support.

  This module orchestrates comparative testing by running identical scenarios
  through agent variants, half with full LSP context and half without,
  then measuring and analyzing the performance differences.
  """

  use GenServer
  require Logger

  alias Lang.Testing.{AgentVariantGenerator, ScenarioDefinitions, PerformanceAnalyzer}
  alias Lang.Analytics.LSPMeasurementEvent
  alias Lang.Workers.LSPComparisonWorker
  alias Phoenix.PubSub

  @pubsub Lang.PubSub

  defstruct [
    :test_session_id,
    :scenarios,
    :agent_variants,
    :test_configurations,
    :results,
    :status,
    :started_at,
    :progress,
    :current_test
  ]

  @doc """
  Start a new LSP comparison test session.
  """
  def start_comparison(scenarios, agent_variants, opts \\ []) do
    session_id = generate_session_id()

    config = %{
      session_id: session_id,
      scenarios: scenarios,
      agent_variants: agent_variants,
      parallel_tests: Keyword.get(opts, :parallel_tests, 4),
      timeout_minutes: Keyword.get(opts, :timeout_minutes, 60),
      user_id: Keyword.get(opts, :user_id),
      organization_id: Keyword.get(opts, :organization_id),
      statistical_significance_threshold: Keyword.get(opts, :significance_threshold, 0.05)
    }

    case start_link(config) do
      {:ok, pid} ->
        GenServer.call(pid, :start_comparison)
        {:ok, %{session_id: session_id, pid: pid}}

      error ->
        error
    end
  end

  @doc """
  Get the current status of a comparison session.
  """
  def get_status(session_id) do
    case Registry.lookup(Lang.Registry, {:lsp_comparator, session_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_status)
      [] -> {:error, :session_not_found}
    end
  end

  @doc """
  Stop a comparison session.
  """
  def stop_comparison(session_id) do
    case Registry.lookup(Lang.Registry, {:lsp_comparator, session_id}) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> {:error, :session_not_found}
    end
  end

  @doc """
  Get results from a completed comparison.
  """
  def get_results(session_id) do
    case Registry.lookup(Lang.Registry, {:lsp_comparator, session_id}) do
      [{pid, _}] ->
        GenServer.call(pid, :get_results)

      [] ->
        # Try to fetch from storage if session is completed
        fetch_stored_results(session_id)
    end
  end

  # GenServer Implementation

  def start_link(config) do
    GenServer.start_link(__MODULE__, config,
      name: {:via, Registry, {Lang.Registry, {:lsp_comparator, config.session_id}}}
    )
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      test_session_id: config.session_id,
      scenarios: config.scenarios,
      agent_variants: config.agent_variants,
      test_configurations: generate_test_configurations(config),
      results: %{},
      status: :initialized,
      started_at: DateTime.utc_now(),
      progress: %{completed: 0, total: 0, current_batch: []},
      current_test: nil
    }

    Logger.info("LSP Comparator initialized", session_id: config.session_id)
    {:ok, state}
  end

  @impl true
  def handle_call(:start_comparison, _from, state) do
    Logger.info("Starting LSP comparison", session_id: state.test_session_id)

    # Calculate total tests
    # 2x for LSP vs non-LSP
    total_tests = length(state.scenarios) * length(state.agent_variants) * 2

    updated_state = %{state | status: :running, progress: %{state.progress | total: total_tests}}

    # Start the comparison process
    send(self(), :begin_testing)

    {:reply, {:ok, :started}, updated_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      session_id: state.test_session_id,
      status: state.status,
      progress: state.progress,
      started_at: state.started_at,
      current_test: state.current_test,
      estimated_completion: estimate_completion_time(state)
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:get_results, _from, state) do
    case state.status do
      :completed ->
        {:reply, {:ok, compile_final_results(state)}, state}

      status when status in [:running, :processing] ->
        {:reply, {:ok, compile_interim_results(state)}, state}

      _ ->
        {:reply, {:error, :not_ready}, state}
    end
  end

  @impl true
  def handle_info(:begin_testing, state) do
    Logger.info("Beginning LSP comparison tests", session_id: state.test_session_id)

    # Broadcast test start
    PubSub.broadcast(
      @pubsub,
      "lsp_comparison:#{state.test_session_id}",
      {:test_started, %{session_id: state.test_session_id, total_tests: state.progress.total}}
    )

    # Queue first batch of tests
    send(self(), :queue_next_batch)

    {:noreply, state}
  end

  @impl true
  def handle_info(:queue_next_batch, state) do
    case get_next_test_batch(state) do
      {[], updated_state} ->
        # No more tests, begin result compilation
        Logger.info("All tests queued, waiting for completion", session_id: state.test_session_id)
        send(self(), :check_completion)
        {:noreply, %{updated_state | status: :processing}}

      {batch, updated_state} ->
        Logger.info("Queueing test batch",
          session_id: state.test_session_id,
          batch_size: length(batch)
        )

        # Queue tests in Oban
        Enum.each(batch, &queue_comparison_test/1)

        # Update progress
        new_progress = %{
          updated_state.progress
          | current_batch: batch
        }

        {:noreply, %{updated_state | progress: new_progress}}
    end
  end

  @impl true
  def handle_info({:test_completed, test_id, results}, state) do
    Logger.info("Test completed", session_id: state.test_session_id, test_id: test_id)

    # Store results
    updated_results = Map.put(state.results, test_id, results)

    # Update progress
    completed = state.progress.completed + 1
    progress = %{state.progress | completed: completed}

    # Broadcast progress
    PubSub.broadcast(
      @pubsub,
      "lsp_comparison:#{state.test_session_id}",
      {:test_progress, %{completed: completed, total: progress.total, test_id: test_id}}
    )

    # Track in analytics
    track_test_completion(state.test_session_id, test_id, results)

    updated_state = %{state | results: updated_results, progress: progress}

    # Check if we need more tests or if we're done
    if completed >= progress.total do
      send(self(), :finalize_results)
    else
      send(self(), :queue_next_batch)
    end

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:test_failed, test_id, error}, state) do
    Logger.error("Test failed",
      session_id: state.test_session_id,
      test_id: test_id,
      error: inspect(error)
    )

    # Store error result
    error_result = %{
      status: :failed,
      error: error,
      completed_at: DateTime.utc_now()
    }

    updated_results = Map.put(state.results, test_id, error_result)

    # Update progress (count as completed even though failed)
    completed = state.progress.completed + 1
    progress = %{state.progress | completed: completed}

    updated_state = %{state | results: updated_results, progress: progress}

    # Continue with next batch
    if completed >= progress.total do
      send(self(), :finalize_results)
    else
      send(self(), :queue_next_batch)
    end

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:check_completion, state) do
    completed = state.progress.completed
    total = state.progress.total

    if completed >= total do
      send(self(), :finalize_results)
    else
      # Check again in 30 seconds
      Process.send_after(self(), :check_completion, 30_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:finalize_results, state) do
    Logger.info("Finalizing LSP comparison results", session_id: state.test_session_id)

    # Compile and analyze final results
    final_results = compile_final_results(state)
    statistical_analysis = PerformanceAnalyzer.analyze_comparison_results(state.results)

    # Store results persistently
    store_final_results(state.test_session_id, final_results, statistical_analysis)

    # Broadcast completion
    PubSub.broadcast(
      @pubsub,
      "lsp_comparison:#{state.test_session_id}",
      {:test_completed,
       %{
         session_id: state.test_session_id,
         results: final_results,
         analysis: statistical_analysis
       }}
    )

    updated_state = %{
      state
      | status: :completed,
        results: Map.put(state.results, :final_analysis, statistical_analysis)
    }

    {:noreply, updated_state}
  end

  # Private Helper Functions

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp generate_test_configurations(config) do
    scenarios = config.scenarios
    variants = config.agent_variants

    # Generate all combinations of scenarios and variants, both with and without LSP
    for scenario <- scenarios,
        variant <- variants,
        lsp_enabled <- [true, false] do
      %{
        test_id: generate_test_id(scenario, variant.name, lsp_enabled),
        scenario_id: scenario,
        agent_variant: variant,
        lsp_enabled: lsp_enabled,
        session_id: config.session_id,
        timeout_minutes: config.timeout_minutes,
        user_id: config.user_id,
        organization_id: config.organization_id
      }
    end
  end

  defp generate_test_id(scenario_id, variant_name, lsp_enabled) do
    suffix = if lsp_enabled, do: "lsp", else: "no_lsp"
    "#{scenario_id}_#{variant_name}_#{suffix}_#{System.unique_integer()}"
  end

  defp get_next_test_batch(state) do
    remaining_configs = state.test_configurations

    case remaining_configs do
      [] ->
        {[], state}

      configs ->
        # Take up to 4 tests for parallel execution
        {batch, remaining} = Enum.split(configs, 4)
        updated_state = %{state | test_configurations: remaining}
        {batch, updated_state}
    end
  end

  defp queue_comparison_test(test_config) do
    %{
      test_id: test_config.test_id,
      scenario_id: test_config.scenario_id,
      agent_variant: test_config.agent_variant,
      lsp_enabled: test_config.lsp_enabled,
      session_id: test_config.session_id,
      timeout_minutes: test_config.timeout_minutes,
      user_id: test_config.user_id,
      organization_id: test_config.organization_id
    }
    |> LSPComparisonWorker.new(queue: :analysis, priority: 2)
    |> Oban.insert()
  end

  defp estimate_completion_time(state) do
    case state.progress do
      %{completed: 0} ->
        nil

      %{completed: completed, total: total} ->
        elapsed = DateTime.diff(DateTime.utc_now(), state.started_at, :second)
        avg_time_per_test = elapsed / completed
        remaining_tests = total - completed
        estimated_seconds = round(remaining_tests * avg_time_per_test)
        DateTime.add(DateTime.utc_now(), estimated_seconds, :second)
    end
  end

  defp compile_interim_results(state) do
    completed_results =
      state.results
      |> Enum.filter(fn {_id, result} -> Map.get(result, :status) != :failed end)
      |> Map.new()

    %{
      session_id: state.test_session_id,
      status: state.status,
      progress: state.progress,
      partial_results: completed_results,
      preliminary_analysis: PerformanceAnalyzer.preliminary_analysis(completed_results)
    }
  end

  defp compile_final_results(state) do
    lsp_results = filter_results_by_lsp(state.results, true)
    no_lsp_results = filter_results_by_lsp(state.results, false)

    %{
      session_id: state.test_session_id,
      total_tests_run: state.progress.total,
      completed_tests: state.progress.completed,
      started_at: state.started_at,
      completed_at: DateTime.utc_now(),
      lsp_enabled_results: lsp_results,
      lsp_disabled_results: no_lsp_results,
      performance_comparison: compare_lsp_vs_no_lsp(lsp_results, no_lsp_results),
      scenario_breakdown: analyze_by_scenario(state.results),
      variant_breakdown: analyze_by_variant(state.results),
      statistical_significance: calculate_statistical_significance(lsp_results, no_lsp_results)
    }
  end

  defp filter_results_by_lsp(results, lsp_enabled) do
    results
    |> Enum.filter(fn {test_id, _result} ->
      String.contains?(test_id, if(lsp_enabled, do: "_lsp_", else: "_no_lsp_"))
    end)
    |> Map.new()
  end

  defp compare_lsp_vs_no_lsp(lsp_results, no_lsp_results) do
    lsp_metrics = extract_performance_metrics(lsp_results)
    no_lsp_metrics = extract_performance_metrics(no_lsp_results)

    %{
      completion_time_improvement:
        calculate_improvement(lsp_metrics.avg_completion_time, no_lsp_metrics.avg_completion_time),
      quality_score_improvement:
        calculate_improvement(no_lsp_metrics.avg_quality_score, lsp_metrics.avg_quality_score),
      error_rate_reduction:
        calculate_improvement(no_lsp_metrics.error_rate, lsp_metrics.error_rate),
      context_utilization_improvement:
        calculate_improvement(no_lsp_metrics.avg_context_usage, lsp_metrics.avg_context_usage),
      overall_performance_gain: calculate_overall_gain(lsp_metrics, no_lsp_metrics)
    }
  end

  defp extract_performance_metrics(results) do
    valid_results =
      Enum.reject(results, fn {_id, result} -> Map.get(result, :status) == :failed end)

    if Enum.empty?(valid_results) do
      %{avg_completion_time: 0, avg_quality_score: 0, error_rate: 1.0, avg_context_usage: 0}
    else
      completion_times =
        Enum.map(valid_results, fn {_id, result} -> Map.get(result, :completion_time_ms, 0) end)

      quality_scores =
        Enum.map(valid_results, fn {_id, result} -> Map.get(result, :quality_score, 0.0) end)

      context_usage =
        Enum.map(valid_results, fn {_id, result} -> Map.get(result, :context_utilization, 0.0) end)

      error_count = Enum.count(results) - length(valid_results)
      error_rate = error_count / Enum.count(results)

      %{
        avg_completion_time: Enum.sum(completion_times) / length(completion_times),
        avg_quality_score: Enum.sum(quality_scores) / length(quality_scores),
        error_rate: error_rate,
        avg_context_usage:
          if(Enum.empty?(context_usage),
            do: 0.0,
            else: Enum.sum(context_usage) / length(context_usage)
          )
      }
    end
  end

  defp calculate_improvement(baseline, improved) when baseline > 0 do
    (improved - baseline) / baseline * 100
  end

  defp calculate_improvement(_baseline, _improved), do: 0.0

  defp calculate_overall_gain(lsp_metrics, no_lsp_metrics) do
    time_weight = 0.3
    quality_weight = 0.4
    error_weight = 0.2
    context_weight = 0.1

    time_gain =
      calculate_improvement(no_lsp_metrics.avg_completion_time, lsp_metrics.avg_completion_time) *
        time_weight

    quality_gain =
      calculate_improvement(no_lsp_metrics.avg_quality_score, lsp_metrics.avg_quality_score) *
        quality_weight

    error_gain =
      calculate_improvement(lsp_metrics.error_rate, no_lsp_metrics.error_rate) * error_weight

    context_gain =
      calculate_improvement(no_lsp_metrics.avg_context_usage, lsp_metrics.avg_context_usage) *
        context_weight

    time_gain + quality_gain + error_gain + context_gain
  end

  defp analyze_by_scenario(results) do
    results
    |> Enum.group_by(fn {test_id, _result} ->
      # Extract scenario from test_id (format: scenario_variant_lsp_unique)
      test_id |> String.split("_") |> hd()
    end)
    |> Enum.map(fn {scenario, scenario_results} ->
      scenario_map = Map.new(scenario_results)
      lsp_results = filter_results_by_lsp(scenario_map, true)
      no_lsp_results = filter_results_by_lsp(scenario_map, false)

      {scenario,
       %{
         total_tests: length(scenario_results),
         lsp_performance: extract_performance_metrics(lsp_results),
         no_lsp_performance: extract_performance_metrics(no_lsp_results),
         improvement: compare_lsp_vs_no_lsp(lsp_results, no_lsp_results)
       }}
    end)
    |> Map.new()
  end

  defp analyze_by_variant(results) do
    results
    |> Enum.group_by(fn {test_id, _result} ->
      # Extract variant from test_id (format: scenario_variant_lsp_unique)
      parts = String.split(test_id, "_")
      Enum.at(parts, 1)
    end)
    |> Enum.map(fn {variant, variant_results} ->
      variant_map = Map.new(variant_results)
      lsp_results = filter_results_by_lsp(variant_map, true)
      no_lsp_results = filter_results_by_lsp(variant_map, false)

      {variant,
       %{
         total_tests: length(variant_results),
         lsp_performance: extract_performance_metrics(lsp_results),
         no_lsp_performance: extract_performance_metrics(no_lsp_results),
         improvement: compare_lsp_vs_no_lsp(lsp_results, no_lsp_results)
       }}
    end)
    |> Map.new()
  end

  defp calculate_statistical_significance(lsp_results, no_lsp_results) do
    # Simplified statistical analysis - in production would use proper statistical tests
    lsp_sample_size = map_size(lsp_results)
    no_lsp_sample_size = map_size(no_lsp_results)

    %{
      lsp_sample_size: lsp_sample_size,
      no_lsp_sample_size: no_lsp_sample_size,
      sufficient_sample_size: lsp_sample_size >= 10 && no_lsp_sample_size >= 10,
      confidence_level: 0.95,
      note: "Statistical significance calculation simplified for demo purposes"
    }
  end

  defp track_test_completion(session_id, test_id, results) do
    # Track individual test completion in analytics
    LSPMeasurementEvent.create(%{
      session_id: session_id,
      request_id: test_id,
      lsp_method: :comparison_test,
      completion_time_ms: Map.get(results, :completion_time_ms, 0),
      quality_score: Map.get(results, :quality_score, 0.0),
      context_utilization: Map.get(results, :context_utilization, 0.0),
      lsp_enabled: Map.get(results, :lsp_enabled, false)
    })
  end

  defp store_final_results(session_id, results, analysis) do
    # Store in a simple way for now - could use proper storage later
    file_path = Path.join([System.tmp_dir(), "lsp_comparison_#{session_id}.json"])

    data = %{
      results: results,
      analysis: analysis,
      stored_at: DateTime.utc_now()
    }

    File.write(file_path, Jason.encode!(data))
    Logger.info("LSP comparison results stored", session_id: session_id, path: file_path)
  end

  defp fetch_stored_results(session_id) do
    file_path = Path.join([System.tmp_dir(), "lsp_comparison_#{session_id}.json"])

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          error -> error
        end

      error ->
        error
    end
  end
end
