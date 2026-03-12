defmodule LangWeb.Api.V2.BillingUsageControllerTest do
  use LangWeb.ConnCase, async: true
  import Ash.Query

  test "/api/v2/billing/aggregates returns data", %{conn: conn} do
    org_id = Ecto.UUID.generate()
    # Seed minimal aggregates
    {:ok, _} =
      Ash.create(Lang.Billing.Aggregate,
        organization_id: org_id,
        period_start: DateTime.add(DateTime.utc_now(), -3600, :second),
        period_end: DateTime.utc_now(),
        granularity: :hour,
        kind: :api_requests,
        total_requests: 5
      )

    conn = Plug.Conn.assign(conn, :current_org, %{id: org_id})
    conn = get(conn, "/api/v2/billing/aggregates")
    assert json_response(conn, 200)["aggregates"] |> is_list()
  end

  test "/api/v2/billing/summary returns month summary", %{conn: conn} do
    org_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    {:ok, _} =
      Ash.create(Lang.Billing.Aggregate,
        organization_id: org_id,
        period_start: DateTime.beginning_of_day(now),
        period_end: now,
        granularity: :day,
        kind: :api_requests,
        total_requests: 3,
        total_content_size_bytes: 100
      )

    {:ok, _} =
      Ash.create(Lang.Billing.Aggregate,
        organization_id: org_id,
        period_start: DateTime.beginning_of_day(now),
        period_end: now,
        granularity: :day,
        kind: :mcp_connections,
        total_mcp_connections: 2
      )

    conn = Plug.Conn.assign(conn, :current_org, %{id: org_id})
    conn = get(conn, "/api/v2/billing/summary")
    body = json_response(conn, 200)
    assert body["totals"]["api_requests"] >= 3
    assert body["totals"]["mcp_connections"] >= 2
  end
end
