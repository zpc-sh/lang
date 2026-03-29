defmodule Lang.Billing do
  @moduledoc """
  Ash Domain for billing resources and actions.
  """

  use Ash.Domain

  resources do
    resource(Lang.Billing.Aggregate)
    resource(Lang.Billing.Subscription)
    resource(Lang.Billing.Invoice)
    resource(Lang.Billing.UsageRecord)
  end
end
