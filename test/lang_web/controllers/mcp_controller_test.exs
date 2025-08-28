defmodule LangWeb.Api.V2.McpControllerTest do
  use LangWeb.ConnCase, async: false

  describe "MCP connect, list, disconnect" do
    test "connect -> list_active -> disconnect by connection_id", %{conn: conn} do
      user = Lang.Factory.create_user!()
      conn = Plug.Conn.assign(conn, :current_user, user)

      # Connect to filesystem MCP
      params = %{"server_type" => "filesystem", "config" => %{}, "session_id" => "test-session"}
      conn1 = post(conn, "/api/v2/mcp/connect", params)

      assert %{"connection_id" => connection_id, "stream_id" => stream_id} =
               json_response(conn1, 201)

      assert is_binary(connection_id)
      assert is_binary(stream_id)

      # List active
      conn2 = get(conn, "/api/v2/mcp/connections")
      %{"connections" => conns, "pool" => pool} = json_response(conn2, 200)
      assert length(conns) >= 1
      assert Enum.any?(conns, fn m -> m["connection_id"] == connection_id end)
      # Check enriched fields on first item
      item = Enum.find(conns, fn m -> m["connection_id"] == connection_id end)
      assert is_integer(item["request_count"]) and item["request_count"] >= 0
      assert is_integer(item["uptime_seconds"]) and item["uptime_seconds"] >= 0
      assert item["server_pid_masked"] =~ ~r/^pid-/
      assert item["health"] in ["healthy", "unhealthy", :healthy, :unhealthy]
      assert is_map(item["endpoints"]) and is_map(item["topics"])
      assert is_map(pool)

      # Disconnect by connection_id
      conn3 = delete(conn, "/api/v2/mcp/disconnect/#{connection_id}")
      assert %{"status" => "disconnected"} = json_response(conn3, 200)
    end

    test "status response includes enriched fields", %{conn: conn} do
      user = Lang.Factory.create_user!()
      conn = Plug.Conn.assign(conn, :current_user, user)

      params = %{"server_type" => "filesystem", "config" => %{}, "session_id" => "test-session"}
      conn1 = post(conn, "/api/v2/mcp/connect", params)
      %{"connection_id" => connection_id, "stream_id" => stream_id} = json_response(conn1, 201)

      conn2 = get(conn, "/api/v2/mcp/status/#{stream_id}")
      res = json_response(conn2, 200)
      assert res["connection_id"] == connection_id
      assert is_map(res["connection_status"])
      cs = res["connection_status"]
      assert cs["server_pid_masked"] =~ ~r/^pid-/
      assert cs["health"] in ["healthy", "unhealthy", :healthy, :unhealthy]
      assert is_map(res["pool"])
      assert is_map(res["endpoints"]) and is_map(res["topics"])
    end

    test "disconnect by stream_id returns connection_id and cleanup", %{conn: conn} do
      user = Lang.Factory.create_user!()
      conn = Plug.Conn.assign(conn, :current_user, user)

      params = %{"server_type" => "filesystem", "config" => %{}, "session_id" => "test-session"}
      conn1 = post(conn, "/api/v2/mcp/connect", params)
      %{"connection_id" => connection_id, "stream_id" => stream_id} = json_response(conn1, 201)

      conn2 = delete(conn, "/api/v2/mcp/disconnect/#{stream_id}")
      res = json_response(conn2, 200)
      assert res["stream_id"] == stream_id
      assert res["connection_id"] == connection_id
      assert res["status"] == "disconnected"
      assert res["cleanup"] == "complete"
    end
  end
end
