defmodule Lang.Workers.BatchCostProcessor do
  @moduledoc """
  Processes a batch of AI requests with cost tracking and budget enforcement.

  Long-running batch work is executed via Oban.
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger
  alias Lang.Providers.Router, as: AIRouter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"requests" => requests} = args}) when is_list(requests) do
    org_id = args["organization_id"]
    user_id = args["user_id"]
    priority = map_priority(args["provider_optimization"]) || :balanced
    global_limit = args["limit"]

    # Process sequentially to respect per-org budgets; tune as needed
    Enum.reduce_while(requests, :ok, fn req, _acc ->
      method = req["method"] || "lang.chat.send_with_cost_tracking"
      params = req["params"] || %{}
      limit = req["cost_options"]["limit"] || global_limit

      with {true, bill} <- Lang.Billing.Service.can_make_request?(org_id),
           :ok <- preflight_cost(method, params, priority, limit) do
        case AIRouter.route_request(method, params, cost_priority: priority) do
          {:ok, result} ->
            Lang.Events.track_event(%{
              event_type: "ai_batch_item_processed",
              organization_id: org_id,
              user_id: user_id,
              metadata: %{method: method, remaining: bill[:remaining]}
            })
            {:cont, :ok}

          {:error, reason} ->
            Logger.warning("Batch item failed", reason: inspect(reason))
            {:halt, {:error, reason}}
        end
      else
        {false, info} -> {:halt, {:error, info}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{}), do: :discard

  defp preflight_cost(method, params, priority, nil), do: :ok
  defp preflight_cost(method, params, priority, limit) when is_number(limit) do
    provider = predicted_provider(priority)
    cost = AIRouter.estimate_cost(method, params, provider)
    if is_number(cost) and cost > limit, do: {:error, :budget_exceeded}, else: :ok
  end

  defp predicted_provider(:cost_first), do: :xai
  defp predicted_provider(:quality_first), do: :anthropic
  defp predicted_provider(_), do: :openai

  defp map_priority("cost_optimized"), do: :cost_first
  defp map_priority("quality_first"), do: :quality_first
  defp map_priority(_), do: :balanced
end

