defmodule LangWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plug for LANG Universal Text Intelligence Platform.

  This module provides session-based and bearer token authentication
  for both web and API routes, integrating with AshAuthentication.
  """

  import Plug.Conn
  require Logger

  alias Lang.Accounts.{User, Organization}
  alias Lang.Events

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, :load_from_session) do
    load_from_session(conn, [])
  end

  def call(conn, :load_from_bearer) do
    load_from_bearer(conn, [])
  end

  def call(conn, opts) do
    strategy = Keyword.get(opts, :strategy, :session)

    case strategy do
      :session -> load_from_session(conn, opts)
      :bearer -> load_from_bearer(conn, opts)
      :api_key -> load_from_api_key(conn, opts)
      _ -> conn
    end
  end

  @doc """
  Loads user from session and assigns to conn.
  """
  def load_from_session(conn, _opts) do
    with user_token when not is_nil(user_token) <- get_session(conn, "user_token"),
         {:ok, user} <- authenticate_session_token(user_token) do
      assign_user_context(conn, user)
    else
      _ ->
        # Try fallback with user_id
        case get_session(conn, "user_id") do
          nil ->
            conn

          user_id ->
            case load_user_by_id(user_id) do
              {:ok, user} ->
                assign_user_context(conn, user)

              {:error, _reason} ->
                conn
                |> delete_session("user_id")
                |> delete_session("user_token")
            end
        end
    end
  end

  @doc """
  Loads user from bearer token and assigns to conn.
  """
  def load_from_bearer(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- authenticate_bearer_token(token) do
      assign_user_context(conn, user)
    else
      [] ->
        # No authorization header
        conn

      [api_key] ->
        # Try API key authentication
        authenticate_and_assign_api_key(conn, api_key)

      {:error, _reason} ->
        conn
    end
  end

  @doc """
  Loads user from API key in authorization header.
  """
  def load_from_api_key(conn, _opts) do
    with [auth_header] <- get_req_header(conn, "authorization"),
         {:ok, user} <- authenticate_api_key(auth_header) do
      assign_user_context(conn, user)
    else
      _ ->
        # Check query params as fallback
        case Map.get(conn.params, "api_key") do
          nil -> conn
          api_key -> authenticate_and_assign_api_key(conn, api_key)
        end
    end
  end

  @doc """
  Stores user in session with proper token management.
  """
  def store_in_session(conn, user) do
    # Generate session token
    case AshAuthentication.Jwt.token_for_user(user) do
      {:ok, token, _claims} ->
        conn
        |> put_session("user_id", user.id)
        |> put_session("user_token", token)
        |> put_session("user_email", user.email)

      {:error, reason} ->
        Logger.warning("Failed to generate session token: #{inspect(reason)}")

        conn
        |> put_session("user_id", user.id)
        |> put_session("user_email", user.email)
    end
  end

  # Private helper functions

  defp assign_user_context(conn, user) do
    org = load_user_organization(user)

    conn
    |> assign(:current_user, user)
    |> assign(:current_org, org)
    |> assign(:current_scope, %{type: :user, id: user.id})
    |> assign(:authenticated?, true)
  end

  defp authenticate_session_token(token) do
    case AshAuthentication.Jwt.verify(token, Lang.Accounts.User) do
      {:ok, %{"sub" => subject}} ->
        case AshAuthentication.subject_to_user(subject, Lang.Accounts.User) do
          {:ok, user} -> {:ok, load_user_with_associations(user)}
          error -> error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authenticate_bearer_token(token) do
    case AshAuthentication.Jwt.verify(token, Lang.Accounts.User) do
      {:ok, %{"sub" => subject}} ->
        case AshAuthentication.subject_to_user(subject, Lang.Accounts.User) do
          {:ok, user} -> {:ok, load_user_with_associations(user)}
          error -> error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authenticate_api_key(api_key) do
    # Remove "Bearer " prefix if present
    cleaned_key = String.replace_prefix(api_key, "Bearer ", "")

    require Ash.Query

    case Lang.Accounts.ApiKey
         |> Ash.Query.filter(key == ^cleaned_key and status == :active)
         |> Ash.Query.load([:user])
         |> Ash.read_one() do
      {:ok, %{user: user}} when not is_nil(user) ->
        # Update last used timestamp
        Lang.Accounts.ApiKey.update(%{id: api_key.id}, %{last_used_at: DateTime.utc_now()})
        {:ok, load_user_with_associations(user)}

      _ ->
        {:error, :invalid_api_key}
    end
  rescue
    _ ->
      {:error, :api_key_lookup_failed}
  end

  defp authenticate_and_assign_api_key(conn, api_key) do
    case authenticate_api_key(api_key) do
      {:ok, user} ->
        # Track API key usage
        Events.track_event(%{
          event_type: "api_key_used",
          user_id: user.id,
          metadata: %{
            ip_address: get_client_ip(conn),
            path: conn.request_path
          }
        })

        assign_user_context(conn, user)

      {:error, _reason} ->
        conn
    end
  end

  defp load_user_with_associations(user) do
    case User.by_id(user.id) |> Ash.Query.load([:organization]) |> Ash.read_one() do
      {:ok, loaded_user} -> loaded_user
      _ -> user
    end
  end

  defp load_user_by_id(user_id) do
    require Ash.Query

    case User
         |> Ash.Query.filter(id == ^user_id)
         |> Ash.Query.load([:organization])
         |> Ash.read_one() do
      {:ok, user} -> {:ok, user}
      {:error, error} -> {:error, error}
      nil -> {:error, :not_found}
    end
  end

  defp load_user_organization(%{organization: org}) when not is_nil(org), do: org

  defp load_user_organization(%{organization_id: org_id}) when is_binary(org_id) do
    require Ash.Query

    case Organization
         |> Ash.Query.filter(id == ^org_id)
         |> Ash.read_one() do
      {:ok, org} -> org
      _ -> create_default_organization_for_user(%{id: org_id})
    end
  end

  defp load_user_organization(user) do
    create_default_organization_for_user(user)
  end

  defp create_default_organization_for_user(user) do
    case Organization.create(%{
           name: "#{Map.get(user, :name, "User")}'s Organization",
           owner_id: user.id,
           plan: :free,
           subscription_status: :trial
         }) do
      {:ok, org} -> org
      _ -> nil
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] when is_binary(ip) ->
        ip |> String.split(",") |> List.first() |> String.trim()

      [] ->
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          _ -> "unknown"
        end
    end
  end
end
