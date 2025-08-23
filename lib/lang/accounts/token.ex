defmodule Lang.Accounts.Token do
  use Ash.Resource,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table("tokens")
    repo(Lang.Repo)
  end

  attributes do
    attribute(:jti, :string,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      sensitive?: true
    )

    attribute(:subject, :string, allow_nil?: false, public?: true)
    attribute(:token, :string, allow_nil?: false, sensitive?: true)
    attribute(:purpose, :string, allow_nil?: false, public?: true)
    attribute(:expires_at, :utc_datetime, allow_nil?: false, public?: true)
    attribute(:extra_data, :map, default: %{}, public?: true)

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :store_token do
      argument(:token, :string, allow_nil?: false, sensitive?: true)
      accept([:subject, :token, :purpose, :expires_at, :extra_data])
      change(AshAuthentication.TokenResource.StoreTokenChange)
    end

    read :get_token do
      argument(:token, :string, allow_nil?: true, sensitive?: true)
      argument(:jti, :string, allow_nil?: true)
      argument(:purpose, :string, allow_nil?: true)
      filter(expr(token == ^arg(:token)))
      prepare(build(limit: 1))
      prepare(AshAuthentication.TokenResource.GetTokenPreparation)
    end

    read :valid_tokens do
      filter(expr(is_nil(expires_at) or expires_at > now()))
    end
  end

  relationships do
    belongs_to :user, Lang.Accounts.User do
      source_attribute(:subject)
      destination_attribute(:id)
      attribute_type(:uuid)
    end
  end

  identities do
    identity(:unique_token, [:token])
  end

  validations do
    validate(present([:subject, :token, :purpose]))

    validate compare(:expires_at, greater_than: &DateTime.utc_now/0) do
      where([present(:expires_at)])
      message("cannot be in the past")
    end
  end

  preparations do
    prepare(build(sort: [inserted_at: :desc]))
  end

  code_interface do
    define(:store_token)
    define(:get_token)
    define(:valid_tokens)
    define(:read_all, action: :read)
    define(:destroy)
  end
end
