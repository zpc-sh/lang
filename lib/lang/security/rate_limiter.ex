defmodule Lang.Security.RateLimiter do
  @moduledoc """
  Rate limiting for API endpoints and LSP requests
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def check_rate_limit(identifier, operation, options \\ %{}) do
    GenServer.call(__MODULE__, {:check_limit, identifier, operation, options})
  end

  def get_rate_limit_status(identifier, operation) do
    GenServer.call(__MODULE__, {:get_status, identifier, operation})
  end

  def reset_rate_limit(identifier, operation) do
    GenServer.call(__MODULE__, {:reset_limit, identifier, operation})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Rate Limiter")

    # Schedule cleanup of expired entries
    # Every minute
    Process.send_after(self(), :cleanup, 60_000)

    {:ok,
     %{
       requests: %{},
       blocks: %{},
       config: build_default_config(),
       stats: %{
         total_requests: 0,
         blocked_requests: 0,
         allowed_requests: 0
       }
     }}
  end

  @impl true
  def handle_call({:check_limit, identifier, operation, options}, _from, state) do
    now = System.system_time(:second)
    config = get_operation_config(state.config, operation)

    # Get or create bucket for this identifier+operation
    bucket_key = {identifier, operation}
    bucket = Map.get(state.requests, bucket_key, create_bucket(now, config))

    # Check if currently blocked
    if is_blocked?(state.blocks, bucket_key, now) do
      updated_stats = %{
        state.stats
        | total_requests: state.stats.total_requests + 1,
          blocked_requests: state.stats.blocked_requests + 1
      }

      {:reply, {:error, :rate_limited}, %{state | stats: updated_stats}}
    else
      # Check rate limit using token bucket algorithm
      {allowed, updated_bucket} = check_token_bucket(bucket, now, config)

      updated_requests = Map.put(state.requests, bucket_key, updated_bucket)

      if allowed do
        updated_stats = %{
          state.stats
          | total_requests: state.stats.total_requests + 1,
            allowed_requests: state.stats.allowed_requests + 1
        }

        {:reply, :ok, %{state | requests: updated_requests, stats: updated_stats}}
      else
        # Add to blocked list if configured
        updated_blocks = maybe_add_block(state.blocks, bucket_key, now, config)

        updated_stats = %{
          state.stats
          | total_requests: state.stats.total_requests + 1,
            blocked_requests: state.stats.blocked_requests + 1
        }

        Logger.warning("Rate limit exceeded",
          identifier: identifier,
          operation: operation,
          config: config
        )

        {:reply, {:error, :rate_limited},
         %{state | requests: updated_requests, blocks: updated_blocks, stats: updated_stats}}
      end
    end
  end

  @impl true
  def handle_call({:get_status, identifier, operation}, _from, state) do
    now = System.system_time(:second)
    bucket_key = {identifier, operation}
    config = get_operation_config(state.config, operation)

    case Map.get(state.requests, bucket_key) do
      nil ->
        status = %{
          remaining: config.limit,
          reset_time: now + config.window,
          blocked: false
        }

        {:reply, status, state}

      bucket ->
        blocked = is_blocked?(state.blocks, bucket_key, now)

        status = %{
          remaining: bucket.tokens,
          reset_time: bucket.last_refill + config.window,
          blocked: blocked,
          requests_made: config.limit - bucket.tokens
        }

        {:reply, status, state}
    end
  end

  @impl true
  def handle_call({:reset_limit, identifier, operation}, _from, state) do
    bucket_key = {identifier, operation}

    updated_requests = Map.delete(state.requests, bucket_key)
    updated_blocks = Map.delete(state.blocks, bucket_key)

    Logger.info("Reset rate limit", identifier: identifier, operation: operation)

    {:reply, :ok, %{state | requests: updated_requests, blocks: updated_blocks}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    detailed_stats = %{
      total_requests: state.stats.total_requests,
      allowed_requests: state.stats.allowed_requests,
      blocked_requests: state.stats.blocked_requests,
      block_rate: calculate_block_rate(state.stats),
      active_buckets: map_size(state.requests),
      active_blocks: map_size(state.blocks),
      operations: get_operation_stats(state.requests)
    }

    {:reply, detailed_stats, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:second)

    # Clean up expired buckets
    updated_requests =
      state.requests
      |> Enum.reject(fn {_key, bucket} ->
        # Remove buckets older than 1 hour
        now - bucket.last_refill > 3600
      end)
      |> Enum.into(%{})

    # Clean up expired blocks
    updated_blocks =
      state.blocks
      |> Enum.reject(fn {_key, block_info} ->
        now > block_info.expires_at
      end)
      |> Enum.into(%{})

    cleaned_buckets = map_size(state.requests) - map_size(updated_requests)
    cleaned_blocks = map_size(state.blocks) - map_size(updated_blocks)

    if cleaned_buckets > 0 or cleaned_blocks > 0 do
      Logger.debug("Cleaned up rate limiter",
        buckets: cleaned_buckets,
        blocks: cleaned_blocks
      )
    end

    # Schedule next cleanup
    Process.send_after(self(), :cleanup, 60_000)

    {:noreply, %{state | requests: updated_requests, blocks: updated_blocks}}
  end

  # Private helper functions

  defp build_default_config do
    %{
      # API endpoints
      # 100/hour
      "analyze" => %{limit: 100, window: 3600, block_duration: 300},
      # 50/hour
      "conversation" => %{limit: 50, window: 3600, block_duration: 300},

      # LSP operations (more permissive)
      # 1000/hour
      "completion" => %{limit: 1000, window: 3600, block_duration: 60},
      # 500/hour
      "hover" => %{limit: 500, window: 3600, block_duration: 60},
      # 200/hour
      "diagnostics" => %{limit: 200, window: 3600, block_duration: 60},

      # Default for unknown operations
      # 10/hour
      "default" => %{limit: 10, window: 3600, block_duration: 300}
    }
  end

  defp get_operation_config(config, operation) do
    Map.get(config, operation, config["default"])
  end

  defp create_bucket(now, config) do
    %{
      tokens: config.limit,
      last_refill: now,
      created_at: now
    }
  end

  defp check_token_bucket(bucket, now, config) do
    # Calculate token refill based on time passed
    time_passed = now - bucket.last_refill
    tokens_to_add = div(time_passed * config.limit, config.window)

    # Refill tokens (up to limit)
    new_tokens = min(bucket.tokens + tokens_to_add, config.limit)

    if new_tokens > 0 do
      # Allow request and consume one token
      updated_bucket = %{bucket | tokens: new_tokens - 1, last_refill: now}
      {true, updated_bucket}
    else
      # No tokens available
      updated_bucket = %{bucket | last_refill: now}
      {false, updated_bucket}
    end
  end

  defp is_blocked?(blocks, bucket_key, now) do
    case Map.get(blocks, bucket_key) do
      nil -> false
      block_info -> now < block_info.expires_at
    end
  end

  defp maybe_add_block(blocks, bucket_key, now, config) do
    if config.block_duration > 0 do
      block_info = %{
        blocked_at: now,
        expires_at: now + config.block_duration,
        reason: "Rate limit exceeded"
      }

      Map.put(blocks, bucket_key, block_info)
    else
      blocks
    end
  end

  defp calculate_block_rate(%{total_requests: 0}), do: 0.0

  defp calculate_block_rate(stats) do
    stats.blocked_requests / stats.total_requests * 100
  end

  defp get_operation_stats(requests) do
    requests
    |> Enum.group_by(fn {{_identifier, operation}, _bucket} -> operation end)
    |> Enum.map(fn {operation, buckets} ->
      {operation, length(buckets)}
    end)
    |> Enum.into(%{})
  end
end
