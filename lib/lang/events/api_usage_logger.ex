defmodule Lang.Events.ApiUsageLogger do
  @moduledoc """
  Efficient API usage event logging that uses the Events domain.

  This replaces the old APIUsageLogger and provides:
  1. Event-driven architecture using Ash events
  2. Redis caching for fast lookups
  3. Real-time updates via PubSub
  4. Consistent with other event tracking in the system
  """

  alias Lang.Events.ApiUsageEvent
  alias Lang.Accounts.User
  require Logger

  @doc """
  Log API usage event
  """
  def log_usage(user_id, operation_type, opts \\ []) do
    # Get organization_id from user
    organization_id = get_organization_id(user_id)

    event_data = %{
      user_id: user_id,
      organization_id: organization_id,
      operation_type: operation_type,
      success: Keyword.get(opts, :status, :success) == :success,
      content_format: Keyword.get(opts, :format),
      content_size: Keyword.get(opts, :content_size_bytes, 0),
      processing_time_ms: Keyword.get(opts, :processing_time_ms),
      error_type: Keyword.get(opts, :error_type),
      ip_address: Keyword.get(opts, :ip_address),
      user_agent: Keyword.get(opts, :user_agent),
      request_id: Keyword.get(opts, :request_id),
      rate_limited: Keyword.get(opts, :status) == :rate_limited,
      metadata: Keyword.get(opts, :metadata, %{})
    }

    case ApiUsageEvent.log_usage(event_data) do
      {:ok, event} ->
        # Update cache for fast lookups
        update_cache(user_id, operation_type, opts)
        broadcast_usage_update(user_id, event)
        {:ok, event}

      error ->
        Logger.error("Failed to log API usage event: #{inspect(error)}")
        error
    end
  end

  @doc """
  Log analysis-specific usage
  """
  def log_analysis_usage(user_id, format, content_size, processing_time, opts \\ []) do
    log_usage(
      user_id,
      :text_analysis,
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
        format: method
      ] ++ opts
    )
  end

  @doc """
  Log conversation usage
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
  Log error usage
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
  Get current month usage count (cached)
  """
  def current_month_count(user_id) do
    month_key = current_month_key()
    cache_key = "api_usage:#{user_id}:#{month_key}:count"

    case Redix.command(Lang.Redis, ["GET", cache_key]) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        count = fetch_and_cache_count(user_id, month_key)
        {:ok, count}

      {:ok, count_str} ->
        {:ok, String.to_integer(count_str)}

      error ->
        Logger.error("Redis error: #{inspect(error)}")
        # Fallback to database
        ApiUsageEvent.current_month_count(user_id)
    end
  end

  @doc """
  Check if user is over limit
  """
  def is_over_limit?(user, operation_count \\ 1) do
    case current_month_count(user.id) do
      {:ok, current_count} ->
        current_count + operation_count > user.monthly_request_limit

      _ ->
        false
    end
  end

  @doc """
  Get usage percentage
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
  Get monthly stats
  """
  def get_monthly_stats(user_id, month_year \\ nil) do
    month_year = month_year || current_month_key()

    # Try cache first
    case get_cached_stats(user_id, month_year) do
      {:ok, stats} -> {:ok, stats}
      _ -> fetch_and_cache_stats(user_id, month_year)
    end
  end

  @doc """
  Subscribe to usage updates
  """
  def subscribe_to_usage_updates(user_id) do
    Phoenix.PubSub.subscribe(Lang.PubSub, "api_usage:#{user_id}")
  end

  def subscribe_to_global_usage_updates do
    Phoenix.PubSub.subscribe(Lang.PubSub, "api_usage:global")
  end

  # Private functions

  defp get_organization_id(user_id) do
    case User.by_id(user_id) do
      {:ok, user} -> user.organization_id
      _ -> nil
    end
  end

  defp current_month_key do
    now = DateTime.utc_now()
    "#{now.year}-#{String.pad_leading(to_string(now.month), 2, "0")}"
  end

  defp update_cache(user_id, _operation_type, _opts) do
    month_key = current_month_key()
    cache_key = "api_usage:#{user_id}:#{month_key}:count"

    # Increment counter
    Redix.command(Lang.Redis, ["INCR", cache_key])
    # Set expiry (60 days)
    Redix.command(Lang.Redis, ["EXPIRE", cache_key, 60 * 24 * 60 * 60])
  end

  defp broadcast_usage_update(user_id, event) do
    Phoenix.PubSub.broadcast(Lang.PubSub, "api_usage:#{user_id}", {:usage_logged, event})
    Phoenix.PubSub.broadcast(Lang.PubSub, "api_usage:global", {:usage_logged, event})
  end

  defp fetch_and_cache_count(user_id, month_key) do
    case ApiUsageEvent.monthly_stats(user_id, month_key) do
      {:ok, events} ->
        count = length(events)
        cache_key = "api_usage:#{user_id}:#{month_key}:count"
        Redix.command(Lang.Redis, ["SET", cache_key, count, "EX", 3600])
        count

      _ ->
        0
    end
  end

  defp get_cached_stats(user_id, month_year) do
    cache_key = "api_usage:#{user_id}:#{month_year}:stats"

    case Redix.command(Lang.Redis, ["GET", cache_key]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, data} -> {:ok, Jason.decode!(data, keys: :atoms)}
      error -> error
    end
  end

  defp fetch_and_cache_stats(user_id, month_year) do
    case ApiUsageEvent.monthly_stats(user_id, month_year) do
      {:ok, events} ->
        stats = calculate_stats(events)
        cache_key = "api_usage:#{user_id}:#{month_year}:stats"
        Redix.command(Lang.Redis, ["SET", cache_key, Jason.encode!(stats), "EX", 3600])
        {:ok, stats}

      error ->
        error
    end
  end

  defp calculate_stats(events) do
    %{
      total_requests: length(events),
      successful_requests: Enum.count(events, & &1.success),
      error_requests: Enum.count(events, &(not &1.success)),
      rate_limited_requests: Enum.count(events, & &1.rate_limited),
      total_content_size: Enum.sum(Enum.map(events, & &1.content_size)),
      avg_processing_time: average(Enum.map(events, & &1.processing_time_ms))
    }
  end

  defp average([]), do: 0.0
  defp average(list), do: Enum.sum(list) / length(list)
end
