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
    attribute(:project_id, :string, allow_nil?: false)
    attribute(:from_label, :string)
    attribute(:to_label, :string)
    attribute(:from_ref, :string)
    attribute(:to_ref, :string)
    attribute(:hops, :integer, default: 1)
    attribute(:rationale, :string)
    attribute(:metadata, :map, default: %{})
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  # Relationships can be added once Lang.Analyses.Project exists

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:project_id, :from_label, :to_label, :metadata])
    end

    update :update do
      accept([:from_label, :to_label, :metadata])
    end
  end

  code_interface do
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:read_all, action: :read)
  end
end
