defmodule Lang.Workspace.Workspace do
  @moduledoc """
  Workspace resource representing an ephemeral analysis context tied to a user/org.

  Durable metadata is stored here; large/ephemeral state lives in Redis via
  `Lang.Workspace.Store` keyed by `workspace.id`.
  """

  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: Lang.Ash.RedisDataLayer

  alias Lang.Accounts.{User, Organization}

  attributes do
    # Redis-backed resource; store id as UUID string
    attribute :id, :uuid do
      primary_key?(true)
      allow_nil?(false)
    end

    attribute :name, :string do
      allow_nil?(false)
    end

    attribute(:slug, :string)

    attribute(:owner_user_id, :uuid)
    attribute(:organization_id, :uuid)

    attribute(:root_path, :string)
    attribute(:vfs_root_uri, :string, description: "VFS URI for workspace root (Kyozo)")

    attribute :status, :atom do
      default(:active)
      constraints(one_of: [:active, :archived, :deleted])
    end

    attribute(:metadata, :map, default: %{})

    # JSON-LD document containing the current state
    attribute(:jsonld, :map, default: %{"@context" => %{}, "@graph" => []})
    attribute(:version, :integer, default: 1)
    attribute(:states, {:array, :map}, default: [])

    # TTL for Redis persistence (seconds)
    attribute(:ttl, :integer, default: 7_200)
  end

  # Cross data-layer relationships are not enforced here; use owner_user_id/organization_id for lookups

  validations do
    validate(present([:name]))
  end

  actions do
    defaults([:read, :destroy])

    read :by_id do
      argument(:id, :uuid, allow_nil?: false)
      filter(expr(id == ^arg(:id)))
    end

    create :create do
      accept([
        :name,
        :slug,
        :root_path,
        :vfs_root_uri,
        :metadata,
        :owner_user_id,
        :organization_id,
        :jsonld,
        :ttl
      ])

      change(fn changeset, _ ->
        id = Ash.Changeset.get_attribute(changeset, :id) || Ecto.UUID.generate()
        name = Ash.Changeset.get_attribute(changeset, :name) || "workspace"

        slug =
          Ash.Changeset.get_attribute(changeset, :slug) ||
            name
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9\-]/, "-")

        jsonld =
          Ash.Changeset.get_attribute(changeset, :jsonld) ||
            %{
              "@context" => %{},
              "@graph" => []
            }

        changeset
        |> Ash.Changeset.change_attribute(:id, id)
        |> Ash.Changeset.change_attribute(:slug, slug)
        |> Ash.Changeset.change_attribute(:jsonld, jsonld)
      end)
    end

    update :merge_ld do
      accept([:jsonld])

      change(fn changeset, _ ->
        current = changeset.data.jsonld || %{}
        incoming = Ash.Changeset.get_attribute(changeset, :jsonld) || %{}
        merged = Map.merge(current, incoming, fn _k, v1, v2 -> deep_merge(v1, v2) end)
        Ash.Changeset.change_attribute(changeset, :jsonld, merged)
      end)
    end

    update :snapshot_state do
      accept([])

      change(fn changeset, _ ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        version = (changeset.data.version || 0) + 1

        states =
          (changeset.data.states || []) ++
            [%{version: version, at: now, jsonld: changeset.data.jsonld}]

        changeset
        |> Ash.Changeset.change_attribute(:version, version)
        |> Ash.Changeset.change_attribute(:states, states)
      end)
    end
  end

  code_interface do
    define(:create)
    define(:merge_ld)
    define(:snapshot_state)
    define(:destroy)
    define(:by_id, get_by: [:id])
    define(:read_all, action: :read)
  end

  defp deep_merge(%{} = a, %{} = b), do: Map.merge(a, b, fn _k, v1, v2 -> deep_merge(v1, v2) end)
  defp deep_merge(_a, b), do: b
end
