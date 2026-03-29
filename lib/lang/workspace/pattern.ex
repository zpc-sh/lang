defmodule Lang.Workspace.Pattern do
  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: Lang.Ash.RedisDataLayer

  attributes do
    uuid_primary_key(:id)

    attribute :workspace_id, :uuid do
      allow_nil?(false)
    end

    attribute :name, :string do
      allow_nil?(false)
    end

    attribute(:description, :string)

    attribute :pattern_type, :atom do
      constraints(one_of: [:syntax, :semantic, :token, :optimization])
    end

    # Pattern definition - could be regex, AST pattern, etc.
    attribute :definition, :map do
      allow_nil?(false)
    end

    # Example matches
    attribute :examples, {:array, :map} do
      default([])
    end

    # Usage statistics
    attribute :match_count, :integer do
      default(0)
    end

    attribute :token_savings, :integer do
      default(0)
    end

    # Confidence level for automatically applying this pattern
    attribute :confidence, :float do
      default(0.7)
      constraints(min: 0.0, max: 1.0)
    end

    timestamps()
  end

  relationships do
    belongs_to :workspace, Lang.Workspace.Workspace
    belongs_to :symbol, Lang.Workspace.Symbol
  end

  actions do
    defaults([:create, :read, :update, :destroy])

    create :discover do
      accept([:workspace_id, :name, :pattern_type, :definition, :examples])

      change(fn changeset, _context ->
        # Generate a descriptive name if not provided
        name = Ash.Changeset.get_attribute(changeset, :name)
        definition = Ash.Changeset.get_attribute(changeset, :definition)

        if is_nil(name) || name == "" do
          generated_name = generate_pattern_name(definition)
          Ash.Changeset.change_attribute(changeset, :name, generated_name)
        else
          changeset
        end
      end)

      # Broadcast new pattern discovery
      after_action(fn result, _context ->
        pattern = result.result

        Lang.Workspace.ChatMessage.broadcast!(
          :patterns,
          %{
            message: "New pattern discovered",
            pattern_name: pattern.name,
            pattern_type: pattern.pattern_type
          }
        )

        {:ok, result}
      end)
    end

    update :record_match do
      argument(:token_savings, :integer, default: 0)

      change(fn changeset, context ->
        current_count = Ash.Changeset.get_attribute(changeset, :match_count) || 0
        current_savings = Ash.Changeset.get_attribute(changeset, :token_savings) || 0

        changeset
        |> Ash.Changeset.change_attribute(:match_count, current_count + 1)
        |> Ash.Changeset.change_attribute(
          :token_savings,
          current_savings + context.arguments.token_savings
        )
      end)
    end

    update :add_example do
      argument(:example, :map, allow_nil?: false)

      change(fn changeset, context ->
        current_examples = Ash.Changeset.get_attribute(changeset, :examples) || []
        new_examples = [context.arguments.example | current_examples] |> Enum.take(10)

        Ash.Changeset.change_attribute(changeset, :examples, new_examples)
      end)
    end

    read :for_optimization do
      filter(expr(pattern_type == :optimization))

      prepare(fn query, _context ->
        Ash.Query.sort(query, token_savings: :desc)
      end)

      prepare(fn query, _context ->
        query
        |> Ash.Query.limit(10)
      end)
    end

    read :find_by_name do
      argument(:name, :string, allow_nil?: false)
      filter(expr(name == ^arg(:name)))
    end

    read :by_confidence_threshold do
      argument(:threshold, :float, allow_nil?: false)
      filter(expr(confidence >= ^arg(:threshold)))
    end
  end

  code_interface do
    define(:create_pattern, action: :create)
    define(:discover_pattern, action: :discover)
    define(:record_pattern_match, action: :record_match, args: [:token_savings])
    define(:add_pattern_example, action: :add_example, args: [:example])
    define(:list_optimization_patterns, action: :for_optimization)
    define(:find_pattern_by_name, action: :find_by_name, args: [:name])

    define(:get_high_confidence_patterns,
      action: :by_confidence_threshold,
      args: [:threshold]
    )
  end

  # Redis configuration
  # 8 hours TTL
  attributes do
    attribute(:ttl, :integer, public?: false, default: 28800)
  end

  identities do
    identity(:by_workspace, [:workspace_id])
    identity(:by_pattern_type, [:pattern_type])
    identity(:by_name, [:name])
  end

  # Helper functions for pattern management
  defp generate_pattern_name(definition) do
    # This would generate a human-readable name based on the pattern definition
    # This is a placeholder implementation
    pattern_type = get_in(definition, [:type]) || "generic"
    target = get_in(definition, [:target]) || "code"

    hash =
      :crypto.hash(:md5, inspect(definition)) |> Base.encode16(case: :lower) |> String.slice(0, 6)

    "#{pattern_type}_#{target}_#{hash}"
  end
end
