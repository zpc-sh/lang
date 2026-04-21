defmodule Lang.Workers.ProductivityMetricsWorker do
  @moduledoc """
  Background worker for processing and aggregating LSP productivity metrics.

  This worker processes measurement events asynchronously to:
  - Update user productivity metrics
  - Generate efficiency reports
  - Calculate aggregated statistics
  - Clean up old measurement data
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3

  alias Lang.Analytics
  alias Lang.Analytics.{LSPMeasurementEvent, UserProductivityMetric, TokenEfficiencyReport}
  alias Lang.Storage.MetricsStore
  alias Lang.Metrics.TokenEfficiency

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args["task"] do
      "update_user_metrics" ->
        handle_user_metrics_update(args)

      "generate_efficiency_report" ->
        handle_efficiency_report_generation(args)

      "aggregate_organization_metrics" ->
        handle_organization_aggregation(args)

      "cleanup_old_data" ->
        handle_data_cleanup(args)

      "bulk_process_events" ->
        handle_bulk_event_processing(args)

      _ ->
        Logger.warning("Unknown productivity metrics task: #{args["task"]}")
        {:error, :unknown_task}
    end
  end

  @doc """
  Queues a user metrics update job.
  """
  def update_user_metrics(user_id, opts \\ []) do
    period_type = Keyword.get(opts, :period_type, :daily)
    date = Keyword.get(opts, :date, Date.utc_today())
    priority = Keyword.get(opts, :priority, 5)

    %{
      task: "update_user_metrics",
      user_id: user_id,
      period_type: period_type,
      date: Date.to_string(date),
      triggered_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> new(priority: priority)
    |> Oban.insert()
  end

  @doc """
  Queues an efficiency report generation job.
  """
  def generate_efficiency_report(period_type \\ :daily, opts \\ []) do
    organization_id = Keyword.get(opts, :organization_id)
    date = Keyword.get(opts, :date, Date.utc_today())
    priority = Keyword.get(opts, :priority, 3)

    %{
      task: "generate_efficiency_report",
      period_type: period_type,
      date: Date.to_string(date),
      organization_id: organization_id,
      triggered_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> new(priority: priority)
    |> Oban.insert()
  end

  @doc """
  Queues organization-wide metrics aggregation.
  """
  def aggregate_organization_metrics(organization_id, opts \\ []) do
    period_type = Keyword.get(opts, :period_type, :daily)
    date = Keyword.get(opts, :date, Date.utc_today())
    priority = Keyword.get(opts, :priority, 4)

    %{
      task: "aggregate_organization_metrics",
      organization_id: organization_id,
      period_type: period_type,
      date: Date.to_string(date),
      triggered_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> new(priority: priority)
    |> Oban.insert()
  end

  @doc """
  Queues data cleanup job.
  """
  def cleanup_old_data(opts \\ []) do
    retention_days = Keyword.get(opts, :retention_days, 365)
    dry_run = Keyword.get(opts, :dry_run, false)

    %{
      task: "cleanup_old_data",
      retention_days: retention_days,
      dry_run: dry_run,
      triggered_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> new(priority: 1)
    |> Oban.insert()
  end


  # Helper for safe atom conversion to prevent DoS via atom table exhaustion
  defp safe_period_type(nil), do: :daily
  defp safe_period_type(period_str) do
    try do
      String.to_existing_atom(period_str)
    rescue
      ArgumentError ->
        Logger.warning("Security Warning: Attempted atom exhaustion with period_type: #{inspect(period_str)}")
        :daily
    end
  end

  # Private handlers


  defp handle_user_metrics_update(args) do
    user_id = args["user_id"]
    period_type = safe_period_type(args["period_type"])
    date = Date.from_iso8601!(args["date"])

    Logger.info("Processing user metrics update for user #{user_id}, period: #{period_type}")

    try do
      case update_user_productivity_metrics(user_id, period_type, date) do
        {:ok, metrics} ->
          Logger.info("Successfully updated productivity metrics for user #{user_id}")
          {:ok, %{user_id: user_id, metrics_id: metrics.id}}

        {:error, reason} ->
          Logger.error("Failed to update user productivity metrics: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception in user metrics update: #{inspect(error)}")
        {:error, :processing_exception}
    end
  end

  defp handle_efficiency_report_generation(args) do
    period_type = safe_period_type(args["period_type"])
    date = Date.from_iso8601!(args["date"])
    organization_id = args["organization_id"]

    Logger.info("Generating efficiency report for #{period_type} on #{date}")

    try do
      opts = [date: date]

      opts =
        if organization_id, do: Keyword.put(opts, :organization_id, organization_id), else: opts

      case TokenEfficiency.generate_efficiency_report(period_type, opts) do
        {:ok, report} ->
          Logger.info("Successfully generated efficiency report: #{report.id}")

          # Broadcast to dashboards for real-time updates
          Phoenix.PubSub.broadcast(
            Lang.PubSub,
            "efficiency_reports:all",
            {:efficiency_report_generated, report}
          )

          if organization_id do
            Phoenix.PubSub.broadcast(
              Lang.PubSub,
              "efficiency_reports:#{organization_id}",
              {:efficiency_report_generated, report}
            )
          end

          {:ok, %{report_id: report.id, period_type: period_type}}

        {:error, reason} ->
          Logger.error("Failed to generate efficiency report: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception in efficiency report generation: #{inspect(error)}")
        {:error, :processing_exception}
    end
  end

  defp handle_organization_aggregation(args) do
    organization_id = args["organization_id"]
    period_type = safe_period_type(args["period_type"])
    date = Date.from_iso8601!(args["date"])

    Logger.info("Aggregating organization metrics for #{organization_id}")

    try do
      case aggregate_organization_productivity(organization_id, period_type, date) do
        {:ok, results} ->
          Logger.info("Successfully aggregated organization metrics")

          # Broadcast organization-wide updates
          Phoenix.PubSub.broadcast(
            Lang.PubSub,
            "org_metrics:#{organization_id}",
            {:organization_metrics_updated, results}
          )

          {:ok, results}

        {:error, reason} ->
          Logger.error("Failed to aggregate organization metrics: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception in organization aggregation: #{inspect(error)}")
        {:error, :processing_exception}
    end
  end

  defp handle_data_cleanup(args) do
    retention_days = args["retention_days"] || 365
    dry_run = args["dry_run"] || false

    Logger.info(
      "Starting data cleanup with #{retention_days} day retention (dry_run: #{dry_run})"
    )

    try do
      case MetricsStore.cleanup_old_data(retention_days: retention_days, dry_run: dry_run) do
        {:ok, results} ->
          Logger.info("Data cleanup completed: #{inspect(results)}")
          {:ok, results}

        {:error, reason} ->
          Logger.error("Data cleanup failed: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception in data cleanup: #{inspect(error)}")
        {:error, :processing_exception}
    end
  end

  defp handle_bulk_event_processing(args) do
    event_ids = args["event_ids"] || []
    organization_id = args["organization_id"]

    Logger.info("Processing bulk events: #{length(event_ids)} events")

    try do
      # Process events in batches to avoid memory issues
      batch_size = 100

      results =
        event_ids
        |> Enum.chunk_every(batch_size)
        |> Enum.map(fn batch ->
          process_event_batch(batch, organization_id)
        end)

      successful_batches = Enum.count(results, &match?({:ok, _}, &1))
      total_batches = length(results)

      Logger.info(
        "Bulk processing completed: #{successful_batches}/#{total_batches} batches successful"
      )

      {:ok,
       %{
         total_events: length(event_ids),
         successful_batches: successful_batches,
         total_batches: total_batches
       }}
    rescue
      error ->
        Logger.error("Exception in bulk event processing: #{inspect(error)}")
        {:error, :processing_exception}
    end
  end

  # Helper functions for metric calculations

  defp update_user_productivity_metrics(user_id, period_type, date) do
    {period_start, period_end} = get_period_bounds(period_type, date)

    # Get measurement events for this user and period
    import Ash.Query

    case LSPMeasurementEvent
         |> Ash.Query.filter(user_id == ^user_id)
         |> Ash.Query.filter(occurred_at >= ^period_start and occurred_at <= ^period_end)
         |> Ash.read() do
      {:ok, events} ->
        metrics_attrs =
          calculate_productivity_metrics(events, user_id, period_start, period_end, period_type)

        MetricsStore.store_productivity_metrics(user_id, metrics_attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp aggregate_organization_productivity(organization_id, period_type, date) do
    {period_start, period_end} = get_period_bounds(period_type, date)

    # Get all users in this organization
    import Ash.Query

    case LSPMeasurementEvent
         |> Ash.Query.filter(organization_id == ^organization_id)
         |> Ash.Query.filter(occurred_at >= ^period_start and occurred_at <= ^period_end)
         |> Ash.read() do
      {:ok, events} ->
        # Group by user and update individual metrics
        user_groups = Enum.group_by(events, & &1.user_id)

        results =
          Enum.map(user_groups, fn {user_id, user_events} ->
            metrics_attrs =
              calculate_productivity_metrics(
                user_events,
                user_id,
                period_start,
                period_end,
                period_type
              )

            MetricsStore.store_productivity_metrics(user_id, metrics_attrs)
          end)

        successful_updates = Enum.count(results, &match?({:ok, _}, &1))

        {:ok,
         %{
           organization_id: organization_id,
           period: %{start: period_start, end: period_end},
           users_updated: successful_updates,
           total_events: length(events)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_productivity_metrics(events, user_id, period_start, period_end, period_type) do
    # Calculate comprehensive metrics from events
    total_operations = length(events)
    lsp_assisted = Enum.count(events, &(&1.feature_used == true))
    non_lsp = total_operations - lsp_assisted

    # Token efficiency
    token_events = Enum.filter(events, fn e -> e.baseline_tokens && e.enhanced_tokens end)
    total_baseline = Enum.sum(Enum.map(token_events, & &1.baseline_tokens))
    total_enhanced = Enum.sum(Enum.map(token_events, & &1.enhanced_tokens))
    total_saved = max(0, total_baseline - total_enhanced)

    avg_reduction = if total_baseline > 0, do: total_saved / total_baseline * 100, else: 0

    # Time efficiency
    time_events = Enum.filter(events, & &1.time_saved_seconds)
    total_time_saved = Enum.sum(Enum.map(time_events, & &1.time_saved_seconds))
    total_operation_time = Enum.sum(Enum.map(events, &(&1.operation_duration_ms || 0)))

    # Quality metrics
    quality_events = Enum.filter(events, & &1.quality_score)

    avg_quality =
      if length(quality_events) > 0 do
        Enum.sum(Enum.map(quality_events, &Decimal.to_float(&1.quality_score))) /
          length(quality_events)
      else
        nil
      end

    errors_prevented = Enum.sum(Enum.map(events, &(&1.error_reduction_count || 0)))
    iterations_saved = Enum.sum(Enum.map(events, &(&1.iterations_saved || 0)))

    # User experience
    satisfaction_events = Enum.filter(events, & &1.user_satisfaction_score)

    avg_satisfaction =
      if length(satisfaction_events) > 0 do
        Enum.sum(Enum.map(satisfaction_events, &Decimal.to_float(&1.user_satisfaction_score))) /
          length(satisfaction_events)
      else
        nil
      end

    completion_events = Enum.filter(events, & &1.completion_rate)

    avg_completion =
      if length(completion_events) > 0 do
        Enum.sum(Enum.map(completion_events, &Decimal.to_float(&1.completion_rate))) /
          length(completion_events)
      else
        nil
      end

    # Method breakdown
    method_breakdown =
      events
      |> Enum.group_by(& &1.lsp_method)
      |> Enum.map(fn {method, method_events} ->
        {to_string(method), length(method_events)}
      end)
      |> Enum.into(%{})

    # Provider performance
    provider_breakdown =
      events
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {provider, provider_events} ->
        provider_baseline = Enum.sum(Enum.map(provider_events, &(&1.baseline_tokens || 0)))
        provider_enhanced = Enum.sum(Enum.map(provider_events, &(&1.enhanced_tokens || 0)))

        provider_reduction =
          if provider_baseline > 0 do
            (provider_baseline - provider_enhanced) / provider_baseline * 100
          else
            0
          end

        {provider || "unknown",
         %{
           operations: length(provider_events),
           reduction_percent: Float.round(provider_reduction, 2)
         }}
      end)
      |> Enum.into(%{})

    # Language breakdown
    language_breakdown =
      events
      |> Enum.group_by(& &1.language)
      |> Enum.map(fn {language, lang_events} ->
        {language || "unknown", length(lang_events)}
      end)
      |> Enum.into(%{})

    # Cohort context
    cohort_type =
      case events do
        [first_event | _] -> first_event.cohort_type
        [] -> nil
      end

    %{
      user_id: user_id,
      period_start: period_start,
      period_end: period_end,
      period_type: period_type,
      total_operations: total_operations,
      lsp_assisted_operations: lsp_assisted,
      non_lsp_operations: non_lsp,
      total_tokens_saved: total_saved,
      avg_token_reduction_percent:
        if(avg_reduction > 0, do: Decimal.new("#{avg_reduction}"), else: nil),
      baseline_token_usage: total_baseline,
      enhanced_token_usage: total_enhanced,
      total_time_saved_seconds: total_time_saved,
      total_operation_time_ms: total_operation_time,
      avg_quality_score: if(avg_quality, do: Decimal.new("#{avg_quality}"), else: nil),
      total_errors_prevented: errors_prevented,
      total_iterations_saved: iterations_saved,
      avg_satisfaction_score:
        if(avg_satisfaction, do: Decimal.new("#{avg_satisfaction}"), else: nil),
      completion_rate: if(avg_completion, do: Decimal.new("#{avg_completion}"), else: nil),
      method_usage_breakdown: method_breakdown,
      provider_performance: provider_breakdown,
      language_breakdown: language_breakdown,
      cohort_type: cohort_type,
      metadata: %{
        calculated_at: DateTime.utc_now(),
        source_events: total_operations
      }
    }
  end

  defp process_event_batch(event_ids, organization_id) do
    # Process a batch of events for aggregation
    import Ash.Query

    case LSPMeasurementEvent
         |> Ash.Query.filter(id in ^event_ids)
         |> Ash.read() do
      {:ok, events} ->
        # Group events by user for efficiency
        user_groups = Enum.group_by(events, & &1.user_id)

        # Update metrics for each user in the batch
        Enum.each(user_groups, fn {user_id, user_events} ->
          # Determine period from events
          if length(user_events) > 0 do
            first_event = hd(user_events)
            event_date = DateTime.to_date(first_event.occurred_at)
            period_start = DateTime.new!(event_date, ~T[00:00:00], "Etc/UTC")
            period_end = DateTime.new!(event_date, ~T[23:59:59], "Etc/UTC")

            metrics_attrs =
              calculate_productivity_metrics(
                user_events,
                user_id,
                period_start,
                period_end,
                :daily
              )

            MetricsStore.store_productivity_metrics(user_id, metrics_attrs)
          end
        end)

        {:ok, %{processed_events: length(events), users_affected: map_size(user_groups)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_period_bounds(:daily, date) do
    start_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
    {start_dt, end_dt}
  end

  defp get_period_bounds(:weekly, date) do
    start_date = Date.beginning_of_week(date)
    end_date = Date.end_of_week(date)
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    {start_dt, end_dt}
  end

  defp get_period_bounds(:monthly, date) do
    start_date = Date.beginning_of_month(date)
    end_date = Date.end_of_month(date)
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    {start_dt, end_dt}
  end
end
