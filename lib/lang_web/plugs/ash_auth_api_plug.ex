defmodule LangWeb.Plugs.AshAuthApiPlug do
  @moduledoc """
  AshAuthentication-compatible API authentication plug for LANG.

  This plug handles bearer token authentication for API routes using
  AshAuthentication tokens and API keys. It provides proper integration
  with the LANG authentication system.
  """

  import Plug.Conn
  alias Lang.Accounts.{User, ApiKey}
  alias Lang.Events
  require Logger

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, opts) do
    required = Keyword.get(opts, :required, true)

    case authenticate_request(conn) do
      {:ok, user, auth_type} ->
        conn
        |> assign(:current_user, user)
        |> assign(:current_org, user.organization)
        |> assign(:authenticated?, true)
        |> assign(:auth_type, auth_type)
        |> track_successful_auth(user, auth_type)

      {:error, reason} when required ->
        conn
        |> track_failed_auth(reason)
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "Unauthorized", reason: to_string(reason)})
        |> halt()

      {:error, _reason} ->
        # Optional auth - continue without user
        conn
        |> assign(:current_user, nil)
        |> assign(:current_org, nil)
        |> assign(:authenticated?, false)
    end
  end

  # Private functions

  defp authenticate_request(conn) do
    with {:ok, token} <- extract_token(conn),
         {:ok, user, auth_type} <- validate_token(token) do
      {:ok, user, auth_type}
    else
      error -> error
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        {:ok, token}

      ["bearer " <> token] ->
        {:ok, token}

      [token] when byte_size(token) > 0 ->
        {:ok, token}

      _ ->
        # Check for API key in query params as fallback
        case conn.query_params do
          %{"api_key" => key} when is_binary(key) -> {:ok, key}
          _ -> {:error, :missing_token}
        end
    end
  end

  defp validate_token(token) do
    cond do
      # Check if it's a LANG API key (starts with "lang_")
      String.starts_with?(token, "lang_") ->
        validate_api_key(token)

      # Check if it's an AshAuthentication JWT token
      String.contains?(token, ".") ->
        validate_jwt_token(token)

      # Assume it's an API key if it doesn't look like JWT
      true ->
        validate_api_key(token)
    end
  end

  defp validate_api_key(api_key) do
    import Ash.Query

    case ApiKey
         |> Ash.Query.filter(key == ^api_key and status == :active)
         |> Ash.Query.load([:user])
         |> Ash.read_one() do
      {:ok, %{user: user} = key} when not is_nil(user) ->
        # Update last used timestamp
        ApiKey.update(key, %{
          last_used_at: DateTime.utc_now(),
          usage_count: (key.usage_count || 0) + 1
        })

        {:ok, user, :api_key}

      {:ok, _key} ->
        {:error, :invalid_api_key}

      nil ->
        {:error, :api_key_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_jwt_token(jwt_token) do
    case AshAuthentication.Jwt.verify(jwt_token, otp_app: :lang) do
      {:ok, %{"sub" => user_id} = _claims} ->
        import Ash.Query

        case User
             |> Ash.Query.filter(id == ^user_id)
             |> Ash.Query.load([:organization])
             |> Ash.read_one() do
          {:ok, user} ->
            {:ok, user, :jwt_token}

          nil ->
            {:error, :user_not_found}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        Logger.debug("JWT validation failed: #{inspect(reason)}")
        {:error, :invalid_jwt_token}
    end
  end

  defp track_successful_auth(conn, user, auth_type) do
    Events.track_event(%{
      event_type: "api_authentication_success",
      user_id: user.id,
      organization_id: user.organization_id,
      metadata: %{
        auth_type: auth_type,
        ip_address: get_client_ip(conn),
        user_agent: get_req_header(conn, "user-agent") |> List.first(),
        endpoint: "#{conn.method} #{conn.request_path}"
      }
    })

    conn
  end

  defp track_failed_auth(conn, reason) do
    Events.track_event(%{
      event_type: "api_authentication_failed",
      metadata: %{
        reason: to_string(reason),
        ip_address: get_client_ip(conn),
        user_agent: get_req_header(conn, "user-agent") |> List.first(),
        endpoint: "#{conn.method} #{conn.request_path}"
      }
    })

    conn
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
