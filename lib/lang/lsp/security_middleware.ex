defmodule Lang.LSP.SecurityMiddleware do
  @moduledoc """
  Security middleware for LSP request processing.
  
  Integrates with Lang.LSP.SecurityValidator and Lang.Security.RedisLimiter
  to provide comprehensive security validation for all LSP operations.
  
  Middleware pipeline:
  1. Client ID validation and extraction
  2. Rate limiting checks 
  3. Parameter validation and sanitization
  4. Method authorization
  5. Resource access control
  6. Security event logging
  """
  
  require Logger
  
  alias Lang.LSP.SecurityValidator
  alias Lang.Security.RedisLimiter
  alias Lang.LSP.PhoenixIntegration
  
  @type lsp_request :: map()
  @type client_context :: %{
    client_id: String.t(),
    method: String.t(),
    authenticated: boolean(),
    permissions: [atom()],
    metadata: map()
  }
  @type middleware_result :: {:ok, lsp_request(), client_context()} | {:error, term()}
  
  @doc """
  Processes an LSP request through the security middleware pipeline.
  
  Returns {:ok, sanitized_request, context} or {:error, reason}.
  """
  @spec process_request(lsp_request(), map()) :: middleware_result()
  def process_request(request, opts \\ %{}) do
    client_id = get_client_id(request, opts)
    method = Map.get(request, "method")
    params = Map.get(request, "params", %{})

    with {:ok, validated_client} <- validate_client_id(client_id, method),
         {:ok, _} <- check_rate_limit(validated_client, method),
         :ok <- reject_prompt_injection(method, params),
         {:ok, sanitized_params} <- validate_and_sanitize_params(method, request),
         {:ok, _} <- check_method_authorization(validated_client, method),
         {:ok, context} <- build_client_context(validated_client, method, request) do
      
      sanitized_request = Map.put(request, "params", sanitized_params)
      log_security_event(:request_processed, context, sanitized_request)
      
      {:ok, sanitized_request, context}
    else
      {:error, reason} = error ->
        log_security_event(:request_blocked, %{client_id: client_id, method: method}, %{reason: reason})
        error
    end
  end

  defp reject_prompt_injection(method, params) do
    case Lang.LSP.SecurityValidator.prompt_injection?(method, params) do
      {true, details} -> {:error, {:prompt_injection, details}}
      false -> :ok
    end
  end
  
  @doc """
  Processes an LSP response through security checks.
  
  Ensures responses don't leak sensitive information.
  """
  @spec process_response(map(), client_context()) :: {:ok, map()} | {:error, term()}
  def process_response(response, context) do
    case sanitize_response(response, context) do
      {:ok, sanitized_response} ->
        log_security_event(:response_sent, context, %{response_size: estimate_size(sanitized_response)})
        {:ok, sanitized_response}
      
      {:error, reason} ->
        log_security_event(:response_blocked, context, %{reason: reason})
        {:error, reason}
    end
  end
  
  @doc """
  Validates a Client_ID for LSP operations.
  """
  @spec validate_client_id(String.t() | nil, String.t()) :: {:ok, String.t()} | {:error, term()}
  def validate_client_id(client_id, method) do
    case SecurityValidator.authorize_client(client_id, method, %{}) do
      :ok -> {:ok, client_id}
      {:error, reason} -> {:error, {:unauthorized, reason}}
    end
  end
  
  @doc """
  Checks rate limits for client and method.
  """
  @spec check_rate_limit(String.t(), String.t()) :: :ok | {:error, :rate_limited}
  def check_rate_limit(client_id, method) do
    case RedisLimiter.allow?(client_id, method) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
      {:error, reason} -> 
        Logger.error("Rate limiter error", client_id: client_id, method: method, reason: reason)
        # Fail open for availability
        :ok
    end
  end
  
  @doc """
  Validates and sanitizes LSP method parameters.
  """
  @spec validate_and_sanitize_params(String.t(), lsp_request()) :: {:ok, map()} | {:error, term()}
  def validate_and_sanitize_params(method, request) do
    params = Map.get(request, "params", %{})
    
    case SecurityValidator.validate_lsp_params(method, params) do
      {:ok, sanitized_params} -> {:ok, sanitized_params}
      {:error, reason} -> {:error, {:invalid_params, reason}}
    end
  end
  
  @doc """
  Checks if client is authorized to call the specific method.
  """
  @spec check_method_authorization(String.t(), String.t()) :: :ok | {:error, term()}
  def check_method_authorization(client_id, method) do
    cond do
      # Critical methods require enhanced authorization
      is_critical_method?(method) ->
        check_critical_method_auth(client_id, method)
      
      # Admin methods require admin role
      is_admin_method?(method) ->
        check_admin_auth(client_id)
        
      # MCP methods require MCP permissions
      is_mcp_method?(method) ->
        check_mcp_permissions(client_id)
        
      # Standard methods - basic auth sufficient
      true ->
        :ok
    end
  end
  
  ## Private Functions
  
  defp get_client_id(request, opts) do
    # Try multiple sources for client ID
    cond do
      # From options (e.g., from identify message)
      client_id = Map.get(opts, :client_id) ->
        client_id
      
      # From request headers or metadata
      client_id = get_in(request, ["params", "client_id"]) ->
        client_id
        
      # From authentication context
      client_id = get_in(request, ["meta", "client_id"]) ->
        client_id
        
      # Generate temporary ID for tracking
      true ->
        generate_temp_client_id()
    end
  end
  
  defp build_client_context(client_id, method, request) do
    # Get additional client information
    auth_info = get_client_auth_info(client_id)
    permissions = get_client_permissions(client_id)
    
    context = %{
      client_id: client_id,
      method: method,
      authenticated: auth_info.authenticated,
      permissions: permissions,
      metadata: %{
        request_time: DateTime.utc_now(),
        user_agent: get_in(request, ["meta", "user_agent"]),
        ip_address: get_in(request, ["meta", "ip_address"]),
        session_id: get_in(request, ["meta", "session_id"])
      }
    }
    
    {:ok, context}
  end
  
  defp sanitize_response(response, context) do
    case response do
      %{"error" => error} ->
        # Sanitize error responses to prevent information disclosure
        sanitized_error = sanitize_error_response(error, context)
        {:ok, %{response | "error" => sanitized_error}}
        
      %{"result" => result} ->
        # Check for sensitive data in results
        case contains_sensitive_data?(result) do
          false -> {:ok, response}
          true -> 
            sanitized_result = sanitize_result(result, context)
            {:ok, %{response | "result" => sanitized_result}}
        end
      
      _ -> {:ok, response}
    end
  end
  
  defp sanitize_error_response(error, context) do
    # Remove potentially sensitive stack traces, file paths, etc.
    sanitized_message = sanitize_error_message(Map.get(error, "message", ""))
    
    base_error = %{
      "code" => Map.get(error, "code", -32603),
      "message" => sanitized_message
    }
    
    # Include additional data only for authorized clients
    if context.authenticated and :debug in context.permissions do
      Map.put(base_error, "data", Map.get(error, "data", %{}))
    else
      base_error
    end
  end
  
  defp sanitize_error_message(message) when is_binary(message) do
    message
    # Remove file system paths
    |> String.replace(~r/\/[\/\w\-\.]+\/[\/\w\-\.]+/u, "[FILE_PATH]")
    # Remove potential secrets (long alphanumeric strings)
    |> String.replace(~r/[A-Za-z0-9]{20,}/u, "[REDACTED]")
    # Remove stack trace patterns
    |> String.replace(~r/\s+at\s+[\w\.]+\([\w\.\:\/]+\:\d+\:\d+\)/u, "")
  end
  
  defp sanitize_error_message(_), do: "Internal error"
  
  defp contains_sensitive_data?(result) when is_map(result) do
    sensitive_keys = ["password", "secret", "token", "key", "auth", "credential"]
    
    Enum.any?(result, fn {key, value} ->
      key_sensitive = Enum.any?(sensitive_keys, &String.contains?(String.downcase(to_string(key)), &1))
      value_sensitive = is_binary(value) and String.length(value) > 16 and 
                       String.match?(value, ~r/^[A-Za-z0-9+\/=]{16,}$/)
      
      key_sensitive or value_sensitive or (is_map(value) and contains_sensitive_data?(value))
    end)
  end
  
  defp contains_sensitive_data?(_), do: false
  
  defp sanitize_result(result, context) when is_map(result) do
    Enum.reduce(result, %{}, fn {key, value}, acc ->
      if should_redact_key?(key, context) do
        Map.put(acc, key, "[REDACTED]")
      else
        sanitized_value = if is_map(value), do: sanitize_result(value, context), else: value
        Map.put(acc, key, sanitized_value)
      end
    end)
  end
  
  defp sanitize_result(result, _context), do: result
  
  defp should_redact_key?(key, context) do
    sensitive_keys = ["password", "secret", "token", "key", "auth", "credential"]
    key_string = String.downcase(to_string(key))
    
    is_sensitive = Enum.any?(sensitive_keys, &String.contains?(key_string, &1))
    
    # Only redact if client doesn't have debug permissions
    is_sensitive and not (:debug in context.permissions)
  end
  
  defp is_critical_method?(method) do
    critical_methods = [
      "mcp.connection.create",
      "mcp.connection.destroy",
      "lang.storage.create_session",
      "lang.agent.spawn",
      "workspace/executeCommand"
    ]
    
    method in critical_methods
  end
  
  defp is_admin_method?(method) do
    admin_methods = [
      "lang.admin.reset_limits",
      "lang.admin.get_stats", 
      "lang.admin.shutdown",
      "rpc.admin.status"
    ]
    
    method in admin_methods or String.starts_with?(method, "lang.admin.")
  end
  
  defp is_mcp_method?(method) do
    String.starts_with?(method, "mcp.")
  end
  
  defp check_critical_method_auth(client_id, method) do
    # Enhanced validation for critical methods
    case get_client_trust_level(client_id) do
      level when level >= 3 -> :ok
      _ -> {:error, "Insufficient trust level for critical method"}
    end
  end
  
  defp check_admin_auth(client_id) do
    case get_client_roles(client_id) do
      roles when is_list(roles) ->
        if :admin in roles or :superuser in roles do
          :ok
        else
          {:error, "Admin role required"}
        end
      
      _ -> {:error, "Unable to verify admin role"}
    end
  end
  
  defp check_mcp_permissions(client_id) do
    permissions = get_client_permissions(client_id)
    
    if :mcp in permissions or :all in permissions do
      :ok
    else
      {:error, "MCP permissions required"}
    end
  end
  
  defp get_client_auth_info(client_id) do
    # In real implementation, this would query auth service/database
    %{
      authenticated: is_valid_client_format?(client_id),
      auth_method: :client_id,
      expires_at: DateTime.add(DateTime.utc_now(), 3600)
    }
  end
  
  defp get_client_permissions(client_id) do
    # In real implementation, this would query permissions service
    # For now, derive from client ID format
    cond do
      String.contains?(client_id, "admin") -> [:all, :admin, :debug, :mcp]
      String.contains?(client_id, "mcp") -> [:mcp, :basic]
      is_valid_client_format?(client_id) -> [:basic]
      true -> []
    end
  end
  
  defp get_client_roles(client_id) do
    # In real implementation, this would query role service
    if String.contains?(client_id, "admin") do
      [:admin, :user]
    else
      [:user]
    end
  end
  
  defp get_client_trust_level(client_id) do
    # Simple trust level based on client behavior
    # In real implementation, this would be calculated from historical behavior
    cond do
      String.contains?(client_id, "trusted") -> 4
      String.contains?(client_id, "admin") -> 5  
      is_valid_client_format?(client_id) -> 2
      true -> 1
    end
  end
  
  defp is_valid_client_format?(client_id) when is_binary(client_id) do
    String.length(client_id) >= 10 and 
    String.length(client_id) <= 64 and
    String.match?(client_id, ~r/^[A-Za-z0-9_-]+$/)
  end
  
  defp is_valid_client_format?(_), do: false
  
  defp generate_temp_client_id do
    "temp_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
  end
  
  defp log_security_event(event_type, context, metadata \\ %{}) do
    event = %{
      type: event_type,
      timestamp: DateTime.utc_now(),
      client_id: Map.get(context, :client_id),
      method: Map.get(context, :method),
      metadata: metadata
    }
    
    # Log to structured security log
    Logger.info("Security event", event)
    
    # Send to Phoenix for real-time monitoring
    PhoenixIntegration.broadcast_security_event(event_type, event)
    
    # Send metrics
    :telemetry.execute([:lang, :lsp, :security, event_type], %{count: 1}, event)
  end
  
  defp estimate_size(data) when is_map(data) do
    data |> Jason.encode!() |> byte_size()
  rescue
    _ -> 0
  end
  
  defp estimate_size(_), do: 0
end
