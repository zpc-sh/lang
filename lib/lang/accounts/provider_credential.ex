defmodule Lang.Accounts.ProviderCredential do
  use Ash.Resource,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "provider_credentials"
    repo Lang.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      constraints one_of: [:openai, :anthropic, :xai, :gemini]
      public? true
    end

    attribute :encrypted_api_key, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :status, :atom do
      default :active
      constraints one_of: [:active, :revoked, :expired]
      public? true
    end

    attribute :default, :boolean do
      default false
      public? true
    end

    attribute :scopes, {:array, :string} do
      default []
      public? true
    end

    attribute :usage_count, :integer do
      default 0
      public? true
    end

    attribute :last_used_at, :utc_datetime do
      public? true
    end

    attribute :rotated_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :organization, Lang.Accounts.Organization do
      allow_nil? true
      public? true
    end

    belongs_to :user, Lang.Accounts.User do
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :org_provider_default, [:organization_id, :provider, :default]
    identity :user_provider_default, [:user_id, :provider, :default]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:provider, :organization_id, :user_id, :scopes, :status, :default]

      argument :api_key, :string, allow_nil?: false

      change fn changeset, _ctx ->
        api_key = Ash.Changeset.get_argument(changeset, :api_key)
        enc = Lang.Security.Encryption.encrypt(api_key)

        changeset
        |> Ash.Changeset.change_attribute(:encrypted_api_key, enc)
      end
    end

    update :rotate do
      accept [:status, :default]
      argument :api_key, :string, allow_nil?: false

      change fn changeset, _ctx ->
        api_key = Ash.Changeset.get_argument(changeset, :api_key)
        enc = Lang.Security.Encryption.encrypt(api_key)

        changeset
        |> Ash.Changeset.change_attribute(:encrypted_api_key, enc)
        |> Ash.Changeset.change_attribute(:rotated_at, DateTime.utc_now())
      end
    end

    update :update do
      accept [:status, :default, :scopes]
    end

    update :touch_usage do
      change fn changeset, _ctx ->
        current = changeset.data.usage_count || 0
        changeset
        |> Ash.Changeset.change_attribute(:usage_count, current + 1)
        |> Ash.Changeset.change_attribute(:last_used_at, DateTime.utc_now())
      end
    end

    read :by_org_and_provider do
      argument :organization_id, :uuid, allow_nil?: false
      argument :provider, :atom, allow_nil?: false

      filter expr(organization_id == ^arg(:organization_id) and provider == ^arg(:provider) and status == :active)

      prepare fn query, _ctx ->
        # Prefer default=true, else most recent
        Ash.Query.sort(query, [default: :desc, inserted_at: :desc])
      end
    end

    read :by_user_and_provider do
      argument :user_id, :uuid, allow_nil?: false
      argument :provider, :atom, allow_nil?: false

      filter expr(user_id == ^arg(:user_id) and provider == ^arg(:provider) and status == :active)

      prepare fn query, _ctx ->
        Ash.Query.sort(query, [default: :desc, inserted_at: :desc])
      end
    end
  end

  code_interface do
    define :create
    define :by_id, get_by: [:id], action: :read
    define :list_by_org_and_provider, action: :by_org_and_provider
    define :list_by_user_and_provider, action: :by_user_and_provider
    define :rotate
    define :touch_usage
  end

  validations do
    validate fn changeset, _ctx ->
      org_id = Ash.Changeset.get_attribute(changeset, :organization_id)
      user_id = Ash.Changeset.get_attribute(changeset, :user_id)

      if is_nil(org_id) and is_nil(user_id) do
        {:error, field: :organization_id, message: "either organization_id or user_id must be present"}
      else
        :ok
      end
    end
  end
end
