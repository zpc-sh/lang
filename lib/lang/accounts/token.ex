defmodule Lang.Accounts.Token do
  use Ash.Resource,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer

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

    attribute :audience, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :jti, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :purpose, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :expires_at, :utc_datetime do
      allow_nil?(false)
      public?(true)
    end

    attribute :token_type, :string do
      allow_nil?(false)
      public?(true)
      default("Bearer")
    end

    attribute :context, :map do
      public?(true)
      default(%{})
    end

    timestamps()
  end

  identities do
    identity(:unique_jti, [:jti])
  end

  actions do
    defaults([:create, :read, :update, :destroy])

    create :sign_in do
      accept([:subject, :audience, :jti, :purpose, :expires_at, :context])
    end

    read :expired do
      filter(expr(expires_at < now()))
    end

    read :valid do
      filter(expr(expires_at >= now()))
    end
  end

  code_interface do
    define(:create)
    define(:sign_in)
    define(:read)
    define(:expired)
    define(:valid)
    define(:by_jti, get_by: [:jti], action: :read)
    define(:destroy)
  end

  # Required for AshAuthentication integration
  def token_revocation_resource, do: Lang.Accounts.TokenRevocation
end
