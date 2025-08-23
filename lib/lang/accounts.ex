defmodule Lang.Accounts do
  @moduledoc """
  The Accounts domain for LANG SaaS platform.

  Provides user management utilities and access to account-related resources.
  """

  use Ash.Domain

  alias Lang.Accounts.User

  resources do
    resource(Lang.Accounts.Organization)
    resource(Lang.Accounts.User)
    resource(Lang.Accounts.Token)
    resource(Lang.Accounts.APIUsage)
  end

  @doc """
  Creates a new user with generated API key
  """
  def create_user(attrs \\ %{}) do
    api_key = generate_api_key()

    attrs = Map.put(attrs, :api_key, api_key)

    case User.create(attrs) do
      {:ok, user} -> {:ok, %{user: user, api_key: api_key}}
      error -> error
    end
  end

  @doc """
  Regenerate API key for existing user
  """
  def regenerate_api_key(user) do
    new_api_key = generate_api_key()

    case User.update(user, %{api_key: new_api_key}) do
      {:ok, updated_user} -> {:ok, %{user: updated_user, api_key: new_api_key}}
      error -> error
    end
  end

  @doc """
  Generate a secure API key
  """
  def generate_api_key do
    "lang_" <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
  end

  @doc """
  Find user by API key
  """
  def get_user_by_api_key(api_key) do
    case User.read_all() do
      {:ok, users} ->
        case Enum.find(users, fn user -> user.api_key == api_key end) do
          nil -> {:error, :user_not_found}
          user -> {:ok, user}
        end

      error ->
        error
    end
  end

  @doc """
  Create a demo user for testing
  """
  def create_demo_user do
    attrs = %{
      email: "demo@lang-platform.com",
      name: "Demo User",
      organization_name: "Demo Organization",
      subscription_tier: :pro,
      monthly_request_limit: 10_000
    }

    create_user(attrs)
  end

  @doc """
  Upgrade user subscription tier
  """
  def upgrade_subscription(user, tier) when tier in [:free, :pro, :enterprise] do
    User.upgrade_subscription(user, %{subscription_tier: tier})
  end

  @doc """
  Check if user is over their monthly limit
  """
  def over_limit?(user) do
    user.monthly_request_count >= user.monthly_request_limit
  end

  @doc """
  Get usage percentage for user
  """
  def usage_percentage(user) do
    if user.monthly_request_limit > 0 do
      user.monthly_request_count / user.monthly_request_limit * 100
    else
      0.0
    end
  end

  @doc """
  Reset monthly usage for user (typically called monthly)
  """
  def reset_monthly_usage(user) do
    User.update(user, %{
      monthly_request_count: 0,
      last_request_reset: DateTime.utc_now()
    })
  end

  @doc """
  Deactivate user account
  """
  def deactivate_user(user) do
    User.update(user, %{is_active: false})
  end

  @doc """
  Reactivate user account
  """
  def reactivate_user(user) do
    User.update(user, %{is_active: true})
  end

  @doc """
  Get user statistics
  """
  def get_user_stats(user) do
    %{
      subscription_tier: user.subscription_tier,
      monthly_usage: user.monthly_request_count,
      monthly_limit: user.monthly_request_limit,
      usage_percentage: usage_percentage(user),
      days_until_reset: days_until_reset(user),
      is_active: user.is_active,
      organization: user.organization_name
    }
  end

  defp days_until_reset(user) do
    next_reset = DateTime.add(user.last_request_reset, 30, :day)
    DateTime.diff(next_reset, DateTime.utc_now(), :day)
  end
end
