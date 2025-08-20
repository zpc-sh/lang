defmodule Lang.Accounts.User do
  @moduledoc """
  User resource for authentication and account management.

  This module defines the core User resource with authentication capabilities,
  subscription management, and API usage tracking.
  """

  use Ash.Resource,
    domain: Lang.Accounts,
    extensions: [
      AshAuthentication,
      AshPostgres.DataLayer
    ]

  postgres do
    table("users")
    repo(Lang.Repo)
  end

  # Authentication configuration
  authentication do
    strategies do
      password :password do
        identity_field(:email)
        hashed_password_field(:hashed_password)
        hash_provider(AshAuthentication.BcryptProvider)
        confirmation_required?(true)
      end
    end

    tokens do
      enabled?(true)
      token_resource(Lang.Accounts.Token)
      signing_secret(Lang.Secrets)
    end

    session_identifier(:jti)
  end

  # Resource attributes
  attributes do
    uuid_primary_key(:id)
    attribute(:email, :ci_string, allow_nil?: false, public?: true)
    attribute(:hashed_password, :string, allow_nil?: false, sensitive?: true)
    attribute(:confirmed_at, :utc_datetime)

    # Organization relationship
    attribute(:organization_id, :uuid, allow_nil?: false, public?: true)

    # Profile information
    attribute(:name, :string, public?: true)
    attribute(:role, :string, public?: true)
    attribute(:is_organization_admin, :boolean, default: false, allow_nil?: false)
    attribute(:permissions, {:array, :atom}, default: [:basic_access], allow_nil?: false)

    # User status
    attribute(:is_active, :boolean, default: true, allow_nil?: false)
    attribute(:last_login_at, :utc_datetime)

    timestamps()
  end

  # Identities
  identities do
    identity(:unique_email, [:email])
    identity(:organization_user, [:organization_id, :email])
  end

  # Relationships
  relationships do
    belongs_to(:organization, Lang.Accounts.Organization)
  end

  # Actions
  actions do
    defaults([:create, :read, :update, :destroy])

    create :register do
      argument(:email, :ci_string, allow_nil?: false)
      argument(:password, :string, allow_nil?: false)
      argument(:password_confirmation, :string, allow_nil?: false)
      argument(:organization_id, :uuid, allow_nil?: false)
      argument(:name, :string)
      argument(:role, :string)

      change(AshAuthentication.PasswordStrategy.Actions.PasswordConfirmationChange)
      change(AshAuthentication.GenerateTokenChange)

      change(fn changeset, _context ->
        organization_id = Ash.Changeset.get_argument(changeset, :organization_id)
        name = Ash.Changeset.get_argument(changeset, :name)
        role = Ash.Changeset.get_argument(changeset, :role)

        changeset
        |> Ash.Changeset.change_attribute(:organization_id, organization_id)
        |> Ash.Changeset.change_attribute(:name, name)
        |> Ash.Changeset.change_attribute(:role, role)
      end)
    end

    create :register_with_organization do
      argument(:email, :ci_string, allow_nil?: false)
      argument(:password, :string, allow_nil?: false)
      argument(:password_confirmation, :string, allow_nil?: false)
      argument(:organization_name, :string, allow_nil?: false)
      argument(:organization_slug, :string, allow_nil?: false)
      argument(:name, :string)
      argument(:role, :string, default: "Owner")

      change(AshAuthentication.PasswordStrategy.Actions.PasswordConfirmationChange)
      change(AshAuthentication.GenerateTokenChange)

      change(fn changeset, context ->
        org_name = Ash.Changeset.get_argument(changeset, :organization_name)
        org_slug = Ash.Changeset.get_argument(changeset, :organization_slug)
        user_name = Ash.Changeset.get_argument(changeset, :name)
        user_role = Ash.Changeset.get_argument(changeset, :role)
        email = Ash.Changeset.get_argument(changeset, :email)

        # Create organization first
        case Lang.Accounts.Organization.register(
               %{
                 name: org_name,
                 slug: org_slug,
                 contact_email: email,
                 billing_email: email
               },
               context
             ) do
          {:ok, organization} ->
            changeset
            |> Ash.Changeset.change_attribute(:organization_id, organization.id)
            |> Ash.Changeset.change_attribute(:name, user_name)
            |> Ash.Changeset.change_attribute(:role, user_role)
            |> Ash.Changeset.change_attribute(:is_organization_admin, true)
            |> Ash.Changeset.change_attribute(:permissions, [
              :basic_access,
              :admin_access,
              :billing_access,
              :user_management
            ])

          {:error, error} ->
            Ash.Changeset.add_error(changeset, error)
        end
      end)
    end

    update :confirm do
      argument(:token, :string, allow_nil?: false)
      change(AshAuthentication.PasswordStrategy.Actions.ConfirmChange)
    end

    update :update_profile do
      argument(:name, :string)
      argument(:role, :string)

      change(fn changeset, _context ->
        name = Ash.Changeset.get_argument(changeset, :name)
        role = Ash.Changeset.get_argument(changeset, :role)

        changeset
        |> Ash.Changeset.change_attribute(:name, name)
        |> Ash.Changeset.change_attribute(:role, role)
      end)
    end

    update :grant_admin_access do
      change(fn changeset, _context ->
        current_permissions = Ash.Changeset.get_attribute(changeset, :permissions) || []
        admin_permissions = [:basic_access, :admin_access, :user_management]
        new_permissions = Enum.uniq(current_permissions ++ admin_permissions)

        changeset
        |> Ash.Changeset.change_attribute(:is_organization_admin, true)
        |> Ash.Changeset.change_attribute(:permissions, new_permissions)
      end)
    end

    update :revoke_admin_access do
      change(fn changeset, _context ->
        current_permissions = Ash.Changeset.get_attribute(changeset, :permissions) || []
        basic_permissions = [:basic_access]

        changeset
        |> Ash.Changeset.change_attribute(:is_organization_admin, false)
        |> Ash.Changeset.change_attribute(:permissions, basic_permissions)
      end)
    end

    update :deactivate do
      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :is_active, false)
      end)
    end

    update :reactivate do
      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :is_active, true)
      end)
    end

    update :update_last_login do
      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :last_login_at, DateTime.utc_now())
      end)
    end

    read :active do
      filter(expr(is_active == true))
    end

    read :by_organization do
      argument(:organization_id, :uuid, allow_nil?: false)
      filter(expr(organization_id == ^arg(:organization_id)))
    end

    read :organization_admins do
      argument(:organization_id, :uuid, allow_nil?: false)
      filter(expr(organization_id == ^arg(:organization_id) and is_organization_admin == true))
    end
  end

  # Validations
  validations do
    validate(present([:email, :organization_id]))
    validate(match(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/), message: "must be a valid email")
  end

  # Calculations
  calculations do
    calculate(:display_name, :string, fn records, _context ->
      Enum.map(records, fn record ->
        case record.name do
          nil -> String.split(record.email, "@") |> List.first() |> String.capitalize()
          name -> name
        end
      end)
    end)

    calculate(:can_access_feature, :boolean, fn records, context ->
      feature = Map.get(context, :feature, :basic_access)

      Enum.map(records, fn record ->
        permissions = record.permissions || []
        feature in permissions
      end)
    end)
  end

  # Preparations
  preparations do
    prepare(build(load: [:confirmed_at, :organization]))
  end
end
