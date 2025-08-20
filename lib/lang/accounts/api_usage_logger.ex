defmodule Lang.Accounts.APIUsageLogger do
  @moduledoc """
  Efficient API usage logging that avoids large resource issues by:
  1. Using background processing with AshOban
  2. Leveraging pub_sub for real-time updates
  3. Caching frequently accessed data in Redis
  4. Batch processing for better performance
  """

  alias Lang.Accounts.APIUsage
  require Logger

  @doc """
  Log API usage - creates record and triggers background processing
  """
  def log_usage(user_id, operation_type, opts \\ []) do
    usage_data = %{
      user_id: user_id,
      operation_type: operation_type,
      status: Keyword.get(opts, :status, :success),
      format: Keyword.get(opts, :format),
      content_size_bytes: Keyword.get(opts, :content_size_bytes),
      processing_time_ms: Keyword.get(opts, :processing_time_ms),
      error_type: Keyword.get(opts, :error_type),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent),
      request_id: Keyword.get(opts, :request_id)
    }

    # Create the usage record - this will trigger pub_sub notifications
    case APIUsage.log_usage(usage_data) do
      {:ok, usage_record} ->
        # Update immediate cache for fast lookups
        update_immediate_cache(user_id, operation_type, opts)

        {:ok, usage_record}

      error ->
        Logger.error("Failed to log API usage: #{inspect(error)}")
        error
    end
  end

  @doc """
  Log analysis-specific usage with additional metrics
  """
  def log_analysis_usage(user_id, format, content_size, processing_time, opts \\ []) do
    log_usage(
      user_id,
      :analyze,
      [
        format: format,
        content_size_bytes: content_size,
        processing_time_ms: processing_time
      ] ++ opts
    )
  end

  @doc """
  Log LSP-specific usage
  """
  def log_lsp_usage(user_id, method, processing_time, opts \\ []) do
    log_usage(
      user_id,
      :lsp,
      [
        processing_time_ms: processing_time,
        # Store LSP method as format for tracking
        format: method
      ] ++ opts
    )
  end

  @doc """
  Log conversation rehearsal usage
  """
  def log_conversation_usage(user_id, session_id, processing_time, opts \\ []) do
    log_usage(
      user_id,
      :conversation,
      [
        processing_time_ms: processing_time,
        request_id: session_id
      ] ++ opts
    )
  end

  @doc """
  Log time machine usage
  """
  def log_timemachine_usage(user_id, timeline_id, processing_time, opts \\ []) do
    log_usage(
      user_id,
      :timemachine,
      [
        processing_time_ms: processing_time,
        request_id: timeline_id
      ] ++ opts
    )
  end

  @doc """
  Log error usage (rate limits, validation errors, etc.)
  """
  def log_error_usage(user_id, operation_type, error_type, opts \\ []) do
    log_usage(
      user_id,
      operation_type,
      [
        status: :error,
        error_type: error_type
      ] ++ opts
    )
  end

  @doc """
  Log rate limited usage
  """
  def log_rate_limited_usage(user_id, operation_type, opts \\ []) do
    log_usage(
      user_id,
      operation_type,
      [
        status: :rate_limited
      ] ++ opts
    )
  end

  @doc """
  Get current month usage count for a user (fast Redis lookup)
  """
  def current_month_count(user_id) do
    now = DateTime.utc_now()
    month_year = "#{now.year}-#{String.pad_leading(to_string(now.month), 2, "0")}"
    cache_key = "user_metrics:#{user_id}:#{month_year}"

    case Redix.command(Lang.Redis, ["HGET", cache_key, "total_requests"]) do
      {:ok, nil} ->
        # Cache miss - fall back to database query but also warm the cache
        Task.start(fn -> warm_user_cache(user_id, month_year) end)
        fallback_current_month_count(user_id)

      {:ok, count_str} ->
        {:ok, String.to_integer(count_str)}

      {:error, _} ->
        fallback_current_month_count(user_id)
    end
  end

  @doc """
  Check if user is over their monthly limit
  """
  def is_over_limit?(user, operation_count \\ 1) do
    case current_month_count(user.id) do
      {:ok, current_count} ->
        current_count + operation_count > user.monthly_request_limit

      {:error, _} ->
        # Default to allowing if we can't check
        false
    end
  end

  @doc """
  Get usage percentage for a user
  """
  def usage_percentage(user) do
    case current_month_count(user.id) do
      {:ok, current_count} ->
        percentage = current_count / user.monthly_request_limit * 100
        {:ok, min(percentage, 100.0)}

      error ->
        error
    end
  end

  @doc """
  Get monthly stats from cache (fast) or database (fallback)
  """
  def get_monthly_stats(user_id, month_year \\ nil) do
    month_year = month_year || current_month_year()
    cache_key = "user_metrics:#{user_id}:#{month_year}"

    # Try to get from Redis cache first
    case Redix.command(Lang.Redis, [
           "HMGET",
           cache_key,
           "total_requests",
           "successful_requests",
           "error_requests",
           "rate_limited_requests",
           "total_content_size",
           "avg_processing_time"
         ]) do
      {:ok, [nil | _]} ->
        # Cache miss - get from database and cache it
        get_monthly_stats_from_db(user_id, month_year)

      {:ok, [total, success, error, rate_limited, content_size, avg_time]} ->
        # Cache hit - return parsed results
        {:ok,
         %{
           total_requests: parse_int(total, 0),
           successful_requests: parse_int(success, 0),
           error_requests: parse_int(error, 0),
           rate_limited_requests: parse_int(rate_limited, 0),
           total_content_size: parse_int(content_size, 0),
           avg_processing_time: parse_float(avg_time, 0.0)
         }}

      {:error, _} ->
        # Redis error - fall back to database
        get_monthly_stats_from_db(user_id, month_year)
    end
  end

  @doc """
  Get operation breakdown for a user and month
  """
  def get_operation_breakdown(user_id, month_year \\ nil) do
    month_year = month_year || current_month_year()

    # Get from cache or database
    operations = [:analyze, :lsp, :conversation, :timemachine, :stylometrics]

    results =
      Enum.map(operations, fn operation ->
        cache_key = "user_operation_metrics:#{user_id}:#{month_year}:#{operation}"

        case Redix.command(Lang.Redis, ["HMGET", cache_key, "count", "avg_processing_time"]) do
          {:ok, [nil, _]} ->
            {operation, %{count: 0, avg_processing_time: 0.0}}

          {:ok, [count, avg_time]} ->
            {operation,
             %{
               count: parse_int(count, 0),
               avg_processing_time: parse_float(avg_time, 0.0)
             }}

          _ ->
            {operation, %{count: 0, avg_processing_time: 0.0}}
        end
      end)

    {:ok, Enum.into(results, %{})}
  end

  # Subscribe to real-time usage updates
  def subscribe_to_usage_updates(user_id) do
    Phoenix.PubSub.subscribe(Lang.PubSub, "api_usage:#{user_id}")
  end

  def subscribe_to_global_usage_updates do
    Phoenix.PubSub.subscribe(Lang.PubSub, "api_usage:global")
  end

  def subscribe_to_metrics_updates do
    Phoenix.PubSub.subscribe(Lang.PubSub, "metrics:updated")
  end

  # Private helper functions

  defp update_immediate_cache(user_id, operation_type, opts) do
    # Update immediate counters for this request
    now = DateTime.utc_now()
    month_year = current_month_year(now)
    status = Keyword.get(opts, :status, :success)

    # Update user's monthly counter
    cache_key = "user_metrics:#{user_id}:#{month_year}"
    Redix.command(Lang.Redis, ["HINCRBY", cache_key, "total_requests", 1])
    Redix.command(Lang.Redis, ["HINCRBY", cache_key, "#{status}_requests", 1])
    # 60 days
    Redix.command(Lang.Redis, ["EXPIRE", cache_key, 60 * 60 * 24 * 60])

    # Update operation-specific counter
    op_cache_key = "user_operation_metrics:#{user_id}:#{month_year}:#{operation_type}"
    Redix.command(Lang.Redis, ["HINCRBY", op_cache_key, "count", 1])
    Redix.command(Lang.Redis, ["EXPIRE", op_cache_key, 60 * 60 * 24 * 60])
  end

  defp warm_user_cache(user_id, month_year) do
    # Warm the cache from database in background
    case get_monthly_stats_from_db(user_id, month_year) do
      {:ok, stats} ->
        cache_key = "user_metrics:#{user_id}:#{month_year}"

        Redix.pipeline(Lang.Redis, [
          ["HSET", cache_key, "total_requests", stats.total_requests],
          ["HSET", cache_key, "successful_requests", stats.successful_requests],
          ["HSET", cache_key, "error_requests", stats.error_requests],
          ["HSET", cache_key, "rate_limited_requests", stats.rate_limited_requests],
          ["HSET", cache_key, "total_content_size", stats.total_content_size],
          ["HSET", cache_key, "avg_processing_time", stats.avg_processing_time],
          ["EXPIRE", cache_key, 60 * 60 * 24 * 60]
        ])

      _ ->
        :ok
    end
  end

  defp fallback_current_month_count(user_id) do
    # Direct database query as fallback
    now = DateTime.utc_now()
    month_year = current_month_year(now)

    case APIUsage.usage_for_user(user_id: user_id, month_year: month_year) do
      {:ok, usage_records} -> {:ok, length(usage_records)}
      error -> error
    end
  end

  defp get_monthly_stats_from_db(user_id, month_year) do
    # Use the existing monthly_stats action from APIUsage resource
    APIUsage.monthly_stats(user_id: user_id, month_year: month_year)
  end

  defp current_month_year(datetime \\ DateTime.utc_now()) do
    "#{datetime.year}-#{String.pad_leading(to_string(datetime.month), 2, "0")}"
  end

  defp parse_int(nil, default), do: default

  defp parse_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(int, _default) when is_integer(int), do: int

  defp parse_float(nil, default), do: default

  defp parse_float(str, default) when is_binary(str) do
    case Float.parse(str) do
      {float, _} -> float
      :error -> default
    end
  end

  defp parse_float(float, _default) when is_float(float), do: float
end
