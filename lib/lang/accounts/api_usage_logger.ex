defmodule Elixir.Lang.LSP.Lang.Lang.Metrics.Usage do
  @moduledoc "API usage statistics"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.metrics.usage"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # Extract usage parameters
    user_id = Map.get(ctx, "user_id") || Map.get(params, "user_id")
    method = Map.get(params, "method", "unknown")
    duration_ms = Map.get(params, "duration_ms", 0)
    tokens_used = Map.get(params, "tokens_used", 0)
    timestamp = Map.get(params, "timestamp", DateTime.utc_now())

    case user_id do
      nil ->
        {:error, "user_id is required"}

      user_id ->
        usage_data = %{
          user_id: user_id,
          method: method,
          duration_ms: duration_ms,
          tokens_used: tokens_used,
          timestamp: timestamp
        }

        # Log usage for analytics
        Logger.info("API usage recorded", usage_data)

        # Track event for billing and metrics
        Lang.Events.track_event(%{
          event_type: "api_call_made",
          user_id: user_id,
          metadata: usage_data
        })

        {:ok,
         %{
           logged: true,
           usage: usage_data
         }}
    end
  end
end
