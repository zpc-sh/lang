defmodule Lang.Git.Artifact do
  @moduledoc """
  Artifact persisted for a snapshot (e.g., pack, tar, index), content-addressed.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "git_artifacts"
    repo Lang.Repo
  end

  actions do
    defaults [:create, :read]
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :string do
      allow_nil? false
      constraints one_of: ["pack", "tar", "index", "blob", "tree"]
    end

    attribute :digest, :string do
      allow_nil? false
      description "Content digest (sha256 or similar)"
    end

    attribute :vfs_uri, :string do
      allow_nil? false
      description "Kyozo VFS CAS URI"
    end

    attribute :size, :integer do
      allow_nil? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :snapshot, Lang.Git.RepoSnapshot do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_artifact, [:snapshot_id, :kind, :digest]
  end
end
