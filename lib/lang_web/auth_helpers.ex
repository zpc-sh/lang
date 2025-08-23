defmodule LangWeb.AuthHelpers do
  @moduledoc """
  Authentication helpers for LANG Universal Text Intelligence Platform.

  Provides consistent authentication utilities across controllers,
  LiveViews, and plugs for session management, user lookups, and
  authentication state handling.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Lang.Accounts.{User, Organization}
  alias Lang.Events
  require Logger

  @doc """
  Signs in a user by storing their ID in the session.
  """
  def sign_in_user(conn, user) do
    Events.track_event(%{
      event_type: "user_signed_in",
      user_id: user.id,
      metadata: %{
        ip_address: get_client_ip(conn),
        user_agent: get_req_header(conn, "user-agent") |> List.first()
      }
    })

    conn
    |> put_session(:current_user_id, user.id)
    |> assign(:current_user, user)
    |> assign(:authenticated?, true)
  end

  @doc """
  Signs out the current user by clearing the session.
  """
  def sign_out_user(conn) do
    user_id = get_session(conn, :current_user_id)

    if user_id do
      Events.track_event(%{
        event_type: "user_signed_out",
        user_id: user_id,
        metadata: %{
          ip_address: get_client_ip(conn)
        }
      })
    end

    conn
    |> clear_session()
    |> assign(:current_user, nil)
    |> assign(:current_org, nil)
    |> assign(:authenticated?, false)
  end

  @doc """
  Gets the current user from the connection assigns.
  """
  def current_user(conn) do
    conn.assigns[:current_user]
  end

  @doc """
  Gets the current organization from the connection assigns.
  """
  def current_org(conn) do
    conn.assigns[:current_org]
  end

  @doc """
  Checks if the current connection is authenticated.
  """
  def authenticated?(conn) do
    !!conn.assigns[:authenticated?] && !is_nil(conn.assigns[:current_user])
  end

  @doc """
  Loads a user by ID with their organization.
  Returns {:ok, user, org} or {:error, reason}.
  """
  def load_user_with_org(user_id) do
    import Ash.Query

    case User
         |> Ash.Query.filter(id == ^user_id)
         |> Ash.Query.load([:organization])
         |> Ash.read_one() do
      {:ok, %{organization: org} = user} when not is_nil(org) ->
        {:ok, user, org}

      {:ok, user} ->
        # User exists but no organization - create default
        case ensure_user_organization(user) do
          {:ok, org} -> {:ok, user, org}
          error -> error
        end

      {:error, _} = error ->
        error

      nil ->
        {:error, :user_not_found}
    end
  end

  @doc """
  Authenticates a user with email and password.
  Returns {:ok, user} or {:error, reason}.
  """
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    import Ash.Query

    case User
         |> Ash.Query.filter(email == ^email and active == true)
         |> Ash.read_one() do
      {:ok, user} ->
        if verify_password(password, user.password_hash) do
          Events.track_event(%{
            event_type: "user_login_success",
            user_id: user.id,
            metadata: %{email: email}
          })

          {:ok, user}
        else
          Events.track_event(%{
            event_type: "user_login_failed",
            user_id: user.id,
            metadata: %{
              email: email,
              reason: "invalid_password"
            }
          })

          {:error, :invalid_credentials}
        end

      nil ->
        # Still check password to prevent timing attacks
        Bcrypt.no_user_verify()

        Events.track_event(%{
          event_type: "user_login_failed",
          metadata: %{
            email: email,
            reason: "user_not_found"
          }
        })

        {:error, :invalid_credentials}

      {:error, reason} ->
        Logger.error("Error during authentication: #{inspect(reason)}")
        {:error, :authentication_error}
    end
  end

  @doc """
  Creates a new user account with email and password.
  Returns {:ok, user} or {:error, changeset}.
  """
  def create_user_account(attrs) do
    case User.create(attrs) do
      {:ok, user} ->
        Events.track_event(%{
          event_type: "user_account_created",
          user_id: user.id,
          metadata: %{
            email: user.email,
            name: user.name
          }
        })

        # Create default organization
        case ensure_user_organization(user) do
          {:ok, _org} ->
            {:ok, user}

          {:error, reason} ->
            Logger.warning("Failed to create organization for new user: #{inspect(reason)}")
            {:ok, user}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates user's last login timestamp and login count.
  """
  def update_user_login_info(user, ip_address \\ nil) do
    update_attrs = %{
      last_login_at: DateTime.utc_now(),
      login_count: (user.login_count || 0) + 1
    }

    update_attrs =
      if ip_address do
        Map.put(update_attrs, :last_login_ip, ip_address)
      else
        update_attrs
      end

    case User.update(user, update_attrs) do
      {:ok, updated_user} ->
        {:ok, updated_user}

      {:error, reason} ->
        Logger.warning("Failed to update user login info: #{inspect(reason)}")
        {:ok, user}
    end
  end

  @doc """
  Generates a secure API key for the user.
  """
  def generate_api_key(user, name \\ "Default API Key") do
    key = generate_secure_key()

    case Lang.Accounts.APIKey.create(%{
           user_id: user.id,
           name: name,
           key: key,
           status: :active,
           created_at: DateTime.utc_now(),
           last_used_at: nil,
           usage_count: 0
         }) do
      {:ok, api_key} ->
        Events.track_event(%{
          event_type: "api_key_created",
          user_id: user.id,
          metadata: %{
            api_key_name: name,
            api_key_id: api_key.id
          }
        })

        {:ok, api_key}

      {:error, reason} ->
        Logger.error("Failed to create API key: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Revokes an API key.
  """
  def revoke_api_key(api_key_id, user_id) do
    import Ash.Query

    case Lang.Accounts.APIKey
         |> Ash.Query.filter(id == ^api_key_id and user_id == ^user_id)
         |> Ash.read_one() do
      {:ok, api_key} ->
        case Lang.Accounts.APIKey.update(api_key, %{
               status: :revoked,
               revoked_at: DateTime.utc_now()
             }) do
          {:ok, revoked_key} ->
            Events.track_event(%{
              event_type: "api_key_revoked",
              user_id: user_id,
              metadata: %{
                api_key_id: api_key_id,
                api_key_name: api_key.name
              }
            })

            {:ok, revoked_key}

          {:error, reason} ->
            {:error, reason}
        end

      nil ->
        {:error, :api_key_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a user can access a resource based on their subscription tier.
  """
  def can_access_resource?(user, resource_type) do
    subscription_tier = user.subscription_tier || :free

    case {subscription_tier, resource_type} do
      # Free tier
      {:free, :basic_analysis} -> true
      {:free, :api_access} -> true
      {:free, _} -> false
      # Pro tier
      {:pro, :advanced_analysis} -> true
      {:pro, :priority_support} -> true
      {:pro, :webhook_integrations} -> true
      {:pro, _} -> true
      # Enterprise tier
      {:enterprise, _} -> true
      # Default deny
      _ -> false
    end
  end

  @doc """
  Gets user's current usage statistics.
  """
  def get_user_usage_stats(user_id) do
    # This would integrate with your usage tracking system
    %{
      api_calls_this_month: 0,
      analysis_sessions_this_month: 0,
      storage_used_mb: 0,
      last_activity: nil
    }
  end

  @doc """
  Sends password reset email.
  """
  def send_password_reset_email(email) do
    import Ash.Query

    case User
         |> Ash.Query.filter(email == ^email and active == true)
         |> Ash.read_one() do
      {:ok, user} ->
        reset_token = generate_secure_token()

        case User.update(user, %{
               password_reset_token: reset_token,
               password_reset_token_expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
             }) do
          {:ok, _updated_user} ->
            # Send email via your mailer
            Lang.Mailer.send_password_reset_email(user, reset_token)

            Events.track_event(%{
              event_type: "password_reset_requested",
              user_id: user.id,
              metadata: %{email: email}
            })

            {:ok, :email_sent}

          {:error, reason} ->
            {:error, reason}
        end

      nil ->
        # Don't reveal if email exists or not
        {:ok, :email_sent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions

  defp verify_password(password, hash) do
    Bcrypt.verify_pass(password, hash)
  end

  defp ensure_user_organization(user) do
    case user.organization_id do
      nil ->
        create_default_organization(user)

      org_id ->
        # Load existing organization
        import Ash.Query

        case Organization
             |> Ash.Query.filter(id == ^org_id)
             |> Ash.read_one() do
          {:ok, org} -> {:ok, org}
          _ -> create_default_organization(user)
        end
    end
  end

  defp create_default_organization(user) do
    org_name =
      if user.name && String.trim(user.name) != "" do
        "#{String.trim(user.name)}'s Organization"
      else
        "My Organization"
      end

    case Organization.create(%{
           name: org_name,
           owner_id: user.id,
           plan: :free,
           subscription_status: :trial,
           created_at: DateTime.utc_now()
         }) do
      {:ok, org} ->
        # Update user with organization_id
        User.update(user, %{organization_id: org.id})
        {:ok, org}

      {:error, reason} ->
        Logger.error("Failed to create default organization: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_secure_key do
    prefix = "lang_"
    random_part = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    "#{prefix}#{random_part}"
  end

  defp generate_secure_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] when is_binary(ip) ->
        ip |> String.split(",") |> List.first() |> String.trim()

      [] ->
        case conn.remote_ip do
          {a, b, c, d} ->
            "#{a}.#{b}.#{c}.#{d}"

          {a, b, c, d, e, f, g, h} ->
            parts = [a, b, c, d, e, f, g, h]

            parts
            |> Enum.map(&Integer.to_string(&1, 16))
            |> Enum.join(":")

          _ ->
            "unknown"
        end
    end
  end
end
