defmodule Lang.Spatial.Path do
  use Ash.Resource,
    domain: Lang.Spatial,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "spatial_paths"
    repo Lang.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :project_id, :string, allow_nil?: false
    attribute :from_label, :string
    attribute :to_label, :string
    attribute :metadata, :map, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]
  end
end

