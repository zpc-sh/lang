defmodule Lang.Documents.Document do
  use Ash.Resource,
    domain: Lang.Documents,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("documents")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
    attribute(:content, :string, allow_nil?: false, public?: true)
    attribute(:format, :string, default: "markdown", public?: true)

    timestamps()
  end

  relationships do
    belongs_to :user, Lang.Accounts.User, public?: true
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end
end
