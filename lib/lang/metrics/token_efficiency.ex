defmodule Lang.Metrics.TokenEfficiency do
  @moduledoc """
  Token Efficiency Tracker - Measures token reduction and efficiency improvements
  from LSP enhancements.

  This module provides comprehensive token efficiency tracking, including:
  - Before/after token usage comparison
  - Provider-specific efficiency metrics
  - Real-time efficiency monitoring
  - Historical trend analysis
  """

  alias Lang.Analytics
  alias Lang.Analytics.{LSPMeasurementEvent, TokenEfficiencyReport}

  require Logger

  @doc """
  Calculates token efficiency for a specific operation.

  ## Examples

      TokenEfficiency.calculate_efficiency(
        baseline_tokens: 150,
        enhanced_tokens: 95,
        provider: "xai",
        method: :completion
      )

      # Returns: {:ok, %{reduction_percent: 36.7, efficiency_ratio: 1.58, ...}}
  """
  def calculate_efficiency(opts) do
    baseline_tokens = Keyword.fetch!(opts, :baseline_tokens)
    enhanced_tokens = Keyword.fetch!(opts, :enhanced_tokens)
    provider = Keyword.get(opts, :provider, "unknown")
    method = Keyword.get(opts, :method, :unknown)

    if baseline_tokens <= 0 do
      {:error, :invalid_baseline_tokens}
    else
      tokens_saved = max(0, baseline_tokens - enhanced_tokens)
      reduction_percent = tokens_saved / baseline_tokens * 100
      efficiency_ratio = baseline_tokens / max(1, enhanced_tokens)

      # Cost estimation (approximate across providers)
      cost_per_token = get_provider_cost_per_token(provider)
      cost_savings = tokens_saved * cost_per_token

      efficiency_metrics = %{
        baseline_tokens: baseline_tokens,
        enhanced_tokens: enhanced_tokens,
        tokens_saved: tokens_saved,
        reduction_percent: Float.round(reduction_percent, 2),
        efficiency_ratio: Float.round(efficiency_ratio, 3),
        cost_savings_usd: Float.round(cost_savings, 6),
        provider: provider,
        method: method,
        efficiency_grade: calculate_efficiency_grade(reduction_percent)
      }

      {:ok, efficiency_metrics}
    end
  end

  @doc """
  Tracks token efficiency for a user over time.
  """
  def track_user_efficiency(user_id, opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -7, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    import Ash.Query

    case LSPMeasurementEvent
         |> Ash.Query.filter(user_id == ^user_id)
         |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
         |> Ash.Query.filter(not is_nil(baseline_tokens) and not is_nil(enhanced_tokens))
         |> Ash.Query.sort(occurred_at: :desc)
         |> Ash.read() do
      {:ok, events} ->
        efficiency_trends = calculate_user_efficiency_trends(events)
        {:ok, efficiency_trends}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets provider-specific efficiency metrics.
  """
  def get_provider_efficiency(provider, opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    import Ash.Query

    case LSPMeasurementEvent
         |> Ash.Query.filter(provider == ^provider)
         |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
         |> Ash.Query.filter(not is_nil(baseline_tokens) and not is_nil(enhanced_tokens))
         |> Ash.read() do
      {:ok, events} ->
        provider_metrics = calculate_provider_metrics(events, provider)
        {:ok, provider_metrics}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Compares efficiency across all providers.
  """
  def compare_provider_efficiency(opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    providers = ["xai", "openai", "anthropic"]

    comparisons =
      Enum.map(providers, fn provider ->
        case get_provider_efficiency(provider, from: from, to: to) do
          {:ok, metrics} ->
            {provider, metrics}

          {:error, _} ->
            {provider,
             %{
               avg_reduction_percent: 0.0,
               total_operations: 0,
               avg_efficiency_ratio: 0.0,
               total_cost_savings: 0.0
             }}
        end
      end)
      |> Enum.into(%{})

    # Find best performing provider
    best_provider =
      comparisons
      |> Enum.max_by(
        fn {_provider, metrics} ->
          Map.get(metrics, :avg_reduction_percent, 0.0)
        end,
        fn -> {"none", %{}} end
      )
      |> elem(0)

    {:ok,
     %{
       period: %{from: from, to: to},
       providers: comparisons,
       best_provider: best_provider,
       ranking: rank_providers_by_efficiency(comparisons)
     }}
  end

  @doc """
  Calculates real-time efficiency metrics for live monitoring.
  """
  def get_realtime_efficiency(opts \\ []) do
    # Get efficiency for the last hour
    from = DateTime.add(DateTime.utc_now(), -1, :hour)
    to = DateTime.utc_now()

    import Ash.Query

    case LSPMeasurementEvent
         |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
         |> Ash.Query.filter(not is_nil(baseline_tokens) and not is_nil(enhanced_tokens))
         |> Ash.read() do
      {:ok, events} ->
        realtime_metrics = calculate_realtime_metrics(events)
        {:ok, realtime_metrics}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a comprehensive efficiency report.
  """
  def generate_efficiency_report(period_type \\ :daily, opts \\ []) do
    {from, to} = get_period_bounds(period_type, opts)
    report_date = DateTime.to_date(to)

    organization_id = Keyword.get(opts, :organization_id)

    import Ash.Query

    query =
      LSPMeasurementEvent
      |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
      |> Ash.Query.filter(not is_nil(baseline_tokens) and not is_nil(enhanced_tokens))

    query =
      if organization_id do
        Ash.Query.filter(query, organization_id == ^organization_id)
      else
        query
      end

    case Ash.read(query) do
      {:ok, events} ->
        report_attrs = compile_efficiency_report(events, from, to, period_type, organization_id)

        # Store the report
        case TokenEfficiencyReport.create(report_attrs) do
          {:ok, report} ->
            Logger.info("Generated efficiency report for #{period_type}: #{report.id}")
            {:ok, report}

          {:error, reason} ->
            Logger.error("Failed to create efficiency report: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets efficiency trends over multiple periods.
  """
  def get_efficiency_trends(opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    organization_id = Keyword.get(opts, :organization_id)

    case TokenEfficiencyReport.by_date_range(
           DateTime.to_date(from),
           DateTime.to_date(to),
           organization_id
         ) do
      {:ok, reports} ->
        trends = calculate_efficiency_trends(reports)
        {:ok, trends}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculates token efficiency benchmarks for comparison.
  """
  def calculate_benchmarks(opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -90, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    import Ash.Query

    case LSPMeasurementEvent
         |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
         |> Ash.Query.filter(not is_nil(baseline_tokens) and not is_nil(enhanced_tokens))
         |> Ash.read() do
      {:ok, events} ->
        benchmarks = compile_benchmarks(events)
        {:ok, benchmarks}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp get_provider_cost_per_token(provider) do
    case provider do
      # Approximate cost per token
      "xai" -> 0.000015
      # GPT-4 pricing
      "openai" -> 0.00002
      # Claude pricing
      "anthropic" -> 0.000025
      # Default/average
      _ -> 0.00002
    end
  end

  defp calculate_efficiency_grade(reduction_percent) do
    cond do
      reduction_percent >= 30 -> "A+"
      reduction_percent >= 25 -> "A"
      reduction_percent >= 20 -> "B+"
      reduction_percent >= 15 -> "B"
      reduction_percent >= 10 -> "C+"
      reduction_percent >= 5 -> "C"
      reduction_percent >= 0 -> "D"
      true -> "F"
    end
  end

  defp calculate_user_efficiency_trends(events) do
    if length(events) == 0 do
      %{
        total_operations: 0,
        avg_reduction_percent: 0.0,
        total_tokens_saved: 0,
        efficiency_trend: "no_data",
        daily_breakdown: []
      }
    else
      {total_baseline, total_enhanced} = sum_tokens(events)
      total_saved = total_baseline - total_enhanced
      avg_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0.0

      # Group by day for trend analysis
      daily_breakdown =
        events
        |> Enum.group_by(fn e -> DateTime.to_date(e.occurred_at) end)
        |> Enum.map(fn {date, day_events} ->
          {day_baseline, day_enhanced} = sum_tokens(day_events)
          day_saved = day_baseline - day_enhanced
          day_reduction = if day_baseline > 0, do: day_saved / day_baseline * 100, else: 0.0

          %{
            date: date,
            operations: length(day_events),
            tokens_saved: day_saved,
            reduction_percent: Float.round(day_reduction, 2)
          }
        end)
        |> Enum.sort_by(& &1.date, Date)

      # Determine trend direction
      trend_direction = calculate_trend_direction(daily_breakdown)

      %{
        total_operations: length(events),
        avg_reduction_percent: Float.round(avg_reduction, 2),
        total_tokens_saved: total_saved,
        efficiency_trend: trend_direction,
        daily_breakdown: daily_breakdown,
        method_efficiency: calculate_method_efficiency(events),
        best_day: find_best_efficiency_day(daily_breakdown),
        improvement_opportunities: identify_improvement_opportunities(events)
      }
    end
  end

  defp calculate_provider_metrics(events, provider) do
    if length(events) == 0 do
      %{
        provider: provider,
        total_operations: 0,
        avg_reduction_percent: 0.0,
        avg_efficiency_ratio: 0.0,
        total_cost_savings: 0.0,
        method_breakdown: %{}
      }
    else
      {total_baseline, total_enhanced} = sum_tokens(events)
      total_saved = total_baseline - total_enhanced
      avg_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0.0

      avg_efficiency_ratio = if total_enhanced > 0, do: total_baseline / total_enhanced, else: 0.0

      cost_per_token = get_provider_cost_per_token(provider)
      total_cost_savings = total_saved * cost_per_token

      method_breakdown =
        events
        |> Enum.group_by(& &1.lsp_method)
        |> Enum.map(fn {method, method_events} ->
          {method_baseline, method_enhanced} = sum_tokens(method_events)
          method_saved = method_baseline - method_enhanced

          method_reduction =
            if method_baseline > 0, do: method_saved / method_baseline * 100, else: 0.0

          {method,
           %{
             operations: length(method_events),
             reduction_percent: Float.round(method_reduction, 2),
             tokens_saved: method_saved
           }}
        end)
        |> Enum.into(%{})

      %{
        provider: provider,
        total_operations: length(events),
        avg_reduction_percent: Float.round(avg_reduction, 2),
        avg_efficiency_ratio: Float.round(avg_efficiency_ratio, 3),
        total_cost_savings: Float.round(total_cost_savings, 6),
        method_breakdown: method_breakdown,
        efficiency_grade: calculate_efficiency_grade(avg_reduction)
      }
    end
  end

  defp calculate_realtime_metrics(events) do
    if length(events) == 0 do
      %{
        current_hour_operations: 0,
        current_reduction_percent: 0.0,
        tokens_saved_last_hour: 0,
        efficiency_status: "no_activity",
        recent_trend: "stable"
      }
    else
      {total_baseline, total_enhanced} = sum_tokens(events)
      total_saved = total_baseline - total_enhanced
      current_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0.0

      efficiency_status =
        cond do
          current_reduction >= 25 -> "excellent"
          current_reduction >= 15 -> "good"
          current_reduction >= 5 -> "moderate"
          current_reduction >= 0 -> "low"
          true -> "poor"
        end

      %{
        current_hour_operations: length(events),
        current_reduction_percent: Float.round(current_reduction, 2),
        tokens_saved_last_hour: total_saved,
        efficiency_status: efficiency_status,
        recent_trend: calculate_recent_trend(events),
        top_performing_methods: get_top_methods(events, 3)
      }
    end
  end

  defp get_period_bounds(:daily, opts) do
    date = Keyword.get(opts, :date, Date.utc_today())
    from = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    to = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    {from, to}
  end

  defp get_period_bounds(:weekly, opts) do
    date = Keyword.get(opts, :date, Date.utc_today())
    start_of_week = Date.beginning_of_week(date)
    end_of_week = Date.end_of_week(date)
    from = DateTime.new!(start_of_week, ~T[00:00:00], "Etc/UTC")
    to = DateTime.new!(end_of_week, ~T[23:59:59], "Etc/UTC")
    {from, to}
  end

  defp get_period_bounds(:monthly, opts) do
    date = Keyword.get(opts, :date, Date.utc_today())
    start_of_month = Date.beginning_of_month(date)
    end_of_month = Date.end_of_month(date)
    from = DateTime.new!(start_of_month, ~T[00:00:00], "Etc/UTC")
    to = DateTime.new!(end_of_month, ~T[23:59:59], "Etc/UTC")
    {from, to}
  end

  defp compile_efficiency_report(events, from, to, period_type, organization_id) do
    {total_baseline, total_enhanced} = sum_tokens(events)
    total_saved = total_baseline - total_enhanced
    avg_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0.0

    successful_ops = Enum.count(events, &(&1.feature_used == true))
    success_rate = if length(events) > 0, do: successful_ops / length(events) * 100, else: 0.0

    # Method efficiency breakdown
    method_efficiency =
      events
      |> Enum.group_by(& &1.lsp_method)
      |> Enum.map(fn {method, method_events} ->
        {method_baseline, method_enhanced} = sum_tokens(method_events)

        method_reduction =
          if method_baseline > 0,
            do: (method_baseline - method_enhanced) / method_baseline * 100,
            else: 0.0

        {to_string(method),
         %{
           operations: length(method_events),
           reduction_percent: Float.round(method_reduction, 2)
         }}
      end)
      |> Enum.into(%{})

    # Provider efficiency breakdown
    provider_efficiency =
      events
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {provider, provider_events} ->
        {provider_baseline, provider_enhanced} = sum_tokens(provider_events)

        provider_reduction =
          if provider_baseline > 0,
            do: (provider_baseline - provider_enhanced) / provider_baseline * 100,
            else: 0.0

        {provider || "unknown",
         %{
           operations: length(provider_events),
           reduction_percent: Float.round(provider_reduction, 2)
         }}
      end)
      |> Enum.into(%{})

    # User metrics
    unique_users = events |> Enum.map(& &1.user_id) |> Enum.uniq() |> length()

    # Quality metrics
    quality_events = Enum.filter(events, &(&1.quality_score != nil))

    avg_quality =
      if length(quality_events) > 0 do
        Enum.reduce(quality_events, 0.0, fn e, acc -> acc + Decimal.to_float(e.quality_score) end) /
          length(quality_events)
      else
        0.0
      end

    # Cost calculations
    # Average cost per token
    total_cost_savings = total_saved * 0.00002
    productivity_value = estimate_productivity_value(events)

    %{
      organization_id: organization_id,
      report_date: DateTime.to_date(to),
      report_period: period_type,
      period_start: from,
      period_end: to,
      total_baseline_tokens: total_baseline,
      total_enhanced_tokens: total_enhanced,
      total_tokens_saved: total_saved,
      avg_token_reduction_percent: Decimal.new("#{avg_reduction}"),
      total_lsp_operations: length(events),
      successful_operations: successful_ops,
      success_rate_percent: Decimal.new("#{success_rate}"),
      method_efficiency: method_efficiency,
      provider_efficiency: provider_efficiency,
      active_users: unique_users,
      avg_quality_score: if(avg_quality > 0, do: Decimal.new("#{avg_quality}"), else: nil),
      estimated_cost_savings_usd: Decimal.new("#{total_cost_savings}"),
      productivity_value_usd: Decimal.new("#{productivity_value}"),
      generated_at: DateTime.utc_now(),
      generated_by: "token_efficiency_tracker"
    }
  end

  defp calculate_efficiency_trends(reports) do
    if length(reports) == 0 do
      %{trend: "no_data", reports: []}
    else
      sorted_reports = Enum.sort_by(reports, & &1.report_date, Date)

      trend_direction =
        if length(sorted_reports) >= 2 do
          # Last 5 reports
          recent = Enum.take(sorted_reports, -5)
          first_avg = Decimal.to_float(hd(recent).avg_token_reduction_percent || Decimal.new("0"))

          last_avg =
            Decimal.to_float(List.last(recent).avg_token_reduction_percent || Decimal.new("0"))

          cond do
            last_avg > first_avg + 2 -> "improving"
            last_avg < first_avg - 2 -> "declining"
            true -> "stable"
          end
        else
          "insufficient_data"
        end

      trend_data =
        Enum.map(sorted_reports, fn report ->
          %{
            date: report.report_date,
            reduction_percent:
              Decimal.to_float(report.avg_token_reduction_percent || Decimal.new("0")),
            tokens_saved: report.total_tokens_saved,
            operations: report.total_lsp_operations
          }
        end)

      %{
        trend: trend_direction,
        trend_data: trend_data,
        summary: %{
          total_reports: length(sorted_reports),
          avg_reduction: calculate_average_reduction(sorted_reports),
          best_period: find_best_period(sorted_reports),
          worst_period: find_worst_period(sorted_reports)
        }
      }
    end
  end

  defp compile_benchmarks(events) do
    if length(events) == 0 do
      %{benchmarks: %{}, sample_size: 0}
    else
      # Calculate percentile benchmarks
      reductions =
        events
        |> Enum.filter(fn e -> e.baseline_tokens > 0 and e.enhanced_tokens >= 0 end)
        |> Enum.map(fn e -> (e.baseline_tokens - e.enhanced_tokens) / e.baseline_tokens * 100 end)
        |> Enum.sort()

      benchmarks =
        if length(reductions) > 0 do
          %{
            p10: percentile(reductions, 10),
            p25: percentile(reductions, 25),
            # Median
            p50: percentile(reductions, 50),
            p75: percentile(reductions, 75),
            p90: percentile(reductions, 90),
            p95: percentile(reductions, 95),
            p99: percentile(reductions, 99)
          }
        else
          %{}
        end

      # Method-specific benchmarks
      method_benchmarks =
        events
        |> Enum.group_by(& &1.lsp_method)
        |> Enum.map(fn {method, method_events} ->
          method_reductions =
            method_events
            |> Enum.filter(fn e -> e.baseline_tokens > 0 and e.enhanced_tokens >= 0 end)
            |> Enum.map(fn e ->
              (e.baseline_tokens - e.enhanced_tokens) / e.baseline_tokens * 100
            end)

          method_median =
            if length(method_reductions) > 0 do
              percentile(method_reductions, 50)
            else
              0.0
            end

          {method,
           %{
             median_reduction: Float.round(method_median, 2),
             sample_size: length(method_reductions)
           }}
        end)
        |> Enum.into(%{})

      %{
        overall_benchmarks: benchmarks,
        method_benchmarks: method_benchmarks,
        sample_size: length(reductions),
        generated_at: DateTime.utc_now()
      }
    end
  end

  defp rank_providers_by_efficiency(comparisons) do
    comparisons
    |> Enum.sort_by(
      fn {_provider, metrics} ->
        Map.get(metrics, :avg_reduction_percent, 0.0)
      end,
      :desc
    )
    |> Enum.with_index(1)
    |> Enum.map(fn {{provider, metrics}, rank} ->
      %{
        rank: rank,
        provider: provider,
        reduction_percent: Map.get(metrics, :avg_reduction_percent, 0.0),
        operations: Map.get(metrics, :total_operations, 0)
      }
    end)
  end

  defp calculate_trend_direction(daily_breakdown) do
    if length(daily_breakdown) < 3 do
      "insufficient_data"
    else
      recent_days = Enum.take(daily_breakdown, -3)
      reductions = Enum.map(recent_days, & &1.reduction_percent)

      # Simple trend analysis
      first = hd(reductions)
      last = List.last(reductions)

      cond do
        last > first + 5 -> "improving"
        last < first - 5 -> "declining"
        true -> "stable"
      end
    end
  end

  defp calculate_method_efficiency(events) do
    events
    |> Enum.group_by(& &1.lsp_method)
    |> Enum.map(fn {method, method_events} ->
      {total_baseline, total_enhanced} = sum_tokens(method_events)

      reduction =
        if total_baseline > 0,
          do: (total_baseline - total_enhanced) / total_baseline * 100,
          else: 0.0

      {method,
       %{
         operations: length(method_events),
         reduction_percent: Float.round(reduction, 2),
         efficiency_grade: calculate_efficiency_grade(reduction)
       }}
    end)
    |> Enum.into(%{})
  end

  defp find_best_efficiency_day(daily_breakdown) do
    if length(daily_breakdown) == 0 do
      nil
    else
      Enum.max_by(daily_breakdown, & &1.reduction_percent, fn -> nil end)
    end
  end

  defp identify_improvement_opportunities(events) do
    opportunities = []

    # Check for low-performing methods
    method_performance = calculate_method_efficiency(events)

    low_performing_methods =
      method_performance
      |> Enum.filter(fn {_method, metrics} ->
        metrics.reduction_percent < 10 and metrics.operations >= 3
      end)
      |> Enum.map(fn {method, _metrics} -> method end)

    opportunities =
      if length(low_performing_methods) > 0 do
        [
          "Optimize LSP enhancements for methods: #{Enum.join(low_performing_methods, ", ")}"
          | opportunities
        ]
      else
        opportunities
      end

    # Check for provider optimization opportunities
    provider_performance =
      events
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {provider, provider_events} ->
        {total_baseline, total_enhanced} = sum_tokens(provider_events)

        reduction =
          if total_baseline > 0,
            do: (total_baseline - total_enhanced) / total_baseline * 100,
            else: 0.0

        {provider, reduction}
      end)

    best_provider =
      if length(provider_performance) > 1 do
        Enum.max_by(provider_performance, fn {_provider, reduction} -> reduction end, fn ->
          {nil, 0}
        end)
      else
        {nil, 0}
      end

    opportunities =
      if elem(best_provider, 0) && elem(best_provider, 1) > 20 do
        [
          "Consider using #{elem(best_provider, 0)} more frequently (#{Float.round(elem(best_provider, 1), 1)}% efficiency)"
          | opportunities
        ]
      else
        opportunities
      end

    if length(opportunities) == 0 do
      ["Current efficiency levels are good - continue monitoring"]
    else
      opportunities
    end
  end

  defp calculate_recent_trend(events) do
    if length(events) < 5 do
      "stable"
    else
      # Sort by time and look at efficiency over the hour
      sorted_events = Enum.sort_by(events, & &1.occurred_at, DateTime)

      # Split into two halves
      mid_point = div(length(sorted_events), 2)
      first_half = Enum.take(sorted_events, mid_point)
      second_half = Enum.drop(sorted_events, mid_point)

      {first_baseline, first_enhanced} = sum_tokens(first_half)

      first_reduction =
        if first_baseline > 0,
          do: (first_baseline - first_enhanced) / first_baseline * 100,
          else: 0.0

      {second_baseline, second_enhanced} = sum_tokens(second_half)

      second_reduction =
        if second_baseline > 0,
          do: (second_baseline - second_enhanced) / second_baseline * 100,
          else: 0.0

      cond do
        second_reduction > first_reduction + 5 -> "improving"
        second_reduction < first_reduction - 5 -> "declining"
        true -> "stable"
      end
    end
  end

  defp get_top_methods(events, limit) do
    events
    |> Enum.group_by(& &1.lsp_method)
    |> Enum.map(fn {method, method_events} ->
      {total_baseline, total_enhanced} = sum_tokens(method_events)

      reduction =
        if total_baseline > 0,
          do: (total_baseline - total_enhanced) / total_baseline * 100,
          else: 0.0

      %{
        method: method,
        operations: length(method_events),
        reduction_percent: Float.round(reduction, 2)
      }
    end)
    |> Enum.sort_by(& &1.reduction_percent, :desc)
    |> Enum.take(limit)
  end

  defp estimate_productivity_value(events) do
    time_events = Enum.filter(events, &(&1.time_saved_seconds != nil))

    if length(time_events) > 0 do
      total_time_saved = Enum.reduce(time_events, 0, fn e, acc -> acc + e.time_saved_seconds end)
      # Convert to hours and multiply by estimated developer hourly rate
      total_time_saved / 3600 * 100
    else
      0.0
    end
  end

  defp calculate_average_reduction(reports) do
    if length(reports) == 0 do
      0.0
    else
      total =
        reports
        |> Enum.map(fn report ->
          Decimal.to_float(report.avg_token_reduction_percent || Decimal.new("0"))
        end)
        |> Enum.sum()

      Float.round(total / length(reports), 2)
    end
  end

  defp find_best_period(reports) do
    if length(reports) == 0 do
      nil
    else
      Enum.max_by(
        reports,
        fn report ->
          Decimal.to_float(report.avg_token_reduction_percent || Decimal.new("0"))
        end,
        fn -> nil end
      )
    end
  end

  defp find_worst_period(reports) do
    if length(reports) == 0 do
      nil
    else
      Enum.min_by(
        reports,
        fn report ->
          Decimal.to_float(report.avg_token_reduction_percent || Decimal.new("0"))
        end,
        fn -> nil end
      )
    end
  end

  defp percentile(list, percentile) when is_list(list) and length(list) > 0 do
    sorted = Enum.sort(list)
    length = length(sorted)
    index = (percentile / 100 * (length - 1)) |> round()

    cond do
      index < 0 -> hd(sorted)
      index >= length -> List.last(sorted)
      true -> Enum.at(sorted, index)
    end
    |> Float.round(2)
  end

  defp percentile([], _percentile), do: 0.0
  # Optimizes O(N) multi-pass operations by calculating both totals in a single pass
  # to prevent unnecessary intermediate list allocations and redundant iterations
  defp sum_tokens(events) do
    Enum.reduce(events, {0, 0}, fn e, {b_acc, e_acc} ->
      {b_acc + e.baseline_tokens, e_acc + e.enhanced_tokens}
    end)
  end

end
