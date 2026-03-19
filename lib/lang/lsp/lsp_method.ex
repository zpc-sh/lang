defmodule Lang.LSP.LspMethod do
  @moduledoc """
  Canonical LSP method record (source-of-truth mirror of JSON-LD specs).
  """
  use Ash.Resource,
    domain: Lang.LSP,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table("lsp_methods")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      constraints(match: ~r/^\w+\.[\w\.]+$/)
      description("Compact method name, e.g., lang.think.explain_intent")
    end

    attribute(:category, :string)
    attribute(:description, :string)
    attribute(:priority, :string)
    attribute(:spec_status, :string)

    attribute :derived_status, :atom do
      constraints(one_of: [:implemented, :in_progress, :not_started])
      default(:not_started)
    end

    attribute(:impl_file, :string)
    attribute(:impl_module, :string)
    attribute(:impl_function, :string)
    attribute(:impl_arity, :integer)

    attribute(:params_schema, :map, default: %{})
    attribute(:result_schema, :map, default: %{})
    attribute(:links, :map, default: %{})
    attribute(:metadata, :map, default: %{})

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_name, [:name])
  end

  actions do
    defaults([:read])

    create :upsert do
      accept([
        :name,
        :category,
        :description,
        :priority,
        :spec_status,
        :impl_file,
        :impl_module,
        :impl_function,
        :impl_arity,
        :params_schema,
        :result_schema,
        :links,
        :metadata,
        :derived_status
      ])

      upsert?(true)
      upsert_identity(:unique_name)
    end

    update :set_derived_status do
      accept([:derived_status])
      require_atomic?(false)
    end

    destroy :delete do
      require_atomic?(false)
      primary?(true)
    end
  end

  # Ash v3 wrapper shims (no code_interface)
  def read_all do
    __MODULE__
    |> Ash.read()
  end

  def upsert(attrs) when is_map(attrs) do
    __MODULE__
    |> Ash.Changeset.for_create(:upsert, attrs)
    |> Ash.create()
  end

  def set_derived_status(name, status) when is_binary(name) do
    case __MODULE__ |> Ash.Query.filter(name == ^name) |> Ash.read_one() do
      {:ok, nil} -> {:error, :not_found}
      {:ok, rec} -> set_derived_status(rec, status)
      {:error, reason} -> {:error, reason}
    end
  end

  def set_derived_status(rec, status) do
    rec
    |> Ash.Changeset.for_update(:set_derived_status, %{derived_status: status})
    |> Ash.update()
  end

  def delete_by_name(name) when is_binary(name) do
    case __MODULE__ |> Ash.Query.filter(name == ^name) |> Ash.read_one() do
      {:ok, nil} -> {:error, :not_found}
      {:ok, rec} -> delete(rec)
      {:error, reason} -> {:error, reason}
    end
  end

  def delete(rec) do
    rec
    |> Ash.Changeset.for_destroy(:delete)
    |> Ash.destroy()
  end
end
