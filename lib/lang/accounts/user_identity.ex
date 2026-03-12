defmodule Lang.Accounts.UserIdentity do
  @moduledoc """
  User Identity resource for tracking OAuth providers and external authentication sources.

  This resource stores information about how users authenticate with the platform,
  supporting multiple OAuth providers per user (GitHub, Google, Apple, etc.).
  """

  use Ash.Resource,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.UserIdentity]

  postgres do
    table("user_identities")
    repo(Lang.Repo)
  end

  user_identity do
    user_resource(Lang.Accounts.User)
  end

  # The UserIdentity extension automatically defines the required attributes:
  # - uid (string, required)
  # - strategy (string, required)
  # - access_token (map, sensitive)
  # - user_id (uuid, required, references User)
  # - timestamps

  # Additional custom attributes can be added here if needed
  attributes do
    # Custom attributes for additional OAuth provider data
    attribute(:provider_email, :string, public?: true)
    attribute(:provider_name, :string, public?: true)
    attribute(:provider_username, :string, public?: true)
    attribute(:avatar_url, :string, public?: true)
    attribute(:raw_user_info, :map, public?: true)
  end

  actions do
    defaults([:read])

    create :upsert do
      argument(:user_info, :map, allow_nil?: false)
      argument(:oauth_tokens, :map, allow_nil?: false)
      argument(:user_id, :uuid, allow_nil?: false)
      upsert?(true)
      upsert_identity(:unique_on_strategy_and_uid_and_user_id)
      change(AshAuthentication.UserIdentity.UpsertIdentityChange)
    end
  end

  identities do
    identity(:unique_on_strategy_and_uid_and_user_id, [:strategy, :uid, :user_id])
  end

  code_interface do
    domain(Lang.Accounts)
    define(:read)
    define(:upsert, action: :upsert)
  end
end
