defmodule Lang.Spatial.Waypoint do
  use Ash.Resource,
    domain: Lang.Spatial,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "spatial_waypoints"
    repo Lang.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :project_id, :string, allow_nil?: false
    attribute :file, :string
    attribute :line, :integer
    attribute :label, :string
    attribute :metadata, :map, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]
  end
end

