defmodule Elixir.Lang.LSP.Lang.Lang.Security.RateLimit do
  @moduledoc "Rate limiting"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.security.rate_limit"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    key = Map.get(params, "key") || Map.get(ctx, "user_id") || Map.get(ctx, "client_id")
    limit = Map.get(params, "limit", 100)
    window_seconds = Map.get(params, "window_seconds", 60)
    action = Map.get(params, "action", "check")

    case key do
      nil ->
        {:error, "key, user_id, or client_id is required"}

      key ->
        case action do
          "check" ->
            check_rate_limit(key, limit, window_seconds)

          "increment" ->
            increment_rate_limit(key, limit, window_seconds)

          "reset" ->
            reset_rate_limit(key)

          _ ->
            {:error, "invalid action: #{action}. Must be 'check', 'increment', or 'reset'"}
        end
    end
  end

  defp check_rate_limit(key, limit, window_seconds) do
    bucket_key = rate_limit_key(key, window_seconds)

    case get_current_count(bucket_key) do
      count when count >= limit ->
        time_to_reset = get_time_to_reset(bucket_key, window_seconds)

        {:ok,
         %{
           allowed: false,
           limit: limit,
           remaining: 0,
           current: count,
           reset_in_seconds: time_to_reset,
           message: "Rate limit exceeded"
         }}

      count ->
        {:ok,
         %{
           allowed: true,
           limit: limit,
           remaining: limit - count,
           current: count,
           reset_in_seconds: get_time_to_reset(bucket_key, window_seconds)
         }}
    end
  end

  defp increment_rate_limit(key, limit, window_seconds) do
    bucket_key = rate_limit_key(key, window_seconds)

    # Increment the counter atomically
    new_count = increment_counter(bucket_key, window_seconds)

    case new_count do
      count when count > limit ->
        time_to_reset = get_time_to_reset(bucket_key, window_seconds)

        {:ok,
         %{
           allowed: false,
           limit: limit,
           remaining: 0,
           current: count,
           reset_in_seconds: time_to_reset,
           message: "Rate limit exceeded after increment"
         }}

      count ->
        {:ok,
         %{
           allowed: true,
           limit: limit,
           remaining: limit - count,
           current: count,
           reset_in_seconds: get_time_to_reset(bucket_key, window_seconds)
         }}
    end
  end

  defp reset_rate_limit(key) do
    # Delete all time buckets for this key
    pattern_key = "rate_limit:#{key}:*"

    case delete_keys_by_pattern(pattern_key) do
      {:ok, deleted_count} ->
        {:ok,
         %{
           reset: true,
           deleted_buckets: deleted_count,
           message: "Rate limit reset successfully"
         }}

      {:error, reason} ->
        {:error, "Failed to reset rate limit: #{reason}"}
    end
  end

  defp rate_limit_key(key, window_seconds) do
    # Create time-based bucket key
    current_time = System.system_time(:second)
    bucket_time = div(current_time, window_seconds) * window_seconds
    "rate_limit:#{key}:#{bucket_time}"
  end

  defp get_current_count(bucket_key) do
    case get_from_cache(bucket_key) do
      nil -> 0
      count when is_integer(count) -> count
      _ -> 0
    end
  end

  defp increment_counter(bucket_key, window_seconds) do
    # Try to use Redis if available, otherwise use ETS
    case get_cache_backend() do
      :redis ->
        increment_redis_counter(bucket_key, window_seconds)

      :ets ->
        increment_ets_counter(bucket_key, window_seconds)
    end
  end

  defp get_time_to_reset(bucket_key, window_seconds) do
    # Extract timestamp from bucket key and calculate reset time
    case String.split(bucket_key, ":") do
      [_prefix, _key, timestamp_str] ->
        case Integer.parse(timestamp_str) do
          {bucket_start, ""} ->
            reset_time = bucket_start + window_seconds
            current_time = System.system_time(:second)
            max(0, reset_time - current_time)

          _ ->
            window_seconds
        end

      _ ->
        window_seconds
    end
  end

  defp get_cache_backend do
    if Process.whereis(Lang.Redis) do
      :redis
    else
      :ets
    end
  end

  defp increment_redis_counter(bucket_key, window_seconds) do
    try do
      case Redix.pipeline(Lang.Redis, [
             ["INCR", bucket_key],
             ["EXPIRE", bucket_key, window_seconds + 1]
           ]) do
        {:ok, [count, _expire_result]} when is_integer(count) ->
          count

        _ ->
          1
      end
    rescue
      _ ->
        # Fallback to ETS if Redis fails
        increment_ets_counter(bucket_key, window_seconds)
    end
  end

  defp increment_ets_counter(bucket_key, _window_seconds) do
    table_name = :rate_limit_cache

    # Ensure ETS table exists
    unless :ets.whereis(table_name) != :undefined do
      :ets.new(table_name, [:named_table, :public, :set])
    end

    # Atomic increment
    case :ets.update_counter(table_name, bucket_key, {2, 1}, {bucket_key, 0}) do
      count when is_integer(count) -> count
      _ -> 1
    end
  end

  defp get_from_cache(key) do
    case get_cache_backend() do
      :redis ->
        get_from_redis(key)

      :ets ->
        get_from_ets(key)
    end
  end

  defp get_from_redis(key) do
    try do
      case Redix.command(Lang.Redis, ["GET", key]) do
        {:ok, nil} -> nil
        {:ok, value} -> String.to_integer(value)
        _ -> nil
      end
    rescue
      _ -> nil
    end
  end

  defp get_from_ets(key) do
    table_name = :rate_limit_cache

    case :ets.whereis(table_name) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(table_name, key) do
          [{^key, count}] -> count
          _ -> nil
        end
    end
  end

  defp delete_keys_by_pattern(pattern) do
    case get_cache_backend() do
      :redis ->
        delete_redis_pattern(pattern)

      :ets ->
        delete_ets_pattern(pattern)
    end
  end

  defp delete_redis_pattern(pattern) do
    try do
      case Redix.command(Lang.Redis, ["KEYS", pattern]) do
        {:ok, keys} when is_list(keys) ->
          if length(keys) > 0 do
            case Redix.command(Lang.Redis, ["DEL" | keys]) do
              {:ok, count} -> {:ok, count}
              _ -> {:error, "delete failed"}
            end
          else
            {:ok, 0}
          end

        _ ->
          {:error, "keys command failed"}
      end
    rescue
      error -> {:error, inspect(error)}
    end
  end

  defp delete_ets_pattern(pattern) do
    table_name = :rate_limit_cache

    case :ets.whereis(table_name) do
      :undefined ->
        {:ok, 0}

      _ ->
        # Convert Redis-style pattern to ETS match pattern
        # This is a simplified conversion - assumes pattern ends with *
        base_pattern = String.replace(pattern, "*", "")

        deleted =
          :ets.select_delete(table_name, [
            {{'$1', '_'},
             [{:"=:=", {:binary_part, '$1', 0, byte_size(base_pattern)}, base_pattern}], [true]}
          ])

        {:ok, deleted}
    end
  end
end
