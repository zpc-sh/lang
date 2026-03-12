defmodule Lang.Billing.UsageRecord do
  @moduledoc """
  Generic usage record (e.g., MCP connection, analysis minutes, etc.).
  Can be aggregated for metered billing.
  """

  use Ash.Resource,
    domain: Lang.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("billing_usage_records")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:organization_id, :uuid, allow_nil?: false)
    attribute(:kind, :string, allow_nil?: false)
    attribute(:quantity, :integer, allow_nil?: false, default: 1)
    attribute(:occurred_at, :utc_datetime, allow_nil?: false, default: &DateTime.utc_now/0)
    attribute(:metadata, :map, default: %{})
    create_timestamp(:inserted_at)
  end

  actions do
    defaults([:read])

    create :record do
      accept([:organization_id, :kind, :quantity, :occurred_at, :metadata])
    end
  end

  code_interface do
    define(:record)
  end
end
