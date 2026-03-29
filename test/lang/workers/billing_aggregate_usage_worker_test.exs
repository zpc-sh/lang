defmodule Lang.Workers.BillingAggregateUsageWorkerTest do
  use Lang.DataCase, async: true
  import Ash.Query

  test "aggregates events and usage records" do
    org_id = Ecto.UUID.generate()
    user_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    # Seed an API usage event
    {:ok, _} =
      Ash.create(Lang.Events.ApiUsageEvent,
        user_id: user_id,
        organization_id: org_id,
        operation_type: :text_analysis,
        success: true,
        content_size: 42,
        inserted_at: now
      )

    # Seed a metered usage record
    {:ok, _} =
      Ash.create(Lang.Billing.UsageRecord,
        organization_id: org_id,
        kind: "mcp_connection",
        occurred_at: now
      )

    # Run worker
    job = %Oban.Job{args: %{"organization_id" => org_id, "granularity" => "hour"}}
    assert {:ok, _} = Lang.Workers.BillingAggregateUsageWorker.perform(job)

    # Assert an hourly aggregate exists for org
    {:ok, agg} =
      Lang.Billing.Aggregate
      |> filter(organization_id == ^org_id and granularity == :hour)
      |> Ash.read_one()

    assert agg.total_requests >= 1
    assert agg.total_mcp_connections >= 1
  end
end
