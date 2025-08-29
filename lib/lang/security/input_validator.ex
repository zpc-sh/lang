defmodule Elixir.Lang.LSP.Lang.Lang.Security.Validate do
  @moduledoc "Request validation"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.security.validate"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    input = Map.get(params, "input")
    validation_type = Map.get(params, "type", "general")

    case input do
      nil ->
        {:error, "input is required"}

      input when is_binary(input) ->
        validation_result = validate_input(input, validation_type)

        {:ok,
         %{
           valid: validation_result.valid,
           issues: validation_result.issues,
           sanitized: validation_result.sanitized,
           risk_level: validation_result.risk_level
         }}

      _ ->
        {:error, "input must be a string"}
    end
  end

  defp validate_input(input, type) do
    issues = []

    # Check for common security issues
    issues = check_sql_injection(input, issues)
    issues = check_xss_patterns(input, issues)
    issues = check_command_injection(input, issues)
    issues = check_path_traversal(input, issues)

    # Type-specific validation
    issues =
      case type do
        "sql" -> check_sql_specific(input, issues)
        "file_path" -> check_file_path_specific(input, issues)
        "command" -> check_command_specific(input, issues)
        "url" -> check_url_specific(input, issues)
        _ -> issues
      end

    risk_level = determine_risk_level(issues)
    sanitized = sanitize_input(input, type, issues)

    %{
      valid: length(issues) == 0,
      issues: issues,
      sanitized: sanitized,
      risk_level: risk_level
    }
  end

  defp check_sql_injection(input, issues) do
    sql_patterns = [
      ~r/('|(''|'.*?'))/i,
      ~r/(;|'|\s)+(drop|delete|truncate|update|insert|alter|create)\s+/i,
      ~r/(union|select|from|where|order|group)\s+/i,
      ~r/--|\#|\/\*/
    ]

    Enum.reduce(sql_patterns, issues, fn pattern, acc ->
      if Regex.match?(pattern, input) do
        [%{type: "sql_injection", severity: "high", pattern: inspect(pattern)} | acc]
      else
        acc
      end
    end)
  end

  defp check_xss_patterns(input, issues) do
    xss_patterns = [
      ~r/<script[^>]*>/i,
      ~r/javascript:/i,
      ~r/on\w+\s*=/i,
      ~r/<iframe[^>]*>/i,
      ~r/<object[^>]*>/i
    ]

    Enum.reduce(xss_patterns, issues, fn pattern, acc ->
      if Regex.match?(pattern, input) do
        [%{type: "xss", severity: "high", pattern: inspect(pattern)} | acc]
      else
        acc
      end
    end)
  end

  defp check_command_injection(input, issues) do
    command_patterns = [
      ~r/[;&|`$()]/,
      ~r/\.\./,
      ~r/(rm|del|format|shutdown|reboot)\s/i
    ]

    Enum.reduce(command_patterns, issues, fn pattern, acc ->
      if Regex.match?(pattern, input) do
        [%{type: "command_injection", severity: "high", pattern: inspect(pattern)} | acc]
      else
        acc
      end
    end)
  end

  defp check_path_traversal(input, issues) do
    if String.contains?(input, "..") or String.contains?(input, "~") do
      [%{type: "path_traversal", severity: "medium", pattern: "directory_traversal"} | issues]
    else
      issues
    end
  end

  defp check_sql_specific(input, issues) do
    # Additional SQL-specific checks
    if String.length(input) > 1000 do
      [%{type: "sql_length", severity: "low", message: "unusually long SQL input"} | issues]
    else
      issues
    end
  end

  defp check_file_path_specific(input, issues) do
    # Check for absolute paths and dangerous directories
    dangerous_paths = ["/etc/", "/proc/", "/sys/", "C:\\Windows\\"]

    Enum.reduce(dangerous_paths, issues, fn path, acc ->
      if String.starts_with?(input, path) do
        [%{type: "dangerous_path", severity: "high", path: path} | acc]
      else
        acc
      end
    end)
  end

  defp check_command_specific(input, issues) do
    # Check for dangerous commands
    dangerous_commands = ["rm -rf", "format", "del /q", "shutdown", "killall"]

    Enum.reduce(dangerous_commands, issues, fn cmd, acc ->
      if String.contains?(String.downcase(input), cmd) do
        [%{type: "dangerous_command", severity: "critical", command: cmd} | acc]
      else
        acc
      end
    end)
  end

  defp check_url_specific(input, issues) do
    # Basic URL validation
    case URI.parse(input) do
      %URI{scheme: nil} ->
        [%{type: "invalid_url", severity: "low", message: "missing scheme"} | issues]

      %URI{scheme: scheme} when scheme not in ["http", "https", "ftp", "ftps"] ->
        [%{type: "suspicious_scheme", severity: "medium", scheme: scheme} | issues]

      _ ->
        issues
    end
  end

  defp determine_risk_level(issues) do
    max_severity =
      issues
      |> Enum.map(& &1.severity)
      |> Enum.max_by(&severity_priority/1, fn -> "none" end)

    max_severity
  end

  defp severity_priority("critical"), do: 4
  defp severity_priority("high"), do: 3
  defp severity_priority("medium"), do: 2
  defp severity_priority("low"), do: 1
  defp severity_priority(_), do: 0

  defp sanitize_input(input, type, issues) do
    # Basic sanitization based on detected issues
    sanitized =
      input
      |> String.replace(~r/<script[^>]*>.*?<\/script>/i, "")
      |> String.replace(~r/javascript:/i, "")
      |> String.replace(~r/[<>\"'&]/, fn char ->
        case char do
          "<" -> "&lt;"
          ">" -> "&gt;"
          "\"" -> "&quot;"
          "'" -> "&#x27;"
          "&" -> "&amp;"
        end
      end)

    # Type-specific sanitization
    case type do
      "file_path" -> Path.expand(sanitized)
      "sql" -> String.replace(sanitized, ~r/['";]/, "")
      _ -> sanitized
    end
  end
end
