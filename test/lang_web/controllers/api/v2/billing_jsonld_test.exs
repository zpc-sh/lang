defmodule LangWeb.Api.V2.BillingJSONLDTest do
  use LangWeb.ConnCase, async: true
  import Ash.Query

  @ctx "https://lang.nulity.com/context/billing"

  test "summary includes @context when JSON-LD negotiated", %{conn: conn} do
    org_id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    {:ok, _} =
      Ash.create(Lang.Billing.Aggregate,
        organization_id: org_id,
        period_start: DateTime.beginning_of_day(now),
        period_end: now,
        granularity: :day,
        kind: :api_requests,
        total_requests: 1
      )

    conn =
      conn
      |> Plug.Conn.assign(:current_org, %{id: org_id})
      |> Plug.Conn.put_req_header("accept", "application/ld+json")

    conn = get(conn, "/api/v2/billing/summary")
    body = json_response(conn, 200)
    assert body["@context"] == @ctx
  end

  test "MCP billing usage includes @context when JSON-LD negotiated", %{conn: conn} do
    user = Lang.Factory.create_user!()

    conn =
      conn
      |> Plug.Conn.assign(:current_user, user)
      |> Plug.Conn.put_req_header("accept", "application/ld+json")

    conn = get(conn, "/api/v2/mcp/billing/usage", %{period: "current_month"})
    body = json_response(conn, 200)
    assert body["@context"] == @ctx
  end
end

