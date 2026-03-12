defmodule Lang.Repo.Migrations.CreateLspMeasurementEvents do
  @moduledoc """
  Creates the lsp_measurement_events table.
  """
  use AshPostgres.Migration

  def up do
    create table(:lsp_measurement_events, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :client_id, :text, null: false
      add :method, :text, null: false
      add :request, :jsonb, null: false
      add :response, :jsonb
      add :duration_ms, :integer
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:lsp_measurement_events, [:client_id])
    create index(:lsp_measurement_events, [:method])
    create index(:lsp_measurement_events, [:created_at])
  end

  def down do
    drop table(:lsp_measurement_events)
  end
end