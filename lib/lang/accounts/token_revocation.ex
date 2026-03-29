defmodule Lang.Accounts.TokenRevocation do
  use Ash.Resource,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("token_revocations")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :token_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :revoked_at, :utc_datetime do
      allow_nil?(false)
      public?(true)
      default(&DateTime.utc_now/0)
    end

    attribute :reason, :string do
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :token, Lang.Accounts.Token do
      public?(true)
    end
  end

  actions do
    defaults([:create, :read, :destroy])

    create :revoke_token do
      accept([:token_id, :reason])
    end
  end

  code_interface do
    define(:create)
    define(:revoke_token)
    define(:read)
    define(:destroy)
  end
end
