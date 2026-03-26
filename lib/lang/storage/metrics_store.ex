defmodule Lang.Storage.MetricsStore do
  @moduledoc """
  Metrics Storage Layer - Efficient storage and retrieval operations for LSP measurement data.

  This module provides optimized data operations for analytics, including:
  - High-performance measurement event storage
  - Time-series aggregation queries
  - Efficient dashboard data loading
  - Data retention and cleanup policies
  """

  alias Lang.Analytics
  alias Lang.Analytics.{LSPMeasurementEvent, UserProductivityMetric, TokenEfficiencyReport}

  require Logger

  @doc """
  Stores a measurement event with optimizations for bulk inserts.
  """
  def store_measurement_event(attrs) do
    case LSPMeasurementEvent.create(attrs) do
      {:ok, event} ->
        # Trigger background aggregation update
        schedule_aggregation_update(event.user_id, event.organization_id)
        {:ok, event}

      {:error, reason} ->
        Logger.warning("Failed to store measurement event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Bulk inserts multiple measurement events for high-throughput scenarios.
  """
  def bulk_store_measurement_events(events_list) when is_list(events_list) do
    # Use Ash.bulk_create for efficient bulk operations
    case Ash.bulk_create(LSPMeasurementEvent, events_list, return_records?: true) do
      %Ash.BulkResult{records: records, errors: []} ->
        # Schedule aggregation updates for affected users/orgs
        schedule_bulk_aggregation_updates(records)
        {:ok, records}

      %Ash.BulkResult{records: records, errors: errors} ->
        Logger.warning("Bulk insert partially failed: #{length(errors)} errors")
        {:partial_success, records, errors}

      error ->
        Logger.error("Bulk insert failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Retrieves measurement events with efficient pagination and filtering.
  """
  def get_measurement_events(filters \\ [], opts \\ []) do
    import Ash.Query

    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    sort_order = Keyword.get(opts, :sort, :desc)

    query =
      LSPMeasurementEvent
      |> Ash.Query.sort(occurred_at: sort_order)
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)

    # Apply filters
    query = apply_measurement_filters(query, filters)

    case Ash.read(query) do
      {:ok, events} ->
        {:ok, events}

      {:error, reason} ->
        Logger.error("Failed to retrieve measurement events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets time-series aggregated data for dashboard charts.
  """
  def get_time_series_data(opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    granularity = Keyword.get(opts, :granularity, :daily)
    organization_id = Keyword.get(opts, :organization_id)
    user_id = Keyword.get(opts, :user_id)

    # Build time series query based on granularity
    time_format = get_time_format(granularity)

    import Ash.Query

    base_query =
      LSPMeasurementEvent
      |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
      |> Ash.Query.filter(not is_nil(baseline_tokens) and not is_nil(enhanced_tokens))

    # Apply optional filters
    query =
      if organization_id do
        Ash.Query.filter(base_query, organization_id == ^organization_id)
      else
        base_query
      end

    query =
      if user_id do
        Ash.Query.filter(query, user_id == ^user_id)
      else
        query
      end

    case Ash.read(query) do
      {:ok, events} ->
        time_series = aggregate_time_series(events, granularity, time_format)
        {:ok, time_series}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves dashboard summary statistics with caching.
  """
  def get_dashboard_summary(opts \\ []) do
    cache_key = build_cache_key("dashboard_summary", opts)

    case get_cached_result(cache_key) do
      {:ok, cached_summary} ->
        {:ok, cached_summary}

      :cache_miss ->
        case calculate_dashboard_summary(opts) do
          {:ok, summary} ->
            # 5-minute cache
            cache_result(cache_key, summary, ttl: 300)
            {:ok, summary}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Gets user-specific analytics with performance optimizations.
  """
  def get_user_analytics_data(user_id, opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())

    import Ash.Query

    # Optimized query with proper indexes
    events_query =
      LSPMeasurementEvent
      |> Ash.Query.filter(user_id == ^user_id)
      |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)
      |> Ash.Query.sort(occurred_at: :desc)

    productivity_query =
      UserProductivityMetric.by_user_and_period(user_id, from, to)

    with {:ok, events} <- Ash.read(events_query),
         {:ok, productivity_metrics} <- Ash.read(productivity_query) do
      analytics_data = compile_user_analytics_data(events, productivity_metrics)
      {:ok, analytics_data}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets organization-wide analytics efficiently.
  """
  def get_organization_analytics(organization_id, opts \\ []) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -30, :day))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    include_users = Keyword.get(opts, :include_users, false)

    import Ash.Query

    # Get organization events
    events_query =
      LSPMeasurementEvent
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> Ash.Query.filter(occurred_at >= ^from and occurred_at <= ^to)

    # Get productivity metrics for the organization
    productivity_query =
      UserProductivityMetric.by_organization(organization_id)
      |> Ash.Query.filter(period_start >= ^from and period_end <= ^to)

    with {:ok, events} <- Ash.read(events_query),
         {:ok, productivity_metrics} <- Ash.read(productivity_query) do
      org_analytics = compile_organization_analytics(events, productivity_metrics, include_users)
      {:ok, org_analytics}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stores aggregated productivity metrics efficiently.
  """
  def store_productivity_metrics(user_id, metrics_attrs) do
    # Check if metrics already exist for this period
    case UserProductivityMetric.by_user_and_period(
           user_id,
           metrics_attrs.period_start,
           metrics_attrs.period_end
         ) do
      {:ok, existing} when not is_nil(existing) ->
        # Update existing metrics
        UserProductivityMetric.update(existing, metrics_attrs)

      {:ok, nil} ->
        # Create new metrics record
        full_attrs = Map.put(metrics_attrs, :user_id, user_id)
        UserProductivityMetric.create(full_attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates and stores efficiency reports.
  """
  def generate_and_store_efficiency_report(period_type, opts \\ []) do
    case Lang.Metrics.TokenEfficiency.generate_efficiency_report(period_type, opts) do
      {:ok, report} ->
        Logger.info("Generated and stored efficiency report: #{report.id}")
        {:ok, report}

      {:error, reason} ->
        Logger.error("Failed to generate efficiency report: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Performs data cleanup based on retention policies.
  """
  def cleanup_old_data(opts \\ []) do
    # Keep 1 year by default
    retention_days = Keyword.get(opts, :retention_days, 365)
    dry_run = Keyword.get(opts, :dry_run, false)

    cutoff_date = DateTime.add(DateTime.utc_now(), -retention_days, :day)

    import Ash.Query

    # Find old measurement events
    old_events_query =
      LSPMeasurementEvent
      |> Ash.Query.filter(occurred_at < ^cutoff_date)

    case Ash.read(old_events_query) do
      {:ok, old_events} ->
        count = length(old_events)

        if dry_run do
          Logger.info(
            "Dry run: Would delete #{count} measurement events older than #{retention_days} days"
          )

          {:ok, %{would_delete: count, dry_run: true}}
        else
          # Delete old events in batches
          deleted_count = delete_events_in_batches(old_events)
          Logger.info("Deleted #{deleted_count} old measurement events")

          # Clean up orphaned productivity metrics
          cleanup_orphaned_metrics(cutoff_date)

          {:ok, %{deleted: deleted_count, dry_run: false}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Optimizes database indexes and statistics for better performance.
  """
  def optimize_storage do
    # This would run database optimization queries
    # For PostgreSQL, this might include VACUUM, ANALYZE, REINDEX
    Logger.info("Starting metrics storage optimization...")

    optimization_queries = [
      "VACUUM ANALYZE lsp_measurement_events",
      "VACUUM ANALYZE user_productivity_metrics",
      "VACUUM ANALYZE token_efficiency_reports",
      "REINDEX TABLE lsp_measurement_events",
      "UPDATE pg_stat_user_tables SET n_tup_ins = 0 WHERE relname IN ('lsp_measurement_events', 'user_productivity_metrics')"
    ]

    results =
      Enum.map(optimization_queries, fn query ->
        case Ecto.Adapters.SQL.query(Lang.Repo, query) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if length(errors) > 0 do
      Logger.warning("Some optimization queries failed: #{inspect(errors)}")
      {:partial_success, results}
    else
      Logger.info("Storage optimization completed successfully")
      {:ok, :optimized}
    end
  end

  # Private helper functions

  defp schedule_aggregation_update(user_id, organization_id) do
    # Queue background job to update aggregated metrics
    %{
      user_id: user_id,
      organization_id: organization_id,
      update_type: "measurement_event",
      triggered_at: DateTime.utc_now()
    }
    |> Lang.Workers.ProductivityMetricsWorker.new(queue: :analytics, priority: 5)
    |> Oban.insert()
  end

  defp schedule_bulk_aggregation_updates(records) do
    # Group by user/org to avoid duplicate jobs
    updates =
      records
      |> Enum.group_by(fn record -> {record.user_id, record.organization_id} end)
      |> Enum.map(fn {{user_id, org_id}, _events} ->
        %{
          user_id: user_id,
          organization_id: org_id,
          update_type: "bulk_measurement_events",
          triggered_at: DateTime.utc_now()
        }
      end)

    # Queue all updates
    Enum.each(updates, fn update_attrs ->
      update_attrs
      |> Lang.Workers.ProductivityMetricsWorker.new(queue: :analytics, priority: 3)
      |> Oban.insert()
    end)
  end

  defp apply_measurement_filters(query, filters) do
    import Ash.Query

    Enum.reduce(filters, query, fn {filter_type, value}, acc_query ->
      case filter_type do
        :user_id ->
          Ash.Query.filter(acc_query, user_id == ^value)

        :organization_id ->
          Ash.Query.filter(acc_query, organization_id == ^value)

        :lsp_method ->
          Ash.Query.filter(acc_query, lsp_method == ^value)

        :provider ->
          Ash.Query.filter(acc_query, provider == ^value)

        :date_from ->
          Ash.Query.filter(acc_query, occurred_at >= ^value)

        :date_to ->
          Ash.Query.filter(acc_query, occurred_at <= ^value)

        :cohort_type ->
          Ash.Query.filter(acc_query, cohort_type == ^value)

        :min_token_reduction ->
          Ash.Query.filter(acc_query, token_reduction_percent >= ^value)

        _ ->
          acc_query
      end
    end)
  end

  defp get_time_format(:hourly), do: "%Y-%m-%d %H:00:00"
  defp get_time_format(:daily), do: "%Y-%m-%d"
  defp get_time_format(:weekly), do: "%Y-W%W"
  defp get_time_format(:monthly), do: "%Y-%m"

  defp aggregate_time_series(events, granularity, _time_format) do
    # Group events by time period
    time_grouper =
      case granularity do
        :hourly ->
          fn event ->
            event.occurred_at |> DateTime.truncate(:hour) |> DateTime.to_iso8601()
          end

        :daily ->
          fn event ->
            event.occurred_at |> DateTime.to_date() |> Date.to_iso8601()
          end

        :weekly ->
          fn event ->
            date = DateTime.to_date(event.occurred_at)
            week_start = Date.beginning_of_week(date)
            Date.to_iso8601(week_start)
          end

        :monthly ->
          fn event ->
            date = DateTime.to_date(event.occurred_at)
            "#{date.year}-#{String.pad_leading("#{date.month}", 2, "0")}"
          end
      end

    events
    |> Enum.group_by(time_grouper)
    |> Enum.map(fn {time_key, time_events} ->
      total_baseline = Enum.reduce(time_events, 0, fn x, acc -> acc + x.baseline_tokens end)
      total_enhanced = Enum.reduce(time_events, 0, fn x, acc -> acc + x.enhanced_tokens end)
      total_saved = total_baseline - total_enhanced
      avg_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0.0

      %{
        time: time_key,
        operations: length(time_events),
        tokens_saved: total_saved,
        avg_reduction_percent: Float.round(avg_reduction, 2),
        baseline_tokens: total_baseline,
        enhanced_tokens: total_enhanced
      }
    end)
    |> Enum.sort_by(& &1.time)
  end

  defp calculate_dashboard_summary(opts) do
    from = Keyword.get(opts, :from, DateTime.add(DateTime.utc_now(), -24, :hour))
    to = Keyword.get(opts, :to, DateTime.utc_now())
    organization_id = Keyword.get(opts, :organization_id)

    case Analytics.calculate_aggregate_stats(from: from, to: to, organization_id: organization_id) do
      {:ok, stats} ->
        summary = %{
          period: %{from: from, to: to},
          total_operations: stats.total_events,
          avg_token_reduction: stats.avg_token_reduction_percent,
          total_tokens_saved: stats.total_tokens_saved,
          avg_time_saved: stats.avg_time_saved_seconds,
          top_methods: get_top_methods_from_stats(stats),
          efficiency_status: get_efficiency_status(stats.avg_token_reduction_percent),
          generated_at: DateTime.utc_now()
        }

        {:ok, summary}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compile_user_analytics_data(events, productivity_metrics) do
    %{
      total_events: length(events),
      productivity_metrics: productivity_metrics,
      recent_activity: Enum.take(events, 10),
      method_breakdown: calculate_method_breakdown(events),
      efficiency_trend: calculate_efficiency_trend(events),
      compiled_at: DateTime.utc_now()
    }
  end

  defp compile_organization_analytics(events, productivity_metrics, include_users) do
    base_analytics = %{
      total_events: length(events),
      productivity_metrics: productivity_metrics,
      method_breakdown: calculate_method_breakdown(events),
      provider_breakdown: calculate_provider_breakdown(events),
      compiled_at: DateTime.utc_now()
    }

    if include_users do
      user_breakdown = calculate_user_breakdown(events)
      Map.put(base_analytics, :user_breakdown, user_breakdown)
    else
      base_analytics
    end
  end

  defp calculate_method_breakdown(events) do
    events
    |> Enum.group_by(& &1.lsp_method)
    |> Enum.map(fn {method, method_events} ->
      total_baseline = Enum.reduce(method_events, 0, fn x, acc -> acc + x.baseline_tokens end)
      total_enhanced = Enum.reduce(method_events, 0, fn x, acc -> acc + x.enhanced_tokens end)

      reduction =
        if total_baseline > 0,
          do: (total_baseline - total_enhanced) / total_baseline * 100,
          else: 0.0

      %{
        method: method,
        operations: length(method_events),
        avg_reduction: Float.round(reduction, 2)
      }
    end)
  end

  defp calculate_provider_breakdown(events) do
    events
    |> Enum.group_by(& &1.provider)
    |> Enum.map(fn {provider, provider_events} ->
      total_baseline = Enum.reduce(provider_events, 0, fn x, acc -> acc + x.baseline_tokens end)
      total_enhanced = Enum.reduce(provider_events, 0, fn x, acc -> acc + x.enhanced_tokens end)

      reduction =
        if total_baseline > 0,
          do: (total_baseline - total_enhanced) / total_baseline * 100,
          else: 0.0

      %{
        provider: provider || "unknown",
        operations: length(provider_events),
        avg_reduction: Float.round(reduction, 2)
      }
    end)
  end

  defp calculate_user_breakdown(events) do
    events
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, user_events} ->
      total_baseline = Enum.reduce(user_events, 0, fn x, acc -> acc + x.baseline_tokens end)
      total_enhanced = Enum.reduce(user_events, 0, fn x, acc -> acc + x.enhanced_tokens end)

      reduction =
        if total_baseline > 0,
          do: (total_baseline - total_enhanced) / total_baseline * 100,
          else: 0.0

      %{
        user_id: user_id,
        operations: length(user_events),
        avg_reduction: Float.round(reduction, 2)
      }
    end)
    |> Enum.sort_by(& &1.operations, :desc)
  end

  defp calculate_efficiency_trend(events) do
    if length(events) < 10 do
      "insufficient_data"
    else
      # Split into first and second half to detect trend
      mid_point = div(length(events), 2)
      first_half = Enum.take(events, mid_point)
      second_half = Enum.drop(events, mid_point)

      first_avg = calculate_avg_reduction(first_half)
      second_avg = calculate_avg_reduction(second_half)

      cond do
        second_avg > first_avg + 5 -> "improving"
        second_avg < first_avg - 5 -> "declining"
        true -> "stable"
      end
    end
  end

  defp calculate_avg_reduction(events) do
    token_events = Enum.filter(events, fn e -> e.baseline_tokens && e.enhanced_tokens end)

    if length(token_events) == 0 do
      0.0
    else
      total_baseline = Enum.reduce(token_events, 0, fn x, acc -> acc + x.baseline_tokens end)
      total_enhanced = Enum.reduce(token_events, 0, fn x, acc -> acc + x.enhanced_tokens end)

      if total_baseline > 0 do
        (total_baseline - total_enhanced) / total_baseline * 100
      else
        0.0
      end
    end
  end

  defp delete_events_in_batches(events, batch_size \\ 1000) do
    events
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce(0, fn batch, acc ->
      batch_ids = Enum.map(batch, & &1.id)

      case Ash.bulk_destroy(LSPMeasurementEvent, batch_ids, %{}) do
        %Ash.BulkResult{records: deleted_records} ->
          acc + length(deleted_records)

        _error ->
          Logger.warning("Failed to delete batch of #{length(batch)} events")
          acc
      end
    end)
  end

  defp cleanup_orphaned_metrics(cutoff_date) do
    import Ash.Query

    old_metrics_query =
      UserProductivityMetric
      |> Ash.Query.filter(period_end < ^cutoff_date)

    case Ash.read(old_metrics_query) do
      {:ok, old_metrics} ->
        old_metrics_ids = Enum.map(old_metrics, & &1.id)

        case Ash.bulk_destroy(UserProductivityMetric, old_metrics_ids, %{}) do
          %Ash.BulkResult{records: deleted_records} ->
            Logger.info("Cleaned up #{length(deleted_records)} orphaned productivity metrics")

          _error ->
            Logger.warning("Failed to clean up orphaned productivity metrics")
        end

      {:error, reason} ->
        Logger.error("Failed to query old productivity metrics: #{inspect(reason)}")
    end
  end

  defp build_cache_key(base_key, opts) do
    # Create a cache key based on the base key and relevant options
    opts_string =
      opts
      |> Enum.sort()
      |> Enum.map(fn {k, v} -> "#{k}:#{inspect(v)}" end)
      |> Enum.join("|")

    "#{base_key}:#{:crypto.hash(:sha256, opts_string) |> Base.encode16()}"
  end

  defp get_cached_result(cache_key) do
    # Simple in-memory cache using ETS
    # In production, you might want Redis or other caching solution
    case :ets.lookup(:metrics_cache, cache_key) do
      [{^cache_key, value, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, value}
        else
          :ets.delete(:metrics_cache, cache_key)
          :cache_miss
        end

      [] ->
        :cache_miss
    end
  end

  defp cache_result(cache_key, value, opts \\ []) do
    # Default 5 minutes
    ttl = Keyword.get(opts, :ttl, 300)
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)

    # Ensure cache table exists
    :ets.insert(:metrics_cache, {cache_key, value, expires_at})
  end

  defp get_top_methods_from_stats(stats) do
    stats.method_breakdown
    |> Enum.sort_by(fn {_method, count} -> count end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {method, count} -> %{method: method, operations: count} end)
  end

  defp get_efficiency_status(avg_reduction) do
    cond do
      avg_reduction >= 25 -> "excellent"
      avg_reduction >= 15 -> "good"
      avg_reduction >= 5 -> "moderate"
      avg_reduction >= 0 -> "low"
      true -> "poor"
    end
  end

  # Initialize cache table on application start
  def init_cache do
    case :ets.info(:metrics_cache) do
      :undefined ->
        :ets.new(:metrics_cache, [:set, :public, :named_table])
        Logger.info("Initialized metrics cache storage")
        :ok

      _ ->
        :ok
    end
  end
end
