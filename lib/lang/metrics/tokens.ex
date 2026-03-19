defmodule Lang.Metrics.Tokens do
  @moduledoc """
  Token consumption tracking (MVP).

  Provides a lightweight summary for token usage. In this MVP, we return
  request counts and placeholder token numbers while wiring a stable API
  surface for future provider-integrated token accounting.
  """

  alias Lang.Accounts.APIUsageLogger

  @type summary :: %{
          window: %{from: DateTime.t(), to: DateTime.t(), granularity: String.t()},
          totals: %{
            requests: non_neg_integer(),
            input_tokens: non_neg_integer(),
            output_tokens: non_neg_integer()
          },
          notes: String.t()
        }

  @doc """
  Return a token usage summary for a given scope.

  Params (strings or atoms accepted):
  - user_id: optional filter by user
  - project_id: optional project filter (reserved)
  - window: "month" | "day" (default: "month")
  """
  @spec summary(map()) :: {:ok, summary()} | {:error, term()}
  def summary(params \\ %{}) when is_map(params) do
    now = DateTime.utc_now()
    window = normalize_window(Map.get(params, "window") || Map.get(params, :window) || "month")
    {from, to, granularity} = window_bounds(window, now)

    user_id = Map.get(params, "user_id") || Map.get(params, :user_id)

    requests_count =
      case user_id do
        nil ->
          0

        uid ->
          case APIUsageLogger.current_month_count(uid) do
            {:ok, cnt} -> cnt
            _ -> 0
          end
      end

    # Placeholder tokens until provider instrumentation lands
    totals = %{requests: requests_count, input_tokens: 0, output_tokens: 0}

    {:ok,
     %{
       window: %{from: from, to: to, granularity: granularity},
       totals: totals,
       notes: "Token accounting is approximated; provider metrics pending"
     }}
  end

  defp normalize_window("day"), do: :day
  defp normalize_window("month"), do: :month
  defp normalize_window(:day), do: :day
  defp normalize_window(_), do: :month

  defp window_bounds(:day, now) do
    from = %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    to = %{now | hour: 23, minute: 59, second: 59}
    {from, to, "hour"}
  end

  defp window_bounds(:month, now) do
    from = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    to = now
    {from, to, "day"}
  end
end
