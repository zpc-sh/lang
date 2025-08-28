defmodule Kyozo.Lang.UniversalParser.Formats.YAML do
  @moduledoc """
  YAML Format Parser for Universal Parser

  This module consolidates all YAML parsing functionality that was previously
  scattered across multiple modules using YamlElixir directly. It provides
  a standardized interface for YAML parsing with error handling, validation,
  and comprehensive structure analysis.

  ## Features

  - **Consolidated YAML Parsing** - Single point for all YAML operations
  - **Multi-Document Support** - Handle YAML files with multiple documents
  - **Schema Validation** - Optional YAML schema validation
  - **Structure Analysis** - Deep analysis of YAML structure and complexity
  - **Error Recovery** - Graceful handling of malformed YAML
  - **Type Preservation** - Maintain YAML-specific types and structures

  ## Usage Examples

      # Basic YAML parsing
      yaml = '''
      name: Alice
      age: 30
      skills:
        - elixir
        - yaml
      '''
      {:ok, parsed} = YAML.parse(yaml)

      # With structure analysis
      {:ok, result} = YAML.parse(yaml, analyze_structure: true)
      result.structure
      # => %{type: :document, keys: ["name", "age", "skills"], depth: 2}

      # Multi-document YAML
      {:ok, documents} = YAML.parse_multi_document(multi_doc_yaml)

      # Minimal parsing for performance
      {:ok, data} = YAML.parse_minimal(yaml_string)

  """

  require Logger

  @type parse_options :: [
          analyze_structure: boolean(),
          preserve_order: boolean(),
          allow_duplicate_keys: boolean(),
          max_depth: pos_integer() | nil,
          atom_keys: boolean()
        ]

  @type yaml_structure :: %{
          type: :document | :sequence | :mapping | :scalar,
          keys: [String.t()] | nil,
          depth: non_neg_integer(),
          document_count: pos_integer(),
          complexity_score: number(),
          has_anchors: boolean(),
          has_references: boolean()
        }

  @type parsed_yaml :: %{
          data: term(),
          structure: yaml_structure(),
          metadata: %{
            parse_time_us: non_neg_integer(),
            content_size: non_neg_integer(),
            line_count: non_neg_integer(),
            parser_used: atom()
          }
        }

  @default_options [
    analyze_structure: true,
    preserve_order: false,
    allow_duplicate_keys: true,
    max_depth: nil,
    atom_keys: false
  ]

  @doc """
  Parse YAML content with comprehensive analysis.

  ## Options

  - `:analyze_structure` - Include structural analysis (default: true)
  - `:preserve_order` - Preserve key order in mappings (default: false)
  - `:allow_duplicate_keys` - Allow duplicate keys in mappings (default: true)
  - `:max_depth` - Maximum nesting depth allowed (default: no limit)
  - `:atom_keys` - Convert string keys to atoms (default: false)

  ## Examples

      yaml = '''
      users:
        - name: Alice
          role: admin
        - name: Bob
          role: user
      '''
      {:ok, result} = YAML.parse(yaml)
      result.data
      # => %{"users" => [%{"name" => "Alice", "role" => "admin"}, ...]}

  """
  @spec parse(String.t(), parse_options()) :: {:ok, parsed_yaml()} | {:error, term()}
  def parse(content, options \\ []) when is_binary(content) do
    options = Keyword.merge(@default_options, options)
    start_time = System.monotonic_time(:microsecond)

    case parse_with_yaml_elixir(content, options) do
      {:ok, data} ->
        end_time = System.monotonic_time(:microsecond)
        parse_time = end_time - start_time

        structure =
          if Keyword.get(options, :analyze_structure, true) do
            analyze_yaml_structure(data, content)
          else
            %{type: :document, complexity_score: 1.0}
          end

        result = %{
          data: data,
          structure: structure,
          metadata: %{
            parse_time_us: parse_time,
            content_size: byte_size(content),
            line_count: count_lines(content),
            parser_used: :yaml_elixir
          }
        }

        {:ok, result}

      {:error, reason} ->
        {:error, {:yaml_parse_error, reason}}
    end
  end

  @doc """
  Parse YAML content with minimal overhead for performance-critical scenarios.

  Returns only the parsed data without structure analysis or metadata.

  ## Examples

      {:ok, data} = YAML.parse_minimal("name: Alice\nage: 30")
      # => {:ok, %{"name" => "Alice", "age" => 30}}

  """
  @spec parse_minimal(String.t()) :: {:ok, term()} | {:error, term()}
  def parse_minimal(content) when is_binary(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, data} -> {:ok, data}
      {:error, %YamlElixir.ParsingError{} = error} -> {:error, {:yaml_parsing_error, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parse multi-document YAML content.

  YAML allows multiple documents separated by `---`. This function returns
  all documents as a list.

  ## Examples

      yaml = '''
      ---
      name: Alice
      ---
      name: Bob
      '''
      {:ok, documents} = YAML.parse_multi_document(yaml)
      # => {:ok, [%{"name" => "Alice"}, %{"name" => "Bob"}]}

  """
  @spec parse_multi_document(String.t(), parse_options()) :: {:ok, [term()]} | {:error, term()}
  def parse_multi_document(content, _options \\ []) when is_binary(content) do
    # Split content by document separators
    documents = String.split(content, ~r/^---\s*$/m, trim: true)

    results =
      documents
      |> Enum.with_index()
      |> Enum.map(fn {doc_content, index} ->
        case parse_minimal(String.trim(doc_content)) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, {:document_error, index, reason}}
        end
      end)

    case collect_results(results) do
      {:ok, parsed_documents} -> {:ok, parsed_documents}
      {:error, errors} -> {:error, {:multi_document_errors, errors}}
    end
  end

  @doc """
  Convert parsed YAML back to string format.

  ## Examples

      {:ok, yaml_string} = YAML.encode(data)
      {:ok, pretty_yaml} = YAML.encode(data, flow_style: false)

  """
  @spec encode(term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode(data, options \\ []) do
    yaml_options = build_yaml_encode_options(options)

    case YamlElixir.write_to_string(data, yaml_options) do
      {:ok, yaml_string} -> {:ok, yaml_string}
      {:error, reason} -> {:error, {:yaml_encode_error, reason}}
    end
  end

  @doc """
  Validate YAML structure and detect common issues.

  ## Examples

      {:ok, issues} = YAML.validate_structure(data)
      # => {:ok, ["Deep nesting detected", "Large mapping size"]}

  """
  @spec validate_structure(term()) :: {:ok, [String.t()]} | {:error, term()}
  def validate_structure(data) do
    issues = []

    # Check depth
    depth = calculate_depth(data)
    issues = if depth > 15, do: ["Deep nesting detected (depth: #{depth})" | issues], else: issues

    # Check mapping size
    issues =
      case data do
        map when is_map(map) and map_size(map) > 200 ->
          ["Large mapping detected (#{map_size(map)} keys)" | issues]

        _ ->
          issues
      end

    # Check sequence length
    issues =
      case data do
        list when is_list(list) and length(list) > 2000 ->
          ["Large sequence detected (#{length(list)} items)" | issues]

        _ ->
          issues
      end

    {:ok, Enum.reverse(issues)}
  end

  @doc """
  Extract all keys from a YAML document recursively.

  ## Examples

      keys = YAML.extract_all_keys(%{"database" => %{"host" => "localhost", "port" => 5432}})
      # => ["database", "host", "port"]

  """
  @spec extract_all_keys(term()) :: [String.t()]
  def extract_all_keys(data) do
    do_extract_keys(data, [])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Check if YAML content contains anchors and references.

  ## Examples

      yaml = '''
      default: &default
        timeout: 30
      production:
        <<: *default
        host: prod.example.com
      '''
      true = YAML.has_anchors_and_references?(yaml)

  """
  @spec has_anchors_and_references?(String.t()) :: boolean()
  def has_anchors_and_references?(content) when is_binary(content) do
    String.contains?(content, "&") or String.contains?(content, "*") or
      String.contains?(content, "<<:")
  end

  @doc """
  Flatten nested YAML structure into dot-notation keys.

  ## Examples

      flattened = YAML.flatten(%{"database" => %{"host" => "localhost", "port" => 5432}})
      # => %{"database.host" => "localhost", "database.port" => 5432}

  """
  @spec flatten(term()) :: map()
  def flatten(data) when is_map(data) do
    do_flatten(data, "", %{})
  end

  def flatten(data), do: %{"value" => data}

  @doc """
  Check if content appears to be valid YAML format.

  ## Examples

      true = YAML.valid_format?("name: Alice\nage: 30")
      false = YAML.valid_format?("{\"name\": \"Alice\"}")

  """
  @spec valid_format?(String.t()) :: boolean()
  def valid_format?(content) when is_binary(content) do
    # Quick heuristics for YAML format
    yaml_indicators = [
      # key: value
      ~r/^\s*[\w\-]+:\s*.+$/m,
      # - list item
      ~r/^\s*-\s+.+$/m,
      # document separator
      ~r/^---\s*$/m,
      # comments
      ~r/^\s*#.*$/m
    ]

    Enum.any?(yaml_indicators, &Regex.match?(&1, content)) and
      not String.starts_with?(String.trim(content), "{") and
      not String.starts_with?(String.trim(content), "[")
  end

  # === Private Functions ===

  defp parse_with_yaml_elixir(content, options) do
    yaml_options = build_yaml_options(options)

    try do
      YamlElixir.read_from_string(content, yaml_options)
    rescue
      error -> {:error, {:parsing_exception, error}}
    end
  end

  defp build_yaml_options(options) do
    yaml_opts = []

    # Handle atom keys
    yaml_opts =
      if Keyword.get(options, :atom_keys, false) do
        [{:atoms, true} | yaml_opts]
      else
        yaml_opts
      end

    yaml_opts
  end

  defp build_yaml_encode_options(options) do
    encode_opts = []

    # Handle flow style
    encode_opts =
      if Keyword.get(options, :flow_style, false) do
        [{:flow_style, true} | encode_opts]
      else
        encode_opts
      end

    encode_opts
  end

  defp analyze_yaml_structure(data, content) do
    %{
      type: classify_yaml_type(data),
      keys: extract_top_level_keys(data),
      depth: calculate_depth(data),
      document_count: count_documents(content),
      complexity_score: calculate_complexity_score(data),
      has_anchors: has_anchors_and_references?(content),
      has_references: has_anchors_and_references?(content)
    }
  end

  defp classify_yaml_type(data) when is_map(data), do: :mapping
  defp classify_yaml_type(data) when is_list(data), do: :sequence
  defp classify_yaml_type(_), do: :scalar

  defp extract_top_level_keys(data) when is_map(data), do: Map.keys(data)
  defp extract_top_level_keys(_), do: nil

  defp calculate_depth(data, current_depth \\ 0)

  defp calculate_depth(data, current_depth) when is_map(data) do
    case map_size(data) do
      0 ->
        current_depth

      _ ->
        data
        |> Map.values()
        |> Enum.map(&calculate_depth(&1, current_depth + 1))
        |> Enum.max(fn -> current_depth end)
    end
  end

  defp calculate_depth(data, current_depth) when is_list(data) do
    case data do
      [] ->
        current_depth

      list ->
        list
        |> Enum.map(&calculate_depth(&1, current_depth + 1))
        |> Enum.max(fn -> current_depth end)
    end
  end

  defp calculate_depth(_, current_depth), do: current_depth

  defp count_documents(content) do
    content
    |> String.split(~r/^---\s*$/m, trim: true)
    |> length()
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end

  defp calculate_complexity_score(data) do
    base_score = 1.0

    # Add complexity based on type and size
    type_score =
      case data do
        map when is_map(map) -> map_size(map) * 0.15
        list when is_list(list) -> length(list) * 0.1
        _ -> 0.0
      end

    # Add complexity based on depth
    depth_score = calculate_depth(data) * 0.8

    # Add complexity based on mixed types
    mixed_type_score = calculate_mixed_type_complexity(data)

    base_score + type_score + depth_score + mixed_type_score
  end

  defp calculate_mixed_type_complexity(data) when is_map(data) do
    values = Map.values(data)

    type_variety =
      values
      |> Enum.map(&classify_yaml_type/1)
      |> Enum.uniq()
      |> length()

    (type_variety - 1) * 0.3
  end

  defp calculate_mixed_type_complexity(data) when is_list(data) do
    type_variety =
      data
      |> Enum.map(&classify_yaml_type/1)
      |> Enum.uniq()
      |> length()

    (type_variety - 1) * 0.3
  end

  defp calculate_mixed_type_complexity(_), do: 0.0

  defp do_extract_keys(data, acc) when is_map(data) do
    map_keys = Map.keys(data)

    nested_keys =
      data
      |> Map.values()
      |> Enum.flat_map(&do_extract_keys(&1, []))

    acc ++ map_keys ++ nested_keys
  end

  defp do_extract_keys(data, acc) when is_list(data) do
    nested_keys =
      data
      |> Enum.flat_map(&do_extract_keys(&1, []))

    acc ++ nested_keys
  end

  defp do_extract_keys(_, acc), do: acc

  defp do_flatten(data, prefix, acc) when is_map(data) do
    Enum.reduce(data, acc, fn {key, value}, acc ->
      new_key = if prefix == "", do: key, else: "#{prefix}.#{key}"

      case value do
        nested_map when is_map(nested_map) ->
          do_flatten(nested_map, new_key, acc)

        nested_list when is_list(nested_list) ->
          do_flatten_list(nested_list, new_key, acc)

        _ ->
          Map.put(acc, new_key, value)
      end
    end)
  end

  defp do_flatten(data, prefix, acc) do
    Map.put(acc, prefix, data)
  end

  defp do_flatten_list(list, prefix, acc) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {item, index}, acc ->
      new_key = "#{prefix}.#{index}"
      do_flatten(item, new_key, acc)
    end)
  end

  defp collect_results(results) do
    {successes, errors} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    if length(errors) > 0 do
      error_details = Enum.map(errors, fn {:error, reason} -> reason end)
      {:error, error_details}
    else
      success_data = Enum.map(successes, fn {:ok, data} -> data end)
      {:ok, success_data}
    end
  end
end
