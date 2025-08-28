defmodule Lang.Spatial.Map do
  @moduledoc """
  Snapshot of a project's code map (symbols, relations, stats). Built by MapBuilder.
  """

  use Ash.Resource,
    domain: Lang.Spatial,
    data_layer: AshPostgres.DataLayer

  alias Lang.Analyses.Project

  postgres do
    table("spatial_maps")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :graph_summary, :map do
      allow_nil?(false)
      default(%{})
    end

    attribute :stats, :map do
      allow_nil?(false)
      default(%{})
    end

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
      accept([:project_id, :graph_summary, :stats])
    end
  end

  code_interface do
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:read_all, action: :read)
  end
end

