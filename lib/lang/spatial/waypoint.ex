defmodule Lang.Spatial.Waypoint do
  @moduledoc """
  Persistent navigation markers for spatial traversal.
  """

  use Ash.Resource,
    domain: Lang.Spatial,
    data_layer: AshPostgres.DataLayer

  alias Lang.Analyses.Project

  postgres do
    table("spatial_waypoints")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute :label, :string
    attribute :path, :string
    attribute :position, :map, default: %{}
    attribute :tags, {:array, :string}, default: []
    attribute :metadata, :map, default: %{}
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :project, Project do
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read])
    create :create do
      accept([:project_id, :label, :path, :position, :tags, :metadata])
    end
  end

  code_interface do
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:read_all, action: :read)
  end
end

