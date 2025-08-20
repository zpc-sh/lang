defmodule Lang.Accounts.Organization do
  @moduledoc """
  Organization resource for multitenancy support.

  Organizations provide tenant isolation and manage subscription plans,
  usage limits, and billing for groups of users.
  """

  use Ash.Resource,
    domain: Lang.Accounts,
    extensions: [AshPostgres.DataLayer]

  postgres do
    table("organizations")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    # Organization details
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:slug, :string, allow_nil?: false, public?: true)
    attribute(:description, :string, public?: true)
    attribute(:website, :string, public?: true)

    # Subscription and billing
    attribute(:subscription_tier, :atom,
      default: :free,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:free, :pro, :enterprise, :custom]]
    )

    attribute(:subscription_status, :atom,
      default: :active,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:active, :suspended, :canceled, :past_due]]
    )

    # Stripe integration fields
    attribute(:stripe_customer_id, :string, public?: true)
    attribute(:stripe_subscription_id, :string, public?: true)

    attribute(:plan, :atom,
      default: :free,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:free, :pro, :enterprise, :custom]]
    )

    # Subscription lifecycle timestamps
    attribute(:subscribed_at, :utc_datetime, public?: true)
    attribute(:cancelled_at, :utc_datetime, public?: true)
    attribute(:trial_ends_at, :utc_datetime, public?: true)
    attribute(:current_period_start, :utc_datetime, public?: true)
    attribute(:current_period_end, :utc_datetime, public?: true)

    # Usage limits and tracking
    attribute(:monthly_request_limit, :integer, default: 1000, allow_nil?: false)
    attribute(:monthly_request_count, :integer, default: 0, allow_nil?: false)
    attribute(:current_month_usage, :integer, default: 0, allow_nil?: false)
    attribute(:last_usage_reset, :utc_datetime, public?: true)
    attribute(:billing_cycle_start, :date, default: &Date.utc_today/0)

    # Payment method status
    attribute(:has_payment_method, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:payment_method_status, :string, public?: true)

    # Enterprise features
    attribute(:custom_rate_limits, :map, public?: true)
    attribute(:webhook_url, :string, public?: true)
    attribute(:api_version, :string, default: "v1", allow_nil?: false, public?: true)

    # Feature flags
    attribute(:features, {:array, :atom}, default: [:basic_analysis], allow_nil?: false)
    attribute(:max_users, :integer, default: 5)
    attribute(:storage_limit_gb, :integer, default: 1)

    # Contact and billing info
    attribute(:billing_email, :string, public?: true)
    attribute(:contact_email, :string, public?: true)
    attribute(:phone, :string, public?: true)

    # Address information
    attribute(:address_line1, :string, public?: true)
    attribute(:address_line2, :string, public?: true)
    attribute(:city, :string, public?: true)
    attribute(:state, :string, public?: true)
    attribute(:postal_code, :string, public?: true)
    attribute(:country, :string, public?: true, default: "US")

    # Settings
    attribute(:settings, :map, default: %{}, allow_nil?: false)
    attribute(:timezone, :string, default: "UTC", public?: true)

    # Status tracking
    attribute(:is_active, :boolean, default: true, allow_nil?: false)
    attribute(:onboarded_at, :utc_datetime)
    attribute(:last_activity_at, :utc_datetime)

    timestamps()
  end

  # Identities
  identities do
    identity(:unique_slug, [:slug])
    identity(:unique_name, [:name])
  end

  # Relationships
  relationships do
    has_many(:users, Lang.Accounts.User)
    has_many(:api_usage_events, Lang.Events.ApiUsageEvent)
  end

  # Actions
  actions do
    defaults([:create, :read, :update, :destroy])

    create :register do
      argument(:name, :string, allow_nil?: false)
      argument(:slug, :string, allow_nil?: false)
      argument(:contact_email, :string, allow_nil?: false)
      argument(:billing_email, :string)

      change(fn changeset, _context ->
        name = Ash.Changeset.get_argument(changeset, :name)
        slug = Ash.Changeset.get_argument(changeset, :slug)
        contact_email = Ash.Changeset.get_argument(changeset, :contact_email)
        billing_email = Ash.Changeset.get_argument(changeset, :billing_email) || contact_email

        changeset
        |> Ash.Changeset.change_attribute(:name, name)
        |> Ash.Changeset.change_attribute(:slug, String.downcase(slug))
        |> Ash.Changeset.change_attribute(:contact_email, contact_email)
        |> Ash.Changeset.change_attribute(:billing_email, billing_email)
        |> Ash.Changeset.change_attribute(:onboarded_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:last_activity_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:features, get_tier_features(:free))
      end)
    end

    update :upgrade_subscription do
      argument(:tier, :atom, allow_nil?: false)
      argument(:features, {:array, :atom})

      change(fn changeset, _context ->
        tier = Ash.Changeset.get_argument(changeset, :tier)
        custom_features = Ash.Changeset.get_argument(changeset, :features)

        features = custom_features || get_tier_features(tier)
        limits = get_tier_limits(tier)

        changeset
        |> Ash.Changeset.change_attribute(:subscription_tier, tier)
        |> Ash.Changeset.change_attribute(:features, features)
        |> Ash.Changeset.change_attribute(:monthly_request_limit, limits.request_limit)
        |> Ash.Changeset.change_attribute(:max_users, limits.max_users)
        |> Ash.Changeset.change_attribute(:storage_limit_gb, limits.storage_gb)
      end)
    end

    update :increment_usage do
      argument(:request_count, :integer, default: 1)

      change(fn changeset, _context ->
        increment = Ash.Changeset.get_argument(changeset, :request_count)
        current_count = Ash.Changeset.get_attribute(changeset, :monthly_request_count) || 0

        changeset
        |> Ash.Changeset.change_attribute(:monthly_request_count, current_count + increment)
        |> Ash.Changeset.change_attribute(:last_activity_at, DateTime.utc_now())
      end)
    end

    update :reset_monthly_usage do
      change(fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:monthly_request_count, 0)
        |> Ash.Changeset.change_attribute(:billing_cycle_start, Date.utc_today())
      end)
    end

    update :suspend do
      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :subscription_status, :suspended)
      end)
    end

    update :reactivate do
      change(fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:subscription_status, :active)
        |> Ash.Changeset.change_attribute(:last_activity_at, DateTime.utc_now())
      end)
    end

    read :active do
      filter(expr(is_active == true and subscription_status == :active))
    end

    read :by_slug do
      argument(:slug, :string, allow_nil?: false)
      filter(expr(slug == ^arg(:slug)))
      get?(true)
    end
  end

  # Validations
  validations do
    validate(present([:name, :slug]))

    validate(match(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$/),
      message: "must be lowercase alphanumeric with hyphens, no spaces"
    )

    validate(string_length(:slug, min: 3, max: 50))
    validate(string_length(:name, min: 2, max: 100))

    validate(match(:contact_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/),
      message: "must be a valid email",
      where: present(:contact_email)
    )

    validate(match(:billing_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/),
      message: "must be a valid email",
      where: present(:billing_email)
    )
  end

  # Calculations
  calculations do
    calculate(:usage_percentage, :float, fn records, _context ->
      Enum.map(records, fn record ->
        if record.monthly_request_limit > 0 do
          record.monthly_request_count / record.monthly_request_limit * 100.0
        else
          0.0
        end
      end)
    end)

    calculate(:days_until_reset, :integer, fn records, _context ->
      Enum.map(records, fn record ->
        today = Date.utc_today()

        case record.billing_cycle_start do
          nil ->
            30

          cycle_start ->
            next_cycle = Date.add(cycle_start, 30)
            Date.diff(next_cycle, today)
        end
      end)
    end)

    calculate(:is_over_limit, :boolean, fn records, _context ->
      Enum.map(records, fn record ->
        record.monthly_request_count >= record.monthly_request_limit
      end)
    end)
  end

  # Private helper functions
  defp get_tier_features(tier) do
    case tier do
      :free ->
        [:basic_analysis, :api_access]

      :pro ->
        [
          :basic_analysis,
          :api_access,
          :advanced_analysis,
          :conversation_rehearsal,
          :bulk_processing
        ]

      :enterprise ->
        [
          :basic_analysis,
          :api_access,
          :advanced_analysis,
          :conversation_rehearsal,
          :bulk_processing,
          :custom_models,
          :priority_support,
          :sso
        ]

      :custom ->
        [:basic_analysis, :api_access]
    end
  end

  defp get_tier_limits(tier) do
    case tier do
      :free -> %{request_limit: 1000, max_users: 5, storage_gb: 1}
      :pro -> %{request_limit: 10000, max_users: 25, storage_gb: 10}
      :enterprise -> %{request_limit: 100_000, max_users: 100, storage_gb: 100}
      :custom -> %{request_limit: 1000, max_users: 5, storage_gb: 1}
    end
  end
end
