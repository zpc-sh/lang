defmodule Lang.Repo.Migrations.CreateOrganizationsAndUpdateUsers do
  use Ecto.Migration

  def up do
    # Create organizations table
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Organization details
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :website, :string

      # Subscription and billing
      add :subscription_tier, :string, null: false, default: "free"
      add :subscription_status, :string, null: false, default: "active"

      # Usage limits and tracking
      add :monthly_request_limit, :integer, null: false, default: 1000
      add :monthly_request_count, :integer, null: false, default: 0
      add :billing_cycle_start, :date, default: fragment("CURRENT_DATE")

      # Feature flags
      add :features, {:array, :string}, null: false, default: ["basic_analysis"]
      add :max_users, :integer, default: 5
      add :storage_limit_gb, :integer, default: 1

      # Contact and billing info
      add :billing_email, :string
      add :contact_email, :string
      add :phone, :string

      # Address information
      add :address_line1, :string
      add :address_line2, :string
      add :city, :string
      add :state, :string
      add :postal_code, :string
      add :country, :string, default: "US"

      # Settings
      add :settings, :map, null: false, default: %{}
      add :timezone, :string, default: "UTC"

      # Status tracking
      add :is_active, :boolean, null: false, default: true
      add :onboarded_at, :utc_datetime
      add :last_activity_at, :utc_datetime

      timestamps()
    end

    # Create indexes for organizations
    create unique_index(:organizations, [:slug])
    create unique_index(:organizations, [:name])
    create index(:organizations, [:subscription_tier])
    create index(:organizations, [:subscription_status])
    create index(:organizations, [:is_active])

    # Update users table to add organization relationship
    alter table(:users) do
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict)
      add :is_organization_admin, :boolean, null: false, default: false
      add :permissions, {:array, :string}, null: false, default: ["basic_access"]
      add :is_active, :boolean, null: false, default: true
      add :last_login_at, :utc_datetime

      # Remove old single-tenant fields that are now handled by organization
      remove_if_exists :subscription_tier, :string
      remove_if_exists :api_requests_count, :integer
      remove_if_exists :api_requests_limit, :integer
      remove_if_exists :last_request_at, :utc_datetime
      remove_if_exists :company, :string
    end

    # Create indexes for updated users table
    create index(:users, [:organization_id])
    create index(:users, [:is_organization_admin])
    create index(:users, [:is_active])
    create unique_index(:users, [:organization_id, :email])

    # Migrate existing users to have a default organization
    flush()

    execute """
    WITH default_org AS (
      INSERT INTO organizations (id, name, slug, contact_email, billing_email, onboarded_at, inserted_at, updated_at)
      SELECT
        gen_random_uuid(),
        'Default Organization',
        'default-org',
        'admin@lang-platform.com',
        'admin@lang-platform.com',
        NOW(),
        NOW(),
        NOW()
      WHERE NOT EXISTS (SELECT 1 FROM organizations WHERE slug = 'default-org')
      RETURNING id
    )
    UPDATE users
    SET organization_id = (SELECT id FROM default_org LIMIT 1),
        is_organization_admin = true,
        permissions = ARRAY['basic_access', 'admin_access', 'billing_access', 'user_management']
    WHERE organization_id IS NULL
    """

    # Make organization_id required after migration
    alter table(:users) do
      modify :organization_id, :binary_id, null: false
    end
  end

  def down do
    # Add back the old single-tenant fields to users
    alter table(:users) do
      add :subscription_tier, :string, default: "free"
      add :api_requests_count, :integer, default: 0
      add :api_requests_limit, :integer, default: 1000
      add :last_request_at, :utc_datetime
      add :company, :string
    end

    # Migrate organization data back to users
    execute """
    UPDATE users
    SET subscription_tier = o.subscription_tier,
        api_requests_count = o.monthly_request_count,
        api_requests_limit = o.monthly_request_limit,
        company = o.name
    FROM organizations o
    WHERE users.organization_id = o.id
    """

    # Remove organization-related fields from users
    alter table(:users) do
      remove :organization_id
      remove :is_organization_admin
      remove :permissions
      remove :is_active
      remove :last_login_at
    end

    # Drop indexes
    drop_if_exists index(:users, [:organization_id])
    drop_if_exists index(:users, [:is_organization_admin])
    drop_if_exists index(:users, [:is_active])
    drop_if_exists unique_index(:users, [:organization_id, :email])

    # Drop organizations table
    drop table(:organizations)
  end
end
