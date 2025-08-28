defmodule Lang.Git.Repo do
  @moduledoc """
  Git repository resource tracked by LANG.

  Stores normalized identification and defaults for read-only Git operations
  whose durable data is persisted in Kyozo VFS CAS.
  """

  use Ash.Resource,
    domain: Lang.Git,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("git_repos")
    repo(Lang.Repo)
  end

  actions do
    defaults([:create, :read, :update])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :url, :string do
      allow_nil?(false)
    end

    attribute :normalized_id, :string do
      allow_nil?(false)
      description("Provider-agnostic unique id (e.g., owner/repo)")
    end

    attribute :provider, :atom do
      allow_nil?(false)
      constraints(one_of: [:github, :gitlab, :bitbucket, :other])
      default(:other)
    end

    attribute :default_branch, :string do
      default("main")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_repo, [:normalized_id, :provider])
  end
end
