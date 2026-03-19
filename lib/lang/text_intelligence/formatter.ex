defmodule Lang.TextIntelligence.Formatter do
  @moduledoc """
  Code formatter for various programming languages and text formats.

  Provides intelligent formatting capabilities including:
  - Language-specific code formatting
  - Indentation correction
  - Style consistency enforcement
  - Custom formatting rules
  - Integration with external formatters
  """

  require Logger
  alias Lang.TextIntelligence.FormatDetector
  alias Lang.Native.PerfEngine

  @type format_result :: {:ok, String.t()} | {:error, String.t()}
  @type format_options :: %{
          indent_size: pos_integer(),
          use_tabs: boolean(),
          max_line_length: pos_integer(),
          preserve_newlines: boolean(),
          custom_rules: map()
        }

  # Default formatting options
  @default_options %{
    indent_size: 2,
    use_tabs: false,
    max_line_length: 80,
    preserve_newlines: true,
    custom_rules: %{}
  }

  # Language-specific formatter configurations
  @language_configs %{
    "elixir" => %{
      indent_size: 2,
      use_tabs: false,
      max_line_length: 98,
      preserve_newlines: true,
      formatter: :mix_format
    },
    "javascript" => %{
      indent_size: 2,
      use_tabs: false,
      max_line_length: 80,
      preserve_newlines: true,
      formatter: :prettier
    },
    "python" => %{
      indent_size: 4,
      use_tabs: false,
      max_line_length: 88,
      preserve_newlines: true,
      formatter: :black
    },
    "json" => %{
      indent_size: 2,
      use_tabs: false,
      max_line_length: 120,
      preserve_newlines: false,
      formatter: :json_formatter
    },
    "css" => %{
      indent_size: 2,
      use_tabs: false,
      max_line_length: 80,
      preserve_newlines: true,
      formatter: :css_formatter
    }
  }

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Format text content with automatic language detection.
  """
  @spec format(String.t(), String.t() | nil, format_options()) :: format_result()
  def format(content, language_id \\ nil, options \\ %{}) when is_binary(content) do
    detected_language = language_id || FormatDetector.detect(content)
    merged_options = merge_options(detected_language, options)

    Logger.debug("Formatting content",
      language: detected_language,
      content_length: String.length(content),
      options: merged_options
    )

    try do
      format_with_language(content, detected_language, merged_options)
    rescue
      error ->
        Logger.error("Formatting failed", error: inspect(error))
        {:error, "Formatting failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Format multiple files in batch.
  """
  @spec format_batch([{String.t(), String.t()}], format_options()) ::
          [{String.t(), format_result()}]
  def format_batch(files, options \\ %{}) when is_list(files) do
    files
    |> Task.async_stream(
      fn {uri, content} ->
        language = FormatDetector.detect_from_uri(uri)
        result = format(content, language, options)
        {uri, result}
      end,
      max_concurrency: 10,
      timeout: 30_000
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Check if content is properly formatted.
  """
  @spec is_formatted?(String.t(), String.t() | nil, format_options()) :: boolean()
  def is_formatted?(content, language_id \\ nil, options \\ %{}) do
    case format(content, language_id, options) do
      {:ok, formatted} -> content == formatted
      {:error, _} -> false
    end
  end

  @doc """
  Get formatting capabilities for a language.
  """
  @spec get_capabilities(String.t()) :: map()
  def get_capabilities(language) do
    config = Map.get(@language_configs, language, %{})

    %{
      supported: Map.has_key?(@language_configs, language),
      formatter: Map.get(config, :formatter, :generic),
      default_options: config,
      features: get_language_features(language)
    }
  end

  # =============================================================================
  # Language-Specific Formatting
  # =============================================================================

  defp format_with_language(content, "elixir", options) do
    case format_elixir(content, options) do
      {:ok, formatted} -> {:ok, formatted}
      {:error, _} -> format_generic(content, options)
    end
  end

  defp format_with_language(content, "javascript", options) do
    case format_javascript(content, options) do
      {:ok, formatted} -> {:ok, formatted}
      {:error, _} -> format_generic(content, options)
    end
  end

  defp format_with_language(content, "python", options) do
    case format_python(content, options) do
      {:ok, formatted} -> {:ok, formatted}
      {:error, _} -> format_generic(content, options)
    end
  end

  defp format_with_language(content, "json", options) do
    format_json(content, options)
  end

  defp format_with_language(content, "css", options) do
    format_css(content, options)
  end

  defp format_with_language(content, "markdown", options) do
    format_markdown(content, options)
  end

  defp format_with_language(content, _language, options) do
    format_generic(content, options)
  end

  # =============================================================================
  # Elixir Formatting
  # =============================================================================

  defp format_elixir(content, options) do
    # Try using mix format if available
    case System.cmd("mix", ["format", "-"], input: content, stderr_to_stdout: true) do
      {formatted_content, 0} ->
        {:ok, String.trim(formatted_content)}

      {error_output, _} ->
        Logger.warning("mix format failed", error: error_output)
        # Fallback to manual formatting
        format_elixir_manual(content, options)
    end
  rescue
    # If mix is not available, use manual formatting
    _error -> format_elixir_manual(content, options)
  end

  defp format_elixir_manual(content, options) do
    content
    |> fix_indentation(options)
    |> normalize_whitespace(options)
    |> apply_elixir_style_rules(options)
    |> wrap_ok()
  end

  defp apply_elixir_style_rules(content, _options) do
    content
    # Normalize pipe operators
    |> String.replace(~r/\s*\|\>\s*/, " |> ")
    # Fix function definitions spacing
    |> String.replace(~r/def\s+(\w+)\s*\(/, "def \\1(")
    # Normalize do...end blocks
    |> String.replace(~r/\s+do\s*\n/, " do\n")
    # Fix pattern matching spacing
    |> String.replace(~r/(\w+)\s*=\s*/, "\\1 = ")
  end

  # =============================================================================
  # JavaScript Formatting
  # =============================================================================

  defp format_javascript(content, options) do
    # Try using prettier if available
    case System.cmd("npx", ["prettier", "--parser", "javascript", "--stdin-filepath", "file.js"],
           input: content,
           stderr_to_stdout: true
         ) do
      {formatted_content, 0} ->
        {:ok, String.trim(formatted_content)}

      {error_output, _} ->
        Logger.warning("prettier failed", error: error_output)
        format_javascript_manual(content, options)
    end
  rescue
    _error -> format_javascript_manual(content, options)
  end

  defp format_javascript_manual(content, options) do
    content
    |> fix_indentation(options)
    |> normalize_whitespace(options)
    |> apply_javascript_style_rules(options)
    |> wrap_ok()
  end

  defp apply_javascript_style_rules(content, _options) do
    content
    # Normalize function declarations
    |> String.replace(~r/function\s+(\w+)\s*\(/, "function \\1(")
    # Fix object/array spacing
    |> String.replace(~r/\{\s+/, "{ ")
    |> String.replace(~r/\s+\}/, " }")
    |> String.replace(~r/\[\s+/, "[")
    |> String.replace(~r/\s+\]/, "]")
    # Normalize semicolons
    |> String.replace(~r/;\s*\n/, ";\n")
  end

  # =============================================================================
  # Python Formatting
  # =============================================================================

  defp format_python(content, options) do
    # Try using black if available
    case System.cmd("black", ["--code", content], stderr_to_stdout: true) do
      {formatted_content, 0} ->
        {:ok, String.trim(formatted_content)}

      {error_output, _} ->
        Logger.warning("black formatter failed", error: error_output)
        format_python_manual(content, options)
    end
  rescue
    _error -> format_python_manual(content, options)
  end

  defp format_python_manual(content, options) do
    content
    |> fix_python_indentation(options)
    |> normalize_whitespace(options)
    |> apply_python_style_rules(options)
    |> wrap_ok()
  end

  defp fix_python_indentation(content, options) do
    indent_size = Map.get(options, :indent_size, 4)

    indent_char =
      if Map.get(options, :use_tabs, false), do: "\t", else: String.duplicate(" ", indent_size)

    lines = String.split(content, "\n")

    {formatted_lines, _level} =
      Enum.map_reduce(lines, 0, fn line, current_level ->
        trimmed = String.trim(line)

        cond do
          trimmed == "" ->
            {line, current_level}

          String.ends_with?(trimmed, ":") ->
            formatted = String.duplicate(indent_char, current_level) <> trimmed
            {formatted, current_level + 1}

          String.starts_with?(trimmed, ["return", "break", "continue", "pass"]) ->
            formatted = String.duplicate(indent_char, max(0, current_level - 1)) <> trimmed
            {formatted, max(0, current_level - 1)}

          true ->
            formatted = String.duplicate(indent_char, current_level) <> trimmed
            {formatted, current_level}
        end
      end)

    Enum.join(formatted_lines, "\n")
  end

  defp apply_python_style_rules(content, _options) do
    content
    # Normalize function definitions
    |> String.replace(~r/def\s+(\w+)\s*\(/, "def \\1(")
    # Fix class definitions
    |> String.replace(~r/class\s+(\w+)\s*\(/, "class \\1(")
    |> String.replace(~r/class\s+(\w+)\s*:/, "class \\1:")
    # Normalize imports
    |> String.replace(~r/import\s+(\w+)/, "import \\1")
    |> String.replace(~r/from\s+(\w+)\s+import/, "from \\1 import")
  end

  # =============================================================================
  # JSON Formatting
  # =============================================================================

  defp format_json(content, options) do
    try do
      parsed = Jason.decode!(content)
      indent_size = Map.get(options, :indent_size, 2)
      formatted = Jason.encode!(parsed, pretty: [indent: String.duplicate(" ", indent_size)])
      {:ok, formatted}
    rescue
      Jason.DecodeError -> {:error, "Invalid JSON content"}
      error -> {:error, "JSON formatting failed: #{Exception.message(error)}"}
    end
  end

  # =============================================================================
  # CSS Formatting
  # =============================================================================

  defp format_css(content, options) do
    content
    |> fix_css_indentation(options)
    |> normalize_css_rules(options)
    |> wrap_ok()
  end

  defp fix_css_indentation(content, options) do
    indent_size = Map.get(options, :indent_size, 2)
    indent = String.duplicate(" ", indent_size)

    content
    |> String.replace(~r/\{\s*/, "{\n")
    |> String.replace(~r/;\s*/, ";\n")
    |> String.replace(~r/\}\s*/, "\n}\n")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      if String.contains?(line, ":") and not String.starts_with?(line, ["{", "}"]) do
        indent <> line
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  defp normalize_css_rules(content, _options) do
    content
    # Normalize property declarations
    |> String.replace(~r/(\w+)\s*:\s*([^;]+);/, "\\1: \\2;")
    # Fix selector spacing
    |> String.replace(~r/([^,\s])\s*,\s*/, "\\1, ")
  end

  # =============================================================================
  # Markdown Formatting
  # =============================================================================

  defp format_markdown(content, options) do
    content
    |> normalize_markdown_headers(options)
    |> fix_markdown_lists(options)
    |> normalize_markdown_links(options)
    |> wrap_ok()
  end

  defp normalize_markdown_headers(content, _options) do
    content
    # Ensure space after hash marks
    |> String.replace(~r/^(#+)([^\s])/, "\\1 \\2")
    # Remove trailing spaces from headers
    |> String.replace(~r/^(#+ .+)\s+$/, "\\1")
  end

  defp fix_markdown_lists(content, _options) do
    content
    # Normalize list markers
    |> String.replace(~r/^(\s*)-([^\s])/, "\\1- \\2")
    |> String.replace(~r/^(\s*)\*([^\s])/, "\\1* \\2")
    |> String.replace(~r/^(\s*)\+([^\s])/, "\\1+ \\2")
  end

  defp normalize_markdown_links(content, _options) do
    content
    # Fix link formatting
    |> String.replace(~r/\[\s*([^\]]+)\s*\]\(\s*([^)]+)\s*\)/, "[\\1](\\2)")
  end

  # =============================================================================
  # Generic Formatting
  # =============================================================================

  defp format_generic(content, options) do
    content
    |> fix_indentation(options)
    |> normalize_whitespace(options)
    |> fix_line_length(options)
    |> wrap_ok()
  end

  defp fix_indentation(content, options) do
    indent_size = Map.get(options, :indent_size, 2)
    use_tabs = Map.get(options, :use_tabs, false)

    target_indent = if use_tabs, do: "\t", else: String.duplicate(" ", indent_size)

    lines = String.split(content, "\n")

    Enum.map(lines, fn line ->
      # Count leading whitespace
      leading_spaces = String.length(line) - String.length(String.trim_leading(line))

      if leading_spaces > 0 do
        # Calculate indent level (assuming 2 or 4 space indents)
        indent_level = div(leading_spaces, if(leading_spaces > 2, do: 4, else: 2))
        trimmed_content = String.trim_leading(line)
        String.duplicate(target_indent, indent_level) <> trimmed_content
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  defp normalize_whitespace(content, options) do
    preserve_newlines = Map.get(options, :preserve_newlines, true)

    content
    # Remove trailing spaces
    |> String.replace(~r/[ \t]+$/, "", [:multiline])
    # Normalize multiple spaces to single spaces (except at start of line)
    |> String.replace(~r/([^\n\r])[ ]+/, "\\1 ")
    # Handle multiple newlines
    |> then(fn text ->
      if preserve_newlines do
        # Limit consecutive newlines to maximum of 2
        String.replace(text, ~r/\n{3,}/, "\n\n")
      else
        # Remove extra newlines
        String.replace(text, ~r/\n+/, "\n")
      end
    end)
  end

  defp fix_line_length(content, options) do
    max_length = Map.get(options, :max_line_length, 80)

    content
    |> String.split("\n")
    |> Enum.map(fn line ->
      if String.length(line) <= max_length do
        line
      else
        # Simple word wrapping
        wrap_line(line, max_length)
      end
    end)
    |> Enum.join("\n")
  end

  defp wrap_line(line, max_length) do
    words = String.split(line, " ")
    indent = get_line_indent(line)

    {wrapped_lines, _current_line} =
      Enum.reduce(words, {[], ""}, fn word, {lines, current_line} ->
        test_line = if current_line == "", do: word, else: current_line <> " " <> word

        if String.length(test_line) <= max_length do
          {lines, test_line}
        else
          new_line = indent <> word
          {lines ++ [current_line], new_line}
        end
      end)

    case wrapped_lines do
      [] -> line
      lines -> Enum.join(lines, "\n")
    end
  end

  defp get_line_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> indent
      _ -> ""
    end
  end

  # =============================================================================
  # Utilities
  # =============================================================================

  defp merge_options(language, custom_options) do
    language_config = Map.get(@language_configs, language, %{})

    @default_options
    |> Map.merge(language_config)
    |> Map.merge(custom_options)
  end

  defp get_language_features(language) do
    case language do
      "elixir" ->
        [:syntax_highlighting, :auto_indentation, :pipe_formatting, :pattern_matching]

      "javascript" ->
        [:syntax_highlighting, :auto_indentation, :semicolon_insertion, :object_formatting]

      "python" ->
        [:syntax_highlighting, :auto_indentation, :pep8_compliance, :import_sorting]

      "json" ->
        [:syntax_highlighting, :pretty_printing, :validation]

      "css" ->
        [:syntax_highlighting, :auto_indentation, :property_sorting]

      "markdown" ->
        [:syntax_highlighting, :list_formatting, :link_validation]

      _ ->
        [:basic_indentation, :whitespace_normalization]
    end
  end

  defp wrap_ok(content), do: {:ok, content}
end
