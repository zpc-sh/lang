defmodule Lang.Git.RepoSnapshot do
  @moduledoc """
  Immutable snapshot reference for a repo at a specific commit.

  Durable content (pack/tree/blob) lives in Kyozo VFS; this record stores
  the reference and minimal metadata for fast lookup.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "git_repo_snapshots"
    repo Lang.Repo
  end

  actions do
    defaults [:create, :read]
  end

  attributes do
    uuid_primary_key :id

    attribute :commit_sha, :string do
      allow_nil? false
    end

    attribute :tree_hash, :string do
      allow_nil? true
    end

    attribute :vfs_uri, :string do
      allow_nil? false
      description "Kyozo VFS CAS URI for the snapshot (content-addressed)"
    end

    attribute :size, :integer do
      allow_nil? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :repo, Lang.Git.Repo do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_snapshot, [:repo_id, :commit_sha]
  end
end
