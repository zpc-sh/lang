defmodule LangWeb.Api.V2.McpOAuthControllerTest do
  use LangWeb.ConnCase, async: true
  use Lang.DataCase

  alias Lang.MCP.OAuthIntegration
  alias Lang.Accounts.User
  alias Lang.Repo

  setup do
    # Create test user
    {:ok, user} = %User{
      email: "oauth_controller_test@example.com",
      hashed_password: "hashed_password"
    } |> Repo.insert()

    # Start OAuthIntegration for testing
    {:ok, _pid} = OAuthIntegration.start_link([])

    # Create a valid JWT token for the user
    {:ok, token, _claims} = LangWeb.AuthToken.generate_and_sign(%{"user_id" => user.id})

    %{user: user, token: token}
  end

  describe "OAuth flow initiation" do
    test "POST /api/v2/mcp/oauth/initiate starts OAuth flow", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      params = %{
        "server_type" => "github",
        "scopes" => ["repo", "read:user"],
        "redirect_uri" => "https://app.example.com/oauth/callback"
      }

      conn = post(conn, "/api/v2/mcp/oauth/initiate", params)

      assert response(conn, 200)
      response_data = json_response(conn, 200)

      assert response_data["@context"] == "https://lang.nulity.com/context/mcp"
      assert is_binary(response_data["flow_id"])
      assert String.starts_with?(response_data["flow_id"], "oauth_flow_")
      assert String.contains?(response_data["authorization_url"], "github.com")
      assert is_binary(response_data["state"])
      assert response_data["server_type"] == "github"
      assert response_data["expires_in"] == 600
    end

    test "POST /api/v2/mcp/oauth/initiate requires authentication", %{conn: conn} do
      params = %{
        "server_type" => "github",
        "scopes" => ["repo"]
      }

      conn = post(conn, "/api/v2/mcp/oauth/initiate", params)

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required for OAuth operations"
    end

    test "POST /api/v2/mcp/oauth/initiate validates required fields", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # Missing server_type
      params = %{"scopes" => ["repo"]}

      conn = post(conn, "/api/v2/mcp/oauth/initiate", params)

      assert response(conn, 400)
      response_data = json_response(conn, 400)
      assert response_data["error"] == "Missing required fields"
      assert "server_type" in response_data["missing_fields"]
    end
  end

  describe "OAuth callback handling" do
    setup %{user: user} do
      # Set up an OAuth flow first
      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://github.com/login/oauth/authorize",
        token_url: "https://github.com/login/oauth/access_token",
        redirect_uri: "https://lang.example.com/oauth/callback",
        scopes: ["repo"]
      }

      {:ok, %{flow_id: flow_id, state: state}} =
        OAuthIntegration.initiate_oauth_flow(user.id, "github", oauth_config)

      %{user: user, flow_id: flow_id, state: state}
    end

    test "GET /api/v2/mcp/oauth/callback completes OAuth flow", %{conn: conn, token: token, flow_id: flow_id, state: state} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      conn = get(conn, "/api/v2/mcp/oauth/callback", %{
        "code" => "auth_code_123",
        "state" => state,
        "flow_id" => flow_id
      })

      assert response(conn, 200)
      response_data = json_response(conn, 200)

      assert response_data["@context"] == "https://lang.nulity.com/context/mcp"
      assert response_data["status"] == "success"
      assert response_data["server_type"] == "github"
      assert response_data["can_connect"] == true
    end

    test "GET /api/v2/mcp/oauth/callback requires authentication", %{conn: conn, flow_id: flow_id, state: state} do
      conn = get(conn, "/api/v2/mcp/oauth/callback", %{
        "code" => "auth_code_123",
        "state" => state,
        "flow_id" => flow_id
      })

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required"
    end

    test "GET /api/v2/mcp/oauth/callback validates state parameter", %{conn: conn, token: token, flow_id: flow_id} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      conn = get(conn, "/api/v2/mcp/oauth/callback", %{
        "code" => "auth_code_123",
        "state" => "invalid_state",
        "flow_id" => flow_id
      })

      assert response(conn, 400)
      response_data = json_response(conn, 400)
      assert response_data["error"] == "Invalid state parameter"
    end

    test "GET /api/v2/mcp/oauth/callback handles invalid flow ID", %{conn: conn, token: token, state: state} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      conn = get(conn, "/api/v2/mcp/oauth/callback", %{
        "code" => "auth_code_123",
        "state" => state,
        "flow_id" => "invalid_flow"
      })

      assert response(conn, 400)
      response_data = json_response(conn, 400)
      assert response_data["error"] == "Invalid OAuth flow ID"
    end
  end

  describe "OAuth connection establishment" do
    test "POST /api/v2/mcp/oauth/connect establishes connection with OAuth", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # First set up OAuth tokens
      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://github.com/login/oauth/authorize",
        token_url: "https://github.com/login/oauth/access_token",
        redirect_uri: "https://lang.example.com/oauth/callback",
        scopes: ["repo"]
      }

      {:ok, %{flow_id: flow_id, state: state}} =
        OAuthIntegration.initiate_oauth_flow(user.id, "github", oauth_config)

      OAuthIntegration.complete_oauth_flow(flow_id, "auth_code", state)

      # Now connect with OAuth
      params = %{
        "server_type" => "github",
        "connection_config" => %{"timeout" => 30000}
      }

      conn = post(conn, "/api/v2/mcp/oauth/connect", params)

      assert response(conn, 200)
      response_data = json_response(conn, 200)

      assert response_data["@context"] == "https://lang.nulity.com/context/mcp"
      assert response_data["status"] == "connected"
      assert response_data["server_type"] == "github"
      assert is_binary(response_data["connection_id"])
    end

    test "POST /api/v2/mcp/oauth/connect requires authentication", %{conn: conn} do
      params = %{
        "server_type" => "github"
      }

      conn = post(conn, "/api/v2/mcp/oauth/connect", params)

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required"
    end

    test "POST /api/v2/mcp/oauth/connect handles missing OAuth tokens", %{conn: conn, token: token} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      params = %{
        "server_type" => "github"
      }

      conn = post(conn, "/api/v2/mcp/oauth/connect", params)

      assert response(conn, 412) # Precondition Failed
      response_data = json_response(conn, 412)
      assert response_data["error"] == "OAuth authorization required for this server type"
      assert response_data["action"] == "initiate_oauth_flow"
    end
  end

  describe "OAuth status checking" do
    test "GET /api/v2/mcp/oauth/status/:server_type returns status", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      conn = get(conn, "/api/v2/mcp/oauth/status/github")

      assert response(conn, 200)
      response_data = json_response(conn, 200)

      assert response_data["@context"] == "https://lang.nulity.com/context/mcp"
      assert response_data["server_type"] == "github"
      assert response_data["authorized"] == false
      assert response_data["can_connect"] == false
      assert response_data["action_required"] == "initiate_oauth_flow"
    end

    test "GET /api/v2/mcp/oauth/status/:server_type shows authorized status", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # Set up OAuth tokens
      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://github.com/login/oauth/authorize",
        token_url: "https://github.com/login/oauth/access_token",
        redirect_uri: "https://lang.example.com/oauth/callback",
        scopes: ["repo"]
      }

      {:ok, %{flow_id: flow_id, state: state}} =
        OAuthIntegration.initiate_oauth_flow(user.id, "github", oauth_config)

      OAuthIntegration.complete_oauth_flow(flow_id, "auth_code", state)

      # Check status again
      conn = get(conn, "/api/v2/mcp/oauth/status/github")

      assert response(conn, 200)
      response_data = json_response(conn, 200)

      assert response_data["authorized"] == true
      assert response_data["can_connect"] == true
      assert %DateTime{} = response_data["expires_at"]
      assert response_data["scopes"] == ["repo"]
    end

    test "GET /api/v2/mcp/oauth/status/:server_type requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v2/mcp/oauth/status/github")

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required"
    end
  end

  describe "OAuth consent revocation" do
    test "DELETE /api/v2/mcp/oauth/revoke/:server_type revokes consent", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # First set up OAuth tokens
      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://github.com/login/oauth/authorize",
        token_url: "https://github.com/login/oauth/access_token",
        redirect_uri: "https://lang.example.com/oauth/callback",
        scopes: ["repo"]
      }

      {:ok, %{flow_id: flow_id, state: state}} =
        OAuthIntegration.initiate_oauth_flow(user.id, "github", oauth_config)

      OAuthIntegration.complete_oauth_flow(flow_id, "auth_code", state)

      # Revoke consent
      conn = delete(conn, "/api/v2/mcp/oauth/revoke/github")

      assert response(conn, 200)
      response_data = json_response(conn, 200)

      assert response_data["@context"] == "https://lang.nulity.com/context/mcp"
      assert response_data["status"] == "revoked"
      assert response_data["server_type"] == "github"
      assert response_data["message"] == "OAuth consent revoked successfully"
    end

    test "DELETE /api/v2/mcp/oauth/revoke/:server_type requires authentication", %{conn: conn} do
      conn = delete(conn, "/api/v2/mcp/oauth/revoke/github")

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required"
    end
  end

  describe "OAuth servers listing" do
    test "GET /api/v2/mcp/oauth/servers lists available servers", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      conn = get(conn, "/api/v2/mcp/oauth/servers")

      assert response(conn, 200)
      response_data = json_response(conn, 200)

      assert response_data["@context"] == "https://lang.nulity.com/context/mcp"
      assert is_list(response_data["servers"])

      # Check that we have the expected servers
      servers = response_data["servers"]
      assert length(servers) > 0

      # Check structure of first server
      first_server = List.first(servers)
      assert first_server["server_type"]
      assert first_server["name"]
      assert first_server["description"]
      assert is_list(first_server["scopes"])
      assert first_server["icon"]
      assert is_boolean(first_server["authorized"])
      assert is_boolean(first_server["valid"])
    end

    test "GET /api/v2/mcp/oauth/servers requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v2/mcp/oauth/servers")

      assert response(conn, 401)
      response_data = json_response(conn, 401)
      assert response_data["error"] == "Authentication required"
    end
  end

  describe "OAuth error handling" do
    test "handles token exchange failures gracefully", %{conn: conn, token: token, user: user} do
      conn = put_req_header(conn, "authorization", "Bearer #{token}")

      # Set up flow but don't complete it properly
      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://example.com/oauth",
        token_url: "https://example.com/token",
        redirect_uri: "https://example.com/callback",
        scopes: ["read"]
      }

      {:ok, %{flow_id: flow_id, state: state}} =
        OAuthIntegration.initiate_oauth_flow(user.id, "github", oauth_config)

      # Try to complete with invalid code
      conn = get(conn, "/api/v2/mcp/oauth/callback", %{
        "code" => "invalid_code",
        "state" => state,
        "flow_id" => flow_id
      })

      # Should handle the error gracefully
      assert response(conn, 500)
      response_data = json_response(conn, 500)
      assert response_data["error"] == "Failed to exchange authorization code for tokens"
    end
  end
end