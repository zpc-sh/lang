defmodule Lang.Experiments.ABTesting do
  @moduledoc """
  A/B Testing Framework for LSP Enhancement Experiments.

  This module provides comprehensive A/B testing capabilities to scientifically
  measure the effectiveness of LSP enhancements through randomized controlled trials.

  Features:
  - User cohort assignment and management
  - Statistical significance testing
  - Experiment result analysis
  - Feature flag management for gradual rollouts
  """

  alias Lang.Analytics
  alias Lang.Analytics.{ABTestCohort, LSPMeasurementEvent}

  require Logger

  @doc """
  Creates a new A/B test experiment.

  ## Examples

      ABTesting.create_experiment("lsp_enhancements_v2", %{
        treatment_probability: 0.5,
        description: "Testing new LSP enhancement features",
        start_date: ~D[2024-01-01],
        expected_end_date: ~D[2024-02-01],
        success_metrics: ["token_reduction", "time_savings", "user_satisfaction"]
      })
  """
  def create_experiment(experiment_name, config \\ %{}) do
    experiment_config = %{
      name: experiment_name,
      treatment_probability: Map.get(config, :treatment_probability, 0.5),
      description: Map.get(config, :description, ""),
      status: :active,
      start_date: Map.get(config, :start_date, Date.utc_today()),
      expected_end_date: Map.get(config, :expected_end_date),
      success_metrics: Map.get(config, :success_metrics, []),
      metadata: Map.get(config, :metadata, %{}),
      created_at: DateTime.utc_now()
    }

    # Store experiment configuration
    store_experiment_config(experiment_config)

    Logger.info("Created A/B test experiment: #{experiment_name}")
    {:ok, experiment_config}
  end

  @doc """
  Assigns a user to an experiment cohort using consistent randomization.
  """
  def assign_user_to_cohort(user_id, experiment_name, opts \\ []) do
    case Analytics.assign_ab_cohort(user_id, experiment_name, opts) do
      {:ok, cohort} ->
        # Log the assignment
        Logger.debug(
          "Assigned user #{user_id} to #{cohort.cohort_type} group for experiment #{experiment_name}"
        )

        # Track assignment event
        track_assignment_event(user_id, experiment_name, cohort.cohort_type)

        {:ok, cohort}

      {:error, reason} ->
        Logger.error(
          "Failed to assign user #{user_id} to experiment #{experiment_name}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Checks if a user is in the treatment group for an experiment.
  """
  def in_treatment_group?(user_id, experiment_name) do
    case get_user_cohort(user_id, experiment_name) do
      {:ok, :treatment} -> true
      {:ok, :control} -> false
      {:error, :not_assigned} -> assign_and_check(user_id, experiment_name)
      _ -> false
    end
  end

  @doc """
  Gets detailed experiment results with statistical analysis.
  """
  def get_experiment_results(experiment_name, opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    confidence_level = Keyword.get(opts, :confidence_level, 0.95)

    case Analytics.analyze_ab_test_results(experiment_name, from: from, to: to) do
      {:ok, analysis} ->
        # Enhance analysis with additional statistical tests
        enhanced_analysis = enhance_statistical_analysis(analysis, confidence_level)

        # Generate experiment report
        report = generate_experiment_report(enhanced_analysis)

        {:ok, report}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Runs statistical significance tests for experiment results.
  """
  def test_statistical_significance(experiment_name, opts \\ []) do
    case get_experiment_results(experiment_name, opts) do
      {:ok, report} ->
        significance_results = %{
          experiment_name: experiment_name,
          is_statistically_significant: report.statistical_tests.overall_significance,
          confidence_level: report.confidence_level,
          p_values: calculate_p_values(report),
          effect_sizes: report.statistical_tests.effect_sizes,
          sample_sizes: report.sample_sizes,
          recommendations: generate_statistical_recommendations(report),
          test_date: DateTime.utc_now()
        }

        {:ok, significance_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculates the minimum sample size needed for statistical power.
  """
  def calculate_required_sample_size(opts \\ []) do
    effect_size = Keyword.get(opts, :effect_size, 0.2)
    power = Keyword.get(opts, :power, 0.8)
    alpha = Keyword.get(opts, :alpha, 0.05)
    baseline_rate = Keyword.get(opts, :baseline_rate, 0.1)

    # Simplified power analysis calculation
    # In a real implementation, you'd use proper statistical libraries
    # For alpha = 0.05
    z_alpha = 1.96
    # For power = 0.8
    z_beta = 0.84

    # For proportions (success rates)
    p1 = baseline_rate
    p2 = baseline_rate + effect_size
    p_pooled = (p1 + p2) / 2

    numerator =
      z_alpha * :math.sqrt(2 * p_pooled * (1 - p_pooled)) +
        z_beta * :math.sqrt(p1 * (1 - p1) + p2 * (1 - p2))

    sample_size_per_group = :math.pow(numerator / (p2 - p1), 2) |> round()

    %{
      sample_size_per_group: sample_size_per_group,
      total_sample_size: sample_size_per_group * 2,
      effect_size: effect_size,
      power: power,
      alpha: alpha,
      baseline_rate: baseline_rate
    }
  end

  @doc """
  Monitors experiment progress and provides real-time status.
  """
  def get_experiment_status(experiment_name) do
    import Ash.Query

    case ABTestCohort.by_experiment(experiment_name) do
      {:ok, cohorts} ->
        treatment_users = Enum.filter(cohorts, &(&1.cohort_type == :treatment))
        control_users = Enum.filter(cohorts, &(&1.cohort_type == :control))

        # Calculate engagement metrics
        total_interactions = Enum.reduce(cohorts, 0, fn x, acc -> acc + x.total_interactions end)
        active_users = Enum.count(cohorts, &(&1.total_interactions > 0))

        # Get latest measurement data
        from = DateTime.add(DateTime.utc_now(), -7, :day)

        case get_recent_measurements(experiment_name, from) do
          {:ok, recent_measurements} ->
            status = %{
              experiment_name: experiment_name,
              total_users: length(cohorts),
              treatment_group_size: length(treatment_users),
              control_group_size: length(control_users),
              active_users: active_users,
              total_interactions: total_interactions,
              recent_measurements: length(recent_measurements),
              balance_ratio: calculate_balance_ratio(treatment_users, control_users),
              engagement_rate:
                if(length(cohorts) > 0, do: active_users / length(cohorts), else: 0.0),
              data_quality: assess_data_quality(cohorts, recent_measurements),
              status: :active,
              last_updated: DateTime.utc_now()
            }

            {:ok, status}

          {:error, _reason} ->
            # Return status without measurement data
            status = %{
              experiment_name: experiment_name,
              total_users: length(cohorts),
              treatment_group_size: length(treatment_users),
              control_group_size: length(control_users),
              active_users: active_users,
              total_interactions: total_interactions,
              status: :active,
              last_updated: DateTime.utc_now()
            }

            {:ok, status}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ends an experiment and archives the results.
  """
  def end_experiment(experiment_name, opts \\ []) do
    reason = Keyword.get(opts, :reason, "experiment_completed")
    save_results = Keyword.get(opts, :save_results, true)

    # Get final experiment results
    final_results =
      if save_results do
        case get_experiment_results(experiment_name) do
          {:ok, results} -> results
          {:error, _} -> %{}
        end
      else
        %{}
      end

    # Update all cohorts to completed status
    import Ash.Query

    case ABTestCohort.by_experiment(experiment_name) do
      {:ok, cohorts} ->
        Enum.each(cohorts, fn cohort ->
          ABTestCohort.complete_experiment(cohort, completed_at: DateTime.utc_now())
        end)

        # Archive experiment configuration
        archive_experiment(experiment_name, reason, final_results)

        Logger.info("Ended experiment #{experiment_name}: #{reason}")

        {:ok,
         %{experiment_name: experiment_name, ended_at: DateTime.utc_now(), results: final_results}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Performs cohort analysis to understand user segments.
  """
  def analyze_user_cohorts(experiment_name, opts \\ []) do
    segment_by = Keyword.get(opts, :segment_by, :signup_date)
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    import Ash.Query

    case ABTestCohort.by_experiment(experiment_name) do
      {:ok, cohorts} ->
        # Get measurement events for these users
        user_ids = Enum.map(cohorts, & &1.user_id)

        measurement_query =
          LSPMeasurementEvent
          |> Ash.Query.filter(user_id in ^user_ids)
          |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)

        case Ash.read(measurement_query) do
          {:ok, measurements} ->
            analysis = perform_cohort_analysis(cohorts, measurements, segment_by)
            {:ok, analysis}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp get_user_cohort(user_id, experiment_name) do
    case ABTestCohort.by_user_and_experiment(user_id, experiment_name) do
      {:ok, cohort} when not is_nil(cohort) ->
        {:ok, cohort.cohort_type}

      {:ok, nil} ->
        {:error, :not_assigned}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp assign_and_check(user_id, experiment_name) do
    case assign_user_to_cohort(user_id, experiment_name) do
      {:ok, %{cohort_type: :treatment}} -> true
      _ -> false
    end
  end

  defp track_assignment_event(user_id, experiment_name, cohort_type) do
    Analytics.track_lsp_event(%{
      user_id: user_id,
      lsp_method: :experiment_assignment,
      cohort_type: cohort_type,
      experiment_name: experiment_name,
      metadata: %{
        event_type: "cohort_assignment",
        assigned_at: DateTime.utc_now()
      }
    })
  end

  defp enhance_statistical_analysis(analysis, confidence_level) do
    # Add additional statistical measures
    enhanced_tests =
      Map.merge(analysis.statistical_tests, %{
        confidence_level: confidence_level,
        statistical_power: calculate_statistical_power(analysis),
        effect_size_interpretation:
          interpret_effect_sizes(analysis.statistical_tests.effect_sizes),
        sample_adequacy: assess_sample_adequacy(analysis.sample_sizes)
      })

    Map.put(analysis, :statistical_tests, enhanced_tests)
  end

  defp generate_experiment_report(analysis) do
    Map.merge(analysis, %{
      summary: %{
        conclusion: generate_conclusion(analysis),
        key_findings: extract_key_findings(analysis),
        business_impact: calculate_business_impact(analysis),
        next_steps: recommend_next_steps(analysis)
      },
      report_generated_at: DateTime.utc_now()
    })
  end

  defp calculate_p_values(report) do
    # Simplified p-value calculation
    # In a real implementation, you'd use proper statistical tests
    treatment_stats = report.treatment_group
    control_stats = report.control_group

    %{
      token_reduction:
        calculate_p_value_for_metric(
          treatment_stats.avg_token_reduction,
          control_stats.avg_token_reduction,
          treatment_stats.sample_size,
          control_stats.sample_size
        ),
      time_savings:
        calculate_p_value_for_metric(
          treatment_stats.avg_time_saved,
          control_stats.avg_time_saved,
          treatment_stats.sample_size,
          control_stats.sample_size
        )
    }
  end

  defp calculate_p_value_for_metric(treatment_mean, control_mean, n1, n2) do
    # Simplified t-test calculation
    # Assumes equal variance (pooled t-test)
    if n1 < 2 or n2 < 2 do
      # No significance with insufficient data
      1.0
    else
      # Mock calculation - in reality you'd use proper statistical libraries
      diff = abs(treatment_mean - control_mean)
      pooled_std = :math.sqrt((n1 + n2) / (n1 * n2))
      t_stat = diff / pooled_std

      # Very simplified p-value approximation
      cond do
        t_stat > 2.5 -> 0.01
        t_stat > 2.0 -> 0.05
        t_stat > 1.5 -> 0.1
        true -> 0.5
      end
    end
  end

  defp generate_statistical_recommendations(report) do
    recommendations = []

    # Check sample size
    recommendations =
      if report.sample_sizes.treatment < 30 or report.sample_sizes.control < 30 do
        [
          "Increase sample size for more reliable results (recommend >100 users per group)"
          | recommendations
        ]
      else
        recommendations
      end

    # Check significance
    recommendations =
      if report.statistical_tests.overall_significance do
        [
          "Results show statistical significance - recommend proceeding with rollout"
          | recommendations
        ]
      else
        [
          "Results not yet statistically significant - continue experiment or increase sample size"
          | recommendations
        ]
      end

    # Check effect size
    token_effect = Map.get(report.statistical_tests.effect_sizes, :token_reduction, 0)

    recommendations =
      if token_effect > 10 do
        [
          "Large practical effect detected - strong business case for implementation"
          | recommendations
        ]
      else
        recommendations
      end

    if length(recommendations) == 0 do
      ["Continue monitoring experiment - more data needed for conclusive results"]
    else
      recommendations
    end
  end

  defp calculate_statistical_power(analysis) do
    # Simplified power calculation
    treatment_size = analysis.sample_sizes.treatment
    control_size = analysis.sample_sizes.control

    min_size = min(treatment_size, control_size)

    cond do
      min_size >= 100 -> 0.9
      min_size >= 50 -> 0.8
      min_size >= 30 -> 0.7
      min_size >= 10 -> 0.6
      true -> 0.5
    end
  end

  defp interpret_effect_sizes(effect_sizes) do
    Enum.map(effect_sizes, fn {metric, size} ->
      interpretation =
        cond do
          size >= 20 -> "large"
          size >= 10 -> "medium"
          size >= 5 -> "small"
          true -> "negligible"
        end

      {metric, interpretation}
    end)
    |> Enum.into(%{})
  end

  defp assess_sample_adequacy(sample_sizes) do
    total_sample = sample_sizes.treatment + sample_sizes.control

    balance_ratio =
      min(sample_sizes.treatment, sample_sizes.control) /
        max(sample_sizes.treatment, sample_sizes.control)

    %{
      total_sample: total_sample,
      adequacy:
        cond do
          total_sample >= 200 and balance_ratio >= 0.8 -> "excellent"
          total_sample >= 100 and balance_ratio >= 0.7 -> "good"
          total_sample >= 50 and balance_ratio >= 0.6 -> "fair"
          true -> "insufficient"
        end,
      balance_ratio: Float.round(balance_ratio, 2)
    }
  end

  defp generate_conclusion(analysis) do
    if analysis.statistical_tests.overall_significance do
      treatment_improvement = analysis.comparisons.token_reduction_improvement

      if treatment_improvement > 10 do
        "LSP enhancements show significant positive impact with #{Float.round(treatment_improvement, 1)}% improvement in token efficiency. Recommend full rollout."
      else
        "LSP enhancements show statistically significant but modest improvements. Consider targeted rollout."
      end
    else
      "Results are not yet statistically significant. Continue experiment or increase sample size for conclusive results."
    end
  end

  defp extract_key_findings(analysis) do
    findings = []

    # Token efficiency finding
    token_improvement = analysis.comparisons.token_reduction_improvement

    findings =
      if token_improvement > 0 do
        ["Token efficiency improved by #{Float.round(token_improvement, 1)}%" | findings]
      else
        findings
      end

    # Time savings finding
    time_improvement = analysis.comparisons.time_savings_improvement

    findings =
      if time_improvement > 0 do
        [
          "Time savings improved by #{Float.round(time_improvement, 1)} seconds per operation"
          | findings
        ]
      else
        findings
      end

    # User adoption
    treatment_adoption = analysis.treatment_group.success_rate
    control_adoption = analysis.control_group.success_rate

    findings =
      if treatment_adoption > control_adoption do
        [
          "Higher feature adoption in treatment group (#{Float.round(treatment_adoption, 1)}% vs #{Float.round(control_adoption, 1)}%)"
          | findings
        ]
      else
        findings
      end

    if length(findings) == 0 do
      ["No significant differences detected between treatment and control groups"]
    else
      findings
    end
  end

  defp calculate_business_impact(analysis) do
    # Rough business impact calculations
    treatment_users = analysis.sample_sizes.treatment
    token_improvement = analysis.comparisons.token_reduction_improvement
    time_improvement = analysis.comparisons.time_savings_improvement

    # Approximate monthly cost savings per user
    monthly_cost_savings_per_user = (token_improvement * 0.1 + time_improvement * 0.5) * 30
    total_monthly_impact = monthly_cost_savings_per_user * treatment_users

    %{
      monthly_cost_savings_per_user: Float.round(monthly_cost_savings_per_user, 2),
      total_monthly_impact: Float.round(total_monthly_impact, 2),
      annual_projection: Float.round(total_monthly_impact * 12, 2)
    }
  end

  defp recommend_next_steps(analysis) do
    if analysis.statistical_tests.overall_significance do
      [
        "Prepare for full rollout of LSP enhancements",
        "Monitor key metrics during rollout phase",
        "Set up ongoing measurement to track long-term impact",
        "Consider A/B testing additional enhancements"
      ]
    else
      [
        "Continue current experiment until statistical significance is reached",
        "Consider increasing sample size or extending experiment duration",
        "Review and optimize LSP enhancement features",
        "Plan follow-up experiments with refined hypotheses"
      ]
    end
  end

  defp get_recent_measurements(experiment_name, from) do
    # Get users in this experiment
    import Ash.Query

    case ABTestCohort.by_experiment(experiment_name) do
      {:ok, cohorts} ->
        user_ids = Enum.map(cohorts, & &1.user_id)

        LSPMeasurementEvent
        |> Ash.Query.filter(user_id in ^user_ids)
        |> Ash.Query.filter(occurred_at >= ^from)
        |> Ash.Query.filter(experiment_name == ^experiment_name)
        |> Ash.read()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_balance_ratio(treatment_users, control_users) do
    treatment_count = length(treatment_users)
    control_count = length(control_users)

    if treatment_count > 0 and control_count > 0 do
      min(treatment_count, control_count) / max(treatment_count, control_count)
    else
      0.0
    end
  end

  defp assess_data_quality(cohorts, measurements) do
    total_users = length(cohorts)
    users_with_data = measurements |> Enum.map(& &1.user_id) |> Enum.uniq() |> length()

    data_coverage = if total_users > 0, do: users_with_data / total_users, else: 0.0

    quality_score =
      cond do
        data_coverage >= 0.8 -> "high"
        data_coverage >= 0.6 -> "medium"
        data_coverage >= 0.3 -> "low"
        true -> "insufficient"
      end

    %{
      data_coverage: Float.round(data_coverage, 2),
      quality_score: quality_score,
      users_with_data: users_with_data,
      total_users: total_users
    }
  end

  defp perform_cohort_analysis(cohorts, measurements, segment_by) do
    # Group users by cohort type and segment
    treatment_cohorts = Enum.filter(cohorts, &(&1.cohort_type == :treatment))
    control_cohorts = Enum.filter(cohorts, &(&1.cohort_type == :control))

    # Analyze each segment
    treatment_analysis = analyze_cohort_segment(treatment_cohorts, measurements, segment_by)
    control_analysis = analyze_cohort_segment(control_cohorts, measurements, segment_by)

    %{
      segment_by: segment_by,
      treatment_segments: treatment_analysis,
      control_segments: control_analysis,
      analyzed_at: DateTime.utc_now()
    }
  end

  defp analyze_cohort_segment(cohorts, measurements, segment_by) do
    # Simple cohort segmentation (could be enhanced based on segment_by)
    user_ids = Enum.map(cohorts, & &1.user_id)
    user_measurements = Enum.filter(measurements, fn m -> m.user_id in user_ids end)

    # Group by assignment date for now (could segment by other factors)
    segments =
      cohorts
      |> Enum.group_by(fn cohort ->
        Date.to_string(DateTime.to_date(cohort.assigned_at))
      end)
      |> Enum.map(fn {date, segment_cohorts} ->
        segment_user_ids = Enum.map(segment_cohorts, & &1.user_id)

        segment_measurements =
          Enum.filter(user_measurements, fn m -> m.user_id in segment_user_ids end)

        # Calculate segment metrics
        total_baseline = Enum.reduce(segment_measurements, 0, fn x, acc -> acc + x.baseline_tokens end)
        total_enhanced = Enum.reduce(segment_measurements, 0, fn x, acc -> acc + x.enhanced_tokens end)

        avg_reduction =
          if total_baseline > 0,
            do: (total_baseline - total_enhanced) / total_baseline * 100,
            else: 0.0

        %{
          segment: date,
          users: length(segment_cohorts),
          measurements: length(segment_measurements),
          avg_token_reduction: Float.round(avg_reduction, 2)
        }
      end)

    segments
  end

  defp store_experiment_config(config) do
    # Store experiment configuration in ETS or database
    # For now, using ETS for simplicity
    :ets.insert(:experiment_configs, {config.name, config})
  end

  defp archive_experiment(experiment_name, reason, results) do
    # Archive experiment data
    archived_data = %{
      experiment_name: experiment_name,
      ended_reason: reason,
      final_results: results,
      archived_at: DateTime.utc_now()
    }

    :ets.insert(:archived_experiments, {experiment_name, archived_data})
    Logger.info("Archived experiment #{experiment_name}")
  end

  # Initialize ETS tables on application start
  def init_storage do
    case :ets.info(:experiment_configs) do
      :undefined ->
        :ets.new(:experiment_configs, [:set, :public, :named_table])
        :ets.new(:archived_experiments, [:set, :public, :named_table])
        Logger.info("Initialized A/B testing storage")
        :ok

      _ ->
        :ok
    end
  end
end
