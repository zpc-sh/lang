defmodule Lang.MCP.Security do
  @moduledoc """
  Security wrapper for MCP requests and responses.

  This module provides comprehensive validation and sanitization of MCP
  communications to prevent security vulnerabilities. All MCP requests
  must pass through these security controls before reaching MCP servers.

  ## Security Controls
  - Request validation and sanitization
  - Response filtering and size limits
  - Path traversal prevention
  - Command injection protection
  - Resource limit enforcement
  - Audit logging of all MCP interactions

  ## Threat Model
  MCP servers are treated as potentially hostile. This wrapper assumes:
  - MCP requests may contain malicious payloads
  - MCP responses may be oversized or malformed
  - MCP servers may attempt unauthorized file system access
  - Users may attempt to exploit MCP for privilege escalation
  """

  require Logger
  alias Lang.Events

  # Maximum sizes to prevent DoS attacks
  # 1MB
  @max_request_size 1024 * 1024
  # 10MB
  @max_response_size 10 * 1024 * 1024
  @max_array_length 1000
  @max_string_length 100_000
  @max_nesting_depth 10

  # Dangerous patterns to block
  # Note: avoid storing compiled Regex structs in module attributes to prevent
  # compile-time injection errors (non-escapable references). Use a function
  # literal list instead.
  defp blocked_patterns do
    [
      # Command injection
      ~r/[;&|`$()]/,
      # Path traversal
      ~r/\.\./,
      ~r/\/\.\./,
      # Protocol handlers
      ~r/^(file|http|https|ftp|ssh|telnet):/i,
      # Shell commands
      ~r/(sh|bash|cmd|powershell|python|node|ruby)/i,
      # Sensitive files
      ~r/(passwd|shadow|hosts|authorized_keys)/i
    ]
  end

  # Allowed file extensions for filesystem operations
  @allowed_extensions [
    ".txt",
    ".md",
    ".json",
    ".yaml",
    ".yml",
    ".xml",
    ".js",
    ".ts",
    ".jsx",
    ".tsx",
    ".vue",
    ".svelte",
    ".py",
    ".rb",
    ".php",
    ".java",
    ".go",
    ".rs",
    ".ex",
    ".exs",
    ".c",
    ".cpp",
    ".h",
    ".hpp",
    ".cs",
    ".swift",
    ".kt",
    ".html",
    ".css",
    ".scss",
    ".sass",
    ".less",
    ".sql",
    ".graphql",
    ".proto",
    ".thrift",
    ".dockerfile",
    ".gitignore",
    ".editorconfig"
  ]

  @type validation_result :: {:ok, map()} | {:error, term()}
  @type mcp_request :: map()
  @type mcp_response :: map()
  @type server_type :: String.t()
  @allowed_server_types [
    "filesystem",
    "git",
    "database",
    "web_search",
    "code_analysis"
  ]

  @doc """
  Return the list of allowed MCP server types.
  """
  @spec allowed_server_types() :: [server_type()]
  def allowed_server_types, do: @allowed_server_types

  @doc """
  Validate that the server type is allowed.
  """
  @spec validate_server_type(server_type()) :: :ok | {:error, :server_type_not_allowed}
  def validate_server_type(server_type) when is_binary(server_type) do
    if server_type in @allowed_server_types, do: :ok, else: {:error, :server_type_not_allowed}
  end

  @doc """
  Validate and sanitize MCP server configuration.

  Ensures MCP server config doesn't contain dangerous settings that could
  lead to security vulnerabilities or resource exhaustion.
  """
  @spec validate_mcp_config(server_type(), map()) :: validation_result()
  def validate_mcp_config(server_type, config) do
    with :ok <- validate_config_size(config),
         :ok <- validate_config_structure(config),
         :ok <- validate_server_specific_config(server_type, config),
         {:ok, sanitized} <- sanitize_config(config) do
      log_security_event("mcp_config_validated", %{
        server_type: server_type,
        config_keys: Map.keys(sanitized)
      })

      {:ok, sanitized}
    else
      {:error, reason} ->
        log_security_event("mcp_config_rejected", %{
          server_type: server_type,
          reason: reason,
          config_keys: Map.keys(config)
        })

        {:error, reason}
    end
  end

  @doc """
  Validate and sanitize MCP request before sending to server.

  All MCP requests must pass through this security layer. Blocks malicious
  requests and sanitizes safe ones.
  """
  @spec validate_mcp_request(server_type(), mcp_request()) :: validation_result()
  def validate_mcp_request(server_type, request) do
    with :ok <- validate_request_size(request),
         :ok <- validate_request_structure(request),
         :ok <- validate_request_content(request),
         :ok <- validate_server_specific_request(server_type, request),
         {:ok, sanitized} <- sanitize_request(request) do
      log_security_event("mcp_request_validated", %{
        server_type: server_type,
        method: Map.get(sanitized, "method", "unknown"),
        params_keys: get_param_keys(sanitized)
      })

      {:ok, sanitized}
    else
      {:error, reason} ->
        log_security_event("mcp_request_rejected", %{
          server_type: server_type,
          reason: reason,
          method: Map.get(request, "method", "unknown")
        })

        {:error, reason}
    end
  end

  @doc """
  Validate and sanitize MCP response before returning to client.

  Ensures MCP server responses don't contain dangerous content or exceed
  size limits that could cause client-side issues.
  """
  @spec validate_mcp_response(server_type(), mcp_response()) :: validation_result()
  def validate_mcp_response(server_type, response) do
    with :ok <- validate_response_size(response),
         :ok <- validate_response_structure(response),
         :ok <- validate_response_content(response),
         {:ok, sanitized} <- sanitize_response(response) do
      {:ok, sanitized}
    else
      {:error, reason} ->
        log_security_event("mcp_response_rejected", %{
          server_type: server_type,
          reason: reason,
          response_type: get_response_type(response)
        })

        {:error, reason}
    end
  end

  @doc """
  Check if file path is safe for MCP filesystem operations.

  Prevents path traversal attacks and restricts access to allowed directories.
  """
  @spec validate_file_path(String.t()) :: :ok | {:error, term()}
  def validate_file_path(path) do
    with :ok <- check_path_traversal(path),
         :ok <- check_file_extension(path),
         :ok <- check_path_length(path),
         :ok <- check_dangerous_patterns(path) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Apply rate limiting for MCP operations.

  Different MCP server types have different rate limits based on resource usage.
  """
  @spec check_rate_limit(String.t(), server_type(), String.t()) :: :ok | {:error, :rate_limited}
  def check_rate_limit(user_id, server_type, operation) do
    rate_limit_key = "mcp_#{server_type}_#{operation}"

    case Lang.Security.RateLimiter.check_rate_limit(user_id, rate_limit_key) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
    end
  end

  ## Private Functions - Config Validation

  defp validate_config_size(config) when is_map(config) do
    encoded_size = byte_size(Jason.encode!(config))

    if encoded_size <= @max_request_size do
      :ok
    else
      {:error, {:config_too_large, encoded_size}}
    end
  rescue
    _ -> {:error, :invalid_config_format}
  end

  defp validate_config_structure(config) when is_map(config) do
    case validate_map_depth(config, 0) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_server_specific_config("filesystem", config) do
    # Validate filesystem server config
    with :ok <- validate_filesystem_config(config) do
      :ok
    end
  end

  defp validate_server_specific_config("git", config) do
    # Validate git server config
    with :ok <- validate_git_config(config) do
      :ok
    end
  end

  defp validate_server_specific_config(_server_type, _config), do: :ok

  defp validate_filesystem_config(config) do
    # Check for dangerous filesystem config
    case Map.get(config, "root_path") do
      nil -> :ok
      path when is_binary(path) -> validate_root_path(path)
      _ -> {:error, :invalid_root_path}
    end
  end

  defp validate_git_config(config) do
    # Check for dangerous git config
    case Map.get(config, "repository_url") do
      nil -> :ok
      url when is_binary(url) -> validate_git_url(url)
      _ -> {:error, :invalid_git_url}
    end
  end

  defp validate_root_path(path) do
    cond do
      String.contains?(path, "..") -> {:error, :path_traversal_in_root}
      String.starts_with?(path, "/") -> {:error, :absolute_path_not_allowed}
      String.contains?(path, "~") -> {:error, :home_directory_not_allowed}
      true -> :ok
    end
  end

  defp validate_git_url(url) do
    uri = URI.parse(url)

    case uri do
      %URI{scheme: scheme} when scheme in ["git", "https", "ssh"] -> :ok
      %URI{scheme: nil} -> {:error, :missing_git_scheme}
      %URI{scheme: scheme} -> {:error, {:invalid_git_scheme, scheme}}
    end
  end

  ## Private Functions - Request Validation

  defp validate_request_size(request) when is_map(request) do
    encoded_size = byte_size(Jason.encode!(request))

    if encoded_size <= @max_request_size do
      :ok
    else
      {:error, {:request_too_large, encoded_size}}
    end
  rescue
    _ -> {:error, :invalid_request_format}
  end

  defp validate_request_structure(request) when is_map(request) do
    with :ok <- validate_required_fields(request),
         :ok <- validate_map_depth(request, 0) do
      :ok
    end
  end

  defp validate_required_fields(request) do
    required_fields = ["method"]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(request, field)
      end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp validate_request_content(request) do
    case deep_validate_content(request) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_server_specific_request("filesystem", request) do
    # Additional validation for filesystem requests
    case Map.get(request, "params") do
      %{"path" => path} when is_binary(path) -> validate_file_path(path)
      %{"uri" => uri} when is_binary(uri) -> validate_uri_path(uri)
      _ -> :ok
    end
  end

  defp validate_server_specific_request("git", request) do
    # Additional validation for git requests
    case Map.get(request, "params") do
      %{"repository" => repo} when is_binary(repo) -> validate_git_repository(repo)
      %{"ref" => ref} when is_binary(ref) -> validate_git_ref(ref)
      _ -> :ok
    end
  end

  defp validate_server_specific_request(_server_type, _request), do: :ok

  ## Private Functions - Response Validation

  defp validate_response_size(response) when is_map(response) do
    encoded_size = byte_size(Jason.encode!(response))

    if encoded_size <= @max_response_size do
      :ok
    else
      {:error, {:response_too_large, encoded_size}}
    end
  rescue
    _ -> {:error, :invalid_response_format}
  end

  defp validate_response_structure(response) when is_map(response) do
    validate_map_depth(response, 0)
  end

  defp validate_response_content(response) do
    deep_validate_content(response)
  end

  ## Private Functions - Content Validation

  defp deep_validate_content(data) when is_map(data) do
    Enum.reduce_while(data, :ok, fn {key, value}, :ok ->
      case validate_key_value(key, value) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp deep_validate_content(data) when is_list(data) do
    if length(data) <= @max_array_length do
      Enum.reduce_while(data, :ok, fn item, :ok ->
        case deep_validate_content(item) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      {:error, {:array_too_long, length(data)}}
    end
  end

  defp deep_validate_content(data) when is_binary(data) do
    cond do
      byte_size(data) > @max_string_length ->
        {:error, {:string_too_long, byte_size(data)}}

      contains_dangerous_patterns?(data) ->
        {:error, :dangerous_pattern_detected}

      true ->
        :ok
    end
  end

  defp deep_validate_content(_data), do: :ok

  defp validate_key_value(key, value) when is_binary(key) do
    with :ok <- validate_key_safety(key),
         :ok <- deep_validate_content(value) do
      :ok
    end
  end

  defp validate_key_value(_key, _value), do: :ok

  defp validate_key_safety(key) do
    if contains_dangerous_patterns?(key) do
      {:error, :dangerous_key_pattern}
    else
      :ok
    end
  end

  defp validate_map_depth(data, current_depth) when is_map(data) do
    if current_depth >= @max_nesting_depth do
      {:error, {:nesting_too_deep, current_depth}}
    else
      Enum.reduce_while(data, :ok, fn {_key, value}, :ok ->
        case validate_map_depth(value, current_depth + 1) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp validate_map_depth(data, current_depth) when is_list(data) do
    Enum.reduce_while(data, :ok, fn item, :ok ->
      case validate_map_depth(item, current_depth) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_map_depth(_data, _depth), do: :ok

  defp contains_dangerous_patterns?(string) when is_binary(string) do
    Enum.any?(blocked_patterns(), fn pattern -> Regex.match?(pattern, string) end)
  end

  ## Private Functions - Path Validation

  defp check_path_traversal(path) do
    if String.contains?(path, "..") do
      {:error, :path_traversal_detected}
    else
      :ok
    end
  end

  defp check_file_extension(path) do
    extension = Path.extname(path) |> String.downcase()

    if extension in @allowed_extensions or extension == "" do
      :ok
    else
      {:error, {:file_extension_not_allowed, extension}}
    end
  end

  defp check_path_length(path) do
    if byte_size(path) <= 1000 do
      :ok
    else
      {:error, {:path_too_long, byte_size(path)}}
    end
  end

  defp check_dangerous_patterns(path) do
    if contains_dangerous_patterns?(path) do
      {:error, :dangerous_pattern_in_path}
    else
      :ok
    end
  end

  defp validate_uri_path(uri) do
    case URI.parse(uri) do
      %URI{scheme: "file", path: path} -> validate_file_path(path)
      %URI{scheme: nil, path: path} -> validate_file_path(path)
      %URI{scheme: scheme} -> {:error, {:invalid_uri_scheme, scheme}}
    end
  end

  defp validate_git_repository(repo) do
    cond do
      String.contains?(repo, "..") -> {:error, :path_traversal_in_repo}
      String.contains?(repo, "|") -> {:error, :command_injection_in_repo}
      String.contains?(repo, ";") -> {:error, :command_injection_in_repo}
      true -> :ok
    end
  end

  defp validate_git_ref(ref) do
    if Regex.match?(~r/^[\w\-\/\.]+$/, ref) do
      :ok
    else
      {:error, :invalid_git_ref}
    end
  end

  ## Private Functions - Sanitization

  defp sanitize_config(config) when is_map(config) do
    sanitized =
      config
      |> Map.new(fn {key, value} -> {sanitize_string(key), sanitize_value(value)} end)

    {:ok, sanitized}
  end

  defp sanitize_request(request) when is_map(request) do
    sanitized =
      request
      |> Map.new(fn {key, value} -> {sanitize_string(key), sanitize_value(value)} end)

    {:ok, sanitized}
  end

  defp sanitize_response(response) when is_map(response) do
    sanitized =
      response
      |> Map.new(fn {key, value} -> {sanitize_string(key), sanitize_value(value)} end)

    {:ok, sanitized}
  end

  defp sanitize_value(value) when is_binary(value) do
    sanitize_string(value)
  end

  defp sanitize_value(value) when is_map(value) do
    value
    |> Map.new(fn {key, val} -> {sanitize_string(key), sanitize_value(val)} end)
  end

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value), do: value

  defp sanitize_string(string) when is_binary(string) do
    string
    |> String.trim()
    |> String.slice(0, @max_string_length)
  end

  defp sanitize_string(value), do: value

  ## Private Functions - Helpers

  defp get_param_keys(%{"params" => params}) when is_map(params) do
    Map.keys(params)
  end

  defp get_param_keys(_request), do: []

  defp get_response_type(%{"result" => _}), do: "result"
  defp get_response_type(%{"error" => _}), do: "error"
  defp get_response_type(_), do: "unknown"

  defp log_security_event(event_type, metadata) do
    Events.track_event(%{
      event_type: event_type,
      metadata: metadata,
      severity: "security",
      timestamp: DateTime.utc_now()
    })

    Logger.info("MCP Security Event",
      event: event_type,
      metadata: metadata
    )
  end
end
