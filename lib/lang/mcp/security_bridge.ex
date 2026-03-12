defmodule Lang.MCP.SecurityBridge do
  @moduledoc """
  Enhanced security layer for MCP (Model Context Protocol) operations.
  
  Provides comprehensive security controls for MCP connections:
  - Connection authentication and authorization
  - Request/response filtering and sanitization
  - Rate limiting for MCP operations
  - Session management and isolation
  - Security event logging and monitoring
  """
  
  use GenServer
  require Logger
  
  alias Lang.MCP.SessionManager
  alias Lang.LSP.SecurityValidator
  alias Lang.Security.RedisLimiter
  alias Lang.Monitoring.SecurityMonitor
  
  @mcp_rate_limits %{
    "mcp.connection.create" => {5, 300},      # 5 per 5 minutes
    "mcp.connection.destroy" => {10, 60},     # 10 per minute  
    "mcp.tools.list" => {30, 60},             # 30 per minute
    "mcp.tools.call" => {100, 60},            # 100 per minute
    "mcp.resources.list" => {50, 60},         # 50 per minute
    "mcp.resources.read" => {200, 60},        # 200 per minute
    "mcp.prompts.list" => {20, 60},           # 20 per minute
    "mcp.prompts.get" => {100, 60}            # 100 per minute
  }
  
  @sensitive_mcp_fields [
    "auth_token", "api_key", "secret", "password", "credentials",
    "private_key", "session_token", "oauth_token", "bearer_token"
  ]
  
  @type mcp_request :: %{
    method: String.t(),
    params: map(),
    client_id: String.t(),
    session_id: String.t() | nil,
    metadata: map()
  }
  
  @type security_result :: {:ok, map()} | {:error, term()}
  
  defstruct [
    :active_connections,
    :blocked_clients,
    :security_events,
    :rate_limiters,
    :session_cache
  ]
  
  ## Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Processes an MCP request through security validation pipeline.
  """
  @spec secure_mcp_request(mcp_request()) :: security_result()
  def secure_mcp_request(request) do
    GenServer.call(__MODULE__, {:secure_request, request})
  end
  
  @doc """
  Validates MCP connection authorization.
  """
  @spec authorize_mcp_connection(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def authorize_mcp_connection(client_id, server_uri, connection_params) do
    GenServer.call(__MODULE__, {:authorize_connection, client_id, server_uri, connection_params})
  end
  
  @doc """
  Processes MCP response through security filtering.
  """
  @spec filter_mcp_response(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def filter_mcp_response(response, client_id) do
    GenServer.call(__MODULE__, {:filter_response, response, client_id})
  end
  
  @doc """
  Terminates all MCP connections for a client.
  """
  @spec terminate_client_connections(String.t()) :: :ok
  def terminate_client_connections(client_id) do
    GenServer.call(__MODULE__, {:terminate_connections, client_id})
  end
  
  @doc """
  Gets security statistics for MCP operations.
  """
  @spec get_security_stats() :: map()
  def get_security_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  ## GenServer Implementation
  
  def init(_opts) do
    state = %__MODULE__{
      active_connections: %{},
      blocked_clients: MapSet.new(),
      security_events: [],
      rate_limiters: %{},
      session_cache: %{}
    }
    
    Logger.info("MCP Security Bridge started")
    {:ok, state}
  end
  
  def handle_call({:secure_request, request}, _from, state) do
    result = 
      request
      |> validate_client_authorization(state)
      |> check_rate_limits()
      |> validate_session_context()
      |> sanitize_mcp_params()
      |> check_resource_permissions()
      |> log_security_event()
    
    case result do
      {:ok, validated_request} ->
        new_state = update_connection_state(state, validated_request)
        {:reply, {:ok, validated_request}, new_state}
      
      {:error, reason} = error ->
        new_state = record_security_violation(state, request, reason)
        {:reply, error, new_state}
    end
  end
  
  def handle_call({:authorize_connection, client_id, server_uri, params}, _from, state) do
    case validate_mcp_connection(client_id, server_uri, params) do
      :ok ->
        new_state = register_connection(state, client_id, server_uri)
        log_mcp_event(:connection_authorized, %{client_id: client_id, server_uri: server_uri})
        {:reply, :ok, new_state}
      
      {:error, reason} = error ->
        log_mcp_event(:connection_denied, %{client_id: client_id, reason: reason})
        {:reply, error, state}
    end
  end
  
  def handle_call({:filter_response, response, client_id}, _from, state) do
    case filter_response_for_client(response, client_id) do
      {:ok, filtered_response} ->
        {:reply, {:ok, filtered_response}, state}
      
      {:error, reason} = error ->
        log_mcp_event(:response_filtered, %{client_id: client_id, reason: reason})
        {:reply, error, state}
    end
  end
  
  def handle_call({:terminate_connections, client_id}, _from, state) do
    new_state = terminate_client_connections_internal(state, client_id)
    log_mcp_event(:connections_terminated, %{client_id: client_id})
    {:reply, :ok, new_state}
  end
  
  def handle_call(:get_stats, _from, state) do
    stats = generate_security_stats(state)
    {:reply, stats, state}
  end
  
  ## Security Validation Pipeline
  
  defp validate_client_authorization(request, state) do
    case SecurityValidator.authorize_client(request.client_id, request.method, %{}) do
      :ok ->
        if MapSet.member?(state.blocked_clients, request.client_id) do
          {:error, "Client is temporarily blocked"}
        else
          {:ok, request}
        end
      
      {:error, reason} ->
        {:error, "Authorization failed: #{reason}"}
    end
  end
  
  defp check_rate_limits({:error, _} = error), do: error
  defp check_rate_limits({:ok, request}) do
    case get_rate_limit_for_method(request.method) do
      {limit, window} ->
        case RedisLimiter.allow?(request.client_id, request.method) do
          :ok -> {:ok, request}
          {:error, :rate_limited} -> {:error, "Rate limit exceeded for #{request.method}"}
        end
      
      nil ->
        # No specific rate limit, use default
        case RedisLimiter.allow?(request.client_id, "mcp.default") do
          :ok -> {:ok, request}
          {:error, :rate_limited} -> {:error, "Rate limit exceeded"}
        end
    end
  end
  
  defp validate_session_context({:error, _} = error), do: error
  defp validate_session_context({:ok, request}) do
    case request.session_id do
      nil ->
        # No session required for some methods
        if method_requires_session?(request.method) do
          {:error, "Session required for #{request.method}"}
        else
          {:ok, request}
        end
      
      session_id ->
        case SessionManager.get_session(session_id) do
          {:ok, session} ->
            if session.client_id == request.client_id do
              {:ok, put_in(request.metadata[:session], session)}
            else
              {:error, "Session client mismatch"}
            end
          
          {:error, reason} ->
            {:error, "Session validation failed: #{reason}"}
        end
    end
  end
  
  defp sanitize_mcp_params({:error, _} = error), do: error
  defp sanitize_mcp_params({:ok, request}) do
    case sanitize_params(request.params, request.method) do
      {:ok, sanitized_params} ->
        {:ok, %{request | params: sanitized_params}}
      
      {:error, reason} ->
        {:error, "Parameter validation failed: #{reason}"}
    end
  end
  
  defp check_resource_permissions({:error, _} = error), do: error
  defp check_resource_permissions({:ok, request}) do
    case request.method do
      "mcp.resources.read" ->
        resource_uri = get_in(request.params, ["uri"])
        validate_resource_access(request.client_id, resource_uri)
      
      "mcp.tools.call" ->
        tool_name = get_in(request.params, ["name"])
        validate_tool_access(request.client_id, tool_name)
      
      _ ->
        {:ok, request}
    end
  end
  
  defp log_security_event({:error, _} = error), do: error
  defp log_security_event({:ok, request}) do
    SecurityMonitor.record_event(%{
      type: :mcp_request,
      timestamp: DateTime.utc_now(),
      client_id: request.client_id,
      method: request.method,
      metadata: %{
        session_id: request.session_id,
        params_keys: Map.keys(request.params)
      }
    })
    
    {:ok, request}
  end
  
  ## MCP Connection Validation
  
  defp validate_mcp_connection(client_id, server_uri, params) do
    with :ok <- validate_client_mcp_permissions(client_id),
         :ok <- validate_server_uri(server_uri),
         :ok <- validate_connection_params(params),
         :ok <- check_connection_limits(client_id) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, "Connection validation failed: #{inspect(error)}"}
    end
  end
  
  defp validate_client_mcp_permissions(client_id) do
    case SecurityValidator.authorize_client(client_id, "mcp.connection.create", %{}) do
      :ok -> :ok
      {:error, reason} -> {:error, "MCP permission denied: #{reason}"}
    end
  end
  
  defp validate_server_uri(server_uri) do
    cond do
      # Allow local development servers
      String.starts_with?(server_uri, "http://localhost:") or
      String.starts_with?(server_uri, "http://127.0.0.1:") ->
        :ok
      
      # Allow HTTPS URLs to approved domains
      String.starts_with?(server_uri, "https://") ->
        validate_approved_domain(server_uri)
      
      # Allow stdio and file schemes for local MCP servers
      String.starts_with?(server_uri, "stdio://") or
      String.starts_with?(server_uri, "file://") ->
        validate_local_mcp_server(server_uri)
      
      true ->
        {:error, "Unsupported MCP server URI scheme"}
    end
  end
  
  defp validate_approved_domain(uri) do
    # In production, this would check against an allowlist
    case URI.parse(uri) do
      %URI{host: host} when is_binary(host) ->
        if String.ends_with?(host, ".anthropic.com") or 
           String.ends_with?(host, ".openai.com") or
           host in ["api.claude.ai"] do
          :ok
        else
          {:error, "MCP server domain not approved: #{host}"}
        end
      
      _ ->
        {:error, "Invalid MCP server URI"}
    end
  end
  
  defp validate_local_mcp_server(uri) do
    case URI.parse(uri) do
      %URI{scheme: "stdio", path: path} ->
        # Validate stdio command is safe
        if path && String.contains?(path, "..") do
          {:error, "Path traversal in MCP stdio command"}
        else
          :ok
        end
      
      %URI{scheme: "file", path: path} ->
        # Validate file path is in allowed directory
        if path && (String.contains?(path, "..") or String.starts_with?(path, "/etc/")) do
          {:error, "Dangerous path in MCP file URI"}
        else
          :ok
        end
      
      _ ->
        {:error, "Invalid local MCP server URI"}
    end
  end
  
  defp validate_connection_params(params) do
    # Check for dangerous connection parameters
    dangerous_keys = ["command", "shell", "env", "exec"]
    
    found_dangerous = Enum.find(dangerous_keys, fn key ->
      Map.has_key?(params, key)
    end)
    
    if found_dangerous do
      {:error, "Dangerous connection parameter: #{found_dangerous}"}
    else
      :ok
    end
  end
  
  defp check_connection_limits(client_id) do
    # Limit number of concurrent MCP connections per client
    max_connections = 5
    
    # In a real implementation, this would check active connection count
    :ok
  end
  
  ## Parameter Sanitization
  
  defp sanitize_params(params, method) do
    sanitized = 
      params
      |> remove_sensitive_fields()
      |> validate_param_types(method)
      |> apply_size_limits(method)
    
    case sanitized do
      {:error, _} = error -> error
      result -> {:ok, result}
    end
  end
  
  defp remove_sensitive_fields(params) do
    Enum.reduce(@sensitive_mcp_fields, params, fn field, acc ->
      Map.delete(acc, field)
    end)
  end
  
  defp validate_param_types(params, method) do
    case method do
      "mcp.tools.call" ->
        validate_tool_call_params(params)
      
      "mcp.resources.read" ->
        validate_resource_read_params(params)
      
      "mcp.prompts.get" ->
        validate_prompt_get_params(params)
      
      _ ->
        params  # Basic validation for other methods
    end
  end
  
  defp validate_tool_call_params(params) do
    required_fields = ["name"]
    
    case validate_required_fields(params, required_fields) do
      :ok ->
        # Additional validation for tool parameters
        tool_name = Map.get(params, "name")
        if is_binary(tool_name) and String.length(tool_name) < 100 do
          params
        else
          {:error, "Invalid tool name"}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp validate_resource_read_params(params) do
    case Map.get(params, "uri") do
      uri when is_binary(uri) ->
        if String.length(uri) < 1000 do
          params
        else
          {:error, "Resource URI too long"}
        end
      
      _ ->
        {:error, "Missing or invalid resource URI"}
    end
  end
  
  defp validate_prompt_get_params(params) do
    case Map.get(params, "name") do
      name when is_binary(name) ->
        if String.length(name) < 200 do
          params
        else
          {:error, "Prompt name too long"}
        end
      
      _ ->
        {:error, "Missing or invalid prompt name"}
    end
  end
  
  defp validate_required_fields(params, required_fields) do
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(params, field)
    end)
    
    if missing_fields == [] do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end
  
  defp apply_size_limits(params, method) do
    max_size = case method do
      "mcp.tools.call" -> 10_000    # 10KB for tool calls
      "mcp.prompts.get" -> 50_000   # 50KB for prompts
      _ -> 5_000                    # 5KB default
    end
    
    serialized_size = params |> Jason.encode!() |> byte_size()
    
    if serialized_size <= max_size do
      params
    else
      {:error, "Parameters too large: #{serialized_size} bytes (max #{max_size})"}
    end
  end
  
  ## Resource and Tool Access Validation
  
  defp validate_resource_access(client_id, resource_uri) do
    case URI.parse(resource_uri || "") do
      %URI{scheme: "file", path: path} ->
        # Validate file access permissions
        if String.contains?(path, "..") or String.starts_with?(path, "/etc/") do
          {:error, "Access denied to resource: #{path}"}
        else
          {:ok, %{validated: true}}
        end
      
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        # Validate external resource access
        if client_has_external_access?(client_id) do
          {:ok, %{validated: true}}
        else
          {:error, "External resource access not permitted"}
        end
      
      _ ->
        {:error, "Invalid or unsupported resource URI"}
    end
  end
  
  defp validate_tool_access(client_id, tool_name) do
    # Check if client has permission to use this tool
    restricted_tools = ["filesystem.delete", "system.exec", "network.request"]
    
    if tool_name in restricted_tools and not client_has_elevated_access?(client_id) do
      {:error, "Access denied to restricted tool: #{tool_name}"}
    else
      {:ok, %{validated: true}}
    end
  end
  
  defp client_has_external_access?(_client_id) do
    # Check client permissions for external resource access
    false  # Default to deny external access
  end
  
  defp client_has_elevated_access?(client_id) do
    # Check if client has elevated permissions
    String.contains?(client_id, "admin") or String.contains?(client_id, "trusted")
  end
  
  ## Response Filtering
  
  defp filter_response_for_client(response, client_id) do
    filtered_response = 
      response
      |> remove_sensitive_response_fields()
      |> limit_response_size()
      |> redact_based_on_permissions(client_id)
    
    {:ok, filtered_response}
  rescue
    error ->
      Logger.error("Response filtering failed", error: inspect(error))
      {:error, "Response filtering failed"}
  end
  
  defp remove_sensitive_response_fields(response) do
    Enum.reduce(@sensitive_mcp_fields, response, fn field, acc ->
      deep_delete_key(acc, field)
    end)
  end
  
  defp deep_delete_key(map, key) when is_map(map) do
    map
    |> Map.delete(key)
    |> Enum.into(%{}, fn {k, v} -> {k, deep_delete_key(v, key)} end)
  end
  
  defp deep_delete_key(list, key) when is_list(list) do
    Enum.map(list, &deep_delete_key(&1, key))
  end
  
  defp deep_delete_key(value, _key), do: value
  
  defp limit_response_size(response) do
    max_size = 1_000_000  # 1MB response limit
    
    serialized = Jason.encode!(response)
    if byte_size(serialized) > max_size do
      %{
        "error" => "Response too large",
        "truncated" => true,
        "original_size" => byte_size(serialized),
        "max_size" => max_size
      }
    else
      response
    end
  rescue
    _ ->
      %{"error" => "Response serialization failed"}
  end
  
  defp redact_based_on_permissions(response, client_id) do
    if client_has_debug_permissions?(client_id) do
      response  # Return full response for debug users
    else
      # Redact debug information for regular users
      response
      |> Map.delete("debug")
      |> Map.delete("internal")
      |> Map.delete("trace")
    end
  end
  
  defp client_has_debug_permissions?(client_id) do
    String.contains?(client_id, "debug") or String.contains?(client_id, "admin")
  end
  
  ## State Management
  
  defp update_connection_state(state, request) do
    connection_key = {request.client_id, request.method}
    updated_connections = Map.put(state.active_connections, connection_key, DateTime.utc_now())
    
    %{state | active_connections: updated_connections}
  end
  
  defp record_security_violation(state, request, reason) do
    event = %{
      type: :mcp_security_violation,
      timestamp: DateTime.utc_now(),
      client_id: request.client_id,
      method: request.method,
      reason: reason
    }
    
    SecurityMonitor.record_event(event)
    
    # Add to blocked clients if severe violation
    new_blocked = if severe_violation?(reason) do
      MapSet.put(state.blocked_clients, request.client_id)
    else
      state.blocked_clients
    end
    
    %{state | 
      security_events: [event | Enum.take(state.security_events, 999)],
      blocked_clients: new_blocked
    }
  end
  
  defp register_connection(state, client_id, server_uri) do
    connection = %{
      client_id: client_id,
      server_uri: server_uri,
      connected_at: DateTime.utc_now()
    }
    
    updated_connections = Map.put(state.active_connections, client_id, connection)
    %{state | active_connections: updated_connections}
  end
  
  defp terminate_client_connections_internal(state, client_id) do
    updated_connections = Map.drop(state.active_connections, [client_id])
    %{state | active_connections: updated_connections}
  end
  
  ## Utility Functions
  
  defp get_rate_limit_for_method(method) do
    Map.get(@mcp_rate_limits, method)
  end
  
  defp method_requires_session?(method) do
    session_required_methods = [
      "mcp.resources.read",
      "mcp.tools.call"
    ]
    
    method in session_required_methods
  end
  
  defp severe_violation?(reason) do
    severe_patterns = [
      "path traversal",
      "command injection",
      "authorization failed",
      "dangerous parameter"
    ]
    
    reason_str = String.downcase(to_string(reason))
    Enum.any?(severe_patterns, &String.contains?(reason_str, &1))
  end
  
  defp log_mcp_event(event_type, metadata) do
    Logger.info("MCP Security Event", type: event_type, metadata: metadata)
    
    SecurityMonitor.record_event(%{
      type: event_type,
      timestamp: DateTime.utc_now(),
      client_id: metadata[:client_id],
      metadata: metadata
    })
  end
  
  defp generate_security_stats(state) do
    %{
      active_connections: map_size(state.active_connections),
      blocked_clients: MapSet.size(state.blocked_clients),
      security_events_count: length(state.security_events),
      recent_events: Enum.take(state.security_events, 10),
      timestamp: DateTime.utc_now()
    }
  end
end