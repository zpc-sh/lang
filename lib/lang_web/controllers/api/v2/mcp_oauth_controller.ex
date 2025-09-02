defmodule LangWeb.Api.V2.McpOAuthController do
  @moduledoc """
  OAuth Controller for MCP External Server Authentication.

  Handles OAuth 2.0 flows for connecting to external MCP servers,
  with full AshAuthentication integration for secure credential management.

  ## Features
  - OAuth authorization flow initiation
  - OAuth callback handling with state validation
  - Secure token storage and management
  - User consent management
  - MCP server-specific OAuth configurations

  ## Security Model
  - Requires AshAuthentication for all OAuth operations
  - CSRF protection via state parameters
  - Secure token storage using AshAuthentication
  - Comprehensive audit logging
  """

  use LangWeb, :controller
  use Phoenix.Controller

  alias Lang.MCP.OAuthIntegration
  alias Lang.Events
  alias LangWeb.AuthHelpers
  require Logger

  @doc """
  Initiate OAuth flow for MCP server connection.

  POST /api/v2/mcp/oauth/initiate

  Request body:
  {
    "server_type": "github",
    "scopes": ["repo", "read:user"],
    "redirect_uri": "https://app.example.com/oauth/callback"
  }

  Initiates OAuth authorization flow for connecting to external MCP server.
  """
  def initiate_oauth_flow(conn, params) do
    {conn, auth_session_id} = AuthHelpers.get_or_put_auth_session_id(conn)

    with {:ok, user} <- get_authenticated_user(conn),
         {:ok, oauth_config} <- validate_oauth_request(params),
         {:ok, flow_result} <- OAuthIntegration.initiate_oauth_flow(user.id, oauth_config.server_type, oauth_config) do

      # Log OAuth flow initiation
      Events.track_event(%{
        event_type: "mcp_oauth_flow_initiated_web",
        user_id: user.id,
        metadata: %{
          flow_id: flow_result.flow_id,
          server_type: oauth_config.server_type,
          scopes: oauth_config.scopes,
          auth_session_id: auth_session_id
        }
      })

      # Return authorization URL to client
      json(conn, %{
        "@context" => "https://lang.nulity.com/context/mcp",
        flow_id: flow_result.flow_id,
        authorization_url: flow_result.authorization_url,
        state: flow_result.state,
        server_type: oauth_config.server_type,
        expires_in: 600  # 10 minutes
      })

    else
      {:error, :not_authenticated} ->
        ApiError.json(conn, :unauthorized, "Authentication required for OAuth operations")

      {:error, {:missing_fields, fields}} ->
        ApiError.json(conn, :bad_request, "Missing required fields", %{missing_fields: fields})

      {:error, reason} ->
        Logger.warning("OAuth flow initiation failed", reason: reason, params: params)
        ApiError.json(conn, :internal_server_error, "Failed to initiate OAuth flow")
    end
  end

  @doc """
  Handle OAuth callback from external provider.

  GET /api/v2/mcp/oauth/callback

  Query parameters:
  - code: Authorization code from OAuth provider
  - state: State parameter for CSRF protection
  - flow_id: OAuth flow identifier

  Completes OAuth flow and stores tokens securely.
  """
  def oauth_callback(conn, %{"code" => authorization_code, "state" => state_param, "flow_id" => flow_id}) do
    with {:ok, user} <- get_authenticated_user(conn),
         {:ok, completion_result} <- OAuthIntegration.complete_oauth_flow(flow_id, authorization_code, state_param) do

      # Log successful OAuth completion
      Events.track_event(%{
        event_type: "mcp_oauth_flow_completed_web",
        user_id: user.id,
        metadata: %{
          flow_id: flow_id,
          server_type: completion_result.server_type,
          tokens_stored: completion_result.tokens_stored
        }
      })

      # Redirect to success page or return JSON response
      case get_req_header(conn, "accept") do
        ["application/json" | _] ->
          json(conn, %{
            "@context" => "https://lang.nulity.com/context/mcp",
            status: "success",
            server_type: completion_result.server_type,
            message: "OAuth authorization completed successfully",
            can_connect: true
          })

        _ ->
          # HTML redirect - in production, redirect to dashboard
          redirect(conn, to: "/dashboard?mcp_oauth_success=true&server_type=#{completion_result.server_type}")
      end

    else
      {:error, :not_authenticated} ->
        handle_oauth_error(conn, :unauthorized, "Authentication required")

      {:error, :invalid_flow_id} ->
        handle_oauth_error(conn, :bad_request, "Invalid OAuth flow ID")

      {:error, :invalid_state} ->
        handle_oauth_error(conn, :bad_request, "Invalid state parameter")

      {:error, {:token_exchange_failed, reason}} ->
        Logger.error("OAuth token exchange failed", reason: reason, flow_id: flow_id)
        handle_oauth_error(conn, :internal_server_error, "Failed to exchange authorization code for tokens")

      {:error, reason} ->
        Logger.warning("OAuth callback failed", reason: reason, flow_id: flow_id)
        handle_oauth_error(conn, :internal_server_error, "OAuth authorization failed")
    end
  end

  @doc """
  Connect to MCP server using stored OAuth tokens.

  POST /api/v2/mcp/oauth/connect

  Request body:
  {
    "server_type": "github",
    "connection_config": {...}
  }

  Establishes MCP connection using previously authorized OAuth tokens.
  """
  def connect_with_oauth(conn, params) do
    {conn, auth_session_id} = AuthHelpers.get_or_put_auth_session_id(conn)

    with {:ok, user} <- get_authenticated_user(conn),
         {:ok, server_type} <- get_required_param(params, "server_type"),
         {:ok, connection_config} <- get_optional_param(params, "connection_config", %{}),
         {:ok, connection_result} <- OAuthIntegration.connect_with_oauth(user.id, server_type, connection_config) do

      # Log successful OAuth-based connection
      Events.track_event(%{
        event_type: "mcp_oauth_connection_established",
        user_id: user.id,
        metadata: %{
          server_type: server_type,
          connection_id: connection_result,
          auth_session_id: auth_session_id
        }
      })

      json(conn, %{
        "@context" => "https://lang.nulity.com/context/mcp",
        status: "connected",
        server_type: server_type,
        connection_id: connection_result
      })

    else
      {:error, :not_authenticated} ->
        ApiError.json(conn, :unauthorized, "Authentication required")

      {:error, :oauth_required} ->
        ApiError.json(conn, :precondition_failed, "OAuth authorization required for this server type", %{
          action: "initiate_oauth_flow",
          server_type: params["server_type"]
        })

      {:error, {:token_refresh_failed, reason}} ->
        Logger.warning("OAuth token refresh failed", reason: reason, params: params)
        ApiError.json(conn, :unauthorized, "OAuth tokens expired and refresh failed", %{
          action: "initiate_oauth_flow",
          server_type: params["server_type"]
        })

      {:error, reason} ->
        Logger.warning("OAuth connection failed", reason: reason, params: params)
        ApiError.json(conn, :internal_server_error, "Failed to connect using OAuth")
    end
  end

  @doc """
  Get OAuth status for user and server type.

  GET /api/v2/mcp/oauth/status/:server_type

  Returns OAuth authorization status for the specified server type.
  """
  def oauth_status(conn, %{"server_type" => server_type}) do
    with {:ok, user} <- get_authenticated_user(conn) do
      case OAuthIntegration.get_oauth_tokens(user.id, server_type) do
        {:ok, tokens} ->
          # Check if tokens are still valid
          now = DateTime.utc_now()
          is_valid = DateTime.compare(tokens.expires_at, now) == :gt

          json(conn, %{
            "@context" => "https://lang.nulity.com/context/mcp",
            server_type: server_type,
            authorized: true,
            valid: is_valid,
            expires_at: tokens.expires_at,
            scopes: tokens.scopes,
            can_connect: is_valid
          })

        {:error, :no_tokens} ->
          json(conn, %{
            "@context" => "https://lang.nulity.com/context/mcp",
            server_type: server_type,
            authorized: false,
            can_connect: false,
            action_required: "initiate_oauth_flow"
          })

        {:error, reason} ->
          Logger.warning("Failed to get OAuth status", reason: reason, server_type: server_type)
          ApiError.json(conn, :internal_server_error, "Failed to get OAuth status")
      end

    else
      {:error, :not_authenticated} ->
        ApiError.json(conn, :unauthorized, "Authentication required")
    end
  end

  @doc """
  Revoke OAuth consent for MCP server.

  DELETE /api/v2/mcp/oauth/revoke/:server_type

  Removes stored OAuth tokens and revokes consent.
  """
  def revoke_oauth_consent(conn, %{"server_type" => server_type}) do
    with {:ok, user} <- get_authenticated_user(conn),
         :ok <- OAuthIntegration.revoke_oauth_consent(user.id, server_type) do

      # Log consent revocation
      Events.track_event(%{
        event_type: "mcp_oauth_consent_revoked_web",
        user_id: user.id,
        metadata: %{
          server_type: server_type
        }
      })

      json(conn, %{
        "@context" => "https://lang.nulity.com/context/mcp",
        status: "revoked",
        server_type: server_type,
        message: "OAuth consent revoked successfully"
      })

    else
      {:error, :not_authenticated} ->
        ApiError.json(conn, :unauthorized, "Authentication required")

      {:error, reason} ->
        Logger.warning("Failed to revoke OAuth consent", reason: reason, server_type: server_type)
        ApiError.json(conn, :internal_server_error, "Failed to revoke OAuth consent")
    end
  end

  @doc """
  List available OAuth-configured MCP servers.

  GET /api/v2/mcp/oauth/servers

  Returns list of MCP server types that support OAuth authentication.
  """
  def list_oauth_servers(conn, _params) do
    with {:ok, user} <- get_authenticated_user(conn) do
      # In production, this would query a configuration database
      # For now, return hardcoded list
      oauth_servers = [
        %{
          server_type: "github",
          name: "GitHub",
          description: "Connect to GitHub for repository and code analysis",
          scopes: ["repo", "read:user", "read:org"],
          icon: "github"
        },
        %{
          server_type: "gitlab",
          name: "GitLab",
          description: "Connect to GitLab for project and CI/CD integration",
          scopes: ["api", "read_user"],
          icon: "gitlab"
        },
        %{
          server_type: "bitbucket",
          name: "Bitbucket",
          description: "Connect to Bitbucket for repository management",
          scopes: ["repository", "account"],
          icon: "bitbucket"
        }
      ]

      # Add authorization status for each server
      servers_with_status = Enum.map(oauth_servers, fn server ->
        status = case OAuthIntegration.get_oauth_tokens(user.id, server.server_type) do
          {:ok, tokens} ->
            now = DateTime.utc_now()
            %{authorized: true, valid: DateTime.compare(tokens.expires_at, now) == :gt}

          _ ->
            %{authorized: false, valid: false}
        end

        Map.merge(server, status)
      end)

      json(conn, %{
        "@context" => "https://lang.nulity.com/context/mcp",
        servers: servers_with_status
      })

    else
      {:error, :not_authenticated} ->
        ApiError.json(conn, :unauthorized, "Authentication required")
    end
  end

  # Private functions

  defp validate_oauth_request(params) do
    with {:ok, server_type} <- get_required_param(params, "server_type"),
         {:ok, scopes} <- get_optional_param(params, "scopes", ["read"]),
         {:ok, redirect_uri} <- get_optional_param(params, "redirect_uri", default_redirect_uri()) do

      # Build OAuth configuration
      oauth_config = %{
        server_type: server_type,
        client_id: get_oauth_client_id(server_type),
        client_secret: get_oauth_client_secret(server_type),
        authorization_url: get_oauth_authorization_url(server_type),
        token_url: get_oauth_token_url(server_type),
        redirect_uri: redirect_uri,
        scopes: scopes
      }

      {:ok, oauth_config}

    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_required_param(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:missing_required_param, key}}
      value -> {:ok, value}
    end
  end

  defp get_optional_param(params, key, default) do
    {:ok, Map.get(params, key, default)}
  end

  defp get_authenticated_user(conn) do
    case conn.assigns[:current_user] do
      %{id: user_id} = user -> {:ok, user}
      nil -> {:error, :not_authenticated}
    end
  end

  defp handle_oauth_error(conn, status, message) do
    case get_req_header(conn, "accept") do
      ["application/json" | _] ->
        conn
        |> put_status(status_to_code(status))
        |> json(%{
          "@context" => "https://lang.nulity.com/context/mcp",
          error: message,
          status: status
        })

      _ ->
        # HTML error page - in production, show user-friendly error page
        conn
        |> put_status(status_to_code(status))
        |> put_view(LangWeb.ErrorView)
        |> render(:"#{status_to_code(status)}.html", %{message: message})
    end
  end

  defp status_to_code(:unauthorized), do: 401
  defp status_to_code(:bad_request), do: 400
  defp status_to_code(:internal_server_error), do: 500
  defp status_to_code(_), do: 500

  # Stub functions - in production, these would load from secure configuration
  defp get_oauth_client_id(server_type) do
    # This should load from secure configuration
    "mcp_#{server_type}_client_id"
  end

  defp get_oauth_client_secret(server_type) do
    # This should load from secure configuration
    "mcp_#{server_type}_client_secret"
  end

  defp get_oauth_authorization_url(server_type) do
    # This should load from configuration
    case server_type do
      "github" -> "https://github.com/login/oauth/authorize"
      "gitlab" -> "https://gitlab.com/oauth/authorize"
      "bitbucket" -> "https://bitbucket.org/site/oauth2/authorize"
      _ -> "https://#{server_type}.example.com/oauth/authorize"
    end
  end

  defp get_oauth_token_url(server_type) do
    # This should load from configuration
    case server_type do
      "github" -> "https://github.com/login/oauth/access_token"
      "gitlab" -> "https://gitlab.com/oauth/token"
      "bitbucket" -> "https://bitbucket.org/site/oauth2/access_token"
      _ -> "https://#{server_type}.example.com/oauth/token"
    end
  end

  defp default_redirect_uri do
    # This should load from configuration
    "https://lang.example.com/api/v2/mcp/oauth/callback"
  end
end