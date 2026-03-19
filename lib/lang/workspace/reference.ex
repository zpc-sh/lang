defmodule Lang.Workspace.Reference do
  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: Lang.Ash.RedisDataLayer

  attributes do
    uuid_primary_key(:id)

    attribute :from_symbol_id, :uuid

    attribute :to_symbol_id, :uuid

    attribute :reference_type, :atom do
      constraints(one_of: [:call, :import, :extend, :implement, :compose])
    end

    attribute(:file_path, :string)
    attribute(:line, :integer)
    attribute(:column, :integer)

    # Context snippet instead of full file
    attribute :context_snippet, :string do
      description("3 lines before/after reference")
    end

    attribute :confidence, :float do
      default(1.0)
      constraints(min: 0.0, max: 1.0)
    end
  end

  relationships do
    belongs_to :from_symbol, Lang.Workspace.Symbol do
      public? true
    end
    belongs_to :to_symbol, Lang.Workspace.Symbol do
      public? true
    end
    belongs_to :workspace, Lang.Workspace.Workspace, domain: Lang.Workspaces
  end

  actions do
    defaults([:create, :read])

    create :track_reference do
      accept([:from_symbol_id, :to_symbol_id, :reference_type, :file_path, :line])

      change(fn changeset, _context ->
        # Extract context snippet instead of storing full file
        file_path = Ash.Changeset.get_attribute(changeset, :file_path)
        line = Ash.Changeset.get_attribute(changeset, :line)

        snippet = Lang.Workspace.Snippets.extract_context(file_path, line, 3)

        Ash.Changeset.change_attribute(changeset, :context_snippet, snippet)
      end)

      change(fn changeset, _context ->
        # Update reference count on the target symbol
        to_symbol_id = Ash.Changeset.get_attribute(changeset, :to_symbol_id)

        case Lang.Workspace.Symbol.get(to_symbol_id) do
          {:ok, symbol} ->
            current_count = symbol.references_count || 0
            Lang.Workspace.Symbol.update!(symbol, %{references_count: current_count + 1})

          _ ->
            # Symbol might not exist yet, that's ok
            :ok
        end

        changeset
      end)
    end

    read :find_references_to do
      argument(:symbol_id, :uuid)

      filter(expr(to_symbol_id == ^arg(:symbol_id)))
    end

    read :find_references_from do
      argument(:symbol_id, :uuid)

      filter(expr(from_symbol_id == ^arg(:symbol_id)))
    end
  end

  code_interface do
    define(:track, action: :track_reference)
    define(:find_to, action: :find_references_to, args: [:symbol_id])
    define(:find_from, action: :find_references_from, args: [:symbol_id])
  end

  # Redis configuration
  # 1 hour TTL
  attributes do
    attribute(:ttl, :integer, public?: false, default: 3600)
  end

  identities do
    identity(:by_from_symbol, [:from_symbol_id])
    identity(:by_to_symbol, [:to_symbol_id])
    identity(:by_reference_type, [:reference_type])
  end
end
