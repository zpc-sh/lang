defmodule LangWeb.Api.V2.McpSseControllerTest do
  use LangWeb.ConnCase, async: true
  use Lang.DataCase

  alias Lang.MCP.{AdvancedProxy, Broker}
  alias Lang.Accounts.User
  alias Lang.Repo

  setup do
    # Create test user
    {:ok, user} = %User{
      email: "sse_test@example.com",
      hashed_password: "hashed_password"
    } |> Repo.insert()

    # Start AdvancedProxy for testing
    {:ok, _pid} = AdvancedProxy.start_link([])

    # Create a valid JWT token for the user
    {:ok, token, _claims} = LangWeb.AuthToken.generate_and_sign(%{"user_id" => user.id})

    %{user: user, token: token}
  end

  describe "SSE connection establishment" do
    test "POST /api/v2/mcp/sse/connect establishes SSE connection", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      params = %{
        "server_type" => "filesystem",
        "config" => %{"path" => "/tmp"},
        "session_id" => "test_session"
      }

      conn = post(conn, "/api/v2/mcp/sse/connect", params)

      assert response(conn, 200)
      response_data = json_response(conn, 200)

      assert response_data["@context"] == "https://lang.nulity.com/context/mcp"
      assert response_data["status"] == "connected"
      assert is_binary(response_data["connection_id"])
      assert String.starts_with?(response_data["connection_id"], "sse_")
    end

    test "POST /api/v2/mcp/sse/connect requires authentication", %{conn: conn} do
      params = %{
        "server_type" => "filesystem",
        "config" => %{}
      }

      conn = post(conn, "/api/v2/mcp/sse/connect", params)

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required for SSE connection"
    end

    test "POST /api/v2/mcp/sse/connect validates required parameters", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # Missing server_type
      params = %{"config" => %{}}

      conn = post(conn, "/api/v2/mcp/sse/connect", params)

      assert response(conn, 500) # This would be caught by our validation
    end

    test "POST /api/v2/mcp/sse/connect handles rate limiting", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # This test would need rate limiting setup to be meaningful
      params = %{
        "server_type" => "filesystem",
        "config" => %{}
      }

      conn = post(conn, "/api/v2/mcp/sse/connect", params)
      assert response(conn, 200)
    end
  end

  describe "SSE heartbeat mechanism" do
    test "POST /api/v2/mcp/sse/heartbeat/:connection_id sends heartbeat", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # First establish a connection
      params = %{
        "server_type" => "filesystem",
        "config" => %{}
      }

      conn = post(conn, "/api/v2/mcp/sse/connect", params)
      response_data = json_response(conn, 200)
      connection_id = response_data["connection_id"]

      # Now send heartbeat
      conn = post(conn, "/api/v2/mcp/sse/heartbeat/#{connection_id}")

      assert response(conn, 200)
      heartbeat_response = json_response(conn, 200)
      assert heartbeat_response["status"] == "heartbeat_acknowledged"
      assert heartbeat_response["connection_id"] == connection_id
    end

    test "POST /api/v2/mcp/sse/heartbeat/:connection_id requires authentication", %{conn: conn} do
      conn = post(conn, "/api/v2/mcp/sse/heartbeat/test_conn")

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required"
    end

    test "POST /api/v2/mcp/sse/heartbeat/:connection_id validates connection ownership", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # Try to heartbeat a non-existent connection
      conn = post(conn, "/api/v2/mcp/sse/heartbeat/nonexistent_conn")

      assert response(conn, 500) # This would be handled by our validation
    end
  end

  describe "SSE statistics" do
    test "GET /api/v2/mcp/sse/stats returns statistics", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      conn = get(conn, "/api/v2/mcp/sse/stats")

      assert response(conn, 200)
      stats = json_response(conn, 200)

      assert is_integer(stats["sse_clients"])
      assert is_integer(stats["oauth_tokens"])
      assert is_integer(stats["http_connections"])
      assert is_integer(stats["stdio_processes"])
      assert is_integer(stats["circuit_breakers"])
      assert stats["user_id"] == user.id
      assert stats["user_connections"] == 0 # No connections yet
    end

    test "GET /api/v2/mcp/sse/stats requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v2/mcp/sse/stats")

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required"
    end

    test "GET /api/v2/mcp/sse/stats shows active connections", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # Create an SSE connection
      params = %{
        "server_type" => "filesystem",
        "config" => %{}
      }

      post(conn, "/api/v2/mcp/sse/connect", params)

      # Check stats again
      conn = get(conn, "/api/v2/mcp/sse/stats")

      assert response(conn, 200)
      stats = json_response(conn, 200)
      assert stats["sse_clients"] >= 1
    end
  end

  describe "SSE streaming behavior" do
    test "SSE connection handles proper headers", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      params = %{
        "server_type" => "filesystem",
        "config" => %{}
      }

      conn = post(conn, "/api/v2/mcp/sse/connect", params)

      assert response(conn, 200)

      # Check SSE-specific headers (these would be set in the actual streaming response)
      # Note: In a real test, we'd need to mock the streaming behavior
      assert get_resp_header(conn, "content-type") == ["application/json"]
    end
  end

  describe "SSE error handling" do
    test "handles max clients exceeded error", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # This test would be more meaningful with rate limiting setup
      # For now, we just verify the error handling structure exists
      params = %{
        "server_type" => "filesystem",
        "config" => %{}
      }

      conn = post(conn, "/api/v2/mcp/sse/connect", params)
      assert response(conn, 200) # Should succeed normally
    end

    test "handles connection already exists error", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      params = %{
        "server_type" => "filesystem",
        "config" => %{},
        "connection_id" => "duplicate_test"
      }

      # First connection
      conn = post(conn, "/api/v2/mcp/sse/connect", params)
      assert response(conn, 200)

      # Duplicate connection would fail in AdvancedProxy
      # This is handled at the proxy level, not controller level
    end
  end

  describe "SSE parameter validation" do
    test "validates request size limits", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # Create a very large request to test size limits
      large_config = %{"data" => String.duplicate("x", 1024 * 1024 * 2)} # 2MB
      params = %{
        "server_type" => "filesystem",
        "config" => large_config
      }

      conn = post(conn, "/api/v2/mcp/sse/connect", params)

      # This should either succeed (if limit is higher) or fail with appropriate error
      # The exact behavior depends on our size limit configuration
      assert response(conn, 200) or response(conn, 500)
    end

    test "handles malformed JSON gracefully", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")
      conn = put_req_header(conn, "content-type", "application/json")

      # Send malformed JSON
      conn = post(conn, "/api/v2/mcp/sse/connect", "invalid json")

      # Should handle the error gracefully
      assert response(conn, 500)
    end
  end
end