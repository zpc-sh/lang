defmodule Lang.LSP.Handler do
  @moduledoc """
  Behavior for LSP method handlers.

  Each LSP method should implement this behavior to provide:
  - Method name identification
  - Request handling logic
  - Consistent error handling
  - Documentation and validation

  ## Example Implementation

      defmodule MyApp.LSP.MyHandler do
        @behaviour Lang.LSP.Handler
        @lsp_method "myapp.my_method"

        @impl true
        def method, do: @lsp_method

        @impl true
        def handle(params, ctx) do
          # Process the request
          {:ok, %{result: "success"}}
        end
      end

  ## Context Structure

  The context (`ctx`) parameter contains:
  - `:session_id` - Unique session identifier
  - `:user_id` - Current user ID (if authenticated)
  - `:workspace_uri` - Root workspace URI
  - `:capabilities` - Client capabilities
  - `:trace` - Trace level for debugging

  ## Response Format

  Handlers should return:
  - `{:ok, result}` - Success with result data
  - `{:error, reason}` - Error with reason
  - `{:error, code, message}` - LSP error with code and message
  - `{:async, task_id}` - For async operations
  """

  @doc """
  Returns the LSP method name this handler responds to.
  """
  @callback method() :: String.t()

  @doc """
  Handle the LSP method request.

  ## Parameters
  - `params` - Method parameters from the LSP request
  - `ctx` - Request context with session info, user, workspace, etc.

  ## Returns
  - `{:ok, result}` - Success response
  - `{:error, reason}` - Generic error
  - `{:error, code, message}` - LSP error with specific code
  - `{:async, task_id}` - Async operation started
  """
  @callback handle(params :: map(), ctx :: map()) ::
              {:ok, any()}
              | {:error, any()}
              | {:error, integer(), String.t()}
              | {:async, String.t()}

  @optional_callbacks []

  # =============================================================================
  # Helper Functions
  # =============================================================================

  @doc """
  Validate required parameters in the request.
  """
  def validate_params(params, required_keys) when is_list(required_keys) do
    missing_keys =
      required_keys
      |> Enum.reject(fn key -> Map.has_key?(params, key) end)

    case missing_keys do
      [] -> :ok
      missing -> {:error, -32602, "Missing required parameters: #{Enum.join(missing, ", ")}"}
    end
  end

  @doc """
  Create a standardized error response.
  """
  def error_response(code, message, data \\ nil) do
    response = %{code: code, message: message}

    if data do
      {:error, code, message, data}
    else
      {:error, code, message}
    end
  end

  @doc """
  Common LSP error codes.
  """
  def error_codes do
    %{
      parse_error: -32700,
      invalid_request: -32600,
      method_not_found: -32601,
      invalid_params: -32602,
      internal_error: -32603,
      server_not_initialized: -32002,
      unknown_error_code: -32001,
      request_cancelled: -32800,
      content_modified: -32801
    }
  end

  @doc """
  Wrap result in async task tracking.
  """
  def async_result(task_id, initial_status \\ :started) do
    {:async,
     %{
       task_id: task_id,
       status: initial_status,
       started_at: DateTime.utc_now()
     }}
  end

  @doc """
  Create success response with optional metadata.
  """
  def success_response(result, metadata \\ %{}) do
    case metadata do
      empty when map_size(empty) == 0 -> {:ok, result}
      meta -> {:ok, %{result: result, metadata: meta}}
    end
  end

  @doc """
  Extract workspace information from context.
  """
  def workspace_info(ctx) do
    %{
      root_uri: Map.get(ctx, :workspace_uri),
      session_id: Map.get(ctx, :session_id),
      user_id: Map.get(ctx, :user_id)
    }
  end

  @doc """
  Check if user has permission for operation.
  """
  def check_permission(ctx, required_permission) do
    user_permissions = Map.get(ctx, :permissions, [])

    if required_permission in user_permissions do
      :ok
    else
      {:error, -32001, "Insufficient permissions for operation"}
    end
  end

  @doc """
  Sanitize parameters for logging (remove sensitive data).
  """
  def sanitize_for_logging(params) when is_map(params) do
    sensitive_keys = [:api_key, :token, :password, :auth, :secret]

    Enum.reduce(sensitive_keys, params, fn key, acc ->
      if Map.has_key?(acc, key) do
        Map.put(acc, key, "***REDACTED***")
      else
        acc
      end
    end)
  end

  def sanitize_for_logging(params), do: params

  @doc """
  Convert string keys to atom keys for internal processing.
  """
  def atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      key = if is_binary(k), do: String.to_existing_atom(k), else: k
      {key, v}
    end)
    |> Map.new()
  rescue
    # Return original if atom doesn't exist
    ArgumentError -> map
  end

  def atomize_keys(value), do: value

  @doc """
  Measure execution time of handler operations.
  """
  defmacro with_timing(operation, do: block) do
    quote do
      start_time = System.monotonic_time(:microsecond)
      result = unquote(block)
      end_time = System.monotonic_time(:microsecond)
      duration_ms = div(end_time - start_time, 1000)

      Logger.debug("#{unquote(operation)} completed", duration_ms: duration_ms)
      result
    end
  end
end
