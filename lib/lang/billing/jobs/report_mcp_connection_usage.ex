defmodule Lang.Billing.Jobs.ReportMcpConnectionUsage do
  @moduledoc """
  Oban job to report MCP connection usage to Stripe as a metered usage record.
  """

  use Oban.Worker, queue: :billing, max_attempts: 5
  require Logger

  alias Lang.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"organization_id" => org_id, "connection_id" => conn_id, "timestamp" => ts}
      }) do
    price_id = System.get_env("STRIPE_MCP_CONNECTION_PRICE_ID")

    if is_nil(price_id) or price_id == "" do
      Logger.info("MCP connection pricing not configured, skipping billing")
      :ok
    else
      with {:ok, org} <- Accounts.get_organization(org_id),
           {:ok, sub_item_id} <- get_subscription_item_id(org, price_id),
           {:ok, _} <- create_usage_record(sub_item_id, ts) do
        Logger.info("Reported MCP connection usage", connection_id: conn_id)
        :ok
      else
        {:error, reason} ->
          Logger.error("Failed to report MCP usage", reason: reason)
          {:error, reason}
      end
    end
  end

  defp get_subscription_item_id(org, price_id) do
    # Find the subscription item for this price
    case Stripe.Subscription.retrieve(org.stripe_subscription_id, %{expand: ["items"]}) do
      {:ok, %{items: %{data: items}}} ->
        item = Enum.find(items, fn item -> item.price.id == price_id end)
        if item, do: {:ok, item.id}, else: {:error, :price_not_found}

      error ->
        error
    end
  end

  defp create_usage_record(subscription_item_id, timestamp) do
    Stripe.UsageRecord.create(subscription_item_id, %{
      quantity: 1,
      timestamp: parse_timestamp(timestamp),
      action: "increment"
    })
  end

  defp ensure_org_subscription(%{stripe_subscription_id: sub_id}) when is_binary(sub_id),
    do: {:ok, sub_id}

  defp ensure_org_subscription(_), do: {:error, :no_subscription}

  # Backwards-compatible timestamp parsing
  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> System.os_time(:second)
    end
  end

  defp parse_timestamp(_), do: System.os_time(:second)

  # Legacy name kept in case other calls refer to it
  defp parse_ts(ts), do: parse_timestamp(ts)
end
