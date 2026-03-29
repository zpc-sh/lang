defmodule Lang.Accounts.User do
  use Ash.Resource,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication]

  postgres do
    table("users")
    repo(Lang.Repo)
  end

  authentication do
    strategies do
      password :password do
        identity_field(:email)
        hashed_password_field(:hashed_password)
        sign_in_tokens_enabled?(true)
        confirmation_required?(false)
        register_action_name(:register_with_password)
      end

      github :github do
        client_id(fn _, _ -> System.get_env("GITHUB_CLIENT_ID") end)
        client_secret(fn _, _ -> System.get_env("GITHUB_CLIENT_SECRET") end)

        redirect_uri(fn _, _ ->
          System.get_env("GITHUB_REDIRECT_URI", "http://localhost:4000/auth/github/callback")
        end)

        register_action_name(:register_with_oauth)
        identity_resource(Lang.Accounts.UserIdentity)
      end

      google :google do
        client_id(fn _, _ -> System.get_env("GOOGLE_CLIENT_ID") end)
        client_secret(fn _, _ -> System.get_env("GOOGLE_CLIENT_SECRET") end)

        redirect_uri(fn _, _ ->
          System.get_env("GOOGLE_REDIRECT_URI", "http://localhost:4000/auth/google/callback")
        end)

        register_action_name(:register_with_oauth)
        identity_resource(Lang.Accounts.UserIdentity)
      end

      oauth2 :apple do
        client_id(fn _, _ -> System.get_env("APPLE_CLIENT_ID") end)
        client_secret(fn _, _ -> System.get_env("APPLE_CLIENT_SECRET") end)

        redirect_uri(fn _, _ ->
          System.get_env("APPLE_REDIRECT_URI", "http://localhost:4000/auth/apple/callback")
        end)

        base_url("https://appleid.apple.com")
        authorize_url("/auth/authorize")
        token_url("/auth/token")
        user_url("/auth/userinfo")
        authorization_params(scope: "openid email name", response_mode: "form_post")

        register_action_name(:register_with_oauth)
        identity_resource(Lang.Accounts.UserIdentity)
      end
    end

    add_ons do
      confirmation :confirm do
        monitor_fields([:email])
        confirm_on_create?(false)
        confirm_on_update?(false)
        inhibit_updates?(false)
        require_interaction?(true)
        sender(Lang.Emails)
      end
    end

    tokens do
      enabled?(true)
      token_resource(Lang.Accounts.Token)
      signing_secret(Lang.Secrets)
      require_token_presence_for_authentication?(true)
      session_identifier(:jti)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :email, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :hashed_password, :string do
      allow_nil?(true)
      sensitive?(true)
    end

    # OAuth2 attributes
    attribute :provider, :string do
      public?(true)
    end

    attribute :provider_uid, :string do
      public?(true)
    end

    attribute :avatar_url, :string do
      public?(true)
    end

    attribute :github_username, :string do
      public?(true)
    end

    attribute :confirmed_at, :utc_datetime do
      public?(true)
    end

    attribute :is_active, :boolean do
      default(true)
      public?(true)
    end

    # Billing fields
    attribute :subscription_tier, :atom do
      constraints(one_of: [:free, :professional, :enterprise])
      default(:free)
      public?(true)
    end

    attribute :monthly_request_count, :integer do
      default(0)
      public?(true)
    end

    attribute :monthly_request_limit, :integer do
      default(1000)
      public?(true)
    end

    attribute :last_request_reset, :utc_datetime do
      default(&DateTime.utc_now/0)
      public?(true)
    end

    attribute :stripe_customer_id, :string do
      public?(true)
    end

    attribute :stripe_subscription_id, :string do
      public?(true)
    end

    attribute :subscription_status, :atom do
      constraints(one_of: [:active, :canceled, :past_due, :unpaid, :trialing])
      default(:active)
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, Lang.Accounts.Organization do
      public?(true)
    end

    has_many :api_keys, Lang.Accounts.ApiKey do
      public?(true)
    end

    has_many :user_identities, Lang.Accounts.UserIdentity do
      public?(true)
    end
  end

  identities do
    identity(:unique_email, [:email])
    identity(:unique_provider_uid, [:provider, :provider_uid])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:email, :name, :subscription_tier, :organization_id])

      argument :password, :string do
        sensitive?(true)
      end

      argument :password_confirmation, :string do
        sensitive?(true)
      end

      validate(confirm(:password, :password_confirmation))
      validate(present([:email, :name, :password]))

      # Hash password change required by AshAuthentication
      change(AshAuthentication.Strategy.Password.HashPasswordChange)

      # Set monthly limits based on subscription tier
      change(fn changeset, _context ->
        tier = Ash.Changeset.get_attribute(changeset, :subscription_tier) || :free
        limit = Lang.Billing.Config.plan_request_limit(tier)

        Ash.Changeset.change_attribute(changeset, :monthly_request_limit, limit)
      end)
    end

    create :register_with_oauth do
      argument(:user_info, :map, allow_nil?: false)
      argument(:oauth_tokens, :map, allow_nil?: false)
      upsert?(true)
      upsert_identity(:unique_email)

      change(AshAuthentication.GenerateTokenChange)
      change(AshAuthentication.Strategy.OAuth2.IdentityChange)

      change(fn changeset, _context ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        # Extract name from different OAuth providers
        name =
          case user_info do
            %{"name" => name} when is_binary(name) -> name
            # GitHub
            %{"login" => login} -> login
            # Microsoft
            %{"displayName" => display_name} -> display_name
            _ -> "User"
          end

        # Extract email
        email =
          case user_info do
            %{"email" => email} when is_binary(email) -> email
            # Microsoft alternative
            %{"mail" => mail} -> mail
            # Microsoft alternative
            %{"userPrincipalName" => upn} -> upn
            _ -> nil
          end

        if email do
          org_name = "#{name}'s Organization"

          # Create organization
          case Lang.Accounts.Organization.create(%{
                 name: org_name,
                 slug: String.downcase(String.replace(org_name, " ", "-"))
               }) do
            {:ok, organization} ->
              changeset
              |> Ash.Changeset.change_attribute(:email, email)
              |> Ash.Changeset.change_attribute(:name, name)
              |> Lang.AshHelpers.set_org(organization.id)
              |> Ash.Changeset.change_attribute(:subscription_tier, :free)
              |> Ash.Changeset.change_attribute(:monthly_request_limit, 1000)

            {:error, _error} ->
              changeset
              |> Ash.Changeset.change_attribute(:email, email)
              |> Ash.Changeset.change_attribute(:name, name)
              |> Ash.Changeset.change_attribute(:subscription_tier, :free)
              |> Ash.Changeset.change_attribute(:monthly_request_limit, 1000)
          end
        else
          Ash.Changeset.add_error(changeset, field: :email, message: "Email is required")
        end
      end)
    end

    create :register_with_password do
      accept([:email, :name, :subscription_tier])

      argument :password, :string do
        sensitive?(true)
      end

      argument :password_confirmation, :string do
        sensitive?(true)
      end

      argument(:organization_name, :string)
      argument(:organization_slug, :string)

      validate(confirm(:password, :password_confirmation))
      validate(present([:email, :name, :password, :organization_name]))

      # Hash password change required by AshAuthentication
      change(AshAuthentication.Strategy.Password.HashPasswordChange)
      change(AshAuthentication.GenerateTokenChange)

      change(fn changeset, _context ->
        org_name = Ash.Changeset.get_argument(changeset, :organization_name)
        org_slug = Ash.Changeset.get_argument(changeset, :organization_slug)

        # Create organization first
        case Lang.Accounts.Organization.create(%{
               name: org_name,
               slug: org_slug || String.downcase(String.replace(org_name, " ", "-"))
             }) do
          {:ok, organization} ->
            changeset
            |> Lang.AshHelpers.set_org(organization.id)

          {:error, error} ->
            Ash.Changeset.add_error(changeset,
              field: :organization_name,
              message: "Failed to create organization: #{inspect(error)}"
            )
        end
      end)

      # Set monthly limits
      change(fn changeset, _context ->
        tier = Ash.Changeset.get_attribute(changeset, :subscription_tier) || :free
        limit = Lang.Billing.Config.plan_request_limit(tier)

        Ash.Changeset.change_attribute(changeset, :monthly_request_limit, limit)
      end)
    end

    update :update do
      primary?(true)
    end

    update :update_profile do
      accept([:name, :email])

      validate(present([:name, :email]))

      validate match(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
        message("must be a valid email address")
      end

      validate(string_length(:name, min: 1, max: 100))
      validate(string_length(:email, min: 3, max: 160))
    end

    update :confirm_email do
      accept([:confirmed_at])

      change(set_attribute(:confirmed_at, &DateTime.utc_now/0))
    end

    update :change_password do
      require_atomic?(false)

      argument :current_password, :string do
        sensitive?(true)
      end

      argument :password, :string do
        sensitive?(true)
      end

      argument :password_confirmation, :string do
        sensitive?(true)
      end

      validate(confirm(:password, :password_confirmation))
      validate(present([:current_password, :password]))

      validate(fn changeset, _context ->
        current_password = Ash.Changeset.get_argument(changeset, :current_password)

        if Bcrypt.verify_pass(current_password, changeset.data.hashed_password) do
          :ok
        else
          {:error, field: :current_password, message: "is incorrect"}
        end
      end)

      change(fn changeset, _context ->
        if password = Ash.Changeset.get_argument(changeset, :password) do
          hashed = Bcrypt.hash_pwd_salt(password)
          Ash.Changeset.change_attribute(changeset, :hashed_password, hashed)
        else
          changeset
        end
      end)
    end

    update :upgrade_subscription do
      require_atomic?(false)

      argument :tier, :atom do
        constraints(one_of: [:free, :professional, :enterprise])
      end

      argument(:stripe_customer_id, :string)
      argument(:stripe_subscription_id, :string)

      change(fn changeset, _context ->
        tier = Ash.Changeset.get_argument(changeset, :tier)
        limit = Lang.Billing.Config.plan_request_limit(tier)

        changeset
        |> Ash.Changeset.change_attribute(:subscription_tier, tier)
        |> Ash.Changeset.change_attribute(:monthly_request_limit, limit)
        |> Ash.Changeset.change_attribute(:subscription_status, :active)
      end)
    end

    update :increment_request_count do
      require_atomic?(false)

      change(fn changeset, _context ->
        current_count = changeset.data.monthly_request_count || 0
        Ash.Changeset.change_attribute(changeset, :monthly_request_count, current_count + 1)
      end)
    end

    update :reset_monthly_usage do
      require_atomic?(false)

      change(fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:monthly_request_count, 0)
        |> Ash.Changeset.change_attribute(:last_request_reset, DateTime.utc_now())
      end)
    end

    destroy :destroy do
      primary?(true)
    end
  end

  code_interface do
    define(:read)
    define(:by_id, get_by: [:id], action: :read)
    define(:by_email, get_by: [:email], action: :read)
    define(:list_all, action: :read)
    define(:create, action: :create)
    define(:register_with_password, action: :register_with_password)
    define(:update)
    define(:confirm_email)
    define(:change_password)
    define(:update_profile)
    define(:upgrade_subscription)
    define(:increment_request_count)
    define(:reset_monthly_usage)
    define(:destroy)
  end

  preparations do
    prepare(build(load: [:organization]))
  end

  validations do
    validate match(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
      message("must be a valid email address")
    end

    validate(string_length(:name, min: 1, max: 100))
    validate(string_length(:email, min: 3, max: 160))
  end

  # Helper functions - authentication is now handled by AshAuthentication
  def authenticate(email, password) do
    case Ash.ActionInput.for_action(__MODULE__, :sign_in_with_password, %{
           "email" => email,
           "password" => password
         })
         |> Ash.run_action() do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, error} -> {:error, error}
    end
  end

  def confirmed?(user) do
    !is_nil(user.confirmed_at)
  end

  def over_limit?(user, additional_requests \\ 1) do
    user.monthly_request_count + additional_requests > user.monthly_request_limit
  end

  def usage_percentage(user) do
    if user.monthly_request_limit > 0 do
      min(user.monthly_request_count / user.monthly_request_limit * 100, 100)
    else
      0
    end
  end

  def subscription_name(tier) do
    Lang.Billing.Config.plan_name(tier)
  end

  def subscription_price(tier) do
    Lang.Billing.Config.plan_price_string(tier)
  end

  @doc """
  Creates a changeset for user creation with default attributes.
  """
  def changeset_for_create(attrs \\ %{}) do
    Ash.Changeset.for_create(__MODULE__, :create, attrs)
  end

  @doc """
  Authenticates a user and returns a proper session token.
  """
  def sign_in_with_token(email, password) do
    case authenticate(email, password) do
      {:ok, user} ->
        # Generate a token for the user
        case AshAuthentication.Jwt.token_for_user(user) do
          {:ok, token, _claims} -> {:ok, user, token}
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end
