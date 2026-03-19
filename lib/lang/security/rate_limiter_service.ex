defmodule Lang.Security.RateLimiter do
  @moduledoc """
  Rate limiter for LANG LSP system operations.

  Provides rate limiting capabilities for:
  - API requests per user/organization
  - LSP method calls
  - Resource-intensive operations
  - Abuse prevention

  Uses multiple strategies:
  - Fixed window counters
  - Token bucket algorithm
  - Sliding window for burst handling
  """

  use GenServer
  require Logger

  @type limit_key :: String.t()
  @type limit_result :: :ok | {:error, :rate_limited} | {:error, term()}
  @type limit_config :: %{
          max_requests: pos_integer(),
          window_seconds: pos_integer(),
          burst_allowance: pos_integer()
        }

  # Default rate limits
  @default_limits %{
    "api_request" => %{max_requests: 100, window_seconds: 60, burst_allowance: 10},
    "lsp_method" => %{max_requests: 1000, window_seconds: 60, burst_allowance: 50},
    "analysis_heavy" => %{max_requests: 10, window_seconds: 60, burst_allowance: 2},
    "file_upload" => %{max_requests: 20, window_seconds: 60, burst_allowance: 5},
    "search_query" => %{max_requests: 200, window_seconds: 60, burst_allowance: 20}
  }

  # ETS table for storing rate limit counters
  @table_name :lang_rate_limits

  # =============================================================================
  # Public API
  # =============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a request is allowed under rate limiting rules.
  """
  @spec check(String.t(), String.t()) :: limit_result()
  def check(user_id, operation) when is_binary(user_id) and is_binary(operation) do
    GenServer.call(__MODULE__, {:check_rate_limit, user_id, operation})
  end

  @doc """
  Check rate limit with custom configuration.
  """
  @spec check_with_config(String.t(), String.t(), limit_config()) :: limit_result()
  def check_with_config(user_id, operation, config) do
    GenServer.call(__MODULE__, {:check_rate_limit_custom, user_id, operation, config})
  end

  @doc """
  Check API key rate limits.
  """
  @spec check_api_key(String.t(), String.t()) :: limit_result()
  def check_api_key(api_key_id, operation) do
    GenServer.call(__MODULE__, {:check_api_key_limit, api_key_id, operation})
  end

  @doc """
  Get current usage statistics for a user.
  """
  @spec get_usage(String.t(), String.t()) :: %{
          used: non_neg_integer(),
          limit: pos_integer(),
          reset_at: DateTime.t()
        }
  def get_usage(user_id, operation) do
    GenServer.call(__MODULE__, {:get_usage, user_id, operation})
  end

  @doc """
  Reset rate limits for a user (admin function).
  """
  @spec reset_limits(String.t()) :: :ok
  def reset_limits(user_id) do
    GenServer.call(__MODULE__, {:reset_limits, user_id})
  end

  @doc """
  Configure custom limits for operations.
  """
  @spec configure_limits(map()) :: :ok
  def configure_limits(limits) when is_map(limits) do
    GenServer.call(__MODULE__, {:configure_limits, limits})
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl GenServer
  def init(opts) do
    table_opts = [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ]

    case :ets.info(@table_name) do
      :undefined ->
        :ets.new(@table_name, table_opts)

      _ ->
        # Table already exists
        :ok
    end

    # Start cleanup timer
    schedule_cleanup()

    custom_limits = Keyword.get(opts, :limits, %{})
    limits = Map.merge(@default_limits, custom_limits)

    state = %{
      limits: limits,
      # 5 minutes
      cleanup_interval: Keyword.get(opts, :cleanup_interval, 300_000)
    }

    Logger.info("Rate limiter started", limits: Map.keys(limits))
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:check_rate_limit, user_id, operation}, _from, state) do
    limit_config = Map.get(state.limits, operation, @default_limits["api_request"])
    result = check_rate_limit_impl(user_id, operation, limit_config)
    {:reply, result, state}
  end

  def handle_call({:check_rate_limit_custom, user_id, operation, config}, _from, state) do
    result = check_rate_limit_impl(user_id, operation, config)
    {:reply, result, state}
  end

  def handle_call({:check_api_key_limit, api_key_id, operation}, _from, state) do
    # API keys get slightly higher limits
    base_config = Map.get(state.limits, operation, @default_limits["api_request"])
    api_config = %{base_config | max_requests: base_config.max_requests * 2}

    key = "api_key:#{api_key_id}"
    result = check_rate_limit_impl(key, operation, api_config)
    {:reply, result, state}
  end

  def handle_call({:get_usage, user_id, operation}, _from, state) do
    limit_config = Map.get(state.limits, operation, @default_limits["api_request"])
    usage = get_usage_impl(user_id, operation, limit_config)
    {:reply, usage, state}
  end

  def handle_call({:reset_limits, user_id}, _from, state) do
    reset_limits_impl(user_id)
    {:reply, :ok, state}
  end

  def handle_call({:configure_limits, new_limits}, _from, state) do
    updated_limits = Map.merge(state.limits, new_limits)
    Logger.info("Rate limits updated", new_operations: Map.keys(new_limits))
    {:reply, :ok, %{state | limits: updated_limits}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # =============================================================================
  # Rate Limiting Implementation
  # =============================================================================

  defp check_rate_limit_impl(user_id, operation, config) do
    now = System.system_time(:second)
    window_start = now - config.window_seconds
    key = rate_limit_key(user_id, operation)

    # Get current counter
    current_count =
      case :ets.lookup(@table_name, key) do
        [{^key, count, timestamp}] when timestamp >= window_start ->
          count

        _ ->
          0
      end

    # Check if within limits
    if current_count < config.max_requests do
      # Increment counter
      :ets.insert(@table_name, {key, current_count + 1, now})

      Logger.debug("Rate limit check passed",
        user_id: user_id,
        operation: operation,
        count: current_count + 1,
        limit: config.max_requests
      )

      :ok
    else
      # Check burst allowance
      burst_key = "#{key}:burst"

      burst_count =
        case :ets.lookup(@table_name, burst_key) do
          [{^burst_key, count, timestamp}] when timestamp >= window_start ->
            count

          _ ->
            0
        end

      if burst_count < config.burst_allowance do
        :ets.insert(@table_name, {burst_key, burst_count + 1, now})

        Logger.warning("Rate limit burst allowance used",
          user_id: user_id,
          operation: operation,
          burst_count: burst_count + 1,
          burst_limit: config.burst_allowance
        )

        :ok
      else
        Logger.warning("Rate limit exceeded",
          user_id: user_id,
          operation: operation,
          count: current_count,
          limit: config.max_requests
        )

        {:error, :rate_limited}
      end
    end
  end

  defp get_usage_impl(user_id, operation, config) do
    now = System.system_time(:second)
    window_start = now - config.window_seconds
    key = rate_limit_key(user_id, operation)

    used =
      case :ets.lookup(@table_name, key) do
        [{^key, count, timestamp}] when timestamp >= window_start ->
          count

        _ ->
          0
      end

    reset_at = DateTime.from_unix!(window_start + config.window_seconds)

    %{
      used: used,
      limit: config.max_requests,
      reset_at: reset_at,
      window_seconds: config.window_seconds
    }
  end

  defp reset_limits_impl(user_id) do
    pattern = {rate_limit_key(user_id, :_), :_, :_}
    :ets.match_delete(@table_name, pattern)

    Logger.info("Rate limits reset for user", user_id: user_id)
  end

  defp rate_limit_key(user_id, operation) do
    "rate_limit:#{user_id}:#{operation}"
  end

  # =============================================================================
  # Cleanup and Maintenance
  # =============================================================================

  defp schedule_cleanup do
    # 5 minutes
    Process.send_after(self(), :cleanup, 300_000)
  end

  defp cleanup_expired_entries do
    now = System.system_time(:second)
    # Remove entries older than 1 hour
    cutoff = now - 3600

    # This is a simple cleanup - in production you might want something more sophisticated
    all_keys = :ets.select(@table_name, [{{:"$1", :_, :"$3"}, [{:<, :"$3", cutoff}], [:"$1"]}])

    Enum.each(all_keys, fn key ->
      :ets.delete(@table_name, key)
    end)

    if length(all_keys) > 0 do
      Logger.debug("Cleaned up expired rate limit entries", count: length(all_keys))
    end
  end

  # =============================================================================
  # Utility Functions
  # =============================================================================

  @doc """
  Check rate limit and return remaining requests info.
  """
  def check_rate_limit(user_id, rate_limit_key) do
    case check(user_id, rate_limit_key) do
      :ok ->
        usage = get_usage(user_id, rate_limit_key)
        {:ok, usage}

      {:error, :rate_limited} = error ->
        error
    end
  end

  @doc """
  Helper for common LSP method rate limiting.
  """
  def check_lsp_method(user_id, method_name) do
    operation =
      case method_name do
        method when method in ["textDocument/completion", "textDocument/hover"] ->
          "lsp_fast"

        method when method in ["textDocument/definition", "textDocument/references"] ->
          "lsp_medium"

        _ ->
          "lsp_method"
      end

    check(user_id, operation)
  end

  @doc """
  Get all configured rate limits.
  """
  def get_configured_limits do
    GenServer.call(__MODULE__, :get_limits)
  end

  @impl GenServer
  def handle_call(:get_limits, _from, state) do
    {:reply, state.limits, state}
  end
end
