defmodule Lang.Billing.Aggregate do
  @moduledoc """
  Periodic usage aggregates for billing and reporting.
  """

  use Ash.Resource,
    domain: Lang.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("billing_aggregates")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:organization_id, :uuid, allow_nil?: false)
    attribute(:period_start, :utc_datetime, allow_nil?: false)
    attribute(:period_end, :utc_datetime, allow_nil?: false)

    attribute(:granularity, :atom,
      allow_nil?: false,
      default: :hour,
      constraints: [one_of: [:hour, :day, :month]]
    )

    attribute(:kind, :atom,
      allow_nil?: false,
      default: :api_requests,
      constraints: [one_of: [:api_requests, :mcp_connections]]
    )

    # Totals
    attribute(:total_requests, :integer, allow_nil?: false, default: 0)
    attribute(:total_mcp_connections, :integer, allow_nil?: false, default: 0)
    attribute(:total_content_size_bytes, :integer, allow_nil?: false, default: 0)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:uniq_period, [:organization_id, :period_start, :period_end, :granularity, :kind])
  end

  actions do
    defaults([:read, :create, :update])

    read :by_org_and_period do
      argument(:organization_id, :uuid, allow_nil?: false)
      argument(:granularity, :atom, allow_nil?: true)
      argument(:kind, :atom, allow_nil?: true)
      argument(:from, :utc_datetime, allow_nil?: true)
      argument(:to, :utc_datetime, allow_nil?: true)

      filter(expr(organization_id == ^arg(:organization_id)))

      filter(expr(is_nil(^arg(:granularity)) or granularity == ^arg(:granularity)))
      filter(expr(is_nil(^arg(:kind)) or kind == ^arg(:kind)))
      filter(expr(is_nil(^arg(:from)) or period_start >= ^arg(:from)))
      filter(expr(is_nil(^arg(:to)) or period_end <= ^arg(:to)))

      prepare(build(sort: [period_start: :desc], limit: 1000))
    end
  end
end
