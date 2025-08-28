defmodule Lang.Spatial.Path do
  @moduledoc """
  Spatial paths tracing relationships (calls/refs) between points in the codebase.
  """

  use Ash.Resource,
    domain: Lang.Spatial,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  alias Lang.Analyses.Project

  postgres do
    table("spatial_paths")
    repo(Lang.Repo)
  end

  json_api do
    type("spatial_path")

    routes do
      base("/paths")
      get(:read)
      index(:read)
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute :from_ref, :string
    attribute :to_ref, :string
    attribute :hops, {:array, :map}, default: []
    attribute :rationale, :map, default: %{}
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :project, Project do
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read, :destroy])
    create :create do
      accept([:project_id, :from_ref, :to_ref, :hops, :rationale])
    end

    update :update do
      accept([:from_ref, :to_ref, :hops, :rationale])
    end
  end

  code_interface do
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:read_all, action: :read)
  end
end
