defmodule Lang.TextIntelligence.FormatDetector do
  @moduledoc """
  Intelligent format detection for text content.

  Detects file formats and content types using multiple strategies:
  - File extension analysis
  - Content pattern matching
  - Magic number detection
  - Syntax heuristics
  - Language-specific markers
  """

  require Logger

  @type format :: String.t()
  @type confidence :: float()
  @type detection_result :: %{
          format: format(),
          confidence: confidence(),
          detected_by: String.t(),
          metadata: map()
        }

  # Common file extensions to format mappings
  @extension_map %{
    # Programming languages
    ".ex" => "elixir",
    ".exs" => "elixir",
    ".eex" => "eex",
    ".heex" => "heex",
    ".leex" => "leex",
    ".js" => "javascript",
    ".jsx" => "jsx",
    ".ts" => "typescript",
    ".tsx" => "tsx",
    ".py" => "python",
    ".rb" => "ruby",
    ".rs" => "rust",
    ".go" => "go",
    ".java" => "java",
    ".c" => "c",
    ".cpp" => "cpp",
    ".cc" => "cpp",
    ".cxx" => "cpp",
    ".h" => "c_header",
    ".hpp" => "cpp_header",
    ".cs" => "csharp",
    ".php" => "php",
    ".swift" => "swift",
    ".kt" => "kotlin",
    ".scala" => "scala",
    ".clj" => "clojure",
    ".cljs" => "clojurescript",

    # Web technologies
    ".html" => "html",
    ".htm" => "html",
    ".css" => "css",
    ".scss" => "scss",
    ".sass" => "sass",
    ".less" => "less",
    ".vue" => "vue",
    ".svelte" => "svelte",

    # Data formats
    ".json" => "json",
    ".yaml" => "yaml",
    ".yml" => "yaml",
    ".xml" => "xml",
    ".toml" => "toml",
    ".ini" => "ini",
    ".csv" => "csv",
    ".tsv" => "tsv",

    # Documentation
    ".md" => "markdown",
    ".mdx" => "mdx",
    ".rst" => "restructuredtext",
    ".tex" => "latex",
    ".adoc" => "asciidoc",

    # Configuration
    ".dockerfile" => "dockerfile",
    ".gitignore" => "gitignore",
    ".env" => "env",
    ".sh" => "bash",
    ".bash" => "bash",
    ".zsh" => "zsh",
    ".fish" => "fish",
    ".ps1" => "powershell",
    ".bat" => "batch",
    ".cmd" => "batch",

    # Database
    ".sql" => "sql",
    ".sqlite" => "sqlite",

    # Logs and output
    ".log" => "log",
    ".txt" => "plain_text"
  }

  # Content patterns for format detection (moved to function to avoid serialization issues)
  defp get_content_patterns do
    %{
      "elixir" => [
        ~r/^defmodule\s+/m,
        ~r/def\s+\w+.*do/,
        ~r/use\s+\w+/,
        ~r/@\w+/,
        ~r/\|>/
      ],
      "javascript" => [
        ~r/function\s+\w+\s*\(/,
        ~r/const\s+\w+\s*=/,
        ~r/let\s+\w+\s*=/,
        ~r/var\s+\w+\s*=/,
        ~r/=>\s*{?/,
        ~r/require\s*\(/,
        ~r/import\s+.*from/
      ],
      "python" => [
        ~r/^def\s+\w+\s*\(/m,
        ~r/^class\s+\w+/m,
        ~r/^import\s+\w+/m,
        ~r/^from\s+\w+\s+import/m,
        ~r/__init__|__main__|__name__/,
        ~r/print\s*\(/
      ],
      "json" => [
        ~r/^\s*\{/,
        ~r/"[^"]*"\s*:/,
        ~r/\[\s*\{/
      ],
      "yaml" => [
        ~r/^---/m,
        ~r/^\w+:\s*$/m,
        ~r/^\s+-\s+\w+/m
      ],
      "markdown" => [
        ~r/^#+ /m,
        ~r/\*\*[^*]+\*\*/,
        ~r/\[[^\]]*\]\([^)]*\)/,
        ~r/```\w*/,
        ~r/^\s*[-*+]\s+/m
      ],
      "html" => [
        ~r/<html/i,
        ~r/<head>/i,
        ~r/<body>/i,
        ~r/<div/i,
        ~r/<!DOCTYPE/i
      ],
      "css" => [
        ~r/\{[^}]*\}/,
        ~r/\w+\s*:\s*[^;]+;/,
        ~r/@media/,
        ~r/\.[\w-]+\s*\{/
      ],
      "sql" => [
        ~r/\bSELECT\b/i,
        ~r/\bFROM\b/i,
        ~r/\bWHERE\b/i,
        ~r/\bINSERT\s+INTO\b/i,
        ~r/\bCREATE\s+TABLE\b/i
      ],
      "dockerfile" => [
        ~r/^FROM\s+/mi,
        ~r/^RUN\s+/mi,
        ~r/^COPY\s+/mi,
        ~r/^ADD\s+/mi,
        ~r/^ENV\s+/mi
      ]
    }
  end

  # Magic numbers for binary format detection
  @magic_numbers %{
    <<0x89, 0x50, 0x4E, 0x47>> => "png",
    <<0xFF, 0xD8, 0xFF>> => "jpeg",
    <<0x47, 0x49, 0x46>> => "gif",
    <<0x25, 0x50, 0x44, 0x46>> => "pdf",
    <<0x50, 0x4B, 0x03, 0x04>> => "zip",
    <<0x1F, 0x8B>> => "gzip"
  }

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Detect format from content with confidence scoring.
  """
  @spec detect(String.t()) :: format()
  def detect(content) when is_binary(content) do
    case detect_detailed(content) do
      %{format: format} -> format
      _ -> "unknown"
    end
  end

  @doc """
  Detect format with detailed results including confidence.
  """
  @spec detect_detailed(String.t()) :: detection_result()
  def detect_detailed(content) when is_binary(content) do
    # Try multiple detection strategies
    strategies = [
      {&detect_by_magic_number/1, "magic_number"},
      {&detect_by_content_patterns/1, "content_patterns"},
      {&detect_by_syntax_heuristics/1, "syntax_heuristics"},
      {&detect_by_structure/1, "structure_analysis"}
    ]

    results =
      strategies
      |> Enum.map(fn {detector, method} ->
        case detector.(content) do
          {format, confidence} -> %{format: format, confidence: confidence, method: method}
          nil -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.confidence, :desc)

    case results do
      [best | _] ->
        %{
          format: best.format,
          confidence: best.confidence,
          detected_by: best.method,
          metadata: %{
            all_results: results,
            content_length: String.length(content),
            line_count: count_lines(content)
          }
        }

      [] ->
        %{
          format: "unknown",
          confidence: 0.0,
          detected_by: "fallback",
          metadata: %{content_length: String.length(content)}
        }
    end
  end

  @doc """
  Detect format from URI/filename.
  """
  @spec detect_from_uri(String.t()) :: format()
  def detect_from_uri(uri) when is_binary(uri) do
    # Extract filename from URI
    filename =
      uri
      |> String.split("/")
      |> List.last()
      |> String.downcase()

    # Check for exact filename matches first
    case filename do
      "dockerfile" -> "dockerfile"
      "makefile" -> "makefile"
      "rakefile" -> "ruby"
      "gemfile" -> "ruby"
      "package.json" -> "json"
      "composer.json" -> "json"
      "cargo.toml" -> "toml"
      "mix.exs" -> "elixir"
      ".gitignore" -> "gitignore"
      ".env" -> "env"
      name -> detect_from_extension(name)
    end
  end

  @doc """
  Detect format from file extension.
  """
  @spec detect_from_extension(String.t()) :: format()
  def detect_from_extension(filename) when is_binary(filename) do
    extension =
      filename
      |> String.downcase()
      |> Path.extname()

    Map.get(@extension_map, extension, "unknown")
  end

  @doc """
  Get all supported formats.
  """
  @spec supported_formats() :: [format()]
  def supported_formats do
    ((@extension_map |> Map.values() |> Enum.uniq()) ++
       Map.keys(get_content_patterns()) ++
       ["binary", "unknown"])
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Check if format is supported.
  """
  @spec supported?(format()) :: boolean()
  def supported?(format) do
    format in supported_formats()
  end

  # =============================================================================
  # Detection Strategies
  # =============================================================================

  defp detect_by_magic_number(content) do
    # Check first few bytes for magic numbers
    Enum.find_value(@magic_numbers, fn {magic, format} ->
      if String.starts_with?(content, magic) do
        {format, 1.0}
      end
    end)
  end

  defp detect_by_content_patterns(content) do
    # Score each format based on pattern matches
    scores =
      get_content_patterns()
      |> Enum.map(fn {format, patterns} ->
        score = calculate_pattern_score(content, patterns)
        {format, score}
      end)
      |> Enum.filter(fn {_, score} -> score > 0 end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)

    case scores do
      [{format, score} | _] when score > 0.3 -> {format, score}
      _ -> nil
    end
  end

  defp detect_by_syntax_heuristics(content) do
    # Look for language-specific syntax markers
    cond do
      # Elixir specific
      String.contains?(content, ["defmodule", "def ", "do:", "|>"]) and
          Regex.match?(~r/\bend\b/, content) ->
        {"elixir", 0.8}

      # JavaScript specific
      String.contains?(content, ["function", "const ", "=>", "require("]) ->
        {"javascript", 0.7}

      # Python specific
      Regex.match?(~r/^def\s+\w+\s*\(/m, content) and
          (String.contains?(content, "import ") or String.contains?(content, "print(")) ->
        {"python", 0.8}

      # JSON specific
      String.starts_with?(String.trim(content), "{") and
        String.ends_with?(String.trim(content), "}") and
          String.contains?(content, "\":") ->
        {"json", 0.9}

      # YAML specific
      Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*:\s/m, content) and
          not String.contains?(content, "{") ->
        {"yaml", 0.7}

      # Markdown specific
      Regex.match?(~r/^#+\s/m, content) or String.contains?(content, ["```", "**", "[]()"]) ->
        {"markdown", 0.6}

      # HTML specific
      String.contains?(content, "<") and String.contains?(content, ">") and
          (String.contains?(content, "html") or String.contains?(content, "DOCTYPE")) ->
        {"html", 0.8}

      true ->
        nil
    end
  end

  defp detect_by_structure(content) do
    # Analyze overall structure
    lines = String.split(content, "\n")
    line_count = length(lines)

    cond do
      # Very short content might be configuration
      line_count < 10 and String.contains?(content, "=") ->
        {"config", 0.3}

      # Many lines starting with # are likely shell scripts or comments
      count_lines_starting_with(lines, "#") > line_count * 0.3 ->
        {"bash", 0.4}

      # Log file patterns
      Enum.any?(lines, &log_line?/1) and line_count > 10 ->
        {"log", 0.6}

      # Data files (mostly numbers and delimiters)
      mostly_data?(content) ->
        cond do
          String.contains?(content, ",") -> {"csv", 0.5}
          String.contains?(content, "\t") -> {"tsv", 0.5}
          true -> {"data", 0.4}
        end

      true ->
        nil
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp calculate_pattern_score(content, patterns) do
    content_length = String.length(content)

    if content_length == 0 do
      0.0
    else
      match_count =
        patterns
        |> Enum.map(fn pattern ->
          case Regex.scan(pattern, content) do
            matches when is_list(matches) -> length(matches)
            _ -> 0
          end
        end)
        |> Enum.sum()

      # Normalize score based on content length and pattern matches
      base_score = match_count / length(patterns)
      length_factor = min(1.0, content_length / 1000)

      base_score * length_factor
    end
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end

  defp count_lines_starting_with(lines, prefix) do
    Enum.count(lines, fn line ->
      String.starts_with?(String.trim(line), prefix)
    end)
  end

  defp log_line?(line) do
    # Common log patterns
    Regex.match?(~r/^\d{4}-\d{2}-\d{2}/, line) or
      Regex.match?(~r/^\[\d{4}-\d{2}-\d{2}/, line) or
      String.contains?(line, ["ERROR", "WARN", "INFO", "DEBUG"])
  end

  defp mostly_data?(content) do
    # Simple heuristic: if more than 50% of characters are numbers, spaces, or common delimiters
    data_chars = Regex.scan(~r/[\d\s,.\-+;:\t]/, content) |> length()
    total_chars = String.length(content)

    total_chars > 0 and data_chars / total_chars > 0.5
  end

  @doc """
  Get format metadata and capabilities.
  """
  @spec format_info(format()) :: map()
  def format_info(format) do
    case format do
      "elixir" ->
        %{
          language: "Elixir",
          type: "programming",
          syntax_highlighting: true,
          lsp_support: true,
          file_extensions: [".ex", ".exs"],
          comment_style: "#"
        }

      "javascript" ->
        %{
          language: "JavaScript",
          type: "programming",
          syntax_highlighting: true,
          lsp_support: true,
          file_extensions: [".js", ".jsx"],
          comment_style: "//"
        }

      "python" ->
        %{
          language: "Python",
          type: "programming",
          syntax_highlighting: true,
          lsp_support: true,
          file_extensions: [".py"],
          comment_style: "#"
        }

      "markdown" ->
        %{
          language: "Markdown",
          type: "documentation",
          syntax_highlighting: true,
          lsp_support: false,
          file_extensions: [".md", ".markdown"],
          comment_style: "<!-- -->"
        }

      "json" ->
        %{
          language: "JSON",
          type: "data",
          syntax_highlighting: true,
          lsp_support: false,
          file_extensions: [".json"],
          comment_style: nil
        }

      _ ->
        %{
          language: "Unknown",
          type: "unknown",
          syntax_highlighting: false,
          lsp_support: false,
          file_extensions: [],
          comment_style: nil
        }
    end
  end
end
