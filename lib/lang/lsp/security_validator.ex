defmodule Lang.LSP.SecurityValidator do
  @moduledoc """
  Security validation layer for LSP operations.
  
  Provides centralized security validation for:
  - LSP method parameter sanitization
  - Path traversal prevention  
  - Resource exhaustion protection
  - Client authorization
  - MCP request security
  """
  
  require Logger
  
  @type validation_result :: :ok | {:error, String.t()}
  @type sanitized_params :: map()
  
  # Dangerous path patterns to block (runtime-built to avoid non-literal attributes)
  
  # Resource limits
  @max_search_results 1000
  @max_file_size 50 * 1024 * 1024  # 50MB
  @max_search_depth 20
  @max_query_length 1000
  
  # Rate limiting
  @default_rate_limit 100  # requests per minute
  @expensive_operation_limit 10  # expensive ops per minute
  
  @doc """
  Validates and sanitizes LSP method parameters.
  
  Returns {:ok, sanitized_params} or {:error, reason}.
  """
  @spec validate_lsp_params(String.t(), map()) :: 
    {:ok, sanitized_params()} | {:error, String.t()}
  def validate_lsp_params(method, params) when is_map(params) do
    case method do
      "lang.fs." <> _ -> validate_fs_params(method, params)
      "lang.storage." <> _ -> validate_storage_params(method, params)  
      "lang.generate." <> _ -> validate_generate_params(method, params)
      "lang.query." <> _ -> validate_query_params(method, params)
      "textDocument/" <> _ -> validate_text_document_params(method, params)
      "mcp." <> _ -> validate_mcp_params(method, params)
      _ -> {:ok, params}  # Default allow for now
    end
  end
  
  def validate_lsp_params(_method, _params), do: {:error, "Invalid parameters"}
  
  @doc """
  Validates file system operation parameters.
  """
  @spec validate_fs_params(String.t(), map()) :: 
    {:ok, sanitized_params()} | {:error, String.t()}
  def validate_fs_params(method, params) do
    with {:ok, sanitized} <- sanitize_paths(params),
         {:ok, limited} <- apply_resource_limits(method, sanitized) do
      {:ok, limited}
    end
  end
  
  @doc """
  Validates storage operation parameters.
  """
  @spec validate_storage_params(String.t(), map()) :: 
    {:ok, sanitized_params()} | {:error, String.t()}
  def validate_storage_params(_method, params) do
    # Validate session IDs and prevent injection
    case params do
      %{"session_id" => session_id} when is_binary(session_id) ->
        if valid_session_id?(session_id) do
          {:ok, params}
        else
          {:error, "Invalid session ID format"}
        end
      
      _ -> {:ok, params}
    end
  end
  
  @doc """
  Validates code generation parameters.
  """
  @spec validate_generate_params(String.t(), map()) :: 
    {:ok, sanitized_params()} | {:error, String.t()}
  def validate_generate_params(_method, params) do
    # Limit code generation input size
    case params do
      %{"code" => code} when is_binary(code) ->
        if String.length(code) > 100_000 do
          {:error, "Code input too large"}
        else
          {:ok, params}
        end
      
      _ -> {:ok, params}
    end
  end
  
  @doc """
  Validates query operation parameters.
  """
  @spec validate_query_params(String.t(), map()) :: 
    {:ok, sanitized_params()} | {:error, String.t()}
  def validate_query_params(_method, params) do
    case params do
      %{"query" => query} when is_binary(query) ->
        if String.length(query) > @max_query_length do
          {:error, "Query too long"}
        else
          sanitized_query = sanitize_query(query)
          {:ok, Map.put(params, "query", sanitized_query)}
        end
      
      _ -> {:ok, params}
    end
  end
  
  @doc """
  Validates text document operation parameters.
  """
  @spec validate_text_document_params(String.t(), map()) :: 
    {:ok, sanitized_params()} | {:error, String.t()}
  def validate_text_document_params(_method, params) do
    case params do
      %{"textDocument" => %{"uri" => uri}} ->
        if valid_document_uri?(uri) do
          {:ok, params}
        else
          {:error, "Invalid document URI"}
        end
      
      _ -> {:ok, params}
    end
  end
  
  @doc """
  Validates MCP operation parameters.
  """
  @spec validate_mcp_params(String.t(), map()) :: 
    {:ok, sanitized_params()} | {:error, String.t()}
  def validate_mcp_params(method, params) do
    case method do
      "mcp.connection.create" ->
        validate_mcp_connection_create(params)
        
      "mcp.connection.destroy" ->
        validate_mcp_connection_destroy(params)
        
      "mcp.connection.status" ->
        validate_mcp_connection_status(params)
        
      _ -> {:ok, params}
    end
  end
  
  @doc """
  Validates client authorization for operation.
  """
  @spec authorize_client(String.t(), String.t(), map()) :: validation_result()
  def authorize_client(client_id, method, params) do
    with :ok <- validate_client_id_format(client_id),
         :ok <- check_method_permissions(client_id, method),
         :ok <- check_resource_permissions(client_id, method, params) do
      :ok
    end
  end
  
  @doc """
  Checks rate limits for client and method.
  """
  @spec check_rate_limit(String.t(), String.t()) :: :ok | {:error, String.t()}  
  def check_rate_limit(client_id, method) do
    limit = if expensive_operation?(method) do
      @expensive_operation_limit
    else
      @default_rate_limit
    end
    
    case Lang.Security.RedisLimiter.allow?(client_id, method, limit) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, "Rate limit exceeded"}
    end
  end
  
  # Private helper functions
  
  defp sanitize_paths(params) do
    sanitized = Enum.reduce(params, %{}, fn
      {"path", path}, acc when is_binary(path) ->
        Map.put(acc, "path", sanitize_path(path))
      
      {"root", root}, acc when is_binary(root) ->
        Map.put(acc, "root", sanitize_path(root))
        
      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
    
    # Check for dangerous paths after sanitization
    if has_dangerous_paths?(sanitized) do
      {:error, "Dangerous path detected"}
    else
      {:ok, sanitized}
    end
  end
  
  defp sanitize_path(path) do
    path
    |> Path.expand()
    |> Path.relative_to_cwd()
    |> case do
      ^path -> path  # No change needed
      sanitized -> sanitized
    end
  rescue
    _ -> ""  # Return empty string for invalid paths
  end
  
  defp has_dangerous_paths?(params) do
    paths = get_path_values(params)
    Enum.any?(paths, &dangerous_path?/1)
  end
  
  defp get_path_values(params) when is_map(params) do
    Enum.flat_map(params, fn
      {_key, value} when is_binary(value) -> [value]
      {_key, value} when is_map(value) -> get_path_values(value)
      _ -> []
    end)
  end
  
  defp dangerous_path?(path) do
    Enum.any?(dangerous_path_patterns(), &Regex.match?(&1, path))
  end

  defp dangerous_path_patterns do
    [
      ~r/\.\./,           # Path traversal
      ~r/\/etc\//,        # System config
      ~r/\/root\//,       # Root user files
      ~r/\/proc\//,       # Process info
      ~r/\/sys\//,        # System info
      ~r/\/dev\//,        # Device files
      ~r/passwd/,         # Password files
      ~r/shadow/,         # Shadow files
      ~r/\.ssh\//         # SSH keys
    ]
  end
  
  defp apply_resource_limits(method, params) do
    limited = Enum.reduce(params, %{}, fn
      {"max_results", val}, acc ->
        Map.put(acc, "max_results", min(val, @max_search_results))
        
      {"max_depth", val}, acc ->
        Map.put(acc, "max_depth", min(val, @max_search_depth))
        
      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
    
    {:ok, limited}
  end
  
  defp sanitize_query(query) do
    query
    |> String.replace(~r/[;&|`$(){}[\]\\]/, "")  # Remove shell metacharacters
    |> String.slice(0, @max_query_length)
  end
  
  defp valid_session_id?(session_id) do
    is_binary(session_id) and 
    String.length(session_id) <= 128 and
    String.match?(session_id, ~r/^[A-Za-z0-9_-]+$/)
  end
  
  defp valid_document_uri?(uri) do
    is_binary(uri) and 
    (String.starts_with?(uri, "file://") or String.starts_with?(uri, "untitled:"))
  end
  
  defp validate_mcp_connection_create(params) do
    case params do
      %{"server_url" => url, "capabilities" => caps} when is_binary(url) and is_list(caps) ->
        if valid_server_url?(url) and valid_capabilities?(caps) do
          {:ok, params}
        else
          {:error, "Invalid MCP connection parameters"}
        end
      
      _ -> {:error, "Missing required MCP connection parameters"}
    end
  end
  
  defp validate_mcp_connection_destroy(params) do
    case params do
      %{"connection_id" => conn_id} when is_binary(conn_id) ->
        {:ok, params}
      
      _ -> {:error, "Missing connection_id"}
    end
  end
  
  defp validate_mcp_connection_status(params) do
    case params do
      %{"connection_id" => conn_id} when is_binary(conn_id) ->
        {:ok, params}
      
      _ -> {:error, "Missing connection_id"}
    end
  end
  
  defp valid_server_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https", "ws", "wss"] and 
    not is_nil(uri.host) and
    uri.host not in ["localhost", "127.0.0.1"] # Prevent SSRF
  end
  
  defp valid_capabilities?(caps) do
    allowed_caps = ["filesystem", "tools", "prompts", "resources"]
    Enum.all?(caps, fn cap -> cap in allowed_caps end)
  end
  
  defp validate_client_id_format(client_id) do
    if is_binary(client_id) and 
       String.length(client_id) >= 10 and 
       String.length(client_id) <= 64 and
       String.match?(client_id, ~r/^[A-Za-z0-9_-]+$/) do
      :ok
    else
      {:error, "Invalid client ID format"}
    end
  end
  
  defp check_method_permissions(client_id, method) do
    # Implement method-level permissions
    case method do
      "lang.fs." <> _ ->
        if client_has_fs_permission?(client_id), do: :ok, else: {:error, "No filesystem permission"}
      
      "mcp." <> _ ->
        if client_has_mcp_permission?(client_id), do: :ok, else: {:error, "No MCP permission"}
        
      _ -> :ok  # Default allow
    end
  end
  
  defp check_resource_permissions(_client_id, _method, _params) do
    # Implement resource-level permissions (e.g., path restrictions)
    :ok
  end
  
  defp expensive_operation?(method) do
    method in [
      "lang.fs.search",
      "lang.fs.search_code", 
      "lang.generate.from_tests",
      "lang.query.impact",
      "lang.timeline.analyze"
    ]
  end
  
  defp client_has_fs_permission?(_client_id) do
    # Check if client has filesystem access
    # This would integrate with your auth system
    true
  end
  
  defp client_has_mcp_permission?(_client_id) do
    # Check if client has MCP access
    # This would integrate with your auth system  
    true
  end
end
