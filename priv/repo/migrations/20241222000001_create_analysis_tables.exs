defmodule Lang.Repo.Migrations.CreateAnalysisTables do
  use Ecto.Migration

  def change do
    # Projects table - represents codebases/repositories
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :repository_url, :string
      add :language, :string
      add :framework, :string
      add :project_type, :string, default: "web_app"
      add :status, :string, default: "active"
      add :settings, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:projects, [:user_id])
    create index(:projects, [:status])
    create unique_index(:projects, [:user_id, :name])

    # Analysis sessions - each upload/analysis run
    create table(:analysis_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :file_count, :integer, default: 0
      add :total_size_bytes, :bigint, default: 0
      add :violations_count, :integer, default: 0
      add :critical_issues_count, :integer, default: 0
      add :warnings_count, :integer, default: 0
      add :processing_time_ms, :integer
      add :metadata, :map, default: %{}
      add :error_message, :text

      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:analysis_sessions, [:project_id])
    create index(:analysis_sessions, [:status])
    create index(:analysis_sessions, [:started_at])

    # Analyzed files within each session
    create table(:analyzed_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :file_path, :string, null: false
      add :file_name, :string, null: false
      add :file_extension, :string
      add :file_size_bytes, :integer
      add :content_type, :string
      add :language_detected, :string
      add :content_hash, :string
      add :content, :text
      add :status, :string, default: "pending"
      add :analysis_result, :map, default: %{}
      add :processed_at, :utc_datetime
      add :processing_time_ms, :integer

      add :analysis_session_id,
          references(:analysis_sessions, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:analyzed_files, [:analysis_session_id])
    create index(:analyzed_files, [:file_extension])
    create index(:analyzed_files, [:language_detected])
    create index(:analyzed_files, [:status])
    create index(:analyzed_files, [:content_hash])

    # Violations found during analysis
    create table(:violations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :rule_id, :string, null: false
      add :rule_name, :string, null: false
      add :rule_category, :string
      add :severity, :string, null: false
      add :status, :string, default: "open"
      add :message, :text, null: false
      add :description, :text
      add :fix_suggestion, :text
      add :line_number, :integer
      add :column_number, :integer
      add :line_content, :text
      add :impact_assessment, :text
      add :compliance_tags, {:array, :string}, default: []
      add :confidence_score, :decimal, precision: 5, scale: 2
      add :metadata, :map, default: %{}
      add :resolved_at, :utc_datetime
      add :resolved_by, :string

      add :analyzed_file_id,
          references(:analyzed_files, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:violations, [:analyzed_file_id])
    create index(:violations, [:rule_id])
    create index(:violations, [:rule_category])
    create index(:violations, [:severity])
    create index(:violations, [:status])
    create index(:violations, [:compliance_tags], using: :gin)

    # Analysis rules configuration
    create table(:analysis_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :rule_id, :string, null: false
      add :name, :string, null: false
      add :category, :string, null: false
      add :description, :text
      add :severity, :string, null: false
      add :enabled, :boolean, default: true
      add :languages, {:array, :string}, default: []
      add :frameworks, {:array, :string}, default: []
      add :rule_config, :map, default: %{}
      add :compliance_standards, {:array, :string}, default: []
      add :created_by, :string
      add :is_custom, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:analysis_rules, [:rule_id])
    create index(:analysis_rules, [:category])
    create index(:analysis_rules, [:enabled])
    create index(:analysis_rules, [:languages], using: :gin)
    create index(:analysis_rules, [:frameworks], using: :gin)
    create index(:analysis_rules, [:compliance_standards], using: :gin)

    # Project rule configurations (which rules are enabled for each project)
    create table(:project_rule_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :enabled, :boolean, default: true
      add :severity_override, :string
      add :custom_config, :map, default: %{}

      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false

      add :analysis_rule_id,
          references(:analysis_rules, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_rule_configs, [:project_id, :analysis_rule_id])
    create index(:project_rule_configs, [:enabled])

    # Analysis insights and suggestions
    create table(:analysis_insights, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :insight_type, :string, null: false
      add :title, :string, null: false
      add :description, :text
      add :suggestion, :text
      add :confidence_score, :decimal, precision: 5, scale: 2
      add :impact_level, :string
      add :category, :string
      add :metadata, :map, default: %{}
      add :files_affected, {:array, :string}, default: []

      add :analysis_session_id,
          references(:analysis_sessions, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:analysis_insights, [:analysis_session_id])
    create index(:analysis_insights, [:insight_type])
    create index(:analysis_insights, [:impact_level])
    create index(:analysis_insights, [:category])
  end
end
