defmodule Lang.Billing.Subscription do
  @moduledoc """
  Organization subscription state with Stripe linkage.

  Stripe calls should be orchestrated by actions here (or surrounding workers),
  and all mutations should emit events to Lang.Events.
  """

  use Ash.Resource,
    domain: Lang.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("billing_subscriptions")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:organization_id, :uuid, allow_nil?: false)

    attribute :plan, :atom do
      constraints(one_of: [:free, :professional, :enterprise])
      default(:free)
    end

    attribute :status, :atom do
      constraints(one_of: [:active, :canceled, :past_due, :unpaid, :trialing, :inactive])
      default(:inactive)
    end

    attribute(:stripe_customer_id, :string)
    attribute(:stripe_subscription_id, :string)

    attribute(:started_at, :utc_datetime)
    attribute(:cancelled_at, :utc_datetime)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:org_unique, [:organization_id])
  end

  actions do
    defaults([:read])

    create :start do
      accept([:organization_id, :plan, :stripe_customer_id, :stripe_subscription_id])
      change(set_attribute(:status, :active))
      change(set_attribute(:started_at, &DateTime.utc_now/0))

      after_action(&__MODULE__.emit_event/2)
    end

    update :upgrade do
      accept([:plan])
      change(set_attribute(:status, :active))
      after_action(&__MODULE__.emit_event/2)
    end

    update :cancel do
      accept([])
      change(set_attribute(:status, :canceled))
      change(set_attribute(:cancelled_at, &DateTime.utc_now/0))
      after_action(&__MODULE__.emit_event/2)
    end

    update :sync_from_stripe do
      accept([:plan, :status, :stripe_subscription_id])
      after_action(&__MODULE__.emit_event/2)
    end
  end

  code_interface do
    define(:start)
    define(:upgrade)
    define(:cancel)
    define(:sync_from_stripe)
  end

  def emit_event(_changeset, record) do
    Lang.Events.track_event(%{
      event_type: "billing_subscription_changed",
      organization_id: record.organization_id,
      metadata: %{
        plan: record.plan,
        status: record.status,
        stripe_subscription_id: record.stripe_subscription_id
      }
    })

    {:ok, record}
  end
end
