defmodule Lang.Repo.Migrations.CreateSpatialTables do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    execute("""
    CREATE TABLE IF NOT EXISTS spatial_maps (
      id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
      project_id varchar NOT NULL,
      graph_summary jsonb,
      stats jsonb,
      inserted_at timestamp(0) without time zone,
      updated_at timestamp(0) without time zone
    )
    """)

    execute("CREATE INDEX IF NOT EXISTS spatial_maps_project_id_index ON spatial_maps(project_id)")

    execute("""
    CREATE TABLE IF NOT EXISTS spatial_waypoints (
      id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
      project_id varchar NOT NULL,
      file varchar,
      line integer,
      label varchar,
      metadata jsonb,
      inserted_at timestamp(0) without time zone,
      updated_at timestamp(0) without time zone
    )
    """)

    execute("CREATE INDEX IF NOT EXISTS spatial_waypoints_project_id_index ON spatial_waypoints(project_id)")

    execute("""
    CREATE TABLE IF NOT EXISTS spatial_paths (
      id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
      project_id varchar NOT NULL,
      from_label varchar,
      to_label varchar,
      metadata jsonb,
      inserted_at timestamp(0) without time zone,
      updated_at timestamp(0) without time zone
    )
    """)

    execute("CREATE INDEX IF NOT EXISTS spatial_paths_project_id_index ON spatial_paths(project_id)")
  end
end
