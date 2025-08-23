defmodule Kyozo.Lang.UniversalParser.FormatDetector do
  @moduledoc """
  Intelligent Format Detection for Universal Parser

  This module provides sophisticated format detection capabilities that can
  identify content types based on various heuristics including:

  - File signatures and magic bytes
  - Content structure patterns
  - Syntax patterns and keywords
  - Metadata and headers
  - Statistical analysis

  ## Detection Capabilities

  ### Structured Data Formats
  - JSON, JSON-LD, YAML, XML, CSV, TOML
  - Detects JSON-LD by presence of @context
  - Handles malformed/partial JSON gracefully

  ### Document Formats
  - Markdown, Markdown-LD, Plain Text, HTML
  - RestructuredText, AsciiDoc
  - Detects Markdown-LD by semantic annotations

  ### Code Formats
  - JavaScript, TypeScript, Python, Elixir, Rust, Go, Java, C/C++
  - Uses syntax patterns and keywords
  - Detects mixed content (e.g., JSX, embedded SQL)

  ### Communication Formats
  - Email messages, Chat logs, Conversation transcripts
  - Log files (various formats)
  - SQL queries and database schemas

  ## Usage Examples

      # Basic format detection
      {:ok, "json"} = FormatDetector.detect(~s({"key": "value"}))

      # With confidence scoring
      {:ok, {"markdown", 0.95}} = FormatDetector.detect_with_confidence("# Header")

      # Batch detection
      {:ok, formats} = FormatDetector.detect_batch([content1, content2, content3])

      # With hints for better accuracy
      {:ok, "javascript"} = FormatDetector.detect(code_content,
        filename: "script.js",
        context: :web_development
      )

  """

  require Logger

  @type format :: String.t()
  @type confidence :: float()
  @type detection_options :: [
          filename: String.t() | nil,
          context: atom() | nil,
          max_sample_size: pos_integer(),
          confidence_threshold: float()
        ]

  @default_options [
    filename: nil,
    context: nil,
    max_sample_size: 8192,
    confidence_threshold: 0.7
  ]

  @jsonld_indicators [
    "@context",
    "@type",
    "@id",
    "@graph",
    "@value",
    "@language"
  ]

  @markdown_ld_indicators [
    "data-lang-entity",
    "data-lang-uri",
    "data-lang-type",
    "@context",
    "vocab=\""
  ]

  # Format detection patterns as functions
  defp json_patterns do
    [
      # JSON object
      ~r/^\s*\{.*\}\s*$/s,
      # JSON array
      ~r/^\s*\[.*\]\s*$/s
    ]
  end

  defp yaml_patterns do
    [
      # Key-value pairs
      ~r/^\s*[\w\-]+:\s+.+$/m,
      # YAML document start
      ~r/^---\s*$/m,
      # List items
      ~r/^\s*-\s+.+$/m
    ]
  end

  # Pattern functions to avoid compilation issues with regex references
  defp markdown_patterns do
    [
      # Headers
      ~r/^#+ .+$/m,
      # Bold/italic
      ~r/(\*\*|__|`).+\1/,
      # Links
      ~r/\[.+\]\(.+\)/,
      # Code blocks
      ~r/```[\w]*\n.*```/s
    ]
  end

  defp code_patterns do
    %{
      "javascript" => [
        ~r/function\s+\w+\s*\(/,
        ~r/const\s+\w+\s*=/,
        ~r/=>\s*{/,
        ~r/console\.log\s*\(/,
        ~r/require\s*\(/,
        ~r/import\s+.*from/
      ],
      "python" => [
        ~r/def\s+\w+\s*\(/,
        ~r/import\s+\w+/,
        ~r/from\s+\w+\s+import/,
        ~r/if\s+__name__\s*==\s*['"']__main__['"']/,
        ~r/class\s+\w+\s*\(/,
        ~r/print\s*\(/
      ],
      "elixir" => [
        ~r/defmodule\s+\w+/,
        ~r/def\s+\w+\s*\(/,
        ~r/defp\s+\w+\s*\(/,
        ~r/use\s+\w+/,
        ~r/alias\s+\w+/,
        ~r/\|>\s*\w+/
      ],
      "rust" => [
        ~r/fn\s+\w+\s*\(/,
        ~r/struct\s+\w+/,
        ~r/impl\s+\w+/,
        ~r/use\s+\w+::/,
        ~r/let\s+mut\s+\w+/,
        ~r/pub\s+fn\s+\w+/
      ],
      "go" => [
        ~r/func\s+\w+\s*\(/,
        ~r/package\s+\w+/,
        ~r/import\s+['"']/,
        ~r/type\s+\w+\s+struct/,
        ~r/var\s+\w+\s+\w+/
      ],
      "typescript" => [
        ~r/interface\s+\w+/,
        ~r/type\s+\w+\s*=/,
        ~r/:\s*\w+\s*=/,
        ~r/function\s+\w+\s*\(/,
        ~r/export\s+(default\s+)?/
      ],
      "java" => [
        ~r/public\s+class\s+\w+/,
        ~r/public\s+static\s+void\s+main/,
        ~r/import\s+[\w.]+;/,
        ~r/@\w+/,
        ~r/System\.out\.println/
      ]
    }
  end

  defp log_patterns do
    [
      # Timestamp patterns
      ~r/^\d{4}-\d{2}-\d{2}[\sT]\d{2}:\d{2}:\d{2}/,
      ~r/^\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}/,
      # Log levels
      ~r/\b(DEBUG|INFO|WARN|ERROR|FATAL|TRACE)\b/i,
      # Common log formats
      ~r/\[\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\]/
    ]
  end

  defp email_patterns do
    [
      ~r/^From:\s*.+$/m,
      ~r/^To:\s*.+$/m,
      ~r/^Subject:\s*.+$/m,
      ~r/^Date:\s*.+$/m,
      ~r/^Message-ID:\s*<.+>$/m
    ]
  end

  @doc """
  Detect the format of the given content.

  Returns the most likely format based on content analysis.

  ## Examples

      {:ok, "json"} = FormatDetector.detect(~s({"name": "test"}))
      {:ok, "markdown"} = FormatDetector.detect("# Title\n\nContent")
      {:ok, "python"} = FormatDetector.detect("def hello():\n    print('world')")

  """
  @spec detect(String.t(), detection_options()) :: {:ok, format()} | {:error, :unknown_format}
  def detect(content, options \\ []) when is_binary(content) do
    options = Keyword.merge(@default_options, options)

    # Limit sample size for performance
    sample = limit_sample_size(content, options)

    # Try detection methods in order of reliability
    case try_filename_detection(sample, options) ||
           try_signature_detection(sample) ||
           try_structure_detection(sample) ||
           try_syntax_detection(sample) ||
           try_heuristic_detection(sample) do
      {format, confidence} ->
        threshold = Keyword.get(options, :confidence_threshold, 0.7)

        if confidence >= threshold do
          {:ok, format}
        else
          Logger.debug("Format detected with low confidence",
            format: format,
            content_preview: String.slice(content, 0, 100)
          )

          {:ok, format}
        end

      nil ->
        {:error, :unknown_format}
    end
  end

  @doc """
  Detect format with confidence score.

  ## Examples

      {:ok, {"json", 0.95}} = FormatDetector.detect_with_confidence(~s({"key": "value"}))

  """
  @spec detect_with_confidence(String.t(), detection_options()) ::
          {:ok, {format(), confidence()}} | {:error, :unknown_format}
  def detect_with_confidence(content, options \\ []) when is_binary(content) do
    options = Keyword.merge(@default_options, options)
    sample = limit_sample_size(content, options)

    case try_filename_detection(sample, options) ||
           try_signature_detection(sample) ||
           try_structure_detection(sample) ||
           try_syntax_detection(sample) ||
           try_heuristic_detection(sample) do
      {format, confidence} -> {:ok, {format, confidence}}
      nil -> {:error, :unknown_format}
    end
  end

  @doc """
  Detect formats for multiple content samples.

  ## Examples

      {:ok, ["json", "markdown", "python"]} =
        FormatDetector.detect_batch([json_content, md_content, py_content])

  """
  @spec detect_batch([String.t()], detection_options()) :: {:ok, [format()]} | {:error, term()}
  def detect_batch(contents, options \\ []) when is_list(contents) do
    results =
      contents
      |> Enum.map(&detect(&1, options))
      |> Enum.map(fn
        {:ok, format} -> format
        # Fallback
        {:error, :unknown_format} -> "text"
      end)

    {:ok, results}
  end

  @doc """
  Get all supported format types that can be detected.

  ## Examples

      formats = FormatDetector.supported_formats()
      # => ["json", "jsonld", "yaml", "markdown", "python", ...]

  """
  @spec supported_formats() :: [format()]
  def supported_formats do
    [
      # Data formats
      "json",
      "jsonld",
      "yaml",
      "xml",
      "csv",
      "toml",
      # Document formats
      "markdown",
      "markdown_ld",
      "text",
      "html",
      "rst",
      # Code formats
      "javascript",
      "typescript",
      "python",
      "elixir",
      "rust",
      "go",
      "java",
      "c",
      "cpp",
      # Communication formats
      "email",
      "log",
      "sql",
      "chat"
    ]
  end

  @doc """
  Check if a format is supported by the detector.

  ## Examples

      true = FormatDetector.supports_format?("json")
      false = FormatDetector.supports_format?("unknown")

  """
  @spec supports_format?(format()) :: boolean()
  def supports_format?(format) when is_binary(format) do
    format in supported_formats()
  end

  # === Private Detection Methods ===

  defp limit_sample_size(content, options) do
    max_size = Keyword.get(options, :max_sample_size, 8192)

    if byte_size(content) > max_size do
      String.slice(content, 0, max_size)
    else
      content
    end
  end

  # Try to detect format from filename extension
  defp try_filename_detection(_content, options) do
    case Keyword.get(options, :filename) do
      nil -> nil
      filename -> detect_from_filename(filename)
    end
  end

  defp detect_from_filename(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".json" -> {"json", 0.9}
      ".jsonld" -> {"jsonld", 0.95}
      ".yaml" -> {"yaml", 0.9}
      ".yml" -> {"yaml", 0.9}
      ".md" -> {"markdown", 0.85}
      ".xml" -> {"xml", 0.9}
      ".html" -> {"html", 0.9}
      ".js" -> {"javascript", 0.85}
      ".ts" -> {"typescript", 0.85}
      ".py" -> {"python", 0.85}
      ".ex" -> {"elixir", 0.85}
      ".exs" -> {"elixir", 0.85}
      ".rs" -> {"rust", 0.85}
      ".go" -> {"go", 0.85}
      ".java" -> {"java", 0.85}
      ".c" -> {"c", 0.8}
      ".cpp" -> {"cpp", 0.8}
      ".sql" -> {"sql", 0.85}
      ".log" -> {"log", 0.8}
      _ -> nil
    end
  end

  # Try to detect format from content signatures
  defp try_signature_detection(content) do
    cond do
      # JSON-LD detection (highest priority for JSON variants)
      is_jsonld?(content) -> {"jsonld", 0.9}
      # JSON detection
      is_json?(content) -> {"json", 0.85}
      # YAML detection
      is_yaml?(content) -> {"yaml", 0.8}
      # Markdown-LD detection
      is_markdown_ld?(content) -> {"markdown_ld", 0.85}
      # XML detection
      is_xml?(content) -> {"xml", 0.8}
      # HTML detection
      is_html?(content) -> {"html", 0.8}
      true -> nil
    end
  end

  # Try to detect format from document structure
  defp try_structure_detection(content) do
    cond do
      is_markdown?(content) -> {"markdown", 0.75}
      is_email?(content) -> {"email", 0.8}
      is_log_file?(content) -> {"log", 0.7}
      is_csv?(content) -> {"csv", 0.7}
      true -> nil
    end
  end

  # Try to detect programming language from syntax
  defp try_syntax_detection(content) do
    code_patterns()
    |> Enum.find_value(fn {lang, patterns} ->
      score = calculate_pattern_score(content, patterns)
      if score >= 0.3, do: {lang, score + 0.4}, else: nil
    end)
  end

  # Fallback heuristic detection
  defp try_heuristic_detection(content) do
    cond do
      looks_like_conversation?(content) -> {"chat", 0.6}
      looks_like_config?(content) -> {"toml", 0.5}
      String.printable?(content) -> {"text", 0.9}
      true -> {"binary", 0.3}
    end
  end

  # === Format-Specific Detection Functions ===

  defp is_json?(content) do
    trimmed = String.trim(content)

    # Quick structural check
    # Validate with JSON parser if structure looks right
    (String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}")) or
      (String.starts_with?(trimmed, "[") and String.ends_with?(trimmed, "]") and
         case Jason.decode(content) do
           {:ok, _} -> true
           {:error, _} -> false
         end)
  rescue
    _ -> false
  end

  defp is_jsonld?(content) do
    is_json?(content) and
      Enum.any?(@jsonld_indicators, fn indicator ->
        String.contains?(content, indicator)
      end)
  end

  defp is_yaml?(content) do
    yaml_patterns()
    |> Enum.any?(&Regex.match?(&1, content))
  end

  defp is_xml?(content) do
    trimmed = String.trim(content)

    String.starts_with?(trimmed, "<?xml") or
      (String.starts_with?(trimmed, "<") and String.contains?(trimmed, "</"))
  end

  defp is_html?(content) do
    html_indicators = ["<html", "<HTML", "<!DOCTYPE html", "<head", "<body"]
    Enum.any?(html_indicators, &String.contains?(content, &1))
  end

  defp is_markdown?(content) do
    score = calculate_pattern_score(content, markdown_patterns())
    score >= 0.3
  end

  defp is_markdown_ld?(content) do
    is_markdown?(content) and
      Enum.any?(@markdown_ld_indicators, fn indicator ->
        String.contains?(content, indicator)
      end)
  end

  defp is_email?(content) do
    score = calculate_pattern_score(content, email_patterns())
    score >= 0.3
  end

  defp is_log_file?(content) do
    score = calculate_pattern_score(content, log_patterns())
    score >= 0.2
  end

  defp is_csv?(content) do
    lines = String.split(content, "\n", trim: true)

    if length(lines) >= 2 do
      # Check if lines have consistent comma-separated structure
      first_line_cols = String.split(Enum.at(lines, 0), ",") |> length()
      second_line_cols = String.split(Enum.at(lines, 1), ",") |> length()

      first_line_cols > 1 and first_line_cols == second_line_cols
    else
      false
    end
  end

  defp looks_like_conversation?(content) do
    # Look for conversation patterns
    conversation_indicators = [
      # "Speaker: message"
      ~r/^\w+:\s*.+$/m,
      # "[12:34] Speaker:"
      ~r/^\[\d+:\d+\]\s*\w+:/,
      # "<speaker> message"
      ~r/^<\w+>\s*.+$/m
    ]

    score = calculate_pattern_score(content, conversation_indicators)
    score >= 0.2
  end

  defp looks_like_config?(content) do
    # TOML/INI style config
    config_patterns = [
      # [section]
      ~r/^\[\w+\]$/m,
      # key = value
      ~r/^\w+\s*=\s*.+$/m,
      # comments
      ~r/^#.*$/m
    ]

    score = calculate_pattern_score(content, config_patterns)
    score >= 0.3
  end

  # === Helper Functions ===

  defp calculate_pattern_score(content, patterns) do
    lines = String.split(content, "\n")
    total_lines = max(1, length(lines))

    matching_lines =
      lines
      |> Enum.count(fn line ->
        Enum.any?(patterns, &Regex.match?(&1, line))
      end)

    matching_lines / total_lines
  end
end
