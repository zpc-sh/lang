defmodule Lang.TextIntelligence.SymbolAnalyzer do
  @moduledoc """
  Symbol analysis engine for code understanding and navigation.

  Provides intelligent symbol analysis capabilities including:
  - Symbol definition finding
  - Reference tracking
  - Symbol extraction from code
  - Workspace-wide symbol search
  - Semantic symbol understanding
  """

  require Logger
  alias Lang.Native.PerfEngine
  alias Lang.TextIntelligence.FormatDetector

  @type symbol :: %{
          name: String.t(),
          kind: symbol_kind(),
          location: location(),
          container_name: String.t() | nil,
          detail: String.t() | nil,
          documentation: String.t() | nil
        }

  @type symbol_kind ::
          :file
          | :module
          | :namespace
          | :package
          | :class
          | :method
          | :property
          | :field
          | :constructor
          | :enum
          | :interface
          | :function
          | :variable
          | :constant
          | :string
          | :number
          | :boolean
          | :array
          | :object
          | :key
          | :null
          | :enum_member
          | :struct
          | :event
          | :operator
          | :type_parameter

  @type location :: %{
          uri: String.t(),
          range: range()
        }

  @type range :: %{
          start: position(),
          end: position()
        }

  @type position :: %{
          line: non_neg_integer(),
          character: non_neg_integer()
        }

  @type definition_result :: %{
          location: location(),
          kind: symbol_kind(),
          name: String.t(),
          detail: String.t() | nil
        }

  @type reference_result :: %{
          location: location(),
          context: String.t()
        }

  # Symbol kind mappings for different languages (moved to functions to avoid serialization issues)
  defp get_symbol_patterns do
    %{
      "elixir" => %{
        module: ~r/defmodule\s+([\w\.]+)/,
        function: ~r/def\s+(\w+)/,
        private_function: ~r/defp\s+(\w+)/,
        macro: ~r/defmacro\s+(\w+)/,
        struct: ~r/defstruct\s+/,
        protocol: ~r/defprotocol\s+(\w+)/,
        implementation: ~r/defimpl\s+(\w+)/,
        attribute: ~r/@(\w+)/,
        variable: ~r/(\w+)\s*=/
      },
      "javascript" => %{
        function: ~r/function\s+(\w+)/,
        arrow_function: ~r/const\s+(\w+)\s*=.*=>/,
        class: ~r/class\s+(\w+)/,
        method: ~r/(\w+)\s*\(/,
        variable: ~r/(?:let|const|var)\s+(\w+)/,
        import: ~r/import.*\{([^}]+)\}.*from/,
        export: ~r/export\s+(?:default\s+)?(?:function\s+)?(\w+)/
      },
      "python" => %{
        class: ~r/class\s+(\w+)/,
        function: ~r/def\s+(\w+)/,
        variable: ~r/(\w+)\s*=/,
        import: ~r/from\s+[\w\.]+\s+import\s+([\w\s,]+)/,
        import_module: ~r/import\s+([\w\.]+)/
      }
    }
  end

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Find definition of a symbol at the given position.
  """
  @spec find_definition(String.t(), String.t(), String.t()) ::
          {:ok, [definition_result()]} | {:error, String.t()}
  def find_definition(word, uri, root_uri) when is_binary(word) and is_binary(uri) do
    Logger.debug("Finding definition for symbol", word: word, uri: uri)

    try do
      # Get file content
      with {:ok, content} <- read_file_content(uri),
           format <- FormatDetector.detect_from_uri(uri),
           definitions <- search_definitions(word, content, format, uri, root_uri) do
        {:ok, definitions}
      else
        {:error, reason} ->
          Logger.warning("Definition search failed", reason: reason, word: word)
          {:error, reason}

        error ->
          Logger.error("Unexpected error in definition search", error: inspect(error))
          {:error, "Definition search failed"}
      end
    rescue
      error ->
        Logger.error("Exception in find_definition", error: inspect(error))
        {:error, "Definition search failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Find all references to a symbol in the workspace.
  """
  @spec find_references(String.t(), String.t()) ::
          {:ok, [reference_result()]} | {:error, String.t()}
  def find_references(word, root_uri) when is_binary(word) and is_binary(root_uri) do
    Logger.debug("Finding references for symbol", word: word, root_uri: root_uri)

    try do
      # Use native file scanner for performance
      case Lang.Native.FSScanner.search(root_uri, word, max_results: 1000) do
        {:ok, results} ->
          references =
            results
            |> Enum.map(&convert_to_reference/1)
            |> Enum.reject(&is_nil/1)

          {:ok, references}

        {:error, reason} ->
          Logger.warning("Reference search failed", reason: reason, word: word)
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception in find_references", error: inspect(error))
        {:error, "Reference search failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Extract symbols from text content.
  """
  @spec extract_symbols(String.t(), String.t()) :: {:ok, [symbol()]} | {:error, String.t()}
  def extract_symbols(text, language_id) when is_binary(text) and is_binary(language_id) do
    Logger.debug("Extracting symbols", language: language_id, content_length: String.length(text))

    try do
      format = normalize_language_id(language_id)
      symbols = parse_symbols(text, format)
      {:ok, symbols}
    rescue
      error ->
        Logger.error("Exception in extract_symbols", error: inspect(error))
        {:error, "Symbol extraction failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Search for symbols across the entire workspace.
  """
  @spec search_workspace(String.t(), String.t()) :: {:ok, [symbol()]} | {:error, String.t()}
  def search_workspace(query, root_uri) when is_binary(query) and is_binary(root_uri) do
    Logger.debug("Searching workspace for symbols", query: query, root_uri: root_uri)

    try do
      # Use semantic search if available, fall back to text search
      case Lang.Native.FSScanner.search_code(root_uri, "elixir", build_tree_sitter_query(query)) do
        {:ok, results} ->
          symbols =
            results
            |> Enum.map(&convert_search_result_to_symbol/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.take(100)

          {:ok, symbols}

        {:error, _} ->
          # Fallback to text search
          fallback_workspace_search(query, root_uri)
      end
    rescue
      error ->
        Logger.error("Exception in search_workspace", error: inspect(error))
        {:error, "Workspace search failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Get symbol information at a specific position.
  """
  @spec get_symbol_at_position(String.t(), position(), String.t()) ::
          {:ok, symbol() | nil} | {:error, String.t()}
  def get_symbol_at_position(content, position, format) do
    try do
      lines = String.split(content, "\n")
      line_content = Enum.at(lines, position.line, "")

      if position.character < String.length(line_content) do
        word = extract_word_at_position(line_content, position.character)

        if word && String.length(word) > 0 do
          symbols = parse_symbols(content, format)

          symbol =
            Enum.find(symbols, fn sym ->
              sym.name == word and
                position_in_range?(position, sym.location.range)
            end)

          {:ok, symbol}
        else
          {:ok, nil}
        end
      else
        {:ok, nil}
      end
    rescue
      error ->
        {:error, "Failed to get symbol: #{Exception.message(error)}"}
    end
  end

  # =============================================================================
  # Symbol Parsing
  # =============================================================================

  defp parse_symbols(content, format) do
    patterns = Map.get(get_symbol_patterns(), format, %{})

    if map_size(patterns) == 0 do
      # Generic symbol extraction
      extract_generic_symbols(content)
    else
      # Language-specific extraction
      extract_language_symbols(content, patterns, format)
    end
  end

  defp extract_language_symbols(content, patterns, format) do
    lines = String.split(content, "\n", parts: :infinity)

    patterns
    |> Enum.flat_map(fn {kind, pattern} ->
      extract_symbols_with_pattern(lines, pattern, kind, format)
    end)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  defp extract_symbols_with_pattern(lines, pattern, kind, format) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, line_number} ->
      case Regex.scan(pattern, line, capture: :all_but_first) do
        [] ->
          []

        matches ->
          Enum.map(matches, fn [name | _] ->
            create_symbol(name, kind, line_number, line, format)
          end)
      end
    end)
  end

  defp extract_generic_symbols(content) do
    # Generic pattern matching for common programming constructs
    lines = String.split(content, "\n")

    generic_patterns = [
      {~r/(\w+)\s*\(/, :function},
      {~r/class\s+(\w+)/, :class},
      {~r/def\s+(\w+)/, :method},
      {~r/(\w+)\s*=/, :variable},
      {~r/const\s+(\w+)/, :constant}
    ]

    generic_patterns
    |> Enum.flat_map(fn {pattern, kind} ->
      extract_symbols_with_pattern(lines, pattern, kind, "generic")
    end)
    |> Enum.uniq_by(& &1.name)
  end

  defp create_symbol(name, kind, line_number, line_content, format) do
    # Find the position of the symbol in the line
    character_pos = find_symbol_position(line_content, name)

    %{
      name: name,
      kind: normalize_symbol_kind(kind),
      location: %{
        # Will be set by caller
        uri: "unknown",
        range: %{
          start: %{line: line_number, character: character_pos},
          end: %{line: line_number, character: character_pos + String.length(name)}
        }
      },
      container_name: nil,
      detail: build_symbol_detail(name, kind, format),
      documentation: nil
    }
  end

  defp find_symbol_position(line, symbol_name) do
    case String.split(line, symbol_name, parts: 2) do
      [prefix, _] -> String.length(prefix)
      _ -> 0
    end
  end

  defp build_symbol_detail(name, kind, format) do
    case {kind, format} do
      {:function, "elixir"} -> "function #{name}/0"
      {:module, "elixir"} -> "module #{name}"
      {:class, _} -> "class #{name}"
      {:method, _} -> "method #{name}"
      {:variable, _} -> "variable #{name}"
      _ -> "#{kind} #{name}"
    end
  end

  # =============================================================================
  # Definition Search
  # =============================================================================

  defp search_definitions(word, content, format, uri, root_uri) do
    # First try to find in current file
    local_definitions = find_local_definitions(word, content, format, uri)

    # Then search in workspace if not found locally
    workspace_definitions =
      if Enum.empty?(local_definitions) do
        find_workspace_definitions(word, root_uri, format)
      else
        []
      end

    local_definitions ++ workspace_definitions
  end

  defp find_local_definitions(word, content, format, uri) do
    symbols = parse_symbols(content, format)

    symbols
    |> Enum.filter(fn symbol -> symbol.name == word end)
    |> Enum.map(fn symbol ->
      %{
        location: %{symbol.location | uri: uri},
        kind: symbol.kind,
        name: symbol.name,
        detail: symbol.detail
      }
    end)
  end

  defp find_workspace_definitions(word, root_uri, _format) do
    # Use native search for better performance
    case Lang.Native.FSScanner.search(root_uri, "def.*#{word}", max_results: 10) do
      {:ok, results} ->
        results
        |> Enum.map(&convert_search_to_definition/1)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  # =============================================================================
  # Workspace Search
  # =============================================================================

  defp fallback_workspace_search(query, root_uri) do
    case Lang.Native.FSScanner.search(root_uri, query, max_results: 100) do
      {:ok, results} ->
        symbols =
          results
          |> Enum.map(&convert_to_symbol/1)
          |> Enum.reject(&is_nil/1)

        {:ok, symbols}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_tree_sitter_query(query) do
    # Simple tree-sitter query for function names
    "(function_item name: (identifier) @function (#match? @function \"#{query}\"))"
  end

  # =============================================================================
  # Conversion Helpers
  # =============================================================================

  defp convert_to_reference(search_result) do
    case search_result do
      %{file: file, line: line, column: column, content: content} ->
        %{
          location: %{
            uri: "file://#{file}",
            range: %{
              start: %{line: line - 1, character: column - 1},
              end: %{line: line - 1, character: column + 10}
            }
          },
          context: String.trim(content)
        }

      _ ->
        nil
    end
  end

  defp convert_search_result_to_symbol(result) do
    case result do
      %{name: name, file: file, line: line, kind: kind} ->
        %{
          name: name,
          kind: normalize_symbol_kind(kind),
          location: %{
            uri: "file://#{file}",
            range: %{
              start: %{line: line - 1, character: 0},
              end: %{line: line - 1, character: String.length(name)}
            }
          },
          container_name: nil,
          detail: "#{kind} #{name}",
          documentation: nil
        }

      _ ->
        nil
    end
  end

  defp convert_to_symbol(search_result) do
    case search_result do
      %{file: file, line: line, content: content} ->
        # Try to extract symbol name from content
        case extract_symbol_from_line(content) do
          {:ok, name, kind} ->
            %{
              name: name,
              kind: kind,
              location: %{
                uri: "file://#{file}",
                range: %{
                  start: %{line: line - 1, character: 0},
                  end: %{line: line - 1, character: String.length(name)}
                }
              },
              container_name: nil,
              detail: "#{kind} #{name}",
              documentation: nil
            }

          :error ->
            nil
        end

      _ ->
        nil
    end
  end

  defp convert_search_to_definition(search_result) do
    case search_result do
      %{file: file, line: line, content: content} ->
        case extract_symbol_from_line(content) do
          {:ok, name, kind} ->
            %{
              location: %{
                uri: "file://#{file}",
                range: %{
                  start: %{line: line - 1, character: 0},
                  end: %{line: line - 1, character: String.length(content)}
                }
              },
              kind: normalize_symbol_kind(kind),
              name: name,
              detail: "#{kind} #{name}"
            }

          :error ->
            nil
        end

      _ ->
        nil
    end
  end

  # =============================================================================
  # Utilities
  # =============================================================================

  defp read_file_content(uri) do
    file_path = String.replace_prefix(uri, "file://", "")

    case File.read(file_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, "Could not read file: #{reason}"}
    end
  end

  defp normalize_language_id(language_id) do
    case String.downcase(language_id) do
      "elixir" -> "elixir"
      "javascript" -> "javascript"
      "js" -> "javascript"
      "python" -> "python"
      "py" -> "python"
      _ -> language_id
    end
  end

  defp normalize_symbol_kind(kind) when is_atom(kind), do: kind

  defp normalize_symbol_kind(kind) when is_binary(kind) do
    case String.downcase(kind) do
      "function" -> :function
      "method" -> :method
      "class" -> :class
      "module" -> :module
      "variable" -> :variable
      "constant" -> :constant
      "property" -> :property
      "field" -> :field
      _ -> :variable
    end
  end

  defp normalize_symbol_kind(kind), do: :variable

  defp extract_word_at_position(line, character) do
    if character >= String.length(line) do
      nil
    else
      # Find word boundaries around the character
      before = String.slice(line, 0, character)
      after_char = String.slice(line, character, String.length(line))

      # Extract the word at this position
      word_pattern = ~r/\w+/

      case Regex.run(word_pattern, line, return: :index) do
        indices when is_list(indices) ->
          Enum.find_value(indices, fn {start, length} ->
            end_pos = start + length

            if character >= start and character < end_pos do
              String.slice(line, start, length)
            end
          end)

        _ ->
          nil
      end
    end
  end

  defp position_in_range?(position, range) do
    start_pos = range.start
    end_pos = range.end

    (position.line > start_pos.line or
       (position.line == start_pos.line and position.character >= start_pos.character)) and
      (position.line < end_pos.line or
         (position.line == end_pos.line and position.character <= end_pos.character))
  end

  defp extract_symbol_from_line(line) do
    patterns = [
      {~r/def\s+(\w+)/, :function},
      {~r/defp\s+(\w+)/, :function},
      {~r/defmodule\s+([\w\.]+)/, :module},
      {~r/class\s+(\w+)/, :class},
      {~r/function\s+(\w+)/, :function},
      {~r/(\w+)\s*\(/, :function},
      {~r/(\w+)\s*=/, :variable}
    ]

    Enum.find_value(patterns, fn {pattern, kind} ->
      case Regex.run(pattern, line, capture: :all_but_first) do
        [name] -> {:ok, name, kind}
        _ -> nil
      end
    end) || :error
  end
end
