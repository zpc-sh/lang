defmodule Lang.Workspace.Symbol do
  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: Lang.Ash.RedisDataLayer

  attributes do
    uuid_primary_key(:id)

    attribute :workspace_id, :uuid do
      allow_nil?(false)
    end

    attribute :file_path, :string do
      allow_nil?(false)
    end

    attribute :name, :string do
      allow_nil?(false)
    end

    attribute :type, :atom do
      constraints(one_of: [:function, :module, :type, :variable, :macro])
    end

    attribute(:line_start, :integer)
    attribute(:line_end, :integer)
    attribute(:column_start, :integer)
    attribute(:column_end, :integer)

    # JSON-LD schema reference
    attribute :jsonld_schema, :map do
      description("Persisted JSON-LD for this symbol")
    end

    # Token optimization metrics
    attribute(:token_count, :integer)
    attribute(:compressed_token_count, :integer)
    attribute(:reduction_percentage, :float)

    # Semantic metadata
    attribute(:semantic_fingerprint, :string)
    attribute(:references_count, :integer, default: 0)
    attribute :pattern_id, :uuid, allow_nil?: true
    attribute(:last_modified, :utc_datetime_usec)

    timestamps()
  end

  relationships do
    belongs_to :workspace, Lang.Workspace.Workspace, domain: Lang.Workspaces

    has_many :outgoing_references, Lang.Workspace.Reference do
      destination_attribute :from_symbol_id
    end

    has_many :incoming_references, Lang.Workspace.Reference do
      destination_attribute :to_symbol_id
    end

    has_many :patterns, Lang.Workspace.Pattern

    many_to_many :working_sets, Lang.Workspace.WorkingSet do
      through(Lang.Workspace.WorkingSetSymbol)
    end
  end

  calculations do
    calculate(:token_savings, :integer, expr(token_count - compressed_token_count))

    calculate :efficiency_grade, :string do
      calculation(fn records, _context ->
        Enum.map(records, fn record ->
          reduction = record.reduction_percentage || 0

          cond do
            # 60% achievement
            reduction >= 0.6 -> "A++"
            # 50% achievement
            reduction >= 0.5 -> "A+"
            reduction >= 0.4 -> "A"
            reduction >= 0.3 -> "B"
            reduction >= 0.2 -> "C"
            true -> "D"
          end
        end)
      end)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([
        :workspace_id,
        :file_path,
        :name,
        :type,
        :line_start,
        :line_end,
        :column_start,
        :column_end,
        :jsonld_schema,
        :token_count,
        :compressed_token_count,
        :reduction_percentage,
        :semantic_fingerprint,
        :references_count,
        :last_modified
      ])
    end

    create :extract do
      accept([:workspace_id, :file_path])

      change(fn changeset, _context ->
        file_path = Ash.Changeset.get_attribute(changeset, :file_path)

        # Use Rust NIF for extraction
        symbols = Lang.Native.TreeParser.extract_symbols(file_path)

        # Process each symbol
        Enum.reduce(symbols, changeset, fn sym, acc ->
          symbol_data = %{
            name: sym.name,
            type: sym.type,
            line_start: sym.line_start,
            line_end: sym.line_end,
            token_count: calculate_tokens(sym),
            compressed_token_count: calculate_compressed_tokens(sym),
            reduction_percentage: calculate_reduction(sym),
            semantic_fingerprint: generate_fingerprint(sym),
            jsonld_schema: emit_jsonld(sym)
          }

          # Notify chatroom if we hit benchmarks
          if symbol_data.reduction_percentage >= 0.5 do
            Lang.Workspace.ChatMessage.broadcast!(
              :optimization,
              %{
                achievement: "50% reduction",
                symbol: sym.name,
                reduction: symbol_data.reduction_percentage
              }
            )
          end

          Ash.Changeset.change_attributes(acc, symbol_data)
        end)
      end)
    end

    read :find_references do
      argument(:symbol_name, :string, allow_nil?: false)

      prepare(fn query, context ->
        symbol_name = context.arguments.symbol_name

        query
        |> Ash.Query.filter(%{name: symbol_name})
        |> Ash.Query.load([:references, :patterns])
      end)
    end

    update :update_metrics do
      accept([:token_count, :compressed_token_count, :reduction_percentage])

      change(fn changeset, _context ->
        # Notify chatroom of optimization success
        if Ash.Changeset.get_attribute(changeset, :reduction_percentage) >= 0.5 do
          Lang.Workspace.ChatMessage.broadcast!(
            :optimization_achieved,
            %{symbol: changeset.data.name}
          )
        end

        changeset
      end)
    end
  end

  code_interface do
    define(:create_symbol, action: :create)
    define(:extract_symbols, action: :extract, args: [:workspace_id, :file_path])
    define(:find_by_name, action: :find_references, args: [:symbol_name])
    define(:update_token_metrics, action: :update_metrics)
  end

  # Redis configuration
  # 4 hours TTL
  attributes do
    attribute(:ttl, :integer, public?: false, default: 14400)
  end

  identities do
    identity(:by_location, [:workspace_id, :file_path])
    identity(:by_name, [:name])
    identity(:by_type, [:type])
    identity(:by_fingerprint, [:semantic_fingerprint])
  end

  # Private helper functions
  defp calculate_tokens(symbol) do
    # Implementation would call Rust NIFs or other token calculation logic
    # This is a placeholder
    String.length(symbol.content || "")
  end

  defp calculate_compressed_tokens(symbol) do
    # Implementation would call compression logic from Rust NIFs
    # This is a placeholder
    content = symbol.content || ""
    max(1, round(String.length(content) * 0.6))
  end

  defp calculate_reduction(symbol) do
    original = calculate_tokens(symbol)
    compressed = calculate_compressed_tokens(symbol)

    if original > 0 do
      (original - compressed) / original
    else
      0.0
    end
  end

  defp generate_fingerprint(symbol) do
    # Create a semantic fingerprint for the symbol
    # This is a placeholder
    :crypto.hash(:sha256, "\#{symbol.name}\#{symbol.type}") |> Base.encode16()
  end

  defp emit_jsonld(symbol) do
    # Generate JSON-LD representation
    # This is a placeholder
    %{
      "@context": "https://schema.org/",
      "@type": "SoftwareSourceCode",
      name: symbol.name,
      codeRepository: symbol.file_path,
      programmingLanguage: detect_language(symbol.file_path)
    }
  end

  defp detect_language(file_path) do
    # Detect language from file extension
    # This is a placeholder
    case Path.extname(file_path) do
      ".ex" -> "Elixir"
      ".exs" -> "Elixir"
      ".rs" -> "Rust"
      ".js" -> "JavaScript"
      ".ts" -> "TypeScript"
      ".py" -> "Python"
      _ -> "Unknown"
    end
  end
end
