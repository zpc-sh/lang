defmodule Lang.Workers.BillingStripeUsageReporter do
  use Oban.Worker, queue: :billing, max_attempts: 5
  require Logger
  import Ash.Query

  @impl true
  def perform(%Oban.Job{args: args}) do
    org_id = args["organization_id"]
    now = DateTime.utc_now()
    last_hour_start = %{now | minute: 0, second: 0, microsecond: {0, 0}}
    last_hour_end = DateTime.add(last_hour_start, 3600, :second)

    # Get aggregates for the last hour
    agg =
      Lang.Billing.Aggregate
      |> Lang.AshHelpers.scope_to_org(org_id)
      |> filter(
        period_start == ^last_hour_start and period_end == ^last_hour_end and granularity == :hour
      )
      |> Ash.read_one()

    case agg do
      {:ok, %{total_mcp_connections: mcp} = a} ->
        # TODO: Integrate with Stripe usage records. For now, log.
        Logger.info("Stripe metered usage: org=#{org_id} mcp_connections=#{mcp}")
        {:ok, %{reported: true, value: mcp, aggregate_id: a.id}}

      _ ->
        Logger.info("No aggregate found for stripe usage reporting", organization_id: org_id)
        {:ok, %{reported: false}}
    end
  rescue
    e ->
      Logger.error("StripeUsageReporter failed", error: Exception.message(e))
      :error
  end
end
