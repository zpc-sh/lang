defmodule Lang.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    execute("""
    CREATE TABLE IF NOT EXISTS workspaces (
      id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
      name varchar,
      project_id varchar,
      metadata jsonb,
      inserted_at timestamp(0) without time zone,
      updated_at timestamp(0) without time zone
    )
    """)

    execute("CREATE INDEX IF NOT EXISTS workspaces_project_id_index ON workspaces(project_id)")
  end
end
