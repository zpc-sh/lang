defmodule Lang.Testing.PerformanceAnalyzer do
  @moduledoc """
  Performance Analyzer for processing and analyzing LSP comparison test results.

  This module provides comprehensive analysis of AI agent performance data,
  including statistical analysis, trend identification, and performance
  improvement measurement when using LSP support.
  """

  require Logger

  @doc """
  Analyze comparison results and generate comprehensive performance report.
  """
  def analyze_comparison_results(test_results) when is_map(test_results) do
    lsp_results = filter_by_lsp_status(test_results, true)
    no_lsp_results = filter_by_lsp_status(test_results, false)

    %{
      overall_analysis: analyze_overall_performance(lsp_results, no_lsp_results),
      statistical_analysis: perform_statistical_analysis(lsp_results, no_lsp_results),
      scenario_analysis: analyze_by_scenario(test_results),
      agent_analysis: analyze_by_agent_variant(test_results),
      performance_improvements: calculate_performance_improvements(lsp_results, no_lsp_results),
      lsp_feature_effectiveness: analyze_lsp_feature_usage(lsp_results),
      recommendations: generate_recommendations(lsp_results, no_lsp_results),
      data_quality: assess_data_quality(test_results)
    }
  end

  @doc """
  Perform preliminary analysis on partial results during testing.
  """
  def preliminary_analysis(partial_results) when is_map(partial_results) do
    if map_size(partial_results) < 4 do
      %{
        status: :insufficient_data,
        sample_size: map_size(partial_results),
        preliminary_trends: "Need more data for meaningful analysis"
      }
    else
      lsp_count = count_lsp_enabled_tests(partial_results)
      no_lsp_count = map_size(partial_results) - lsp_count

      %{
        status: :preliminary,
        sample_size: map_size(partial_results),
        lsp_tests: lsp_count,
        no_lsp_tests: no_lsp_count,
        early_trends: identify_early_trends(partial_results),
        completion_rate: calculate_overall_completion_rate(partial_results)
      }
    end
  end

  @doc """
  Generate detailed performance report with visualizable data.
  """
  def generate_performance_report(analysis_results) do
    %{
      executive_summary: create_executive_summary(analysis_results),
      key_metrics: extract_key_metrics(analysis_results),
      performance_charts: prepare_chart_data(analysis_results),
      detailed_findings: compile_detailed_findings(analysis_results),
      methodology: describe_methodology(),
      conclusions: draw_conclusions(analysis_results),
      next_steps: suggest_next_steps(analysis_results)
    }
  end

  # Private Analysis Functions

  defp filter_by_lsp_status(results, lsp_enabled) do
    results
    |> Enum.filter(fn {_test_id, result} ->
      Map.get(result, :lsp_enabled) == lsp_enabled && Map.get(result, :status) == :completed
    end)
    |> Map.new()
  end

  defp analyze_overall_performance(lsp_results, no_lsp_results) do
    lsp_metrics = calculate_aggregate_metrics(lsp_results)
    no_lsp_metrics = calculate_aggregate_metrics(no_lsp_results)

    %{
      lsp_performance: lsp_metrics,
      no_lsp_performance: no_lsp_metrics,
      improvement_summary: %{
        completion_time_change:
          percentage_change(no_lsp_metrics.avg_completion_time, lsp_metrics.avg_completion_time),
        quality_score_change:
          percentage_change(no_lsp_metrics.avg_quality_score, lsp_metrics.avg_quality_score),
        error_rate_change: percentage_change(lsp_metrics.error_rate, no_lsp_metrics.error_rate),
        context_utilization_improvement: lsp_metrics.avg_context_utilization
      },
      sample_sizes: %{
        lsp_tests: map_size(lsp_results),
        no_lsp_tests: map_size(no_lsp_results)
      }
    }
  end

  defp calculate_aggregate_metrics(results) when map_size(results) == 0 do
    %{
      avg_completion_time: 0,
      avg_quality_score: 0.0,
      avg_context_utilization: 0.0,
      error_rate: 1.0,
      task_completion_rate: 0.0
    }
  end

  defp calculate_aggregate_metrics(results) do
    values = Map.values(results)

    completion_times = Enum.map(values, &Map.get(&1, :completion_time_ms, 0))
    quality_scores = Enum.map(values, &Map.get(&1, :quality_score, 0.0))
    context_utilization = Enum.map(values, &Map.get(&1, :context_utilization, 0.0))
    error_counts = Enum.map(values, &Map.get(&1, :error_count, 0))
    completion_rates = Enum.map(values, &Map.get(&1, :task_completion_rate, 0.0))

    %{
      avg_completion_time: safe_average(completion_times),
      avg_quality_score: safe_average(quality_scores),
      avg_context_utilization: safe_average(context_utilization),
      error_rate: safe_average(error_counts),
      task_completion_rate: safe_average(completion_rates),
      median_completion_time: calculate_median(completion_times),
      std_dev_completion_time: calculate_std_deviation(completion_times),
      min_completion_time: Enum.min(completion_times, fn -> 0 end),
      max_completion_time: Enum.max(completion_times, fn -> 0 end)
    }
  end

  defp perform_statistical_analysis(lsp_results, no_lsp_results) do
    lsp_completion_times = extract_completion_times(lsp_results)
    no_lsp_completion_times = extract_completion_times(no_lsp_results)

    lsp_quality_scores = extract_quality_scores(lsp_results)
    no_lsp_quality_scores = extract_quality_scores(no_lsp_results)

    %{
      completion_time_analysis: %{
        t_test_result: perform_t_test(lsp_completion_times, no_lsp_completion_times),
        effect_size: calculate_cohens_d(lsp_completion_times, no_lsp_completion_times),
        confidence_interval:
          calculate_confidence_interval(lsp_completion_times, no_lsp_completion_times)
      },
      quality_score_analysis: %{
        t_test_result: perform_t_test(lsp_quality_scores, no_lsp_quality_scores),
        effect_size: calculate_cohens_d(lsp_quality_scores, no_lsp_quality_scores),
        confidence_interval:
          calculate_confidence_interval(lsp_quality_scores, no_lsp_quality_scores)
      },
      sample_adequacy: assess_sample_adequacy(lsp_results, no_lsp_results),
      power_analysis: calculate_statistical_power(lsp_results, no_lsp_results)
    }
  end

  defp analyze_by_scenario(test_results) do
    test_results
    |> group_by_scenario()
    |> Enum.map(fn {scenario_id, scenario_results} ->
      lsp_results = filter_by_lsp_status(scenario_results, true)
      no_lsp_results = filter_by_lsp_status(scenario_results, false)

      {scenario_id,
       %{
         total_tests: map_size(scenario_results),
         lsp_performance: calculate_aggregate_metrics(lsp_results),
         no_lsp_performance: calculate_aggregate_metrics(no_lsp_results),
         lsp_benefit_score: calculate_lsp_benefit_score(lsp_results, no_lsp_results),
         complexity_correlation:
           analyze_complexity_correlation(scenario_id, lsp_results, no_lsp_results)
       }}
    end)
    |> Map.new()
  end

  defp analyze_by_agent_variant(test_results) do
    test_results
    |> group_by_agent_variant()
    |> Enum.map(fn {variant_name, variant_results} ->
      lsp_results = filter_by_lsp_status(variant_results, true)
      no_lsp_results = filter_by_lsp_status(variant_results, false)

      {variant_name,
       %{
         total_tests: map_size(variant_results),
         lsp_performance: calculate_aggregate_metrics(lsp_results),
         no_lsp_performance: calculate_aggregate_metrics(no_lsp_results),
         lsp_responsiveness: calculate_lsp_responsiveness(lsp_results, no_lsp_results),
         personality_lsp_fit:
           assess_personality_lsp_compatibility(variant_name, lsp_results, no_lsp_results)
       }}
    end)
    |> Map.new()
  end

  defp calculate_performance_improvements(lsp_results, no_lsp_results) do
    if map_size(lsp_results) == 0 || map_size(no_lsp_results) == 0 do
      %{error: "Insufficient data for improvement calculation"}
    else
      lsp_metrics = calculate_aggregate_metrics(lsp_results)
      no_lsp_metrics = calculate_aggregate_metrics(no_lsp_results)

      %{
        time_efficiency: %{
          improvement_percentage:
            percentage_change(no_lsp_metrics.avg_completion_time, lsp_metrics.avg_completion_time),
          absolute_time_saved_ms:
            no_lsp_metrics.avg_completion_time - lsp_metrics.avg_completion_time,
          consistency_improvement:
            no_lsp_metrics.std_dev_completion_time - lsp_metrics.std_dev_completion_time
        },
        quality_improvements: %{
          quality_score_lift: lsp_metrics.avg_quality_score - no_lsp_metrics.avg_quality_score,
          error_reduction: no_lsp_metrics.error_rate - lsp_metrics.error_rate,
          completion_rate_improvement:
            lsp_metrics.task_completion_rate - no_lsp_metrics.task_completion_rate
        },
        context_benefits: %{
          context_utilization_score: lsp_metrics.avg_context_utilization,
          estimated_context_value: estimate_context_value(lsp_results, no_lsp_results)
        }
      }
    end
  end

  defp analyze_lsp_feature_usage(lsp_results) do
    feature_usage = extract_feature_usage_data(lsp_results)

    %{
      most_valuable_features: identify_most_valuable_features(feature_usage, lsp_results),
      feature_correlation: analyze_feature_performance_correlation(feature_usage, lsp_results),
      underutilized_features: identify_underutilized_features(feature_usage),
      feature_effectiveness_ranking: rank_features_by_effectiveness(feature_usage, lsp_results)
    }
  end

  defp generate_recommendations(lsp_results, no_lsp_results) do
    analysis = analyze_overall_performance(lsp_results, no_lsp_results)

    recommendations = []

    recommendations =
      if analysis.improvement_summary.completion_time_change > 20 do
        [
          "LSP integration shows significant time savings - recommend full deployment"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.improvement_summary.quality_score_change > 15 do
        [
          "Quality improvements justify LSP overhead - focus on quality-critical scenarios"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if analysis.sample_sizes.lsp_tests < 10 || analysis.sample_sizes.no_lsp_tests < 10 do
        ["Increase sample size for more reliable statistical conclusions" | recommendations]
      else
        recommendations
      end

    %{
      strategic_recommendations: recommendations,
      tactical_improvements: suggest_tactical_improvements(lsp_results, no_lsp_results),
      implementation_priorities: prioritize_implementation_areas(lsp_results, no_lsp_results),
      risk_considerations: identify_risk_considerations(lsp_results, no_lsp_results)
    }
  end

  # Helper Functions

  defp group_by_scenario(test_results) do
    test_results
    |> Enum.group_by(fn {_test_id, result} ->
      Map.get(result, :scenario_id, "unknown")
    end)
    |> Enum.map(fn {scenario_id, results} ->
      {scenario_id, Map.new(results)}
    end)
    |> Map.new()
  end

  defp group_by_agent_variant(test_results) do
    test_results
    |> Enum.group_by(fn {_test_id, result} ->
      Map.get(result, :agent_variant_name, "unknown")
    end)
    |> Enum.map(fn {variant_name, results} ->
      {variant_name, Map.new(results)}
    end)
    |> Map.new()
  end

  defp extract_completion_times(results) do
    results
    |> Map.values()
    |> Enum.map(&Map.get(&1, :completion_time_ms, 0))
    |> Enum.filter(&(&1 > 0))
  end

  defp extract_quality_scores(results) do
    results
    |> Map.values()
    |> Enum.map(&Map.get(&1, :quality_score, 0.0))
  end

  defp safe_average([]), do: 0

  defp safe_average(values) do
    Enum.sum(values) / length(values)
  end

  defp calculate_median([]), do: 0

  defp calculate_median(values) do
    sorted = Enum.sort(values)
    length = length(sorted)

    if rem(length, 2) == 0 do
      mid1 = Enum.at(sorted, div(length, 2) - 1)
      mid2 = Enum.at(sorted, div(length, 2))
      (mid1 + mid2) / 2
    else
      Enum.at(sorted, div(length, 2))
    end
  end

  defp calculate_std_deviation([]), do: 0

  defp calculate_std_deviation(values) do
    mean = safe_average(values)
    variance = values |> Enum.map(&((&1 - mean) * (&1 - mean))) |> safe_average()
    :math.sqrt(variance)
  end

  defp percentage_change(old_value, new_value) when old_value > 0 do
    (new_value - old_value) / old_value * 100
  end

  defp percentage_change(_, _), do: 0

  defp perform_t_test(sample1, sample2) do
    # Simplified t-test implementation
    # In production, would use proper statistical library
    if length(sample1) < 2 || length(sample2) < 2 do
      %{p_value: 1.0, statistically_significant: false, note: "Insufficient sample size"}
    else
      mean1 = safe_average(sample1)
      mean2 = safe_average(sample2)
      std1 = calculate_std_deviation(sample1)
      std2 = calculate_std_deviation(sample2)

      # Simplified calculation
      pooled_std = :math.sqrt((std1 * std1 + std2 * std2) / 2)
      t_stat = abs(mean1 - mean2) / (pooled_std * :math.sqrt(2 / length(sample1)))

      # Very rough p-value approximation
      p_value = if t_stat > 2.0, do: 0.05, else: 0.2

      %{
        t_statistic: t_stat,
        p_value: p_value,
        statistically_significant: p_value < 0.05,
        note: "Simplified t-test - use proper statistical software for production"
      }
    end
  end

  defp calculate_cohens_d(sample1, sample2) do
    if length(sample1) < 2 || length(sample2) < 2 do
      0.0
    else
      mean1 = safe_average(sample1)
      mean2 = safe_average(sample2)
      std1 = calculate_std_deviation(sample1)
      std2 = calculate_std_deviation(sample2)

      pooled_std = :math.sqrt((std1 * std1 + std2 * std2) / 2)
      if pooled_std > 0, do: abs(mean1 - mean2) / pooled_std, else: 0.0
    end
  end

  defp calculate_confidence_interval(sample1, sample2) do
    # Simplified 95% confidence interval
    mean_diff = safe_average(sample1) - safe_average(sample2)
    # Rough standard error
    std_error = (calculate_std_deviation(sample1) + calculate_std_deviation(sample2)) / 2

    %{
      mean_difference: mean_diff,
      confidence_95_lower: mean_diff - 1.96 * std_error,
      confidence_95_upper: mean_diff + 1.96 * std_error,
      note: "Simplified confidence interval calculation"
    }
  end

  defp assess_sample_adequacy(lsp_results, no_lsp_results) do
    lsp_size = map_size(lsp_results)
    no_lsp_size = map_size(no_lsp_results)

    %{
      lsp_sample_size: lsp_size,
      no_lsp_sample_size: no_lsp_size,
      minimum_recommended: 30,
      adequate_for_t_test: lsp_size >= 10 && no_lsp_size >= 10,
      adequate_for_robust_analysis: lsp_size >= 30 && no_lsp_size >= 30,
      power_analysis_feasible: lsp_size >= 20 && no_lsp_size >= 20
    }
  end

  defp calculate_statistical_power(_lsp_results, _no_lsp_results) do
    # Simplified power analysis
    %{
      estimated_power: 0.8,
      note: "Power analysis would require effect size estimation and proper statistical tools"
    }
  end

  defp calculate_lsp_benefit_score(lsp_results, no_lsp_results) do
    if map_size(lsp_results) == 0 || map_size(no_lsp_results) == 0 do
      0.0
    else
      lsp_metrics = calculate_aggregate_metrics(lsp_results)
      no_lsp_metrics = calculate_aggregate_metrics(no_lsp_results)

      # Weighted benefit score
      time_benefit =
        safe_benefit_score(no_lsp_metrics.avg_completion_time, lsp_metrics.avg_completion_time)

      quality_benefit =
        safe_benefit_score(no_lsp_metrics.avg_quality_score, lsp_metrics.avg_quality_score)

      error_benefit = safe_benefit_score(lsp_metrics.error_rate, no_lsp_metrics.error_rate)

      (time_benefit * 0.4 + quality_benefit * 0.4 + error_benefit * 0.2) * 100
    end
  end

  defp safe_benefit_score(baseline, improved) when baseline > 0 do
    max(0, min(1, (baseline - improved) / baseline))
  end

  defp safe_benefit_score(_, _), do: 0

  defp analyze_complexity_correlation(scenario_id, lsp_results, no_lsp_results) do
    # Map scenario complexity (would be better to have this data-driven)
    complexity_map = %{
      "legacy_modernization" => 5,
      "dependency_hell" => 5,
      "performance_hunt" => 4,
      "security_audit" => 5,
      "test_coverage_gaps" => 4,
      "api_evolution" => 4,
      "error_propagation" => 5,
      "style_harmonization" => 3,
      "domain_documentation" => 4,
      "collaborative_refactoring" => 5
    }

    complexity = Map.get(complexity_map, to_string(scenario_id), 3)
    benefit_score = calculate_lsp_benefit_score(lsp_results, no_lsp_results)

    %{
      scenario_complexity: complexity,
      lsp_benefit_score: benefit_score,
      complexity_benefit_ratio: if(complexity > 0, do: benefit_score / complexity, else: 0),
      correlation_strength: classify_correlation_strength(complexity, benefit_score)
    }
  end

  defp classify_correlation_strength(complexity, benefit) do
    ratio = if complexity > 0, do: benefit / complexity, else: 0

    cond do
      ratio > 15 -> :strong_positive
      ratio > 10 -> :moderate_positive
      ratio > 5 -> :weak_positive
      true -> :minimal
    end
  end

  defp calculate_lsp_responsiveness(lsp_results, no_lsp_results) do
    if map_size(lsp_results) == 0 do
      %{responsiveness_score: 0.0, note: "No LSP results to analyze"}
    else
      lsp_times = extract_completion_times(lsp_results)
      no_lsp_times = extract_completion_times(no_lsp_results)

      lsp_avg = safe_average(lsp_times)
      no_lsp_avg = safe_average(no_lsp_times)

      # Responsiveness considers both speed and consistency
      consistency_score = 1 - calculate_std_deviation(lsp_times) / max(lsp_avg, 1)
      speed_score = if no_lsp_avg > 0, do: max(0, 1 - lsp_avg / no_lsp_avg), else: 0

      %{
        responsiveness_score: (consistency_score * 0.6 + speed_score * 0.4) * 100,
        consistency_component: consistency_score * 100,
        speed_component: speed_score * 100
      }
    end
  end

  defp assess_personality_lsp_compatibility(variant_name, lsp_results, no_lsp_results) do
    benefit_score = calculate_lsp_benefit_score(lsp_results, no_lsp_results)

    # Different agent personalities may benefit differently from LSP
    personality_expectations = %{
      # High benefit expected
      "conservative_refactorer" => 75,
      # Very high benefit expected
      "security_first_analyst" => 80,
      # High benefit expected
      "documentation_zealot" => 70,
      # Good benefit expected
      "test_driven_purist" => 65,
      # High benefit expected
      "academic_perfectionist" => 75,
      # High benefit expected
      "enterprise_maintainer" => 70,
      # Moderate benefit expected
      "pragmatic_balancer" => 60,
      # Lower benefit expected
      "aggressive_optimizer" => 40,
      # Low benefit expected (might be slowed by context)
      "speed_demon" => 30,
      # Low benefit expected
      "startup_hacker" => 35
    }

    expected_benefit = Map.get(personality_expectations, variant_name, 50)
    actual_benefit = benefit_score

    compatibility_score = 100 - abs(expected_benefit - actual_benefit)

    %{
      expected_benefit: expected_benefit,
      actual_benefit: actual_benefit,
      compatibility_score: compatibility_score,
      alignment: classify_alignment(compatibility_score)
    }
  end

  defp classify_alignment(score) when score >= 80, do: :excellent
  defp classify_alignment(score) when score >= 60, do: :good
  defp classify_alignment(score) when score >= 40, do: :moderate
  defp classify_alignment(_), do: :poor

  defp count_lsp_enabled_tests(results) do
    results
    |> Enum.count(fn {_id, result} -> Map.get(result, :lsp_enabled) == true end)
  end

  defp calculate_overall_completion_rate(results) do
    completed =
      Enum.count(results, fn {_id, result} -> Map.get(result, :status) == :completed end)

    total = map_size(results)
    if total > 0, do: completed / total, else: 0.0
  end

  defp identify_early_trends(results) do
    lsp_results = filter_by_lsp_status(results, true)
    no_lsp_results = filter_by_lsp_status(results, false)

    if map_size(lsp_results) > 0 && map_size(no_lsp_results) > 0 do
      lsp_avg_time =
        lsp_results
        |> Map.values()
        |> Enum.map(&Map.get(&1, :completion_time_ms, 0))
        |> safe_average()

      no_lsp_avg_time =
        no_lsp_results
        |> Map.values()
        |> Enum.map(&Map.get(&1, :completion_time_ms, 0))
        |> safe_average()

      cond do
        lsp_avg_time < no_lsp_avg_time * 0.8 ->
          "LSP showing significant speed improvements"

        lsp_avg_time > no_lsp_avg_time * 1.2 ->
          "LSP showing slower performance (context overhead?)"

        true ->
          "Performance appears comparable between LSP and non-LSP"
      end
    else
      "Need more balanced data (both LSP and non-LSP results)"
    end
  end

  # Report Generation Functions

  defp create_executive_summary(analysis) do
    overall = analysis.overall_analysis
    improvements = analysis.performance_improvements

    summary = []

    summary =
      if Map.has_key?(improvements, :time_efficiency) do
        time_improvement = improvements.time_efficiency.improvement_percentage

        if time_improvement > 10 do
          [
            "LSP integration resulted in #{round(time_improvement)}% improvement in completion time"
            | summary
          ]
        else
          summary
        end
      else
        summary
      end

    summary =
      if Map.has_key?(improvements, :quality_improvements) do
        quality_lift = improvements.quality_improvements.quality_score_lift

        if quality_lift > 0.1 do
          [
            "Quality scores improved by #{Float.round(quality_lift * 100, 1)}% with LSP support"
            | summary
          ]
        else
          summary
        end
      else
        summary
      end

    %{
      key_findings: summary,
      recommendation:
        if(length(summary) > 0,
          do: "LSP integration recommended",
          else: "Further evaluation needed"
        ),
      confidence_level: assess_confidence_level(analysis)
    }
  end

  defp extract_key_metrics(analysis) do
    overall = analysis.overall_analysis

    %{
      total_tests_analyzed: overall.sample_sizes.lsp_tests + overall.sample_sizes.no_lsp_tests,
      average_lsp_completion_time: overall.lsp_performance.avg_completion_time,
      average_no_lsp_completion_time: overall.no_lsp_performance.avg_completion_time,
      quality_improvement: overall.improvement_summary.quality_score_change,
      time_improvement: overall.improvement_summary.completion_time_change,
      statistical_significance:
        get_statistical_significance_summary(analysis.statistical_analysis)
    }
  end

  defp get_statistical_significance_summary(stats) do
    completion_significant =
      get_in(stats, [:completion_time_analysis, :t_test_result, :statistically_significant])

    quality_significant =
      get_in(stats, [:quality_score_analysis, :t_test_result, :statistically_significant])

    cond do
      completion_significant && quality_significant ->
        "Both time and quality improvements are statistically significant"

      completion_significant ->
        "Time improvements are statistically significant"

      quality_significant ->
        "Quality improvements are statistically significant"

      true ->
        "Results not statistically significant with current sample size"
    end
  end

  defp assess_confidence_level(analysis) do
    sample_adequacy = analysis.statistical_analysis.sample_adequacy

    cond do
      sample_adequacy.adequate_for_robust_analysis -> "High"
      sample_adequacy.adequate_for_t_test -> "Medium"
      true -> "Low"
    end
  end

  # Placeholder functions for comprehensive analysis

  defp prepare_chart_data(_analysis), do: %{note: "Chart data preparation not implemented"}

  defp compile_detailed_findings(_analysis),
    do: %{note: "Detailed findings compilation not implemented"}

  defp describe_methodology, do: %{note: "Methodology description not implemented"}
  defp draw_conclusions(_analysis), do: %{note: "Conclusion drawing not implemented"}
  defp suggest_next_steps(_analysis), do: %{note: "Next steps suggestion not implemented"}

  defp extract_feature_usage_data(_lsp_results), do: %{}
  defp identify_most_valuable_features(_feature_usage, _lsp_results), do: []
  defp analyze_feature_performance_correlation(_feature_usage, _lsp_results), do: %{}
  defp identify_underutilized_features(_feature_usage), do: []
  defp rank_features_by_effectiveness(_feature_usage, _lsp_results), do: []

  defp suggest_tactical_improvements(_lsp_results, _no_lsp_results), do: []
  defp prioritize_implementation_areas(_lsp_results, _no_lsp_results), do: []
  defp identify_risk_considerations(_lsp_results, _no_lsp_results), do: []

  defp estimate_context_value(_lsp_results, _no_lsp_results), do: 0.0

  defp assess_data_quality(test_results) do
    total_tests = map_size(test_results)

    completed_tests =
      Enum.count(test_results, fn {_id, result} -> Map.get(result, :status) == :completed end)

    failed_tests = total_tests - completed_tests

    %{
      total_tests: total_tests,
      completed_tests: completed_tests,
      failed_tests: failed_tests,
      completion_rate: if(total_tests > 0, do: completed_tests / total_tests, else: 0),
      data_quality_score: if(total_tests > 0, do: completed_tests / total_tests * 100, else: 0),
      assessment:
        if(failed_tests / max(total_tests, 1) > 0.2,
          do: "High failure rate may impact reliability",
          else: "Data quality acceptable"
        )
    }
  end
end
