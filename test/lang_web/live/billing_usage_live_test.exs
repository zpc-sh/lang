defmodule LangWeb.BillingUsageLiveTest do
  use LangWeb.ConnCase
  import Phoenix.LiveViewTest
  import Lang.Factory
  import Ash.Query

  test "renders usage summary and aggregates", %{conn: conn} do
    {:ok, data} = create_complete_user()
    org_id = data.organization.id

    # Seed aggregates for org
    now = DateTime.utc_now()

    {:ok, _} =
      Ash.create(Lang.Billing.Aggregate,
        organization_id: org_id,
        period_start: DateTime.beginning_of_day(now),
        period_end: now,
        granularity: :day,
        kind: :api_requests,
        total_requests: 7,
        total_content_size_bytes: 123
      )

    {:ok, _} =
      Ash.create(Lang.Billing.Aggregate,
        organization_id: org_id,
        period_start: DateTime.beginning_of_day(now),
        period_end: now,
        granularity: :day,
        kind: :mcp_connections,
        total_mcp_connections: 4
      )

    conn = authenticate_conn(conn, data.user)
    {:ok, _view, html} = live(conn, "/billing/usage")

    assert html =~ "Billing Usage"
    assert html =~ "API Requests"
    assert html =~ "MCP Connections"
  end

  test "filters by granularity and kind", %{conn: conn} do
    {:ok, data} = create_complete_user()
    conn = authenticate_conn(conn, data.user)

    {:ok, view, _html} = live(conn, "/billing/usage")

    # Change granularity and kind
    html =
      view
      |> form("#usage-filter-form", %{filters: %{granularity: "hour", kind: "mcp_connections"}})
      |> render_change()

    assert html =~ "Recent Aggregates"
  end
end
