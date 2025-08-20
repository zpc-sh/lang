defmodule Lang.Repo.Migrations.AddStripeBillingFields do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      # Stripe customer and subscription management
      add :stripe_customer_id, :string, null: true
      add :stripe_subscription_id, :string, null: true

      # Enhanced plan management
      add :plan, :string, null: false, default: "free"
      add :subscribed_at, :utc_datetime, null: true
      add :cancelled_at, :utc_datetime, null: true

      # Payment and billing details
      add :trial_ends_at, :utc_datetime, null: true
      add :current_period_start, :utc_datetime, null: true
      add :current_period_end, :utc_datetime, null: true

      # Usage tracking for billing
      add :current_month_usage, :integer, null: false, default: 0
      add :last_usage_reset, :utc_datetime, null: true, default: fragment("NOW()")

      # Payment method status
      add :has_payment_method, :boolean, null: false, default: false
      add :payment_method_status, :string, null: true

      # Enterprise features
      add :custom_rate_limits, :map, null: true
      add :webhook_url, :string, null: true
      add :api_version, :string, null: false, default: "v1"
    end

    # Add indexes for efficient querying
    create index(:organizations, [:stripe_customer_id],
             unique: true,
             where: "stripe_customer_id IS NOT NULL"
           )

    create index(:organizations, [:stripe_subscription_id],
             unique: true,
             where: "stripe_subscription_id IS NOT NULL"
           )

    create index(:organizations, [:plan])
    create index(:organizations, [:subscription_status])
    create index(:organizations, [:current_period_end])

    # Create billing events table for detailed tracking
    create table(:billing_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id), null: false

      add :event_type, :string, null: false
      add :stripe_event_id, :string, null: true
      add :amount, :integer, null: true
      add :currency, :string, null: true, default: "usd"

      add :metadata, :map, null: true
      add :processed_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:billing_events, [:organization_id])
    create index(:billing_events, [:event_type])

    create index(:billing_events, [:stripe_event_id],
             unique: true,
             where: "stripe_event_id IS NOT NULL"
           )

    create index(:billing_events, [:inserted_at])

    # Create subscription usage tracking table
    create table(:usage_records, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id), null: false

      add :period_start, :utc_datetime, null: false
      add :period_end, :utc_datetime, null: false
      add :api_requests, :integer, null: false, default: 0
      add :data_processed_bytes, :bigint, null: false, default: 0

      # JSON field for detailed feature usage
      add :feature_usage, :map, null: true
      # Overage charges in cents
      add :overage_amount, :integer, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:usage_records, [:organization_id])
    create index(:usage_records, [:period_start, :period_end])
    create unique_index(:usage_records, [:organization_id, :period_start, :period_end])
  end
end
