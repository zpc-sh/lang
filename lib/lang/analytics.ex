defmodule Lang.Analytics do
  @moduledoc """
  LANG Analytics Domain

  This domain handles all LSP enhancement measurement and analytics functionality
  using proper Ash resources with PubSub notifications for real-time dashboards.

  Tracks token efficiency, productivity improvements, user adoption, and A/B testing
  to prove quantifiable business value of LSP enhancements.
  """

  use Ash.Domain

  resources do
    resource(Lang.Analytics.LSPMeasurementEvent)
    resource(Lang.Analytics.UserProductivityMetric)
    resource(Lang.Analytics.ABTestCohort)
    resource(Lang.Analytics.TokenEfficiencyReport)
  end

  @doc """
  Tracks an LSP measurement event for analytics.

  ## Examples

      Analytics.track_lsp_event(%{
        user_id: user.id,
        organization_id: org.id,
        lsp_method: :completion,
        baseline_tokens: 150,
        enhanced_tokens: 95,
        time_saved_seconds: 25,
        quality_score: 0.85,
        metadata: %{language: "elixir", provider: "xai"}
      })
  """
  def track_lsp_event(attrs) do
    case Lang.Analytics.LSPMeasurementEvent.create(attrs) do
      {:ok, event} ->
        # Broadcast for real-time dashboard updates
        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "lsp_analytics:#{event.user_id}",
          {:lsp_measurement_event, event}
        )

        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "lsp_analytics:all",
          {:lsp_measurement_tracked, event}
        )

        # Queue background job to update aggregated metrics
        %{event_id: event.id, user_id: event.user_id}
        |> Lang.Workers.ProductivityMetricsWorker.new(queue: :analytics)
        |> Oban.insert()

        {:ok, event}

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to track LSP event: #{inspect(reason)}, attrs: #{inspect(attrs)}")
        {:error, reason}
    end
  end

  @doc """
  Assigns a user to an A/B test cohort for LSP enhancement experiments.
  """
  def assign_ab_cohort(user_id, experiment_name, opts \\ []) do
    # Check if user is already assigned
    import Ash.Query

    existing =
      Lang.Analytics.ABTestCohort
      |> Ash.Query.filter(user_id == ^user_id and experiment_name == ^experiment_name)
      |> Ash.read_one()

    case existing do
      {:ok, cohort} when not is_nil(cohort) ->
        {:ok, cohort}

      _ ->
        # Randomly assign to treatment or control (50/50 split by default)
        treatment_probability = Keyword.get(opts, :treatment_probability, 0.5)
        cohort_type = if :rand.uniform() < treatment_probability, do: :treatment, else: :control

        attrs = %{
          user_id: user_id,
          experiment_name: experiment_name,
          cohort_type: cohort_type,
          assigned_at: DateTime.utc_now(),
          metadata: Keyword.get(opts, :metadata, %{})
        }

        Lang.Analytics.ABTestCohort.create(attrs)
    end
  end

  @doc """
  Checks if a user is in the treatment group for LSP enhancements.
  """
  def lsp_enhancement_enabled?(user_id) do
    import Ash.Query

    case Lang.Analytics.ABTestCohort
         |> Ash.Query.filter(user_id == ^user_id and experiment_name == "lsp_enhancements")
         |> Ash.read_one() do
      {:ok, %{cohort_type: :treatment}} ->
        true

      {:ok, %{cohort_type: :control}} ->
        false

      _ ->
        # Auto-assign if not found
        case assign_ab_cohort(user_id, "lsp_enhancements") do
          {:ok, %{cohort_type: :treatment}} -> true
          _ -> false
        end
    end
  end

  @doc """
  Gets productivity metrics for a user over a time period.
  """
  def get_user_productivity(user_id, opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    import Ash.Query

    Lang.Analytics.UserProductivityMetric
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.filter(period_start >= ^from and period_end <= ^to)
    |> Ash.Query.sort(period_start: :desc)
    |> Ash.read()
  end

  @doc """
  Gets token efficiency trends for analysis.
  """
  def get_token_efficiency_trends(opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    organization_id = Keyword.get(opts, :organization_id)

    import Ash.Query

    query =
      Lang.Analytics.TokenEfficiencyReport
      |> Ash.Query.filter(report_date >= ^from and report_date <= ^to)
      |> Ash.Query.sort(report_date: :desc)

    query =
      if organization_id do
        Ash.Query.filter(query, organization_id == ^organization_id)
      else
        query
      end

    Ash.read(query)
  end

  @doc """
  Performs A/B test analysis to compare treatment vs control groups.
  """
  def analyze_ab_test_results(experiment_name, opts \\ []) do
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
  Calculates aggregate statistics across all LSP measurement events.
  """
  def calculate_aggregate_stats(opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    organization_id = Keyword.get(opts, :organization_id)

    import Ash.Query

    query =
      Lang.Analytics.LSPMeasurementEvent
      |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)

    query =
      if organization_id do
        Ash.Query.filter(query, organization_id == ^organization_id)
      else
        query
      end

    case Ash.read(query) do
      {:ok, events} ->
        stats = calculate_stats_from_events(events)
        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp calculate_stats_from_events(events) when is_list(events) do
    total_events = length(events)

    if total_events == 0 do
      %{
        total_events: 0,
        avg_token_reduction_percent: 0.0,
        total_tokens_saved: 0,
        avg_time_saved_seconds: 0.0,
        avg_quality_improvement: 0.0,
        method_breakdown: %{},
        provider_performance: %{}
      }
    else
      # Calculate token savings
      token_events = Enum.filter(events, fn e -> e.baseline_tokens && e.enhanced_tokens end)
      total_baseline_tokens = Enum.reduce(token_events, 0, fn x, acc -> acc + x.baseline_tokens end)
      total_enhanced_tokens = Enum.reduce(token_events, 0, fn x, acc -> acc + x.enhanced_tokens end)
      total_tokens_saved = total_baseline_tokens - total_enhanced_tokens

      avg_token_reduction_percent =
        if total_baseline_tokens > 0 do
          total_tokens_saved / total_baseline_tokens * 100
        else
          0.0
        end

      # Calculate time savings
      time_events = Enum.filter(events, fn e -> e.time_saved_seconds end)

      avg_time_saved =
        if length(time_events) > 0 do
          Enum.reduce(time_events, 0, fn x, acc -> acc + x.time_saved_seconds end) / length(time_events)
        else
          0.0
        end

      # Calculate quality improvements
      quality_events = Enum.filter(events, fn e -> e.quality_score end)

      avg_quality =
        if length(quality_events) > 0 do
          Enum.reduce(quality_events, 0, fn x, acc -> acc + x.quality_score end) / length(quality_events)
        else
          0.0
        end

      # Method breakdown
      method_breakdown =
        events
        |> Enum.group_by(& &1.lsp_method)
        |> Enum.map(fn {method, method_events} ->
          {method, length(method_events)}
        end)
        |> Enum.into(%{})

      # Provider performance
      provider_performance =
        events
        |> Enum.filter(fn e -> get_in(e.metadata, ["provider"]) end)
        |> Enum.group_by(fn e -> get_in(e.metadata, ["provider"]) end)
        |> Enum.map(fn {provider, provider_events} ->
          avg_provider_reduction =
            provider_events
            |> Enum.filter(fn e -> e.baseline_tokens && e.enhanced_tokens end)
            |> case do
              [] ->
                0.0

              token_events ->
                baseline = Enum.reduce(token_events, 0, fn x, acc -> acc + x.baseline_tokens end)
                enhanced = Enum.reduce(token_events, 0, fn x, acc -> acc + x.enhanced_tokens end)
                if baseline > 0, do: (baseline - enhanced) / baseline * 100, else: 0.0
            end

          {provider,
           %{count: length(provider_events), avg_token_reduction: avg_provider_reduction}}
        end)
        |> Enum.into(%{})

      %{
        total_events: total_events,
        avg_token_reduction_percent: Float.round(avg_token_reduction_percent, 2),
        total_tokens_saved: total_tokens_saved,
        avg_time_saved_seconds: Float.round(avg_time_saved, 2),
        avg_quality_improvement: Float.round(avg_quality, 3),
        method_breakdown: method_breakdown,
        provider_performance: provider_performance
      }
    end
  end

  @doc """
  Generates a comprehensive analytics report for business stakeholders.
  """
  def generate_business_report(opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    with {:ok, stats} <- calculate_aggregate_stats(from: from, to: to),
         {:ok, efficiency_trends} <- get_token_efficiency_trends(from: from, to: to) do
      # Calculate business metrics
      # Approximate cost per token across providers
      cost_per_token = 0.00002
      total_cost_savings = stats.total_tokens_saved * cost_per_token

      # Productivity calculations (assuming $100/hour developer cost)
      developer_hourly_rate = 100
      total_time_saved_hours = stats.avg_time_saved_seconds / 3600 * stats.total_events
      productivity_savings = total_time_saved_hours * developer_hourly_rate

      report = %{
        period: %{from: from, to: to},
        summary: %{
          total_lsp_operations: stats.total_events,
          avg_token_reduction: "#{stats.avg_token_reduction_percent}%",
          total_tokens_saved: stats.total_tokens_saved,
          estimated_cost_savings: "$#{Float.round(total_cost_savings, 2)}",
          avg_time_saved_per_operation: "#{stats.avg_time_saved_seconds}s",
          total_productivity_savings: "$#{Float.round(productivity_savings, 2)}",
          roi_multiplier: calculate_roi_multiplier(total_cost_savings + productivity_savings)
        },
        detailed_metrics: stats,
        efficiency_trends: efficiency_trends,
        generated_at: DateTime.utc_now()
      }

      {:ok, report}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp calculate_roi_multiplier(total_savings) do
    # Rough estimate of LSP infrastructure costs
    # Estimated monthly cost
    monthly_infrastructure_cost = 500

    if monthly_infrastructure_cost > 0 do
      Float.round(total_savings / monthly_infrastructure_cost, 1)
    else
      0.0
    end
  end

  # Private helper functions for A/B test analysis

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

      total_baseline = Enum.reduce(token_events, 0, fn x, acc -> acc + x.baseline_tokens end)
      total_enhanced = Enum.reduce(token_events, 0, fn x, acc -> acc + x.enhanced_tokens end)
      total_saved = total_baseline - total_enhanced

      avg_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0.0

      time_events = Enum.filter(events, fn e -> e.time_saved_seconds end)

      avg_time_saved =
        if length(time_events) > 0 do
          Enum.reduce(time_events, 0, fn x, acc -> acc + x.time_saved_seconds end) / length(time_events)
        else
          0.0
        end

      quality_events = Enum.filter(events, fn e -> e.quality_score end)

      avg_quality =
        if length(quality_events) > 0 do
          Enum.reduce(quality_events, 0, fn x, acc -> acc + Decimal.to_float(x.quality_score) end) /
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

  defp perform_significance_tests(treatment_stats, control_stats) do
    # Simplified statistical significance tests
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

  defp calculate_comparisons(treatment_stats, control_stats) do
    %{
      token_reduction_improvement:
        treatment_stats.avg_token_reduction - control_stats.avg_token_reduction,
      time_savings_improvement: treatment_stats.avg_time_saved - control_stats.avg_time_saved,
      quality_improvement: treatment_stats.avg_quality_score - control_stats.avg_quality_score,
      success_rate_improvement: treatment_stats.success_rate - control_stats.success_rate
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
end
