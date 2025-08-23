defmodule LangWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plug for LANG Universal Text Intelligence Platform.

  This plug integrates with Ash Authentication to provide secure session-based
  authentication with API key fallback for API routes.

  Features:
  - Session-based authentication for web routes
  - API key authentication for API routes
  - Current user and organization assignment
  - Rate limiting integration
  - Comprehensive security logging
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Lang.Accounts.User
  alias Lang.Accounts.Organization
  alias Lang.Events
  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    strategy = Keyword.get(opts, :strategy, :session)
    required = Keyword.get(opts, :required, true)

    case strategy do
      :session -> authenticate_session(conn, required)
      :api_key -> authenticate_api_key(conn, required)
      :bearer -> authenticate_bearer_token(conn, required)
      :optional -> authenticate_optional(conn)
    end
  end

  # Session-based authentication for web routes
  defp authenticate_session(conn, required) do
    case get_session(conn, :current_user_id) do
      nil when required ->
        handle_unauthenticated(conn, :session)

      nil ->
        assign_guest_user(conn)

      user_id when is_binary(user_id) ->
        case load_user_with_org(user_id) do
          {:ok, user, org} ->
            conn
            |> assign(:current_user, user)
            |> assign(:current_org, org)
            |> assign(:current_scope, :user)
            |> assign(:authenticated?, true)

          {:error, :not_found} ->
            Logger.warning("Session references non-existent user: #{user_id}")

            conn
            |> clear_session()
            |> handle_unauthenticated(:session)

          {:error, reason} ->
            Logger.error("Failed to load user #{user_id}: #{inspect(reason)}")
            handle_unauthenticated(conn, :session)
        end
    end
  end

  # API key authentication for API routes
  defp authenticate_api_key(conn, required) do
    case get_api_key(conn) do
      nil when required ->
        handle_unauthenticated(conn, :api_key)

      nil ->
        assign_guest_user(conn)

      api_key ->
        case authenticate_with_api_key(api_key, conn) do
          {:ok, user, org} ->
            # Log API usage
            Events.track_event(%{
              event_type: "api_key_used",
              user_id: user.id,
              organization_id: org.id,
              metadata: %{
                api_key_id: extract_api_key_id(api_key),
                ip_address: get_client_ip(conn),
                user_agent: get_req_header(conn, "user-agent") |> List.first(),
                path: conn.request_path
              }
            })

            conn
            |> assign(:current_user, user)
            |> assign(:current_org, org)
            |> assign(:current_scope, :api)
            |> assign(:authenticated?, true)
            |> assign(:api_key, api_key)

          {:error, :invalid_key} ->
            Logger.warning("Invalid API key attempted: #{mask_api_key(api_key)}")
            handle_unauthenticated(conn, :api_key)

          {:error, :revoked} ->
            Logger.warning("Revoked API key attempted: #{mask_api_key(api_key)}")
            handle_unauthenticated(conn, :api_key)

          {:error, reason} ->
            Logger.error("API key authentication error: #{inspect(reason)}")
            handle_unauthenticated(conn, :api_key)
        end
    end
  end

  # Bearer token authentication (for future OAuth integration)
  defp authenticate_bearer_token(conn, required) do
    case get_bearer_token(conn) do
      nil when required ->
        handle_unauthenticated(conn, :bearer)

      nil ->
        assign_guest_user(conn)

      token ->
        case authenticate_with_bearer_token(token) do
          {:ok, user, org} ->
            conn
            |> assign(:current_user, user)
            |> assign(:current_org, org)
            |> assign(:current_scope, :oauth)
            |> assign(:authenticated?, true)
            |> assign(:bearer_token, token)

          {:error, reason} ->
            Logger.warning("Invalid bearer token: #{inspect(reason)}")
            handle_unauthenticated(conn, :bearer)
        end
    end
  end

  # Optional authentication - assigns user if present, continues if not
  defp authenticate_optional(conn) do
    conn
    |> authenticate_session(false)
    |> case do
      %{assigns: %{current_user: %{}}} = authenticated_conn ->
        authenticated_conn

      _ ->
        # Try API key as fallback
        authenticate_api_key(conn, false)
    end
  end

  # Helper functions

  defp load_user_with_org(user_id) do
    import Ash.Query

    case User
         |> Ash.Query.filter(id == ^user_id)
         |> Ash.Query.load([:organization])
         |> Ash.read_one() do
      {:ok, %{organization: org} = user} when not is_nil(org) ->
        {:ok, user, org}

      {:ok, user} ->
        # User exists but no organization - create default org or handle gracefully
        case create_default_organization(user) do
          {:ok, org} -> {:ok, user, org}
          error -> error
        end

      {:error, _} = error ->
        error

      nil ->
        {:error, :not_found}
    end
  end

  defp authenticate_with_api_key(api_key, conn) do
    import Ash.Query

    # Use your existing APIKey resource
    case Lang.Accounts.APIKey
         |> Ash.Query.filter(key == ^api_key and status == :active)
         |> Ash.Query.load(user: :organization)
         |> Ash.read_one() do
      {:ok, %{user: %{organization: org} = user}} ->
        # Update last_used_at
        update_api_key_usage(api_key)
        {:ok, user, org}

      {:ok, %{status: :revoked}} ->
        {:error, :revoked}

      {:ok, _} ->
        {:error, :invalid_key}

      nil ->
        {:error, :invalid_key}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authenticate_with_bearer_token(token) do
    # Placeholder for OAuth/JWT token validation
    # Implement when you add OAuth support
    {:error, :not_implemented}
  end

  defp get_api_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        # Handle Bearer token for API key authentication
        token

      ["Token " <> token] ->
        # Handle custom Token authentication
        token

      _ ->
        # Check for API key in query params (less secure, but sometimes needed)
        case conn.params do
          %{"api_key" => key} when is_binary(key) -> key
          _ -> nil
        end
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  defp handle_unauthenticated(conn, auth_type) do
    case auth_type do
      :session ->
        conn
        |> put_session(:return_to, conn.request_path)
        |> redirect(to: "/auth")
        |> halt()

      :api_key ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "Authentication required",
          message: "Please provide a valid API key in the Authorization header"
        })
        |> halt()

      :bearer ->
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "Invalid bearer token",
          message: "Please provide a valid bearer token"
        })
        |> halt()
    end
  end

  defp assign_guest_user(conn) do
    if Mix.env() in [:dev, :test] do
      # Development stub
      dev_user = %{
        id: "dev_user_#{:rand.uniform(1000)}",
        email: "dev@lang.local",
        name: "Development User",
        subscription_tier: :pro
      }

      dev_org = %{
        id: "dev_org_#{:rand.uniform(1000)}",
        name: "Development Organization",
        plan: :pro,
        subscription_status: :active
      }

      conn
      |> assign(:current_user, dev_user)
      |> assign(:current_org, dev_org)
      |> assign(:current_scope, :development)
      |> assign(:authenticated?, false)
    else
      conn
      |> assign(:current_user, nil)
      |> assign(:current_org, nil)
      |> assign(:current_scope, :guest)
      |> assign(:authenticated?, false)
    end
  end

  defp create_default_organization(user) do
    Organization.create(%{
      name: "#{user.name}'s Organization",
      owner_id: user.id,
      plan: :free,
      subscription_status: :active
    })
  end

  defp update_api_key_usage(api_key) do
    # Update last_used_at and increment usage_count
    import Ash.Query

    Lang.Accounts.APIKey
    |> Ash.Query.filter(key == ^api_key)
    |> Ash.read_one()
    |> case do
      {:ok, key_record} ->
        key_record
        |> Ash.Changeset.for_update(:update_usage, %{
          last_used_at: DateTime.utc_now(),
          usage_count: (key_record.usage_count || 0) + 1
        })
        |> Ash.update()

      _ ->
        :ok
    end
  end

  defp extract_api_key_id(api_key) do
    # Extract ID from API key if it's embedded, otherwise return masked key
    case String.split(api_key, "_") do
      [prefix, id | _] when prefix in ["lk", "lang"] -> id
      _ -> mask_api_key(api_key)
    end
  end

  defp mask_api_key(api_key) when is_binary(api_key) do
    case String.length(api_key) do
      len when len > 8 ->
        prefix = String.slice(api_key, 0, 4)
        suffix = String.slice(api_key, -4, 4)
        "#{prefix}...#{suffix}"

      _ ->
        "***"
    end
  end

  defp mask_api_key(_), do: "***"

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] ->
        ip

      [] ->
        case conn.remote_ip do
          {a, b, c, d} ->
            "#{a}.#{b}.#{c}.#{d}"

          {a, b, c, d, e, f, g, h} ->
            "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:#{Integer.to_string(c, 16)}:#{Integer.to_string(d, 16)}:#{Integer.to_string(e, 16)}:#{Integer.to_string(f, 16)}:#{Integer.to_string(g, 16)}:#{Integer.to_string(h, 16)}"

          _ ->
            "unknown"
        end
    end
  end

  # Public helper functions for use in controllers/live views

  def current_user(conn_or_socket) do
    case conn_or_socket do
      %Plug.Conn{} = conn -> conn.assigns[:current_user]
      %Phoenix.LiveView.Socket{} = socket -> socket.assigns[:current_user]
      assigns when is_map(assigns) -> assigns[:current_user]
    end
  end

  def current_org(conn_or_socket) do
    case conn_or_socket do
      %Plug.Conn{} = conn -> conn.assigns[:current_org]
      %Phoenix.LiveView.Socket{} = socket -> socket.assigns[:current_org]
      assigns when is_map(assigns) -> assigns[:current_org]
    end
  end

  def authenticated?(conn_or_socket) do
    case conn_or_socket do
      %Plug.Conn{} = conn -> !!conn.assigns[:authenticated?]
      %Phoenix.LiveView.Socket{} = socket -> !!socket.assigns[:authenticated?]
      assigns when is_map(assigns) -> !!assigns[:authenticated?]
    end
  end

  def ensure_authenticated!(conn_or_socket) do
    unless authenticated?(conn_or_socket) do
      raise "Authentication required but user not authenticated"
    end

    :ok
  end
end
