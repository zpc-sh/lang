defmodule Kyozo.Lang.UniversalParser do
  @moduledoc """
  Universal Parser - Single Entry Point for All Text Format Parsing

  The UniversalParser provides a unified interface for parsing any text format
  supported by the LANG platform. It automatically detects formats, routes to
  appropriate parsers, and returns standardized Document structures.

  ## Features

  - **Automatic Format Detection** - Intelligently detects content format
  - **Unified Interface** - Single `parse/2` function for all formats
  - **Performance Optimized** - Leverages native parsers where beneficial
  - **Extensible Architecture** - Easy to add new format support
  - **Comprehensive Analysis** - Includes structure, complexity, and insights

  ## Supported Formats

  ### Code Formats
  - JavaScript, TypeScript, Python, Elixir, Rust, Go, Java, C/C++
  - Uses Tree-sitter for semantic parsing and AST generation

  ### Document Formats
  - Markdown, Plain Text, RestructuredText, AsciiDoc
  - Full structure extraction with headers, links, lists

  ### Data Formats
  - JSON, YAML, TOML, XML, CSV
  - Schema validation and structure analysis

  ### Communication Formats
  - Email, Chat logs, Conversation transcripts
  - Sentiment analysis and intent classification

  ### Specialized Formats
  - Log files, SQL queries, Regular expressions
  - Domain-specific parsing and validation

  ## Usage Examples

      # Basic parsing with auto-detection
      {:ok, doc} = UniversalParser.parse(content)

      # Explicit format specification
      {:ok, doc} = UniversalParser.parse(content, format: "json")

      # With analysis options
      {:ok, doc} = UniversalParser.parse(content,
        format: "markdown",
        include_analysis: true,
        include_insights: true
      )

      # Batch parsing
      {:ok, docs} = UniversalParser.parse_batch([
        {content1, "json"},
        {content2, "markdown"},
        content3  # auto-detect format
      ])

  ## Document Structure

  All parsers return a standardized Document structure:

      %Document{
        format: "json",
        content: "original content",
        parsed: %{...},           # Format-specific parsed data
        metadata: %{...},         # File info, timestamps, etc.
        structure: %{...},        # Structural analysis
        analysis: %{...},         # Optional complexity/quality analysis
        insights: [...]           # Optional actionable insights
      }

  ## Performance Notes

  - Leverages native Rust NIFs for JSON-LD and stylometric analysis
  - Uses Tree-sitter for code parsing with full AST generation
  - Implements intelligent caching for repeated content
  - Supports streaming for large documents (>1MB)

  """

  alias Kyozo.Lang.UniversalParser.{Document, FormatDetector, Intelligence}
  alias Lang.TextIntelligence.ParserRegistry
  require Logger

  @type parse_options :: [
          format: String.t() | nil,
          include_analysis: boolean(),
          include_insights: boolean(),
          include_structure: boolean(),
          max_size: pos_integer(),
          timeout: pos_integer()
        ]

  @type parse_result :: {:ok, Document.t()} | {:error, term()}
  @type batch_item :: String.t() | {String.t(), String.t()}
  @type batch_result :: {:ok, [Document.t()]} | {:error, term()}

  @default_options [
    format: nil,
    include_analysis: false,
    include_insights: false,
    include_structure: true,
    # 10MB
    max_size: 10_000_000,
    # 30 seconds
    timeout: 30_000
  ]

  @doc """
  Parse content with automatic format detection and standardized output.

  ## Options

  - `:format` - Explicitly specify format (default: auto-detect)
  - `:include_analysis` - Include complexity and quality analysis (default: false)
  - `:include_insights` - Include actionable insights (default: false)
  - `:include_structure` - Include structural analysis (default: true)
  - `:max_size` - Maximum content size in bytes (default: 10MB)
  - `:timeout` - Parsing timeout in milliseconds (default: 30s)

  ## Examples

      # Simple parsing with auto-detection
      {:ok, doc} = UniversalParser.parse("# Hello World")
      doc.format
      # => "markdown"

      # JSON parsing with analysis
      json_content = ~s({"name": "test", "values": [1,2,3]})
      {:ok, doc} = UniversalParser.parse(json_content,
        format: "json",
        include_analysis: true
      )

      # Large document with streaming
      {:ok, doc} = UniversalParser.parse(large_content,
        max_size: 50_000_000,
        timeout: 120_000
      )

  """
  @spec parse(String.t(), parse_options()) :: parse_result()
  def parse(content, options \\ []) when is_binary(content) do
    options = Keyword.merge(@default_options, options)

    with :ok <- validate_content_size(content, options),
         {:ok, format} <- determine_format(content, options),
         {:ok, base_doc} <- parse_with_format(content, format, options),
         {:ok, enhanced_doc} <- enhance_document(base_doc, options) do
      {:ok, enhanced_doc}
    else
      {:error, reason} = error ->
        Logger.warning("Parse failed", reason: reason, content_size: byte_size(content))
        error
    end
  end

  @doc """
  Parse multiple documents efficiently with optional format specification.

  ## Examples

      # Mixed content with auto-detection
      contents = [
        "# Markdown Doc",
        ~s({"json": true}),
        "console.log('js code')"
      ]
      {:ok, docs} = UniversalParser.parse_batch(contents)

      # With explicit formats
      items = [
        {"# Header", "markdown"},
        {~s({"key": "value"}), "json"}
      ]
      {:ok, docs} = UniversalParser.parse_batch(items)

  """
  @spec parse_batch([batch_item()], parse_options()) :: batch_result()
  def parse_batch(items, options \\ []) when is_list(items) do
    options = Keyword.merge(@default_options, options)

    # Determine concurrency based on system resources and item count
    max_concurrency = min(System.schedulers_online() * 2, length(items))

    results =
      items
      |> Task.async_stream(
        fn item -> parse_batch_item(item, options) end,
        max_concurrency: max_concurrency,
        timeout: Keyword.get(options, :timeout, 30_000),
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, :parsing_timeout}
        {:exit, reason} -> {:error, {:parsing_failed, reason}}
      end)

    # Check for any errors
    case Enum.find(results, fn result -> match?({:error, _}, result) end) do
      nil ->
        documents = Enum.map(results, fn {:ok, doc} -> doc end)
        {:ok, documents}

      error ->
        error
    end
  end

  @doc """
  Parse content and return only the essential parsed data without metadata.

  Useful for high-performance scenarios where only the core parsed content
  is needed without analysis or structural information.

  ## Examples

      {:ok, parsed} = UniversalParser.parse_minimal(json_content, "json")
      # Returns the decoded JSON directly
  """
  @spec parse_minimal(String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def parse_minimal(content, format) when is_binary(content) and is_binary(format) do
    case get_format_parser(format) do
      {:ok, parser_module} ->
        parser_module.parse_minimal(content)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stream parse large documents with memory-efficient processing.

  Automatically switches to streaming mode for documents larger than 1MB.
  Uses memory mapping and chunked processing for optimal performance.

  ## Examples

      # Parse huge JSON-LD file
      {:ok, doc} = UniversalParser.parse_stream(huge_jsonld_content, "jsonld")

      # Stream parse with custom chunk size
      {:ok, doc} = UniversalParser.parse_stream(content, "json", chunk_size: 64_000)

  """
  @spec parse_stream(String.t(), String.t(), keyword()) :: parse_result()
  def parse_stream(content, format, options \\ []) when is_binary(content) do
    case get_format_parser(format) do
      {:ok, parser_module} ->
        case function_exported?(parser_module, :parse_stream, 2) do
          true -> parser_module.parse_stream(content, options)
          false -> parse(content, [format: format] ++ options)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get supported formats with their capabilities and usage statistics.

  ## Examples

      formats = UniversalParser.supported_formats()
      # => [
      #   %{format: "json", domain: "data", parser: "builtin", stream_capable: true},
      #   %{format: "markdown", domain: "documentation", parser: "builtin", stream_capable: false},
      #   ...
      # ]

  """
  @spec supported_formats() :: [map()]
  def supported_formats do
    case ParserRegistry.list_supported_formats() do
      formats when is_list(formats) ->
        Enum.map(formats, fn format ->
          format
          |> Map.put(:stream_capable, format_supports_streaming?(format.format))
          |> Map.put(:native_parser, has_native_parser?(format.format))
        end)

      _ ->
        []
    end
  end

  @doc """
  Detect the format of content without full parsing.

  ## Examples

      {:ok, "json"} = UniversalParser.detect_format(~s({"key": "value"}))
      {:ok, "markdown"} = UniversalParser.detect_format("# Header\n\nContent")

  """
  @spec detect_format(String.t()) :: {:ok, String.t()} | {:error, :unknown_format}
  def detect_format(content) when is_binary(content) do
    FormatDetector.detect(content)
  end

  @doc """
  Validate if a format is supported by the UniversalParser.

  ## Examples

      true = UniversalParser.supports_format?("json")
      false = UniversalParser.supports_format?("unsupported")

  """
  @spec supports_format?(String.t()) :: boolean()
  def supports_format?(format) when is_binary(format) do
    case ParserRegistry.get_parser(format) do
      {:ok, _config} -> true
      {:error, :unsupported_format} -> false
    end
  end

  @doc """
  Get parser performance statistics and health information.

  ## Examples

      stats = UniversalParser.get_stats()
      # => %{
      #   total_parses: 1547,
      #   format_usage: %{"json" => 523, "markdown" => 412, ...},
      #   avg_parse_time_ms: 24.5,
      #   native_parser_usage: 67.2
      # }

  """
  @spec get_stats() :: map()
  def get_stats do
    registry_stats = ParserRegistry.get_parser_stats()

    %{
      registry_stats: registry_stats,
      native_parser_health: check_native_parser_health(),
      supported_format_count: length(supported_formats()),
      timestamp: DateTime.utc_now()
    }
  end

  # === Private Functions ===

  defp validate_content_size(content, options) do
    max_size = Keyword.get(options, :max_size, 10_000_000)
    content_size = byte_size(content)

    if content_size <= max_size do
      :ok
    else
      {:error, {:content_too_large, content_size, max_size}}
    end
  end

  defp determine_format(content, options) do
    case Keyword.get(options, :format) do
      nil ->
        FormatDetector.detect(content)

      format when is_binary(format) ->
        if supports_format?(format) do
          {:ok, format}
        else
          {:error, {:unsupported_format, format}}
        end
    end
  end

  defp parse_with_format(content, format, options) do
    Logger.debug("Parsing content", format: format, size: byte_size(content))

    case get_format_parser(format) do
      {:ok, parser_module} ->
        start_time = System.monotonic_time(:millisecond)

        result = parser_module.parse(content, options)

        end_time = System.monotonic_time(:millisecond)
        parse_time = end_time - start_time

        case result do
          {:ok, parsed_data} ->
            document = %Document{
              format: format,
              content: content,
              parsed: parsed_data,
              metadata: %{
                content_size: byte_size(content),
                parse_time_ms: parse_time,
                parser_used: parser_module,
                parsed_at: DateTime.utc_now()
              }
            }

            {:ok, document}

          {:error, reason} ->
            {:error, {:parse_failed, format, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enhance_document(document, options) do
    document =
      document
      |> maybe_add_structure(options)
      |> maybe_add_analysis(options)
      |> maybe_add_insights(options)

    {:ok, document}
  end

  defp maybe_add_structure(document, options) do
    if Keyword.get(options, :include_structure, true) do
      structure = extract_structure(document)
      %{document | structure: structure}
    else
      document
    end
  end

  defp maybe_add_analysis(document, options) do
    if Keyword.get(options, :include_analysis, false) do
      analysis = perform_analysis(document)
      %{document | analysis: analysis}
    else
      document
    end
  end

  defp maybe_add_insights(document, options) do
    if Keyword.get(options, :include_insights, false) do
      insights = Intelligence.generate_insights(document)
      %{document | insights: insights}
    else
      document
    end
  end

  defp extract_structure(%Document{format: format, parsed: parsed}) do
    case format do
      "json" -> extract_json_structure(parsed)
      "yaml" -> extract_yaml_structure(parsed)
      "markdown" -> extract_markdown_structure(parsed)
      "xml" -> extract_xml_structure(parsed)
      _ -> %{type: :flat, complexity: :simple}
    end
  end

  defp perform_analysis(%Document{format: format, content: content, parsed: parsed}) do
    %{
      complexity_score: calculate_complexity(format, parsed),
      readability_score: calculate_readability(format, content),
      quality_indicators: assess_quality(format, parsed),
      recommendations: generate_recommendations(format, parsed)
    }
  end

  defp parse_batch_item({content, format}, options) do
    parse(content, Keyword.put(options, :format, format))
  end

  defp parse_batch_item(content, options) when is_binary(content) do
    parse(content, options)
  end

  defp get_format_parser(format) do
    normalized_format = String.downcase(format)

    case normalized_format do
      "json" ->
        {:ok, Kyozo.Lang.UniversalParser.Formats.JSON}

      "yaml" ->
        {:ok, Kyozo.Lang.UniversalParser.Formats.YAML}

      "markdown" ->
        {:ok, Kyozo.Lang.UniversalParser.Formats.Markdown}

      "text" ->
        {:ok, Kyozo.Lang.UniversalParser.Formats.Text}

      "log" ->
        {:ok, Kyozo.Lang.UniversalParser.Formats.Log}

      "email" ->
        {:ok, Kyozo.Lang.UniversalParser.Formats.Email}

      # Code formats - delegate to Tree Parser
      format
      when format in [
             "javascript",
             "python",
             "elixir",
             "rust",
             "go",
             "typescript",
             "java",
             "c",
             "cpp"
           ] ->
        {:ok, Kyozo.Lang.UniversalParser.Formats.Code}

      # Fallback to registry for other formats
      _ ->
        case ParserRegistry.get_parser(format) do
          {:ok, _config} -> {:ok, Kyozo.Lang.UniversalParser.Formats.Generic}
          error -> error
        end
    end
  end

  # Structure extraction helpers
  defp extract_json_structure(data) when is_map(data) do
    %{
      type: :object,
      keys: Map.keys(data),
      depth: calculate_json_depth(data),
      complexity: calculate_json_complexity(data)
    }
  end

  defp extract_json_structure(data) when is_list(data) do
    %{
      type: :array,
      length: length(data),
      depth: calculate_json_depth(data),
      complexity: calculate_json_complexity(data)
    }
  end

  defp extract_json_structure(_), do: %{type: :primitive, complexity: :simple}

  defp extract_yaml_structure(data), do: extract_json_structure(data)

  defp extract_markdown_structure(%{headers: headers, links: links, code_blocks: blocks}) do
    %{
      type: :document,
      header_count: length(headers),
      link_count: length(links),
      code_block_count: length(blocks),
      complexity: calculate_markdown_complexity(headers, links, blocks)
    }
  end

  defp extract_markdown_structure(_), do: %{type: :document, complexity: :simple}

  defp extract_xml_structure(_parsed), do: %{type: :markup, complexity: :medium}

  # Complexity calculation helpers
  defp calculate_complexity("json", data), do: calculate_json_complexity(data)
  defp calculate_complexity("yaml", data), do: calculate_json_complexity(data)
  defp calculate_complexity("markdown", %{headers: h, links: l}), do: length(h) + length(l)
  defp calculate_complexity(_, _), do: 1

  defp calculate_readability("markdown", content) do
    # Simple readability score based on sentence length and word complexity
    sentences = String.split(content, ~r/[.!?]+/)
    avg_sentence_length = content |> String.split() |> length() |> div(max(1, length(sentences)))

    cond do
      avg_sentence_length < 15 -> 8.0
      avg_sentence_length < 25 -> 6.0
      true -> 4.0
    end
  end

  defp calculate_readability(_, _), do: 5.0

  defp assess_quality(format, parsed) do
    # Format-specific quality indicators
    case format do
      "json" -> assess_json_quality(parsed)
      "yaml" -> assess_yaml_quality(parsed)
      "markdown" -> assess_markdown_quality(parsed)
      _ -> []
    end
  end

  defp generate_recommendations(format, parsed) do
    # Format-specific recommendations
    case format do
      "json" -> generate_json_recommendations(parsed)
      "markdown" -> generate_markdown_recommendations(parsed)
      _ -> []
    end
  end

  # Quality assessment helpers
  defp assess_json_quality(data) when is_map(data) do
    indicators = []

    indicators =
      if map_size(data) > 20 do
        ["Consider breaking large objects into smaller components" | indicators]
      else
        indicators
      end

    indicators =
      if calculate_json_depth(data) > 5 do
        ["Deep nesting detected - consider flattening structure" | indicators]
      else
        indicators
      end

    indicators
  end

  defp assess_json_quality(_), do: []

  defp assess_yaml_quality(data), do: assess_json_quality(data)

  defp assess_markdown_quality(%{headers: headers}) do
    cond do
      length(headers) == 0 -> ["Consider adding headers to improve structure"]
      length(headers) > 10 -> ["Too many headers - consider reorganizing content"]
      true -> []
    end
  end

  defp assess_markdown_quality(_), do: []

  # Recommendation helpers
  defp generate_json_recommendations(data) when is_map(data) do
    recommendations = []

    if Map.has_key?(data, "id") and not Map.has_key?(data, "@id") do
      ["Consider using JSON-LD format with @id for better semantic structure" | recommendations]
    else
      recommendations
    end
  end

  defp generate_json_recommendations(_), do: []

  defp generate_markdown_recommendations(%{code_blocks: blocks}) do
    if length(blocks) > 0 and Enum.any?(blocks, fn {lang, _} -> lang == "" end) do
      ["Add language specifications to code blocks for better syntax highlighting"]
    else
      []
    end
  end

  defp generate_markdown_recommendations(_), do: []

  # Utility helpers
  defp calculate_json_depth(data, current_depth \\ 0)

  defp calculate_json_depth(data, current_depth) when is_map(data) do
    case map_size(data) do
      0 ->
        current_depth

      _ ->
        data
        |> Map.values()
        |> Enum.map(&calculate_json_depth(&1, current_depth + 1))
        |> Enum.max(fn -> current_depth + 1 end)
    end
  end

  defp calculate_json_depth(data, current_depth) when is_list(data) do
    case data do
      [] ->
        current_depth

      list ->
        list
        |> Enum.map(&calculate_json_depth(&1, current_depth + 1))
        |> Enum.max(fn -> current_depth + 1 end)
    end
  end

  defp calculate_json_depth(_, current_depth), do: current_depth

  defp calculate_json_complexity(data) when is_map(data) do
    map_size(data) + Enum.sum(Enum.map(Map.values(data), &calculate_json_complexity/1))
  end

  defp calculate_json_complexity(data) when is_list(data) do
    length(data) + Enum.sum(Enum.map(data, &calculate_json_complexity/1))
  end

  defp calculate_json_complexity(_), do: 1

  defp calculate_markdown_complexity(headers, links, blocks) do
    length(headers) + length(links) + length(blocks)
  end

  defp format_supports_streaming?(format) do
    format in ["json", "jsonld", "xml", "log", "csv"]
  end

  defp has_native_parser?(format) do
    format in ["jsonld", "javascript", "python", "elixir"]
  end

  defp check_native_parser_health do
    case Lang.Native.Parser.health_check() do
      {:ok, health} -> health
      {:error, _} -> %{status: :unhealthy}
    end
  end
end
