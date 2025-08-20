defmodule Lang.Repo.Migrations.AddSaasFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Rename password_hash to hashed_password for Ash Authentication compatibility
      rename :password_hash, to: :hashed_password

      # Add API key for authentication
      add :api_key, :string

      # Add SaaS subscription fields
      add :subscription_tier, :string, default: "free", null: false
      add :monthly_request_count, :integer, default: 0, null: false
      add :monthly_request_limit, :integer, default: 1000, null: false
      add :last_request_reset, :utc_datetime, default: fragment("now()"), null: false
      add :organization_name, :string
      add :is_active, :boolean, default: true, null: false
    end

    # Create index on API key for fast lookups
    create unique_index(:users, [:api_key])

    # Create tokens table for authentication sessions
    create table(:tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :subject, :string, null: false
      add :token, :string, null: false
      add :purpose, :string, null: false
      add :expires_at, :utc_datetime
      add :extra_data, :map, default: %{}

      timestamps()
    end

    create unique_index(:tokens, [:token])
    create index(:tokens, [:subject])
    create index(:tokens, [:purpose])

    # Create API usage tracking table
    create table(:api_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id), null: false
      add :operation_type, :string, null: false
      add :format, :string
      add :content_size_bytes, :integer
      add :processing_time_ms, :integer
      add :status, :string, null: false
      add :error_type, :string
      add :ip_address, :string
      add :user_agent, :string
      add :request_id, :string
      add :month_year, :string, null: false

      timestamps()
    end

    create index(:api_usage, [:user_id])
    create index(:api_usage, [:month_year])
    create index(:api_usage, [:user_id, :month_year])
    create index(:api_usage, [:operation_type])
    create index(:api_usage, [:status])
  end
end
