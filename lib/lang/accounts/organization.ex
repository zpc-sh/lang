defmodule Lang.Accounts.Organization do
  use Ash.Resource,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("organizations")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :slug, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :contact_email, :string do
      public?(true)
    end

    attribute :billing_email, :string do
      public?(true)
    end

    attribute :website, :string do
      public?(true)
    end

    attribute :description, :string do
      public?(true)
    end

    # Organization settings
    attribute :is_active, :boolean do
      default(true)
      public?(true)
    end

    attribute :max_users, :integer do
      default(10)
      public?(true)
    end

    # Billing fields
    attribute :stripe_customer_id, :string do
      public?(true)
    end

    attribute :stripe_subscription_id, :string do
      public?(true)
    end

    attribute :subscription_tier, :atom do
      constraints(one_of: [:free, :professional, :enterprise])
      default(:free)
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
    has_many :users, Lang.Accounts.User do
      public?(true)
    end

    has_many :api_keys, Lang.Accounts.ApiKey do
      public?(true)
    end
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :slug, :contact_email, :billing_email, :website, :description])

      change(fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)
        slug = Ash.Changeset.get_attribute(changeset, :slug)

        # Generate slug from name if not provided
        final_slug = slug || String.downcase(String.replace(name || "", " ", "-"))

        changeset
        |> Ash.Changeset.change_attribute(:slug, final_slug)
        |> Ash.Changeset.change_attribute(
          :contact_email,
          Ash.Changeset.get_attribute(changeset, :contact_email) ||
            Ash.Changeset.get_attribute(changeset, :billing_email)
        )
      end)
    end

    update :update do
      primary?(true)
      accept([:name, :slug, :contact_email, :billing_email, :website, :description, :max_users])
    end

    update :update_billing do
      # Transitional action to update billing fields via Ash, not raw Ecto
      argument(:stripe_customer_id, :string)
      argument(:stripe_subscription_id, :string)

      argument(:subscription_tier, :atom,
        constraints: [one_of: [:free, :professional, :enterprise]]
      )

      argument(:subscription_status, :atom,
        constraints: [one_of: [:active, :canceled, :past_due, :unpaid, :trialing]]
      )

      change(fn changeset, _ctx ->
        changeset
        |> maybe_change(:stripe_customer_id)
        |> maybe_change(:stripe_subscription_id)
        |> maybe_change(:subscription_tier)
        |> maybe_change(:subscription_status)
      end)
    end

    update :upgrade_subscription do
      argument :tier, :atom do
        constraints(one_of: [:free, :professional, :enterprise])
      end

      argument(:stripe_customer_id, :string)
      argument(:stripe_subscription_id, :string)

      change(fn changeset, _context ->
        tier = Ash.Changeset.get_argument(changeset, :tier)

        max_users = Lang.Billing.Config.max_team_members(tier)

        changeset
        |> Ash.Changeset.change_attribute(:subscription_tier, tier)
        |> Ash.Changeset.change_attribute(:subscription_status, :active)
        |> Ash.Changeset.change_attribute(:max_users, max_users)
      end)
    end

    destroy :destroy do
      primary?(true)
    end
  end

  code_interface do
    define(:create)
    define(:by_id, get_by: [:id], action: :read)
    define(:by_slug, get_by: [:slug], action: :read)
    define(:list_all, action: :read)
    define(:update)
    define(:update_billing)
    define(:upgrade_subscription)
    define(:destroy)
  end

  preparations do
    prepare(build(load: [:users]))
  end

  validations do
    validate match(:contact_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
      message("must be a valid email address")
    end

    validate match(:billing_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
      message("must be a valid email address")
    end

    validate(string_length(:name, min: 1, max: 100))
    validate(string_length(:slug, min: 1, max: 100))

    validate match(:slug, ~r/^[a-z0-9\-]+$/) do
      message("can only contain lowercase letters, numbers, and dashes")
    end
  end

  # Helper functions
  def subscription_name(tier) do
    Lang.Billing.Config.plan_name(tier)
  end

  def subscription_price(tier) do
    Lang.Billing.Config.plan_price_string(tier)
  end

  def user_count(organization) do
    length(organization.users || [])
  end

  def at_user_limit?(organization) do
    user_count(organization) >= organization.max_users
  end

  defp maybe_change(changeset, field) do
    case Ash.Changeset.get_argument(changeset, field) do
      nil -> changeset
      value -> Ash.Changeset.change_attribute(changeset, field, value)
    end
  end
end
