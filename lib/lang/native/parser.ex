defmodule Lang.Native.Parser do
  @moduledoc """
  LANG Native Parser - High-Performance NIF Interface

  This module provides Elixir bindings to the Rust NIF implementation
  for blazing fast text analysis, JSON-LD semantic diffing, and streaming parsing.

  CRITICAL: All functions in this module are performance-optimized native code.
  """

  use RustlerPrecompiled,
    otp_app: :lang,
    crate: "lang_parser",
    base_url: "https://github.com/nocsi/lang/releases/download/v",
    force_build: true,
    version: "0.1.0"

  # NIF Result Structs
  defmodule ParseResult do
    @moduledoc """
    Result structure from native parsing operations
    """
    defstruct [
      :format,
      :tokens,
      :ast_nodes,
      :complexity_score,
      :readability_score,
      :line_count,
      :word_count,
      :char_count,
      :functions,
      :classes,
      :imports,
      :errors,
      :warnings,
      :suggestions,
      :processing_time_us
    ]
  end

  defmodule StyleAnalysis do
    @moduledoc """
    Stylometric analysis result from native engine
    """
    defstruct [
      :fingerprint_hash,
      :fingerprint_vector,
      :linguistic_features,
      :syntactic_features,
      :lexical_features,
      :confidence_score,
      :processing_time_us
    ]
  end

  defmodule ComparisonResult do
    @moduledoc """
    Style comparison result between two text samples
    """
    defstruct [
      :similarity_score,
      :likely_same_author,
      :confidence_level,
      :feature_differences,
      :distinctive_markers
    ]
  end

  defmodule SemanticDiff do
    @moduledoc """
    Semantic diff result for JSON-LD documents
    """
    defstruct [
      :additions,
      :deletions,
      :modifications,
      :context_changes,
      :processing_time_us
    ]
  end

  defmodule StreamingResult do
    @moduledoc """
    Streaming parser result with performance metrics
    """
    defstruct [
      :nodes_extracted,
      :bytes_processed,
      :parsing_errors,
      :processing_time_us
    ]
  end

  # === CORE PARSING FUNCTIONS ===

  @doc """
  Parse content with native performance optimizations.

  ## Examples

      iex> Lang.Native.Parser.parse_content("# Hello World", "markdown")
      {:ok, %ParseResult{format: "markdown", tokens: ["Hello", "World"], ...}}

      iex> Lang.Native.Parser.parse_content("invalid", "unsupported")
      {:error, :unsupported_format}

  ## Performance Notes
  - Uses Tree-sitter for code parsing
  - SIMD-optimized for large documents
  - Aggressive caching for repeated content
  """
  @spec parse_content(String.t(), String.t(), map()) ::
          {:ok, ParseResult.t()} | {:error, atom()}
  def parse_content(_content, _format, _options \\ %{})
  def parse_content(_content, _format, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Analyze writing style for fingerprinting and author attribution.

  This function extracts linguistic, syntactic, and lexical features
  from text content using parallel processing for maximum performance.

  ## Examples

      iex> content = "I believe technology will fundamentally change..."
      iex> {:ok, analysis} = Lang.Native.Parser.analyze_style(content)
      iex> analysis.confidence_score > 0.7
      true

  ## Performance Notes
  - Uses Rayon for parallel feature extraction
  - Memory-mapped processing for large texts
  - Advanced fingerprinting algorithms
  """
  @spec analyze_style(String.t(), map()) ::
          {:ok, StyleAnalysis.t()} | {:error, term()}
  def analyze_style(_content, _options \\ %{})
  def analyze_style(_content, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Compare two style analyses for authorship attribution.

  ## Examples

      iex> {:ok, style1} = Lang.Native.Parser.analyze_style(sample1)
      iex> {:ok, style2} = Lang.Native.Parser.analyze_style(sample2)
      iex> {:ok, comparison} = Lang.Native.Parser.compare_styles(style1, style2)
      iex> comparison.similarity_score
      0.85

  """
  @spec compare_styles(StyleAnalysis.t(), StyleAnalysis.t()) ::
          {:ok, ComparisonResult.t()} | {:error, term()}
  def compare_styles(_style1, _style2), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Process multiple documents in parallel with maximum throughput.

  Uses Rayon for parallel processing and SIMD optimizations.
  Ideal for batch operations on large document sets.

  ## Examples

      iex> contents = [
      ...>   {"# Document 1", "markdown"},
      ...>   {"function test() {}", "javascript"},
      ...>   {"def main():", "python"}
      ...> ]
      iex> {:ok, results} = Lang.Native.Parser.batch_parse(contents)
      iex> length(results) == 3
      true

  ## Performance Notes
  - Automatic load balancing across CPU cores
  - Memory-efficient processing
  - Error isolation (one failure doesn't stop batch)
  """
  @spec batch_parse([{String.t(), String.t()}], map()) ::
          {:ok, [ParseResult.t()]} | {:error, term()}
  def batch_parse(_contents, _options \\ %{})
  def batch_parse(_contents, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Apply style obfuscation to text while preserving meaning.

  ## Examples

      iex> original = "I think this is a great solution to the problem."
      iex> {:ok, obfuscated} = Lang.Native.Parser.obfuscate_text(original, 0.7, true)
      iex> obfuscated != original
      true

  """
  @spec obfuscate_text(String.t(), float(), boolean()) ::
          {:ok, String.t()} | {:error, term()}
  def obfuscate_text(_content, _intensity, _preserve_meaning),
    do: :erlang.nif_error(:nif_not_loaded)

  # === JSON-LD SEMANTIC DIFF FUNCTIONS ===

  @doc """
  Compute semantic diff between two JSON-LD documents.

  This is the CRITICAL performance function that implements the gnarly bits
  of semantic diffing with maximum optimization:

  - Fast structural hash comparison
  - Context-only change detection
  - Parallel triple processing
  - Memory-efficient operations

  ## Examples

      iex> old_doc = ~s({"@context": "http://example.org/v1", "@id": "test", "name": "old"})
      iex> new_doc = ~s({"@context": "http://example.org/v1", "@id": "test", "name": "new"})
      iex> {:ok, diff} = Lang.Native.Parser.semantic_diff(old_doc, new_doc, "doc123")
      iex> diff.additions > 0 or diff.deletions > 0
      true

  ## Performance Critical Path
  1. Quick structural hash (xxHash) - O(1) for identical docs
  2. Context-only change detection - Skip expensive RDF expansion
  3. Full semantic diff with parallel processing - For complex changes
  4. SIMD-optimized triple hashing and comparison

  """
  @spec semantic_diff(String.t(), String.t(), String.t()) ::
          {:ok, SemanticDiff.t()} | {:error, term()}
  def semantic_diff(_old_doc, _new_doc, _doc_id),
    do: :erlang.nif_error(:nif_not_loaded)

  # === STREAMING PARSER FUNCTIONS ===

  @doc """
  Stream parse JSON-LD content with state machine optimization.

  PERFORMANCE CRITICAL: This function processes every byte through
  an optimized state machine with lookup tables for maximum speed.

  ## Examples

      iex> large_jsonld = File.read!("large_document.jsonld")
      iex> {:ok, result} = Lang.Native.Parser.stream_parse_jsonld(large_jsonld)
      iex> result.nodes_extracted > 0
      true

  ## Performance Features
  - Zero-copy parsing where possible
  - Pre-computed lookup tables for character classification
  - Direct field extraction without full JSON parsing
  - Memory-efficient buffer rotation
  - Parallel processing for large datasets

  """
  @spec stream_parse_jsonld(String.t(), pos_integer() | nil) ::
          {:ok, StreamingResult.t()} | {:error, term()}
  def stream_parse_jsonld(_content, _chunk_size \\ nil)

  def stream_parse_jsonld(_content, _chunk_size),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Stream parse JSON-LD file using memory mapping for maximum performance.

  Uses mmap for zero-copy file access and parallel chunk processing
  for massive documents that don't fit in memory.

  ## Examples

      iex> {:ok, result} = Lang.Native.Parser.stream_parse_file_mmap("huge_file.jsonld")
      iex> result.bytes_processed > 1_000_000
      true

  ## Performance Features
  - Memory mapping for zero-copy file access
  - Object boundary detection for safe parallel processing
  - Automatic chunk size optimization based on CPU cores
  - NUMA-aware memory allocation

  """
  @spec stream_parse_file_mmap(String.t()) ::
          {:ok, StreamingResult.t()} | {:error, term()}
  def stream_parse_file_mmap(_file_path),
    do: :erlang.nif_error(:nif_not_loaded)

  # === PERFORMANCE MONITORING ===

  @doc """
  Get performance statistics from the native engine.

  ## Examples

      iex> {:ok, stats} = Lang.Native.Parser.get_performance_stats()
      iex> Map.has_key?(stats, "memory_usage")
      true

  """
  @spec get_performance_stats() :: {:ok, map()} | {:error, term()}
  def get_performance_stats(), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Clear all internal caches to free memory.

  ## Examples

      iex> Lang.Native.Parser.clear_caches()
      :ok

  """
  @spec clear_caches() :: :ok
  def clear_caches(), do: :erlang.nif_error(:nif_not_loaded)

  # === HIGH-LEVEL CONVENIENCE FUNCTIONS ===

  @doc """
  High-level content analysis with automatic format detection.

  This function combines parsing, analysis, and intelligence generation
  in a single optimized call.
  """
  @spec analyze_intelligent(String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def analyze_intelligent(content, opts \\ []) do
    format = Keyword.get(opts, :format, detect_format(content))
    include_style = Keyword.get(opts, :include_style, false)

    with {:ok, parse_result} <- parse_content(content, format),
         style_result <- maybe_analyze_style(content, include_style) do
      analysis = %{
        parsing: parse_result,
        style_analysis: style_result,
        intelligence: %{
          content_type: classify_content_type(parse_result),
          quality_score: calculate_quality_score(parse_result),
          actionable_insights: generate_insights(parse_result)
        }
      }

      {:ok, analysis}
    end
  end

  @doc """
  Batch process documents with intelligent load balancing.

  Automatically determines optimal chunk sizes and processing strategies
  based on document characteristics and system resources.
  """
  @spec batch_analyze_intelligent([{String.t(), String.t()}], keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def batch_analyze_intelligent(documents, opts \\ []) do
    # Determine processing strategy based on document sizes
    {small_docs, large_docs} =
      Enum.split_with(documents, fn {content, _format} ->
        # 50KB threshold
        String.length(content) < 50_000
      end)

    # Process small documents in batch
    small_results =
      case small_docs do
        [] -> {:ok, []}
        docs -> batch_parse(docs, Map.new(opts))
      end

    # Process large documents individually with streaming if needed
    large_results =
      Enum.map(large_docs, fn {content, format} ->
        # 1MB threshold
        if String.length(content) > 1_000_000 do
          # Use streaming parser for very large documents
          stream_parse_jsonld(content)
        else
          parse_content(content, format)
        end
      end)

    # Combine results
    case {small_results, large_results} do
      {{:ok, small}, large} when is_list(large) ->
        all_results =
          small ++
            Enum.map(large, fn
              {:ok, result} -> result
              {:error, _} -> %ParseResult{errors: ["Processing failed"]}
            end)

        {:ok, all_results}

      {{:error, reason}, _} ->
        {:error, reason}
    end
  end

  # === PRIVATE HELPER FUNCTIONS ===

  defp detect_format(content) do
    cond do
      String.starts_with?(content, "#") -> "markdown"
      String.contains?(content, "@context") -> "jsonld"
      String.starts_with?(content, "{") -> "json"
      String.starts_with?(content, "function") -> "javascript"
      String.starts_with?(content, "def ") -> "python"
      true -> "text"
    end
  end

  defp maybe_analyze_style(content, true) when byte_size(content) > 100 do
    case analyze_style(content) do
      {:ok, result} -> result
      {:error, _} -> nil
    end
  end

  defp maybe_analyze_style(_content, _include), do: nil

  defp classify_content_type(%{format: format, functions: functions, classes: classes}) do
    cond do
      format in ["javascript", "python", "elixir"] and length(functions) > 0 -> :code
      format == "markdown" -> :documentation
      format in ["json", "yaml"] -> :data
      format == "conversation" -> :communication
      true -> :text
    end
  end

  defp calculate_quality_score(%ParseResult{} = result) do
    base_score = 50.0

    # Adjust for complexity
    complexity_adjustment =
      case result.complexity_score do
        # Too complex
        score when score > 8.0 -> -10.0
        # Too simple
        score when score < 2.0 -> -5.0
        _ -> 0.0
      end

    # Adjust for readability
    readability_adjustment = (result.readability_score - 5.0) * 5.0

    # Adjust for errors/warnings
    error_penalty = length(result.errors) * -5.0
    warning_penalty = length(result.warnings) * -2.0

    # Combine and clamp to 0-100
    total_score =
      base_score + complexity_adjustment + readability_adjustment +
        error_penalty + warning_penalty

    max(0.0, min(100.0, total_score))
  end

  defp generate_insights(%ParseResult{
         suggestions: suggestions,
         errors: errors,
         warnings: warnings
       }) do
    insights = []

    # Add error-based insights
    insights =
      if length(errors) > 0 do
        ["Critical issues found that need immediate attention" | insights]
      else
        insights
      end

    # Add warning-based insights
    insights =
      if length(warnings) > 3 do
        ["Multiple warnings detected - consider reviewing for best practices" | insights]
      else
        insights
      end

    # Add suggestion-based insights
    insights =
      if length(suggestions) > 0 do
        ["Optimization opportunities available" | insights]
      else
        insights
      end

    # Default insight if no specific issues
    case insights do
      [] -> ["Content appears well-structured"]
      insights -> insights
    end
  end

  # === PERFORMANCE UTILITIES ===

  @doc """
  Warm up caches and optimize memory layout for better performance.
  Call this during application startup for optimal performance.
  """
  @spec warm_up_caches() :: :ok
  def warm_up_caches do
    # Parse small samples of each format to warm up caches
    sample_formats = [
      {"# Sample", "markdown"},
      {"function test() {}", "javascript"},
      {"{\"key\": \"value\"}", "json"},
      {"Sample text content", "text"}
    ]

    # Warm up parsing caches
    Enum.each(sample_formats, fn {content, format} ->
      parse_content(content, format)
    end)

    # Warm up style analysis
    analyze_style("This is a sample text for warming up the stylometric analysis engine.")

    :ok
  end

  @doc """
  Check if native module is properly loaded and functional.
  """
  @spec health_check() :: {:ok, map()} | {:error, term()}
  def health_check do
    try do
      # Test basic parsing
      {:ok, _result} = parse_content("test", "text")

      # Test performance stats
      {:ok, stats} = get_performance_stats()

      {:ok,
       %{
         status: :healthy,
         nif_loaded: true,
         stats: stats,
         timestamp: DateTime.utc_now()
       }}
    rescue
      error -> {:error, {:health_check_failed, error}}
    end
  end
end
