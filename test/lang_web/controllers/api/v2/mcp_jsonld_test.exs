defmodule LangWeb.Api.V2.MCPJSONLDTest do
  use LangWeb.ConnCase, async: true

  @ctx "https://lang.nulity.com/context/mcp"

  test "connections includes @context when JSON-LD negotiated", %{conn: conn} do
    user = Lang.Factory.create_user!()

    conn =
      conn
      |> Plug.Conn.assign(:current_user, user)
      |> Plug.Conn.put_req_header("accept", "application/ld+json")

    conn = get(conn, "/api/v2/mcp/connections")
    body = json_response(conn, 200)
    assert body["@context"] == @ctx
    assert is_list(body["connections"]) or body["connections"] == []
  end
end
