defmodule Lang.Workspace.Workspace do
  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "workspaces"
    repo Lang.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string
    attribute :project_id, :string
    attribute :metadata, :map, default: %{}
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]
  end
end

