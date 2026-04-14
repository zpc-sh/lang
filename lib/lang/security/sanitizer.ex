defmodule Lang.Security.Sanitizer do
  @moduledoc """
  Security sanitization engine for LANG system.

  Provides comprehensive input sanitization including:
  - HTML/XML sanitization
  - SQL injection prevention
  - XSS prevention
  - Path traversal prevention
  - Command injection prevention
  - Content filtering
  """

  require Logger

  @type sanitization_type ::
          :html | :sql | :path | :command | :json | :regex | :filename | :generic
  @type sanitization_result :: {:ok, String.t()} | {:error, String.t()}

  # HTML entities for encoding
  @html_entities %{
    "&" => "&amp;",
    "<" => "&lt;",
    ">" => "&gt;",
    "\"" => "&quot;",
    "'" => "&#x27;",
    "/" => "&#x2F;",
    "`" => "&#x60;",
    "=" => "&#x3D;"
  }

  # Dangerous SQL keywords and patterns (moved to functions to avoid serialization issues)
  defp get_sql_dangerous_patterns do
    [
      ~r/(\bUNION\b|\bSELECT\b|\bINSERT\b|\bUPDATE\b|\bDELETE\b|\bDROP\b|\bCREATE\b|\bALTER\b|\bTRUNCATE\b)/i,
      ~r/(\bEXEC\b|\bEVAL\b|\bSCRIPT\b)/i,
      ~r/(;|\|\||&&|\-\-|\/\*|\*\/)/,
      ~r/(\bxp_|\bsp_)/i
    ]
  end

  # Command injection patterns
  defp get_command_patterns do
    [
      ~r/[;&|`$(){}]/,
      ~r/\b(rm|del|format|fdisk|kill|shutdown|reboot)\b/i,
      ~r/[\r\n]/
    ]
  end

  # File path dangerous patterns
  defp get_path_patterns do
    [
      ~r/\.\./,
      ~r/[<>:"|?*]/,
      ~r/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)/i,
      ~r/[\x00-\x1f\x7f]/
    ]
  end

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Sanitize input based on the specified type.
  """
  @spec sanitize(String.t(), sanitization_type()) :: sanitization_result()
  def sanitize(input, type) when is_binary(input) do
    Logger.debug("Sanitizing input", type: type, length: String.length(input))

    try do
      result = perform_sanitization(input, type)
      {:ok, result}
    rescue
      error ->
        Logger.error("Sanitization failed", error: inspect(error), type: type)
        {:error, "Sanitization failed: #{Exception.message(error)}"}
    end
  end

  def sanitize(input, _type) when not is_binary(input) do
    {:error, "Input must be a string"}
  end

  @doc """
  Sanitize HTML content to prevent XSS attacks.
  """
  @spec sanitize_html(String.t()) :: String.t()
  def sanitize_html(input) when is_binary(input) do
    input
    |> encode_html_entities()
    |> remove_script_tags()
    |> remove_event_handlers()
    |> remove_javascript_urls()
  end

  @doc """
  Sanitize SQL input to prevent injection attacks.
  """
  @spec sanitize_sql(String.t()) :: String.t()
  def sanitize_sql(input) when is_binary(input) do
    input
    |> escape_sql_quotes()
    |> remove_sql_comments()
    |> remove_dangerous_sql_keywords()
    |> limit_sql_length()
  end

  @doc """
  Sanitize file paths to prevent traversal attacks.
  """
  @spec sanitize_path(String.t()) :: String.t()
  def sanitize_path(input) when is_binary(input) do
    input
    |> remove_path_traversal()
    |> remove_dangerous_path_chars()
    |> normalize_path_separators()
    |> limit_path_length()
  end

  @doc """
  Sanitize command input to prevent injection.
  """
  @spec sanitize_command(String.t()) :: String.t()
  def sanitize_command(input) when is_binary(input) do
    input
    |> remove_shell_metacharacters()
    |> remove_dangerous_commands()
    |> remove_control_characters()
    |> limit_command_length()
  end

  @doc """
  Sanitize filename to be filesystem-safe.
  """
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(input) when is_binary(input) do
    input
    |> String.trim()
    |> remove_path_separators()
    |> remove_reserved_names()
    |> remove_dangerous_extensions()
    |> limit_filename_length()
    |> ensure_non_empty_filename()
  end

  @doc """
  Generic sanitization for unknown content types.
  """
  @spec sanitize_generic(String.t()) :: String.t()
  def sanitize_generic(input) when is_binary(input) do
    input
    |> remove_control_characters()
    |> normalize_unicode()
    |> limit_generic_length()
  end

  @doc """
  Check if input contains dangerous patterns.
  """
  @spec contains_dangerous_patterns?(String.t(), sanitization_type()) :: boolean()
  def contains_dangerous_patterns?(input, :sql) do
    Enum.any?(get_sql_dangerous_patterns(), fn pattern ->
      Regex.match?(pattern, input)
    end)
  end

  def contains_dangerous_patterns?(input, :command) do
    Enum.any?(get_command_patterns(), fn pattern ->
      Regex.match?(pattern, input)
    end)
  end

  def contains_dangerous_patterns?(input, :path) do
    Enum.any?(get_path_patterns(), fn pattern ->
      Regex.match?(pattern, input)
    end)
  end

  def contains_dangerous_patterns?(input, :html) do
    String.contains?(input, ["<script", "javascript:", "on"]) or
      Regex.match?(~r/<[^>]*on\w+\s*=/i, input)
  end

  def contains_dangerous_patterns?(_input, _type), do: false

  # =============================================================================
  # Sanitization Implementations
  # =============================================================================

  defp perform_sanitization(input, :html), do: sanitize_html(input)
  defp perform_sanitization(input, :sql), do: sanitize_sql(input)
  defp perform_sanitization(input, :path), do: sanitize_path(input)
  defp perform_sanitization(input, :command), do: sanitize_command(input)
  defp perform_sanitization(input, :filename), do: sanitize_filename(input)
  defp perform_sanitization(input, :json), do: sanitize_json(input)
  defp perform_sanitization(input, :regex), do: sanitize_regex(input)
  defp perform_sanitization(input, :generic), do: sanitize_generic(input)
  defp perform_sanitization(input, _unknown), do: sanitize_generic(input)

  # =============================================================================
  # HTML Sanitization
  # =============================================================================

  defp encode_html_entities(input) do
    Enum.reduce(@html_entities, input, fn {char, entity}, acc ->
      String.replace(acc, char, entity)
    end)
  end

  defp remove_script_tags(input) do
    input
    |> String.replace(~r/<script[^>]*>.*?<\/script>/i, "")
    |> String.replace(~r/<script[^>]*>/i, "")
    |> String.replace(~r/<\/script>/i, "")
  end

  defp remove_event_handlers(input) do
    # Remove HTML event handlers like onclick, onload, etc.
    String.replace(input, ~r/\bon\w+\s*=\s*['""][^'"]*['""]|on\w+\s*=\s*[^\s>]+/i, "")
  end

  defp remove_javascript_urls(input) do
    input
    |> String.replace(~r/javascript:\s*[^'"\s]*/i, "")
    |> String.replace(~r/vbscript:\s*[^'"\s]*/i, "")
    |> String.replace(~r/data:\s*[^'"\s]*/i, "")
  end

  # =============================================================================
  # SQL Sanitization
  # =============================================================================

  defp escape_sql_quotes(input) do
    input
    |> String.replace("'", "''")
    |> String.replace("\"", "\"\"")
    |> String.replace("\\", "\\\\")
  end

  defp remove_sql_comments(input) do
    input
    |> String.replace(~r/--.*$/, "", [:multiline])
    |> String.replace(~r/\/\*.*?\*\//, "", [:multiline, :dotall])
    |> String.replace(~r/#.*$/, "", [:multiline])
  end

  defp remove_dangerous_sql_keywords(input) do
    Enum.reduce(get_sql_dangerous_patterns(), input, fn pattern, acc ->
      String.replace(acc, pattern, "")
    end)
  end

  defp limit_sql_length(input) do
    max_length = 10_000

    if String.length(input) > max_length do
      String.slice(input, 0, max_length)
    else
      input
    end
  end

  # =============================================================================
  # Path Sanitization
  # =============================================================================

  defp remove_path_traversal(input) do
    input
    |> String.replace("..", "")
    |> String.replace("./", "")
    |> String.replace("~/", "")
  end

  defp remove_dangerous_path_chars(input) do
    # Remove or replace dangerous path characters
    input
    |> String.replace(~r/[<>:"|?*]/, "")
    |> String.replace(~r/[\x00-\x1f\x7f]/, "")
  end

  defp normalize_path_separators(input) do
    input
    |> String.replace("\\", "/")
    |> String.replace(~r/\/+/, "/")
  end

  defp limit_path_length(input) do
    max_length = 4096

    if String.length(input) > max_length do
      String.slice(input, 0, max_length)
    else
      input
    end
  end

  # =============================================================================
  # Command Sanitization
  # =============================================================================

  defp remove_shell_metacharacters(input) do
    # Remove shell metacharacters that could be used for command injection
    String.replace(input, ~r/[;&|`$(){}]/, "")
  end

  defp remove_dangerous_commands(input) do
    dangerous_commands = [
      "rm",
      "del",
      "format",
      "fdisk",
      "kill",
      "shutdown",
      "reboot",
      "sudo",
      "su",
      "chmod",
      "chown",
      "passwd",
      "useradd",
      "userdel"
    ]

    Enum.reduce(dangerous_commands, input, fn cmd, acc ->
      String.replace(acc, ~r/\b#{cmd}\b/i, "")
    end)
  end

  defp limit_command_length(input) do
    max_length = 1000

    if String.length(input) > max_length do
      String.slice(input, 0, max_length)
    else
      input
    end
  end

  # =============================================================================
  # Filename Sanitization
  # =============================================================================

  defp remove_path_separators(input) do
    input
    |> String.replace("/", "")
    |> String.replace("\\", "")
  end

  defp remove_reserved_names(input) do
    reserved_names =
      ["CON", "PRN", "AUX", "NUL"] ++
        for(i <- 1..9, do: "COM#{i}") ++
        for(i <- 1..9, do: "LPT#{i}")

    name_without_ext = Path.rootname(input)

    if String.upcase(name_without_ext) in reserved_names do
      "safe_#{input}"
    else
      input
    end
  end

  defp remove_dangerous_extensions(input) do
    dangerous_extensions = [".exe", ".bat", ".cmd", ".com", ".pif", ".scr", ".vbs", ".js"]

    extension = Path.extname(input)

    if String.downcase(extension) in dangerous_extensions do
      Path.rootname(input) <> ".txt"
    else
      input
    end
  end

  defp limit_filename_length(input) do
    max_length = 255

    if String.length(input) > max_length do
      extension = Path.extname(input)
      basename = Path.rootname(input)
      max_basename_length = max_length - String.length(extension)
      String.slice(basename, 0, max_basename_length) <> extension
    else
      input
    end
  end

  defp ensure_non_empty_filename(""), do: "untitled"
  defp ensure_non_empty_filename(filename), do: filename

  # =============================================================================
  # JSON Sanitization
  # =============================================================================

  defp sanitize_json(input) do
    input
    |> remove_control_characters()
    |> escape_json_special_chars()
    |> limit_json_depth()
  end

  defp escape_json_special_chars(input) do
    input
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp limit_json_depth(input) do
    # Simple depth limiting by counting braces
    max_depth = 20
    depth = count_max_nesting_depth(input)

    if depth > max_depth do
      Logger.warning("JSON depth exceeds limit", depth: depth, max: max_depth)
      "{\"error\": \"JSON too deeply nested\"}"
    else
      input
    end
  end

  defp count_max_nesting_depth(input) do
    {_final_depth, max_depth} =
      input
      |> String.graphemes()
      |> Enum.reduce({0, 0}, fn char, {current_depth, max_depth} ->
        new_depth =
          case char do
            "{" -> current_depth + 1
            "[" -> current_depth + 1
            "}" -> max(0, current_depth - 1)
            "]" -> max(0, current_depth - 1)
            _ -> current_depth
          end

        {new_depth, max(max_depth, new_depth)}
      end)

    max_depth
  end

  # =============================================================================
  # Regex Sanitization
  # =============================================================================

  defp sanitize_regex(input) do
    input
    |> escape_regex_metacharacters()
    |> limit_regex_complexity()
  end

  defp escape_regex_metacharacters(input) do
    # Escape regex metacharacters to prevent ReDoS attacks
    metacharacters = ["\\", "^", "$", ".", "|", "?", "*", "+", "(", ")", "[", "]", "{", "}"]

    Enum.reduce(metacharacters, input, fn char, acc ->
      String.replace(acc, char, "\\#{char}")
    end)
  end

  defp limit_regex_complexity(input) do
    # Simple complexity check - limit length and certain patterns
    max_length = 1000

    if String.length(input) > max_length do
      String.slice(input, 0, max_length)
    else
      # Remove potentially dangerous regex patterns
      input
      # Remove comments
      |> String.replace(~r/\(\?\#.*?\)/, "")
      # Convert non-capturing to capturing
      |> String.replace(~r/\(\?\:/, "(")
    end
  end

  # =============================================================================
  # Generic Utilities
  # =============================================================================

  defp remove_control_characters(input) do
    String.replace(input, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  defp normalize_unicode(input) do
    # Basic unicode normalization - remove zero-width characters
    input
    # Zero-width spaces
    |> String.replace(~r/[\x{200B}-\x{200D}\x{FEFF}]/u, "")
    # Line/paragraph separators
    |> String.replace(~r/[\x{2028}\x{2029}]/u, " ")
  end

  defp limit_generic_length(input) do
    max_length = 100_000

    if String.length(input) > max_length do
      String.slice(input, 0, max_length)
    else
      input
    end
  end

  # =============================================================================
  # Batch Operations
  # =============================================================================

  @doc """
  Sanitize multiple inputs at once.
  """
  @spec sanitize_batch([{String.t(), sanitization_type()}]) :: [sanitization_result()]
  def sanitize_batch(inputs) when is_list(inputs) do
    inputs
    |> Task.async_stream(
      fn {input, type} -> sanitize(input, type) end,
      max_concurrency: 10,
      timeout: 5000
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Get sanitization recommendations for content.
  """
  @spec get_sanitization_recommendations(String.t()) :: [atom()]
  def get_sanitization_recommendations(input) when is_binary(input) do
    recommendations = []

    recommendations =
      if contains_dangerous_patterns?(input, :html) do
        [:html | recommendations]
      else
        recommendations
      end

    recommendations =
      if contains_dangerous_patterns?(input, :sql) do
        [:sql | recommendations]
      else
        recommendations
      end

    recommendations =
      if contains_dangerous_patterns?(input, :command) do
        [:command | recommendations]
      else
        recommendations
      end

    recommendations =
      if contains_dangerous_patterns?(input, :path) do
        [:path | recommendations]
      else
        recommendations
      end

    case recommendations do
      [] -> [:generic]
      recs -> recs
    end
  end
end
