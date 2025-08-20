defmodule Lang.Repo.Migrations.CreateLangTables do
  use Ecto.Migration

  def change do
    # Create analysis results table
    create table(:analysis_results, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content_hash, :string, null: false
      add :format, :string, null: false
      add :analysis_data, :map
      add :completions, {:array, :map}
      add :diagnostics, {:array, :map}

      timestamps(type: :utc_datetime)
    end

    create index(:analysis_results, [:content_hash])
    create index(:analysis_results, [:format])

    # Create conversation sessions table
    create table(:conversation_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scenario, :string, null: false
      add :participants, {:array, :string}
      add :conversation_tree, :map
      add :status, :string, default: "active"

      timestamps(type: :utc_datetime)
    end

    create index(:conversation_sessions, [:scenario])
    create index(:conversation_sessions, [:status])

    # Create timeline states table
    create table(:timeline_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :timeline_id, :string, null: false
      add :state_data, :map
      add :metadata, :map
      add :position, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:timeline_states, [:timeline_id])
    create index(:timeline_states, [:timeline_id, :position])

    # Create stylometric profiles table
    create table(:stylometric_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content_hash, :string, null: false
      add :fingerprint_hash, :string, null: false
      add :linguistic_features, :map
      add :syntactic_features, :map
      add :lexical_features, :map
      add :stylistic_features, :map
      add :confidence_score, :float

      timestamps(type: :utc_datetime)
    end

    create index(:stylometric_profiles, [:content_hash])
    create index(:stylometric_profiles, [:fingerprint_hash])

    # Create LSP documents table
    create table(:lsp_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :uri, :string, null: false
      add :language_id, :string, null: false
      add :version, :integer, default: 1
      add :content, :text
      add :analysis_cache, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lsp_documents, [:uri])
    create index(:lsp_documents, [:language_id])

    # Enable Oban tables
    Oban.Migration.up(version: 12)
  end
end
