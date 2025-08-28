defmodule LangWeb.Api.V2.SpatialControllerTest do
  use LangWeb.ConnCase, async: true

  describe "traverse" do
    test "returns 400 when file is missing", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.assign(:current_user, %{id: "user-1"})
        |> get(~p"/api/v2/spatial/traverse/proj-1")

      assert json_response(conn, 400)["error"] =~ "file is required"
    end
  end

  describe "trace_path" do
    test "returns 400 when from/to missing", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.assign(:current_user, %{id: "user-1"})
        |> get(~p"/api/v2/spatial/trace_path/proj-1")

      # Controller returns 500 for generic errors and 400 for invalid_spec
      # Since both from/to are missing, expect 400 invalid_spec mapping
      assert json_response(conn, 400)["error"] =~ "required"
    end
  end
end

