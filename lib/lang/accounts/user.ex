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
      allow_nil?(false)
      sensitive?(true)
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
  end

  identities do
    identity(:unique_email, [:email])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

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

      # Set monthly limits based on subscription tier
      change(fn changeset, _context ->
        tier = Ash.Changeset.get_attribute(changeset, :subscription_tier) || :free
        limit = Lang.Billing.Config.plan_request_limit(tier)

        Ash.Changeset.change_attribute(changeset, :monthly_request_limit, limit)
      end)
    end

    create :register_with_password do
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

      change(fn changeset, context ->
        org_name = Ash.Changeset.get_argument(changeset, :organization_name)
        org_slug = Ash.Changeset.get_argument(changeset, :organization_slug)

        # Create organization first
        case Lang.Accounts.Organization.create(
               %{
                 name: org_name,
                 slug: org_slug || String.downcase(String.replace(org_name, " ", "-"))
               },
               context
             ) do
          {:ok, organization} ->
            changeset
            |> Ash.Changeset.change_attribute(:organization_id, organization.id)

          {:error, error} ->
            Ash.Changeset.add_error(changeset,
              field: :organization_name,
              message: "Failed to create organization: #{inspect(error)}"
            )
        end
      end)

      # Set monthly limits and create initial API key
      change(fn changeset, _context ->
        tier = Ash.Changeset.get_attribute(changeset, :subscription_tier) || :free
        limit = Lang.Billing.Config.plan_request_limit(tier)

        Ash.Changeset.change_attribute(changeset, :monthly_request_limit, limit)
      end)
    end

    update :update do
      primary?(true)
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
    AshAuthentication.authenticate(__MODULE__, :password, %{
      "email" => email,
      "password" => password
    })
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
end
