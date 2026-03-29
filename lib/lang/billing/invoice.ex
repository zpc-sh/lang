defmodule Lang.Billing.Invoice do
  @moduledoc """
  Recorded invoice from Stripe.
  """

  use Ash.Resource,
    domain: Lang.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("billing_invoices")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:organization_id, :uuid, allow_nil?: false)
    attribute(:stripe_invoice_id, :string, allow_nil?: false)
    attribute(:amount, :integer, allow_nil?: false)
    attribute(:currency, :string, allow_nil?: false)
    attribute(:status, :string, allow_nil?: false)
    attribute(:created_at, :utc_datetime, allow_nil?: false)
    create_timestamp(:inserted_at)
  end

  identities do
    identity(:uniq_inv, [:stripe_invoice_id])
  end

  actions do
    defaults([:read])

    create :record_from_stripe do
      accept([:organization_id, :stripe_invoice_id, :amount, :currency, :status, :created_at])
      after_action(&__MODULE__.emit_event/2)
    end
  end

  code_interface do
    define(:record_from_stripe)
  end

  def emit_event(_changeset, record) do
    Lang.Events.track_event(%{
      event_type: "invoice_recorded",
      organization_id: record.organization_id,
      metadata: %{
        stripe_invoice_id: record.stripe_invoice_id,
        amount: record.amount,
        currency: record.currency,
        status: record.status
      }
    })

    {:ok, record}
  end
end
