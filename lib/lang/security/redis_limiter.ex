defmodule Lang.Security.RedisLimiter do
  @moduledoc """
  Redis-backed rate limiter for JSON-RPC methods and other operations.

  Uses a simple fixed-window counter per (api_key_id, method) with EXPIRE.
  Suitable for horizontal scaling and light contention.
  """

  alias Lang.Redis

  @default_limit 60
  @default_window 60

  @doc """
  Check if the call is allowed for the given api_key and method.
  Returns :ok or {:error, :rate_limited}.
  """
  def allow?(api_key_id, method) when is_binary(method) do
    {limit, window} = limits_for(method)
    now = System.system_time(:second)
    window_slot = div(now, window)
    key = "ratelimit:" <> to_string(api_key_id) <> ":" <> method <> ":" <> Integer.to_string(window_slot)

    case Redis.incr(key) do
      {:ok, count} when is_integer(count) ->
        # Set TTL when first seen
        if count == 1, do: Redis.expire(key, window)
        if count <= limit, do: :ok, else: {:error, :rate_limited}

      {:error, _} ->
        # Fail-open minimally but log upstream if desired
        :ok
    end
  end

  defp limits_for(method) do
    config = Application.get_env(:lang, :rpc_limits, %{})
    method_cfg = Map.get(config, method)

    case method_cfg do
      %{limit: l, window: w} when is_integer(l) and is_integer(w) and l > 0 and w > 0 -> {l, w}
      _ ->
        # sensible defaults per namespace
        cond do
          String.starts_with?(method, "lang.fs.") -> {300, 60}
          String.starts_with?(method, "lang.code.") -> {300, 60}
          String.starts_with?(method, "lang.analysis.") -> {120, 60}
          method in ["rpc.ping", "rpc.initialize", "rpc.shutdown"] -> {600, 60}
          true -> {@default_limit, @default_window}
        end
    end
  end
end

