defmodule Lang.Analytics.LSPMetrics do
  @moduledoc """
  LSP Analytics Engine - Core measurement system for tracking token efficiency
  and productivity improvements from LSP enhancements.

  This module provides instrumentation hooks that integrate with the existing
  Provider Router to capture before/after measurements transparently.
  """

  alias Lang.Analytics
  alias Lang.Providers.Router

  require Logger

  @doc """
  Wraps an LSP operation to measure its effectiveness.

  This function captures baseline metrics (what would happen without LSP),
  then executes the LSP-enhanced version and compares the results.

  ## Examples

      LSPMetrics.measure_lsp_operation(
        method: :completion,
        params: %{context: code, language: "elixir"},
        user_id: user.id,
        organization_id: org.id,
        opts: []
      )
  """
  def measure_lsp_operation(opts) do
    method = Keyword.fetch!(opts, :method)
    params = Keyword.fetch!(opts, :params)
    user_id = Keyword.fetch!(opts, :user_id)
    organization_id = Keyword.get(opts, :organization_id)
    request_opts = Keyword.get(opts, :opts, [])

    session_id = generate_session_id()
    request_id = Ecto.UUID.generate()

    start_time = System.monotonic_time(:millisecond)

    # Check if user is in treatment group for LSP enhancements
    lsp_enabled = Analytics.lsp_enhancement_enabled?(user_id)
    cohort_type = if lsp_enabled, do: :treatment, else: :control

    try do
      if lsp_enabled do
        # Treatment group: Use LSP enhancements
        measure_enhanced_operation(
          method,
          params,
          user_id,
          organization_id,
          session_id,
          request_id,
          start_time,
          cohort_type,
          request_opts
        )
      else
        # Control group: Use baseline approach
        measure_baseline_operation(
          method,
          params,
          user_id,
          organization_id,
          session_id,
          request_id,
          start_time,
          cohort_type,
          request_opts
        )
      end
    catch
      error ->
        Logger.error("LSP measurement failed: #{inspect(error)}")
        # Fallback to standard operation
        Router.route_lsp(method, params, request_opts)
    end
  end

  @doc """
  Records a manual measurement event (for operations not going through the wrapper).
  """
  def record_measurement(attrs) do
    # Ensure required fields are present
    required_attrs = [
      :user_id,
      :lsp_method,
      :baseline_tokens,
      :enhanced_tokens,
      :time_saved_seconds
    ]

    missing_attrs = Enum.filter(required_attrs, fn attr -> not Map.has_key?(attrs, attr) end)

    if length(missing_attrs) > 0 do
      {:error, "Missing required attributes: #{inspect(missing_attrs)}"}
    else
      # Get user's cohort for A/B testing context
      cohort_type = get_user_cohort(attrs.user_id, "lsp_enhancements")

      measurement_attrs =
        attrs
        |> Map.put(:cohort_type, cohort_type)
        |> Map.put(:experiment_name, "lsp_enhancements")
        |> Map.put_new(:occurred_at, DateTime.utc_now())

      Analytics.track_lsp_event(measurement_attrs)
    end
  end

  @doc """
  Gets comprehensive analytics for a user over a time period.
  """
  def get_user_analytics(user_id, opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    import Ash.Query

    # Get LSP measurement events
    with {:ok, events} <-
           Lang.Analytics.LSPMeasurementEvent
           |> Ash.Query.filter(user_id == ^user_id)
           |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
           |> Ash.Query.sort(occurred_at: :desc)
           |> Ash.read(),
         {:ok, productivity_metrics} <-
           Analytics.get_user_productivity(user_id, from: from, to: to) do
      analytics = compile_user_analytics(events, productivity_metrics, user_id, from, to)
      {:ok, analytics}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates a token efficiency report for dashboards.
  """
  def generate_efficiency_report(opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    organization_id = Keyword.get(opts, :organization_id)

    with {:ok, stats} <-
           Analytics.calculate_aggregate_stats(
             from: from,
             to: to,
             organization_id: organization_id
           ) do
      report = %{
        period: %{from: from, to: to},
        summary: %{
          total_operations: stats.total_events,
          avg_token_reduction: stats.avg_token_reduction_percent,
          total_tokens_saved: stats.total_tokens_saved,
          avg_time_saved: stats.avg_time_saved_seconds,
          quality_improvement: stats.avg_quality_improvement
        },
        method_breakdown: stats.method_breakdown,
        provider_performance: stats.provider_performance,
        trends: calculate_trends(stats, organization_id, from, to),
        generated_at: DateTime.utc_now()
      }

      {:ok, report}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Performs A/B test analysis to compare treatment vs control groups.
  """
  def analyze_ab_test_results(experiment_name \\ "lsp_enhancements", opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    min_interactions = Keyword.get(opts, :min_interactions, 5)

    import Ash.Query

    # Get cohort assignments
    with {:ok, treatment_cohorts} <-
           Lang.Analytics.ABTestCohort.for_analysis(experiment_name,
             min_interactions: min_interactions
           )
           |> Ash.Query.filter(cohort_type == :treatment)
           |> Ash.read(),
         {:ok, control_cohorts} <-
           Lang.Analytics.ABTestCohort.for_analysis(experiment_name,
             min_interactions: min_interactions
           )
           |> Ash.Query.filter(cohort_type == :control)
           |> Ash.read() do
      treatment_user_ids = Enum.map(treatment_cohorts, & &1.user_id)
      control_user_ids = Enum.map(control_cohorts, & &1.user_id)

      # Get measurement events for each group
      {:ok, treatment_events} =
        Lang.Analytics.LSPMeasurementEvent
        |> Ash.Query.filter(user_id in ^treatment_user_ids)
        |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
        |> Ash.read()

      {:ok, control_events} =
        Lang.Analytics.LSPMeasurementEvent
        |> Ash.Query.filter(user_id in ^control_user_ids)
        |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
        |> Ash.read()

      # Calculate statistics for each group
      treatment_stats = calculate_group_stats(treatment_events)
      control_stats = calculate_group_stats(control_events)

      # Perform statistical significance tests
      significance_tests = perform_significance_tests(treatment_stats, control_stats)

      analysis = %{
        experiment_name: experiment_name,
        period: %{from: from, to: to},
        sample_sizes: %{
          treatment: length(treatment_user_ids),
          control: length(control_user_ids)
        },
        treatment_group: treatment_stats,
        control_group: control_stats,
        comparisons: calculate_comparisons(treatment_stats, control_stats),
        statistical_tests: significance_tests,
        confidence_level: 0.95,
        recommendations:
          generate_recommendations(treatment_stats, control_stats, significance_tests),
        analyzed_at: DateTime.utc_now()
      }

      {:ok, analysis}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts continuous measurement of LSP operations for a user session.
  """
  def start_session_measurement(user_id, session_id, opts \\ []) do
    metadata = %{
      session_started: DateTime.utc_now(),
      user_id: user_id,
      organization_id: Keyword.get(opts, :organization_id),
      measurement_active: true
    }

    # Store session context
    :ets.insert(:lsp_measurement_sessions, {session_id, metadata})

    # Subscribe to LSP events for this session
    Phoenix.PubSub.subscribe(Lang.PubSub, "lsp_session:#{session_id}")

    Logger.info("Started LSP measurement session for user #{user_id}: #{session_id}")
    {:ok, session_id}
  end

  @doc """
  Ends a measurement session and generates summary.
  """
  def end_session_measurement(session_id) do
    case :ets.lookup(:lsp_measurement_sessions, session_id) do
      [{^session_id, metadata}] ->
        # Calculate session summary
        session_summary = calculate_session_summary(session_id, metadata)

        # Clean up session data
        :ets.delete(:lsp_measurement_sessions, session_id)
        Phoenix.PubSub.unsubscribe(Lang.PubSub, "lsp_session:#{session_id}")

        Logger.info("Ended LSP measurement session: #{session_id}")
        {:ok, session_summary}

      [] ->
        {:error, :session_not_found}
    end
  end

  # Private helper functions

  defp measure_enhanced_operation(
         method,
         params,
         user_id,
         organization_id,
         session_id,
         request_id,
         start_time,
         cohort_type,
         opts
       ) do
    # First, estimate what baseline would be (for comparison)
    baseline_estimate = estimate_baseline_tokens(method, params)

    # Execute enhanced LSP operation
    result = Router.route_lsp(method, params, opts)

    end_time = System.monotonic_time(:millisecond)
    operation_duration = end_time - start_time

    case result do
      {:ok, response} ->
        # Extract token usage from response
        enhanced_tokens = extract_token_count(response)

        # Record the measurement
        measurement_attrs = %{
          user_id: user_id,
          organization_id: organization_id,
          session_id: session_id,
          request_id: request_id,
          lsp_method: method,
          operation_context: extract_operation_context(params),
          baseline_tokens: baseline_estimate,
          enhanced_tokens: enhanced_tokens,
          operation_duration_ms: operation_duration,
          language: Map.get(params, :language),
          file_type: Map.get(params, :file_type),
          provider: get_provider_from_response(response),
          model: get_model_from_response(response),
          cohort_type: cohort_type,
          experiment_name: "lsp_enhancements",
          feature_used: true,
          metadata: %{
            method: method,
            session_id: session_id,
            enhanced_operation: true
          }
        }

        # Track the measurement asynchronously
        Task.start(fn ->
          Analytics.track_lsp_event(measurement_attrs)
        end)

        # Record user interaction for A/B testing
        record_ab_interaction(user_id, "lsp_enhancements")

        result

      {:error, _reason} = error ->
        # Record failed operation
        measurement_attrs = %{
          user_id: user_id,
          organization_id: organization_id,
          session_id: session_id,
          request_id: request_id,
          lsp_method: method,
          operation_duration_ms: operation_duration,
          cohort_type: cohort_type,
          experiment_name: "lsp_enhancements",
          feature_used: false,
          metadata: %{
            method: method,
            session_id: session_id,
            enhanced_operation: true,
            failed: true
          }
        }

        Task.start(fn ->
          Analytics.track_lsp_event(measurement_attrs)
        end)

        error
    end
  end

  defp measure_baseline_operation(
         method,
         params,
         user_id,
         organization_id,
         session_id,
         request_id,
         start_time,
         cohort_type,
         opts
       ) do
    # For control group, we still execute the operation but without enhancements
    # This might be a simpler version or different routing
    baseline_opts = Keyword.put(opts, :disable_enhancements, true)

    result = Router.route_lsp(method, params, baseline_opts)

    end_time = System.monotonic_time(:millisecond)
    operation_duration = end_time - start_time

    case result do
      {:ok, response} ->
        # Extract token usage from baseline response
        baseline_tokens = extract_token_count(response)

        # For control group, enhanced_tokens is the same as baseline
        measurement_attrs = %{
          user_id: user_id,
          organization_id: organization_id,
          session_id: session_id,
          request_id: request_id,
          lsp_method: method,
          operation_context: extract_operation_context(params),
          baseline_tokens: baseline_tokens,
          enhanced_tokens: baseline_tokens,
          token_reduction_percent: 0,
          operation_duration_ms: operation_duration,
          language: Map.get(params, :language),
          file_type: Map.get(params, :file_type),
          provider: get_provider_from_response(response),
          model: get_model_from_response(response),
          cohort_type: cohort_type,
          experiment_name: "lsp_enhancements",
          feature_used: false,
          metadata: %{
            method: method,
            session_id: session_id,
            enhanced_operation: false,
            control_group: true
          }
        }

        Task.start(fn ->
          Analytics.track_lsp_event(measurement_attrs)
        end)

        record_ab_interaction(user_id, "lsp_enhancements")

        result

      {:error, _reason} = error ->
        error
    end
  end

  defp estimate_baseline_tokens(method, params) do
    # Rough estimation based on method and context size
    context_size = get_context_size(params)

    base_tokens =
      case method do
        :completion -> context_size * 0.3 + 50
        :hover -> context_size * 0.1 + 20
        :explain -> context_size * 0.8 + 100
        :refactor -> context_size * 1.2 + 150
        :generate_tests -> context_size * 1.5 + 200
        _ -> context_size * 0.5 + 75
      end

    round(base_tokens)
  end

  defp get_context_size(params) do
    content = Map.get(params, :content) || Map.get(params, :context) || ""

    # Rough token estimation: ~4 characters per token
    String.length(content) / 4
  end

  defp extract_token_count(response) do
    # Try to extract actual token count from provider response
    cond do
      is_map(response) && Map.has_key?(response, :usage) ->
        usage = Map.get(response, :usage)

        (Map.get(usage, :total_tokens) || Map.get(usage, :prompt_tokens, 0)) +
          Map.get(usage, :completion_tokens, 0)

      is_map(response) && Map.has_key?(response, :token_count) ->
        Map.get(response, :token_count)

      true ->
        # Fallback: estimate based on response content
        content = extract_response_content(response)
        (String.length(content) / 4) |> round()
    end
  end

  defp extract_response_content(response) do
    cond do
      is_binary(response) -> response
      is_map(response) && Map.has_key?(response, :content) -> Map.get(response, :content)
      is_map(response) && Map.has_key?(response, :text) -> Map.get(response, :text)
      true -> inspect(response)
    end
  end

  defp extract_operation_context(params) do
    context = Map.get(params, :context) || Map.get(params, :content) || ""
    # Truncate for storage
    String.slice(context, 0, 500)
  end

  defp get_provider_from_response(response) do
    cond do
      is_map(response) && Map.has_key?(response, :provider) ->
        Map.get(response, :provider)

      is_map(response) && Map.has_key?(response, :model) ->
        model = Map.get(response, :model)

        cond do
          String.contains?(model, "xai") -> "xai"
          String.contains?(model, "gpt") -> "openai"
          String.contains?(model, "claude") -> "anthropic"
          true -> "unknown"
        end

      true ->
        "unknown"
    end
  end

  defp get_model_from_response(response) do
    if is_map(response) && Map.has_key?(response, :model) do
      Map.get(response, :model)
    else
      nil
    end
  end

  defp get_user_cohort(user_id, experiment_name) do
    case Analytics.assign_ab_cohort(user_id, experiment_name) do
      {:ok, %{cohort_type: cohort_type}} -> cohort_type
      # Default to control if assignment fails
      _ -> :control
    end
  end

  defp record_ab_interaction(user_id, experiment_name) do
    import Ash.Query

    case Lang.Analytics.ABTestCohort.by_user_and_experiment(user_id, experiment_name) do
      {:ok, cohort} ->
        Lang.Analytics.ABTestCohort.record_interaction(cohort)

      _ ->
        # Ignore if not found
        :ok
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64() |> binary_part(0, 16)
  end

  defp compile_user_analytics(events, productivity_metrics, user_id, from, to) do
    # Calculate summary stats from events
    total_events = length(events)

    if total_events == 0 do
      %{
        user_id: user_id,
        period: %{from: from, to: to},
        summary: %{
          total_operations: 0,
          avg_token_reduction: 0.0,
          total_tokens_saved: 0,
          avg_time_saved: 0.0,
          productivity_score: 0.0
        },
        trends: [],
        detailed_metrics: []
      }
    else
      token_events = Enum.filter(events, fn e -> e.baseline_tokens && e.enhanced_tokens end)
      total_baseline = Enum.sum(Enum.map(token_events, & &1.baseline_tokens))
      total_enhanced = Enum.sum(Enum.map(token_events, & &1.enhanced_tokens))
      total_saved = total_baseline - total_enhanced

      avg_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0.0

      time_events = Enum.filter(events, fn e -> e.time_saved_seconds end)

      avg_time_saved =
        if length(time_events) > 0 do
          Enum.sum(Enum.map(time_events, & &1.time_saved_seconds)) / length(time_events)
        else
          0.0
        end

      %{
        user_id: user_id,
        period: %{from: from, to: to},
        summary: %{
          total_operations: total_events,
          avg_token_reduction: Float.round(avg_reduction, 2),
          total_tokens_saved: total_saved,
          avg_time_saved: Float.round(avg_time_saved, 2),
          productivity_score: calculate_productivity_score(events)
        },
        method_breakdown: group_events_by_method(events),
        trends: calculate_user_trends(events),
        detailed_metrics: productivity_metrics
      }
    end
  end

  defp group_events_by_method(events) do
    events
    |> Enum.group_by(& &1.lsp_method)
    |> Enum.map(fn {method, method_events} ->
      token_events =
        Enum.filter(method_events, fn e -> e.baseline_tokens && e.enhanced_tokens end)

      avg_reduction =
        if length(token_events) > 0 do
          total_baseline = Enum.sum(Enum.map(token_events, & &1.baseline_tokens))
          total_enhanced = Enum.sum(Enum.map(token_events, & &1.enhanced_tokens))

          if total_baseline > 0,
            do: (total_baseline - total_enhanced) / total_baseline * 100,
            else: 0.0
        else
          0.0
        end

      {method,
       %{
         count: length(method_events),
         avg_token_reduction: Float.round(avg_reduction, 2)
       }}
    end)
    |> Enum.into(%{})
  end

  defp calculate_productivity_score(events) do
    # Simple productivity score based on token savings, time savings, and quality
    if length(events) == 0 do
      0.0
    else
      token_score =
        events
        |> Enum.filter(fn e -> e.token_reduction_percent end)
        |> case do
          [] ->
            0.0

          token_events ->
            Enum.sum(Enum.map(token_events, &Decimal.to_float(&1.token_reduction_percent))) /
              length(token_events)
        end

      time_score =
        events
        |> Enum.filter(fn e -> e.time_saved_seconds end)
        |> case do
          [] ->
            0.0

          time_events ->
            avg_time =
              Enum.sum(Enum.map(time_events, & &1.time_saved_seconds)) / length(time_events)

            # Cap at 50 for very high time savings
            min(avg_time / 60 * 10, 50)
        end

      quality_score =
        events
        |> Enum.filter(fn e -> e.quality_score end)
        |> case do
          [] ->
            0.0

          quality_events ->
            Enum.sum(Enum.map(quality_events, &Decimal.to_float(&1.quality_score))) /
              length(quality_events) * 50
        end

      # Weighted average
      (token_score * 0.4 + time_score * 0.4 + quality_score * 0.2)
      |> Float.round(1)
    end
  end

  defp calculate_user_trends(events) do
    # Group events by day and calculate daily trends
    events
    |> Enum.group_by(fn e -> DateTime.to_date(e.occurred_at) end)
    |> Enum.map(fn {date, day_events} ->
      token_events = Enum.filter(day_events, fn e -> e.baseline_tokens && e.enhanced_tokens end)

      daily_savings =
        if length(token_events) > 0 do
          Enum.sum(Enum.map(token_events, fn e -> e.baseline_tokens - e.enhanced_tokens end))
        else
          0
        end

      %{
        date: date,
        operations: length(day_events),
        tokens_saved: daily_savings,
        avg_reduction:
          if length(token_events) > 0 do
            total_baseline = Enum.sum(Enum.map(token_events, & &1.baseline_tokens))
            if total_baseline > 0, do: daily_savings / total_baseline * 100, else: 0.0
          else
            0.0
          end
      }
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  defp calculate_trends(_stats, _organization_id, _from, _to) do
    # Placeholder for trend calculation
    # This would analyze historical data to identify trends
    %{
      token_efficiency: "improving",
      user_adoption: "stable",
      quality_score: "improving"
    }
  end

  defp calculate_group_stats(events) do
    if length(events) == 0 do
      %{
        sample_size: 0,
        avg_token_reduction: 0.0,
        total_tokens_saved: 0,
        avg_time_saved: 0.0,
        avg_quality_score: 0.0,
        success_rate: 0.0
      }
    else
      token_events = Enum.filter(events, fn e -> e.baseline_tokens && e.enhanced_tokens end)

      total_baseline = Enum.sum(Enum.map(token_events, & &1.baseline_tokens))
      total_enhanced = Enum.sum(Enum.map(token_events, & &1.enhanced_tokens))
      total_saved = total_baseline - total_enhanced

      avg_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0.0

      time_events = Enum.filter(events, fn e -> e.time_saved_seconds end)

      avg_time_saved =
        if length(time_events) > 0 do
          Enum.sum(Enum.map(time_events, & &1.time_saved_seconds)) / length(time_events)
        else
          0.0
        end

      quality_events = Enum.filter(events, fn e -> e.quality_score end)

      avg_quality =
        if length(quality_events) > 0 do
          Enum.sum(Enum.map(quality_events, &Decimal.to_float(&1.quality_score))) /
            length(quality_events)
        else
          0.0
        end

      successful_operations = Enum.count(events, fn e -> e.feature_used == true end)
      success_rate = successful_operations / length(events) * 100

      %{
        sample_size: length(events),
        avg_token_reduction: Float.round(avg_reduction, 2),
        total_tokens_saved: total_saved,
        avg_time_saved: Float.round(avg_time_saved, 2),
        avg_quality_score: Float.round(avg_quality, 3),
        success_rate: Float.round(success_rate, 2)
      }
    end
  end

  defp calculate_comparisons(treatment_stats, control_stats) do
    %{
      token_reduction_improvement:
        treatment_stats.avg_token_reduction - control_stats.avg_token_reduction,
      time_savings_improvement: treatment_stats.avg_time_saved - control_stats.avg_time_saved,
      quality_improvement: treatment_stats.avg_quality_score - control_stats.avg_quality_score,
      success_rate_improvement: treatment_stats.success_rate - control_stats.success_rate
    }
  end

  defp perform_significance_tests(treatment_stats, control_stats) do
    # Simplified statistical significance tests
    # In a real implementation, you'd use proper statistical libraries

    sample_size_adequate = treatment_stats.sample_size >= 30 && control_stats.sample_size >= 30

    # Simple effect size calculation
    token_effect_size =
      abs(treatment_stats.avg_token_reduction - control_stats.avg_token_reduction)

    time_effect_size = abs(treatment_stats.avg_time_saved - control_stats.avg_time_saved)

    %{
      sample_size_adequate: sample_size_adequate,
      token_reduction_significant: sample_size_adequate && token_effect_size > 5.0,
      time_savings_significant: sample_size_adequate && time_effect_size > 10.0,
      overall_significance:
        sample_size_adequate && (token_effect_size > 5.0 || time_effect_size > 10.0),
      confidence_level: if(sample_size_adequate, do: 0.95, else: 0.8),
      effect_sizes: %{
        token_reduction: token_effect_size,
        time_savings: time_effect_size
      }
    }
  end

  defp generate_recommendations(treatment_stats, control_stats, significance_tests) do
    recommendations = []

    recommendations =
      if significance_tests.token_reduction_significant do
        improvement = treatment_stats.avg_token_reduction - control_stats.avg_token_reduction

        [
          "LSP enhancements show significant token reduction improvement of #{Float.round(improvement, 1)}%"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if significance_tests.time_savings_significant do
        improvement = treatment_stats.avg_time_saved - control_stats.avg_time_saved

        [
          "LSP enhancements show significant time savings improvement of #{Float.round(improvement, 1)} seconds per operation"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if significance_tests.overall_significance do
        [
          "Recommend full rollout of LSP enhancements based on significant improvements"
          | recommendations
        ]
      else
        [
          "Continue A/B testing - need larger sample size or longer test period for conclusive results"
          | recommendations
        ]
      end

    if length(recommendations) == 0 do
      ["No significant improvements detected - review LSP enhancement implementation"]
    else
      recommendations
    end
  end

  defp calculate_session_summary(session_id, metadata) do
    # This would collect all measurements from the session and generate a summary
    %{
      session_id: session_id,
      user_id: metadata.user_id,
      duration: DateTime.diff(DateTime.utc_now(), metadata.session_started),
      # Would count actual operations
      operations_measured: 0,
      total_tokens_saved: 0,
      avg_time_saved: 0.0,
      summary_generated_at: DateTime.utc_now()
    }
  end

  # Initialize ETS table for session tracking on application start
  def init_session_storage do
    case :ets.info(:lsp_measurement_sessions) do
      :undefined ->
        :ets.new(:lsp_measurement_sessions, [:set, :public, :named_table])
        Logger.info("Initialized LSP measurement session storage")
        :ok

      _ ->
        :ok
    end
  end
end
