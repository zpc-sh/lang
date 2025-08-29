defmodule Lang.Accounts.ApiKey do
  use Ash.Resource,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("api_keys")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :key, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :key_prefix, :string do
      public?(true)
    end

    attribute :hashed_key, :string do
      allow_nil?(false)
      sensitive?(true)
    end

    attribute :status, :atom do
      constraints(one_of: [:active, :revoked, :expired])
      default(:active)
      public?(true)
    end

    attribute :last_used_at, :utc_datetime do
      public?(true)
    end

    attribute :usage_count, :integer do
      default(0)
      public?(true)
    end

    attribute :expires_at, :utc_datetime do
      public?(true)
    end

    # Scope and permissions
    attribute :scopes, {:array, :string} do
      default(["read", "write"])
      public?(true)
    end

    attribute :ip_whitelist, {:array, :string} do
      default([])
      public?(true)
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Lang.Accounts.User do
      attribute_writable?(true)
    end

    belongs_to :organization, Lang.Accounts.Organization do
      allow_nil?(false)
      public?(true)
    end
  end

  identities do
    identity(:unique_key, [:key])
    identity(:unique_name_per_user, [:user_id, :name])
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :user_id, :organization_id, :scopes, :ip_whitelist, :expires_at])

      change(fn changeset, _context ->
        # Generate API key
        key = generate_api_key()
        key_prefix = String.slice(key, 0, 8)
        hashed_key = hash_api_key(key)

        changeset
        |> Ash.Changeset.change_attribute(:key, key)
        |> Ash.Changeset.change_attribute(:key_prefix, key_prefix)
        |> Ash.Changeset.change_attribute(:hashed_key, hashed_key)
      end)
    end

    update :update do
      primary?(true)
      accept([:name, :scopes, :ip_whitelist, :expires_at])
    end

    update :revoke do
      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :revoked)
      end)
    end

    update :activate do
      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :status, :active)
      end)
    end

    update :record_usage do
      change(fn changeset, _context ->
        current_count = changeset.data.usage_count || 0

        changeset
        |> Ash.Changeset.change_attribute(:usage_count, current_count + 1)
        |> Ash.Changeset.change_attribute(:last_used_at, DateTime.utc_now())
      end)
    end

    destroy :destroy do
      primary?(true)
    end

    read :active do
      filter(expr(status == :active))
    end

    read :by_user do
      argument(:user_id, :uuid, allow_nil?: false)
      filter(expr(user_id == ^arg(:user_id)))
    end

    read :by_organization do
      argument(:organization_id, :uuid, allow_nil?: false)
      filter(expr(organization_id == ^arg(:organization_id)))
    end
  end

  code_interface do
    define(:create)
    define(:by_id, get_by: [:id], action: :read)
    define(:by_key, get_by: [:key], action: :read)
    define(:list_active, action: :active)
    define(:list_by_user, action: :by_user)
    define(:list_by_organization, action: :by_organization)
    define(:update)
    define(:revoke)
    define(:activate)
    define(:record_usage)
    define(:destroy)
  end

  preparations do
    prepare(build(load: [:user, :organization]))
  end

  validations do
    validate(string_length(:name, min: 1, max: 100))
    validate(present([:name, :user_id, :organization_id]))

    validate(fn changeset, _context ->
      scopes = Ash.Changeset.get_attribute(changeset, :scopes) || []
      valid_scopes = ["read", "write", "admin"]

      if Enum.all?(scopes, &(&1 in valid_scopes)) do
        :ok
      else
        {:error,
         field: :scopes, message: "contains invalid scopes. Valid: #{inspect(valid_scopes)}"}
      end
    end)
  end

  # Helper functions
  def authenticate(api_key) do
    case by_key(api_key) do
      {:ok, key} ->
        if active?(key) and not expired?(key) do
          {:ok, key}
        else
          {:error, :invalid_key}
        end

      {:error, _} ->
        {:error, :invalid_key}
    end
  end

  def active?(%{status: :active}), do: true
  def active?(_), do: false

  def expired?(%{expires_at: nil}), do: false

  def expired?(%{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  def has_scope?(%{scopes: scopes}, required_scope) do
    required_scope in (scopes || [])
  end

  def allowed_ip?(%{ip_whitelist: []}, _ip), do: true

  def allowed_ip?(%{ip_whitelist: whitelist}, ip) do
    ip in whitelist
  end

  def display_key(%{key_prefix: prefix}) when is_binary(prefix) do
    prefix <> "..." <> String.duplicate("*", 32)
  end

  def display_key(_), do: "sk-****..."

  defp generate_api_key do
    ("sk_" <> Base.encode64(:crypto.strong_rand_bytes(32), padding: false))
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.slice(0, 48)
  end

  defp hash_api_key(key) do
    salt = Application.get_env(:lang, :api_key_salt, "lang_default_salt")
    :crypto.hash(:sha256, key <> salt) |> Base.encode64()
  end
end
