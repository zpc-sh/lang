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
    uuid_primary_key(:id)

    attribute :subject, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :token, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :purpose, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :context, :map do
      public?(true)
    end

    attribute :expires_at, :utc_datetime do
      allow_nil?(false)
      public?(true)
    end

    timestamps()
  end

  identities do
    identity(:unique_token, [:token])
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  code_interface do
    define(:create)
    define(:read)
    define(:by_token, get_by: [:token], action: :read)
    define(:destroy)
  end

  token_resource do
    revocation_resource(Lang.Accounts.TokenRevocation)
  end
end
