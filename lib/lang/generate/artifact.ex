defmodule Lang.Generate.Artifact do
  @moduledoc """
  Generated artifact (patch, file, service config) created by a Generate request.
  """

  use Ash.Resource,
    domain: Lang.Generate,
    data_layer: AshPostgres.DataLayer

  alias Lang.Generate.Request

  postgres do
    table("generate_artifacts")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :path, :string do
      allow_nil?(true)
    end

    attribute :language, :string do
      allow_nil?(true)
    end

    attribute :change_type, :atom do
      allow_nil?(false)
      default(:create)
      constraints(one_of: [:create, :update, :delete])
    end

    attribute :patch, :string do
      allow_nil?(true)
      description("Unified diff or semantic patch content")
    end

    attribute :vfs_uri, :string do
      allow_nil?(true)
    end

    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :request, Request do
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read])
    create :create do
      accept([:request_id, :path, :language, :change_type, :patch, :vfs_uri, :metadata])
    end
  end

  code_interface do
    define(:read_all, action: :read)
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
  end
end

