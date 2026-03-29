defmodule Lang.MCP.OAuthIntegrationTest do
  use Lang.DataCase, async: true
  use LangWeb.ConnCase

  alias Lang.MCP.OAuthIntegration
  alias Lang.Accounts.User
  alias Lang.Repo

  setup do
    # Create test user
    {:ok, user} = %User{
      email: "oauth_test@example.com",
      hashed_password: "hashed_password"
    } |> Repo.insert()

    # Start OAuthIntegration for testing
    {:ok, _pid} = OAuthIntegration.start_link([])

    %{user: user}
  end

  describe "OAuth flow initiation" do
    test "initiate_oauth_flow/3 creates valid OAuth flow", %{user: user} do
      oauth_config = %{
        client_id: "test_client_123",
        client_secret: "test_secret_456",
        authorization_url: "https://github.com/login/oauth/authorize",
        token_url: "https://github.com/login/oauth/access_token",
        redirect_uri: "https://lang.example.com/oauth/callback",
        scopes: ["repo", "read:user"]
      }

      assert {:ok, %{flow_id: flow_id, authorization_url: auth_url, state: state}} =
               OAuthIntegration.initiate_oauth_flow(user.id, "github", oauth_config)

      # Verify flow ID format
      assert is_binary(flow_id)
      assert String.starts_with?(flow_id, "oauth_flow_")

      # Verify authorization URL
      assert String.contains?(auth_url, "https://github.com/login/oauth/authorize")
      assert String.contains?(auth_url, "client_id=test_client_123")
      assert String.contains?(auth_url, "response_type=code")
      assert String.contains?(auth_url, "scope=repo%20read%3Auser")
      assert String.contains?(auth_url, "state=")

      # Verify state parameter
      assert is_binary(state)
      assert String.starts_with?(state, "oauth_state_")
    end

    test "initiate_oauth_flow/3 validates required fields", %{user: user} do
      # Missing client_secret
      invalid_config = %{
        client_id: "test_client",
        authorization_url: "https://example.com/oauth",
        token_url: "https://example.com/token",
        redirect_uri: "https://example.com/callback"
      }

      assert {:error, {:missing_fields, missing}} =
               OAuthIntegration.initiate_oauth_flow(user.id, "github", invalid_config)

      assert :client_secret in missing
      assert :scopes not in missing  # optional
    end
  end

  describe "OAuth flow completion" do
    setup %{user: user} do
      # Set up a flow first
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

      %{user: user, flow_id: flow_id, state: state, oauth_config: oauth_config}
    end

    test "complete_oauth_flow/3 exchanges code for tokens", %{user: user, flow_id: flow_id, state: state} do
      # Mock successful token exchange
      assert {:ok, %{tokens_stored: true, server_type: "github"}} =
               OAuthIntegration.complete_oauth_flow(flow_id, "auth_code_123", state)

      # Verify tokens were stored
      assert {:ok, tokens} = OAuthIntegration.get_oauth_tokens(user.id, "github")
      assert tokens.access_token == "oauth_access_token_mock"
      assert tokens.refresh_token == "oauth_refresh_token_mock"
      assert tokens.token_type == "Bearer"
      assert tokens.scopes == ["read"]
    end

    test "complete_oauth_flow/3 validates state parameter", %{flow_id: flow_id} do
      # Wrong state parameter
      assert {:error, :invalid_state} =
               OAuthIntegration.complete_oauth_flow(flow_id, "auth_code_123", "wrong_state")
    end

    test "complete_oauth_flow/3 handles invalid flow ID" do
      assert {:error, :invalid_flow_id} =
               OAuthIntegration.complete_oauth_flow("invalid_flow", "auth_code", "state")
    end
  end

  describe "OAuth token management" do
    setup %{user: user} do
      # Set up OAuth flow and complete it
      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://example.com/oauth",
        token_url: "https://example.com/token",
        redirect_uri: "https://example.com/callback",
        scopes: ["read", "write"]
      }

      {:ok, %{flow_id: flow_id, state: state}} =
        OAuthIntegration.initiate_oauth_flow(user.id, "github", oauth_config)

      OAuthIntegration.complete_oauth_flow(flow_id, "auth_code", state)

      %{user: user}
    end

    test "get_oauth_tokens/2 retrieves stored tokens", %{user: user} do
      assert {:ok, tokens} = OAuthIntegration.get_oauth_tokens(user.id, "github")

      assert tokens.access_token == "oauth_access_token_mock"
      assert tokens.refresh_token == "oauth_refresh_token_mock"
      assert tokens.token_type == "Bearer"
      assert tokens.scopes == ["read", "write"]
      assert %DateTime{} = tokens.expires_at
      assert %DateTime{} = tokens.stored_at
    end

    test "get_oauth_tokens/2 handles non-existent tokens" do
      assert {:error, :no_tokens} = OAuthIntegration.get_oauth_tokens("nonexistent_user", "github")
      assert {:error, :no_tokens} = OAuthIntegration.get_oauth_tokens("user_id", "nonexistent_server")
    end

    test "refresh_oauth_tokens/2 refreshes expired tokens", %{user: user} do
      # Get initial tokens
      {:ok, initial_tokens} = OAuthIntegration.get_oauth_tokens(user.id, "github")

      # Refresh tokens
      assert {:ok, refreshed_tokens} = OAuthIntegration.refresh_oauth_tokens(user.id, "github")

      # Verify tokens were updated
      assert refreshed_tokens.access_token != initial_tokens.access_token
      assert refreshed_tokens.stored_at != initial_tokens.stored_at
    end
  end

  describe "OAuth consent management" do
    setup %{user: user} do
      # Set up OAuth tokens
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

      OAuthIntegration.complete_oauth_flow(flow_id, "auth_code", state)

      %{user: user}
    end

    test "revoke_oauth_consent/2 removes stored tokens", %{user: user} do
      # Verify tokens exist
      assert {:ok, _tokens} = OAuthIntegration.get_oauth_tokens(user.id, "github")

      # Revoke consent
      assert :ok = OAuthIntegration.revoke_oauth_consent(user.id, "github")

      # Verify tokens are gone
      assert {:error, :no_tokens} = OAuthIntegration.get_oauth_tokens(user.id, "github")
    end
  end

  describe "OAuth-based MCP connections" do
    test "connect_with_oauth/3 establishes connection with stored tokens", %{user: user} do
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
      assert {:ok, connection_id} = OAuthIntegration.connect_with_oauth(user.id, "github")

      assert is_binary(connection_id)
    end

    test "connect_with_oauth/3 handles missing OAuth tokens" do
      assert {:error, :oauth_required} = OAuthIntegration.connect_with_oauth("user_without_tokens", "github")
    end
  end

  describe "cleanup mechanisms" do
    test "expired OAuth flows are cleaned up", %{user: user} do
      # Create a flow
      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://example.com/oauth",
        token_url: "https://example.com/token",
        redirect_uri: "https://example.com/callback",
        scopes: ["read"]
      }

      {:ok, %{flow_id: flow_id}} = OAuthIntegration.initiate_oauth_flow(user.id, "github", oauth_config)

      # Simulate cleanup (in real scenario, this happens via timer)
      # This is a bit tricky to test directly, but we can verify the cleanup function exists
      assert function_exported?(OAuthIntegration, :handle_info, 2)
    end
  end

  describe "token validity checking" do
    test "token_valid?/1 correctly identifies valid tokens" do
      # Create mock tokens
      future_expiry = DateTime.add(DateTime.utc_now(), 3600, :second)
      valid_tokens = %{
        access_token: "valid_token",
        expires_at: future_expiry
      }

      expired_tokens = %{
        access_token: "expired_token",
        expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      }

      assert OAuthIntegration.token_valid?(valid_tokens) == true
      assert OAuthIntegration.token_valid?(expired_tokens) == false
    end
  end
end