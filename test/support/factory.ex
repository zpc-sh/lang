defmodule Lang.Factory do
  @moduledoc """
  Test factory for creating test data using Ash resources.

  Provides helper functions to create Users, Organizations, API Keys,
  and other test data following LANG architecture guidelines.

  All factory functions use Ash resources directly, never raw Ecto.
  """

  alias Lang.Accounts.{User, Organization, ApiKey}
  alias Lang.Events
  require Logger

  @doc """
  Creates a test user with default attributes.

  ## Options
  - `:email` - User email (default: generated)
  - `:name` - User name (default: generated)
  - `:password` - User password (default: "password123")
  - `:confirmed_at` - Confirmation timestamp (default: now)
  - `:subscription_tier` - Subscription tier (default: "free")
  """
  def create_user(attrs \\ %{}) do
    email = attrs[:email] || "test#{System.unique_integer()}@example.com"
    name = attrs[:name] || "Test User #{System.unique_integer()}"
    password = attrs[:password] || "password123"

    default_attrs = %{
      email: email,
      name: name,
      password: password,
      confirmed_at: attrs[:confirmed_at] || DateTime.utc_now(),
      subscription_tier: attrs[:subscription_tier] || "free"
    }

    final_attrs = Map.merge(default_attrs, Map.new(attrs))

    case User.register_with_password(final_attrs) do
      {:ok, user} ->
        Logger.debug("Factory created user: #{user.email}")
        {:ok, user}

      {:error, error} ->
        Logger.error("Factory failed to create user: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates a test user and returns it directly (raises on error).
  """
  def create_user!(attrs \\ %{}) do
    case create_user(attrs) do
      {:ok, user} -> user
      {:error, error} -> raise "Failed to create user: #{inspect(error)}"
    end
  end

  @doc """
  Creates a test organization with default attributes.

  ## Options
  - `:name` - Organization name (default: generated)
  - `:owner_id` - Owner user ID (required)
  - `:subscription_tier` - Subscription tier (default: "free")
  - `:billing_email` - Billing email (default: uses owner email)
  """
  def create_organization(attrs \\ %{}) do
    unless attrs[:owner_id] do
      raise ArgumentError, "owner_id is required for organization creation"
    end

    name = attrs[:name] || "Test Org #{System.unique_integer()}"

    default_attrs = %{
      name: name,
      subscription_tier: attrs[:subscription_tier] || "free",
      billing_email: attrs[:billing_email] || "billing#{System.unique_integer()}@example.com",
      active: true
    }

    final_attrs = Map.merge(default_attrs, Map.new(attrs))

    case Organization.create(final_attrs) do
      {:ok, organization} ->
        Logger.debug("Factory created organization: #{organization.name}")
        {:ok, organization}

      {:error, error} ->
        Logger.error("Factory failed to create organization: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates a test organization and returns it directly (raises on error).
  """
  def create_organization!(attrs \\ %{}) do
    case create_organization(attrs) do
      {:ok, organization} -> organization
      {:error, error} -> raise "Failed to create organization: #{inspect(error)}"
    end
  end

  @doc """
  Creates a test API key with default attributes.

  ## Options
  - `:name` - API key name (default: generated)
  - `:user_id` - User ID (required)
  - `:organization_id` - Organization ID (required)
  - `:scopes` - API key scopes (default: ["read", "write"])
  - `:active` - Whether key is active (default: true)
  """
  def create_api_key(attrs \\ %{}) do
    unless attrs[:user_id] do
      raise ArgumentError, "user_id is required for API key creation"
    end

    unless attrs[:organization_id] do
      raise ArgumentError, "organization_id is required for API key creation"
    end

    name = attrs[:name] || "Test API Key #{System.unique_integer()}"

    default_attrs = %{
      name: name,
      scopes: attrs[:scopes] || ["read", "write"],
      active: attrs[:active] || true
    }

    final_attrs = Map.merge(default_attrs, Map.new(attrs))

    case ApiKey.create(final_attrs) do
      {:ok, api_key} ->
        Logger.debug("Factory created API key: #{api_key.name}")
        {:ok, api_key}

      {:error, error} ->
        Logger.error("Factory failed to create API key: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates a test API key and returns it directly (raises on error).
  """
  def create_api_key!(attrs \\ %{}) do
    case create_api_key(attrs) do
      {:ok, api_key} -> api_key
      {:error, error} -> raise "Failed to create API key: #{inspect(error)}"
    end
  end

  @doc """
  Creates a complete user with organization and API key setup.

  ## Options
  - All user creation options
  - `:organization_name` - Organization name override
  - `:api_key_name` - API key name override
  - `:subscription_tier` - Applied to both user and organization

  Returns: `{:ok, %{user: user, organization: organization, api_key: api_key}}`
  """
  def create_complete_user(attrs \\ %{}) do
    subscription_tier = attrs[:subscription_tier] || "free"

    # Create user
    user_attrs = Map.merge(attrs, %{subscription_tier: subscription_tier})

    case create_user(user_attrs) do
      {:ok, user} ->
        # Create organization
        org_attrs = %{
          owner_id: user.id,
          name: attrs[:organization_name] || "#{user.name}'s Organization",
          subscription_tier: subscription_tier,
          billing_email: user.email
        }

        case create_organization(org_attrs) do
          {:ok, organization} ->
            # Create API key
            api_key_attrs = %{
              user_id: user.id,
              organization_id: organization.id,
              name: attrs[:api_key_name] || "#{user.name}'s API Key"
            }

            case create_api_key(api_key_attrs) do
              {:ok, api_key} ->
                result = %{
                  user: user,
                  organization: organization,
                  api_key: api_key
                }

                Logger.debug("Factory created complete user setup for: #{user.email}")
                {:ok, result}

              {:error, error} ->
                Logger.error(
                  "Factory failed to create API key in complete setup: #{inspect(error)}"
                )

                {:error, error}
            end

          {:error, error} ->
            Logger.error(
              "Factory failed to create organization in complete setup: #{inspect(error)}"
            )

            {:error, error}
        end

      {:error, error} ->
        Logger.error("Factory failed to create user in complete setup: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates a complete user setup and returns it directly (raises on error).
  """
  def create_complete_user!(attrs \\ %{}) do
    case create_complete_user(attrs) do
      {:ok, result} -> result
      {:error, error} -> raise "Failed to create complete user: #{inspect(error)}"
    end
  end

  @doc """
  Creates multiple users for testing different subscription tiers.

  Returns: `{:ok, %{free: complete_user, professional: complete_user, enterprise: complete_user}}`
  """
  def create_tier_users do
    with {:ok, free_user} <-
           create_complete_user(%{
             email: "free@example.com",
             name: "Free User",
             subscription_tier: "free"
           }),
         {:ok, pro_user} <-
           create_complete_user(%{
             email: "pro@example.com",
             name: "Professional User",
             subscription_tier: "professional"
           }),
         {:ok, enterprise_user} <-
           create_complete_user(%{
             email: "enterprise@example.com",
             name: "Enterprise User",
             subscription_tier: "enterprise"
           }) do
      {:ok,
       %{
         free: free_user,
         professional: pro_user,
         enterprise: enterprise_user
       }}
    else
      {:error, error} ->
        Logger.error("Factory failed to create tier users: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates tier users and returns them directly (raises on error).
  """
  def create_tier_users! do
    case create_tier_users() do
      {:ok, users} -> users
      {:error, error} -> raise "Failed to create tier users: #{inspect(error)}"
    end
  end

  @doc """
  Creates sample events for testing.

  ## Options
  - `:user_id` - User ID for events (required)
  - `:organization_id` - Organization ID for events
  - `:count` - Number of events to create (default: 10)
  - `:event_types` - List of event types to create
  """
  def create_sample_events(attrs \\ %{}) do
    unless attrs[:user_id] do
      raise ArgumentError, "user_id is required for event creation"
    end

    count = attrs[:count] || 10
    user_id = attrs[:user_id]
    organization_id = attrs[:organization_id]

    event_types =
      attrs[:event_types] ||
        [
          "user_login_success",
          "user_login_failed",
          "api_call_made",
          "api_key_generated",
          "organization_created",
          "subscription_changed"
        ]

    events =
      for i <- 1..count do
        event_type = Enum.random(event_types)

        base_event = %{
          event_type: event_type,
          user_id: user_id,
          metadata: %{
            ip_address: "192.168.1.#{rem(i, 255)}",
            user_agent: "Test Agent #{i}",
            timestamp: DateTime.utc_now() |> DateTime.add(-i * 3600, :second)
          }
        }

        # Add organization_id if provided
        event =
          if organization_id do
            Map.put(base_event, :organization_id, organization_id)
          else
            base_event
          end

        case Events.track_event(event) do
          {:ok, event_record} ->
            Logger.debug("Factory created event: #{event_type}")
            {:ok, event_record}

          {:error, error} ->
            Logger.error("Factory failed to create event #{event_type}: #{inspect(error)}")
            {:error, error}
        end
      end

    # Separate successful and failed events
    {successful_events, errors} =
      Enum.split_with(events, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    if length(errors) > 0 do
      Logger.warning(
        "Factory created #{length(successful_events)}/#{count} events, #{length(errors)} failed"
      )
    end

    {:ok, Enum.map(successful_events, fn {:ok, event} -> event end)}
  end

  @doc """
  Creates sample events and returns them directly (raises on error).
  """
  def create_sample_events!(attrs \\ %{}) do
    case create_sample_events(attrs) do
      {:ok, events} -> events
      {:error, error} -> raise "Failed to create sample events: #{inspect(error)}"
    end
  end

  @doc """
  Helper to get a valid JWT token for a user (for API testing).
  """
  def get_user_token(user) do
    case AshAuthentication.user_to_token(user, %{}) do
      {:ok, token} ->
        Logger.debug("Factory generated token for user: #{user.email}")
        token

      {:error, error} ->
        Logger.error("Factory failed to generate token for user #{user.email}: #{inspect(error)}")
        raise "Failed to generate user token: #{inspect(error)}"
    end
  end

  @doc """
  Helper to authenticate a conn with a user (for controller testing).
  """
  def authenticate_conn(conn, user) do
    token = get_user_token(user)
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end

  @doc """
  Helper to authenticate a conn with an API key (for API testing).
  """
  def authenticate_conn_with_api_key(conn, api_key) do
    # Assuming API keys use the format "lang_" + key value
    key_value = api_key.key || "lang_test_#{System.unique_integer()}"
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{key_value}")
  end

  @doc """
  Cleans up all test data created by the factory.
  Useful for test cleanup.
  """
  def cleanup_test_data do
    # This would typically be handled by the SQL sandbox in tests,
    # but can be useful for manual cleanup in development
    Logger.debug("Factory cleanup requested - typically handled by SQL sandbox")
    :ok
  end
end
