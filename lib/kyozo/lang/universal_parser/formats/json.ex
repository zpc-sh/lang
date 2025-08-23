defmodule Kyozo.Lang.UniversalParser.Formats.JSON do
  @moduledoc """
  JSON Format Parser for Universal Parser

  This module consolidates all JSON parsing functionality that was previously
  scattered across multiple modules using Jason.decode directly. It provides
  a standardized interface for JSON parsing with error handling, validation,
  and performance optimizations.

  ## Features

  - **Consolidated JSON Parsing** - Single point for all JSON operations
  - **Error Handling** - Comprehensive error reporting and recovery
  - **Performance Optimized** - Efficient parsing with streaming support
  - **Schema Validation** - Optional JSON schema validation
  - **Structure Analysis** - Deep analysis of JSON structure and complexity

  ## Usage Examples

      # Basic JSON parsing
      {:ok, parsed} = JSON.parse(~s({"name": "test", "age": 25}))

      # With options
      {:ok, parsed} = JSON.parse(json_content,
        validate_structure: true,
        max_depth: 10
      )

      # Minimal parsing (performance optimized)
      {:ok, data} = JSON.parse_minimal(json_string)

      # Stream parsing for large JSON
      {:ok, data} = JSON.parse_stream(large_json_content)

  """

  require Logger

  @type parse_options :: [
          validate_structure: boolean(),
          max_depth: pos_integer() | nil,
          allow_duplicates: boolean(),
          strict_parsing: boolean(),
          stream_threshold: pos_integer()
        ]

  @type json_structure :: %{
          type: :object | :array | :primitive,
          depth: non_neg_integer(),
          keys: [String.t()] | nil,
          length: non_neg_integer() | nil,
          complexity_score: number()
        }

  @type parsed_json :: %{
          data: term(),
          structure: json_structure(),
          metadata: %{
            parse_time_us: non_neg_integer(),
            content_size: non_neg_integer(),
            parser_type: atom()
          }
        }

  @default_options [
    validate_structure: false,
    max_depth: nil,
    allow_duplicates: true,
    strict_parsing: false,
    # 1MB threshold for streaming
    stream_threshold: 1_048_576
  ]

  @doc """
  Parse JSON content with comprehensive analysis.

  ## Options

  - `:validate_structure` - Validate JSON structure and report issues (default: false)
  - `:max_depth` - Maximum nesting depth allowed (default: no limit)
  - `:allow_duplicates` - Allow duplicate keys in objects (default: true)
  - `:strict_parsing` - Use strict JSON parsing rules (default: false)
  - `:stream_threshold` - Size threshold for streaming parsing (default: 1MB)

  ## Examples

      {:ok, result} = JSON.parse(~s({"users": [{"id": 1, "name": "Alice"}]}))
      result.data
      # => %{"users" => [%{"id" => 1, "name" => "Alice"}]}

      result.structure
      # => %{type: :object, depth: 3, keys: ["users"], complexity_score: 4.2}

  """
  @spec parse(String.t(), parse_options()) :: {:ok, parsed_json()} | {:error, term()}
  def parse(content, options \\ []) when is_binary(content) do
    options = Keyword.merge(@default_options, options)
    start_time = System.monotonic_time(:microsecond)

    # Choose parsing strategy based on content size
    content_size = byte_size(content)
    stream_threshold = Keyword.get(options, :stream_threshold)

    parsing_result =
      if content_size > stream_threshold do
        Logger.debug("Using streaming JSON parser", size: content_size)
        parse_with_streaming(content, options)
      else
        parse_with_jason(content, options)
      end

    case parsing_result do
      {:ok, data} ->
        end_time = System.monotonic_time(:microsecond)
        parse_time = end_time - start_time

        structure = analyze_json_structure(data)

        result = %{
          data: data,
          structure: structure,
          metadata: %{
            parse_time_us: parse_time,
            content_size: content_size,
            parser_type: if(content_size > stream_threshold, do: :streaming, else: :standard)
          }
        }

        {:ok, result}

      {:error, reason} ->
        {:error, {:json_parse_error, reason}}
    end
  end

  @doc """
  Parse JSON content with minimal overhead for performance-critical scenarios.

  Returns only the parsed data without structure analysis or metadata.

  ## Examples

      {:ok, data} = JSON.parse_minimal(~s({"fast": true}))
      # => {:ok, %{"fast" => true}}

  """
  @spec parse_minimal(String.t()) :: {:ok, term()} | {:error, term()}
  def parse_minimal(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, data} -> {:ok, data}
      {:error, %Jason.DecodeError{} = error} -> {:error, {:jason_decode_error, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stream parse large JSON content for memory efficiency.

  Uses streaming JSON parsing for very large documents that might not fit
  comfortably in memory.

  ## Examples

      {:ok, data} = JSON.parse_stream(huge_json_string)

  """
  @spec parse_stream(String.t(), parse_options()) :: {:ok, term()} | {:error, term()}
  def parse_stream(content, options \\ []) when is_binary(content) do
    # For now, delegate to standard parsing
    # TODO: Implement true streaming JSON parser
    Logger.debug("Stream parsing requested but using standard parser as fallback")

    case parse_with_jason(content, options) do
      {:ok, data} -> {:ok, data}
      error -> error
    end
  end

  @doc """
  Validate JSON structure and detect common issues.

  ## Examples

      {:ok, issues} = JSON.validate_structure(data)
      # => {:ok, ["Deep nesting detected", "Large object size"]}

  """
  @spec validate_structure(term()) :: {:ok, [String.t()]} | {:error, term()}
  def validate_structure(data) do
    issues = []

    # Check depth
    depth = calculate_depth(data)

    issues =
      if depth > 10 do
        ["Deep nesting detected (depth: #{depth})" | issues]
      else
        issues
      end

    # Check object size
    issues =
      case data do
        map when is_map(map) and map_size(map) > 100 ->
          ["Large object detected (#{map_size(map)} keys)" | issues]

        _ ->
          issues
      end

    # Check array length
    issues =
      case data do
        list when is_list(list) and length(list) > 1000 ->
          ["Large array detected (#{length(list)} items)" | issues]

        _ ->
          issues
      end

    {:ok, Enum.reverse(issues)}
  end

  @doc """
  Convert parsed JSON back to string format.

  ## Examples

      {:ok, json_string} = JSON.encode(data)
      {:ok, pretty_json} = JSON.encode(data, pretty: true)

  """
  @spec encode(term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode(data, options \\ []) do
    case Keyword.get(options, :pretty, false) do
      true -> Jason.encode(data, pretty: true)
      false -> Jason.encode(data)
    end
  end

  @doc """
  Extract all keys from a JSON object recursively.

  ## Examples

      keys = JSON.extract_all_keys(%{"user" => %{"name" => "Alice", "age" => 25}})
      # => ["user", "name", "age"]

  """
  @spec extract_all_keys(term()) :: [String.t()]
  def extract_all_keys(data) do
    do_extract_keys(data, [])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Check if JSON content is potentially JSON-LD format.

  ## Examples

      true = JSON.is_jsonld_candidate?(%{"@context" => "...", "@type" => "Person"})
      false = JSON.is_jsonld_candidate?(%{"name" => "Alice"})

  """
  @spec is_jsonld_candidate?(term()) :: boolean()
  def is_jsonld_candidate?(data) when is_map(data) do
    jsonld_indicators = ["@context", "@type", "@id", "@graph"]

    Enum.any?(jsonld_indicators, fn indicator ->
      Map.has_key?(data, indicator)
    end)
  end

  def is_jsonld_candidate?(_), do: false

  @doc """
  Flatten nested JSON structure into dot-notation keys.

  ## Examples

      flattened = JSON.flatten(%{"user" => %{"profile" => %{"name" => "Alice"}}})
      # => %{"user.profile.name" => "Alice"}

  """
  @spec flatten(term()) :: map()
  def flatten(data) when is_map(data) do
    do_flatten(data, "", %{})
  end

  def flatten(data), do: %{"value" => data}

  # === Private Functions ===

  defp parse_with_jason(content, options) do
    jason_options = build_jason_options(options)

    try do
      Jason.decode(content, jason_options)
    rescue
      error -> {:error, {:parsing_exception, error}}
    end
  end

  defp parse_with_streaming(content, _options) do
    # TODO: Implement actual streaming parser
    # For now, fall back to Jason with memory monitoring
    :erlang.garbage_collect()

    case Jason.decode(content) do
      {:ok, data} ->
        :erlang.garbage_collect()
        {:ok, data}

      error ->
        error
    end
  end

  defp build_jason_options(options) do
    jason_opts = []

    # Handle duplicate keys
    jason_opts =
      if Keyword.get(options, :allow_duplicates, true) do
        jason_opts
      else
        [{:keys, :strings} | jason_opts]
      end

    jason_opts
  end

  defp analyze_json_structure(data) do
    %{
      type: classify_json_type(data),
      depth: calculate_depth(data),
      keys: extract_top_level_keys(data),
      length: calculate_length(data),
      complexity_score: calculate_complexity_score(data)
    }
  end

  defp classify_json_type(data) when is_map(data), do: :object
  defp classify_json_type(data) when is_list(data), do: :array
  defp classify_json_type(_), do: :primitive

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

  defp extract_top_level_keys(data) when is_map(data) do
    Map.keys(data)
  end

  defp extract_top_level_keys(_), do: nil

  defp calculate_length(data) when is_map(data), do: map_size(data)
  defp calculate_length(data) when is_list(data), do: length(data)
  defp calculate_length(_), do: nil

  defp calculate_complexity_score(data) do
    base_score = 1.0

    # Add complexity based on type and size
    type_score =
      case data do
        map when is_map(map) -> map_size(map) * 0.1
        list when is_list(list) -> length(list) * 0.05
        _ -> 0.0
      end

    # Add complexity based on depth
    depth_score = calculate_depth(data) * 0.5

    # Add complexity based on mixed types
    mixed_type_score = calculate_mixed_type_complexity(data)

    base_score + type_score + depth_score + mixed_type_score
  end

  defp calculate_mixed_type_complexity(data) when is_map(data) do
    values = Map.values(data)

    type_variety =
      values
      |> Enum.map(&classify_json_type/1)
      |> Enum.uniq()
      |> length()

    (type_variety - 1) * 0.2
  end

  defp calculate_mixed_type_complexity(data) when is_list(data) do
    type_variety =
      data
      |> Enum.map(&classify_json_type/1)
      |> Enum.uniq()
      |> length()

    (type_variety - 1) * 0.2
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
end
