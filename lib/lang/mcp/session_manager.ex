defmodule Lang.MCP.SessionManager do
  @moduledoc """
  Secure session management for MCP bridge connections.
  
  Provides session lifecycle management, token validation, and isolation
  between different clients accessing MCP services through LSP.
  """
  
  use GenServer
  require Logger
  
  alias Lang.Redis
  alias Lang.LSP.SecurityValidator
  
  @session_ttl 3600  # 1 hour
  @cleanup_interval 300_000  # 5 minutes
  @max_sessions_per_client 5
  
  @type session_id :: String.t()
  @type client_id :: String.t()
  @type session_info :: %{
    session_id: session_id(),
    client_id: client_id(),
    created_at: DateTime.t(),
    last_activity: DateTime.t(),
    permissions: [atom()],
    metadata: map(),
    mcp_connections: [pid()]
  }
  
  ## Public API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Creates a new secure session for MCP access.
  """
  @spec create_session(client_id(), map()) :: {:ok, session_id()} | {:error, term()}
  def create_session(client_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:create_session, client_id, metadata})
  end
  
  @doc """
  Validates and retrieves session information.
  """
  @spec get_session(session_id()) :: {:ok, session_info()} | {:error, :not_found | :expired}
  def get_session(session_id) do
    GenServer.call(__MODULE__, {:get_session, session_id})
  end
  
  @doc """
  Updates session activity timestamp.
  """
  @spec touch_session(session_id()) :: :ok | {:error, :not_found}
  def touch_session(session_id) do
    GenServer.call(__MODULE__, {:touch_session, session_id})
  end
  
  @doc """
  Registers an MCP connection with a session.
  """
  @spec register_connection(session_id(), pid()) :: :ok | {:error, term()}
  def register_connection(session_id, connection_pid) do
    GenServer.call(__MODULE__, {:register_connection, session_id, connection_pid})
  end
  
  @doc """
  Terminates a session and cleans up resources.
  """
  @spec terminate_session(session_id()) :: :ok
  def terminate_session(session_id) do
    GenServer.call(__MODULE__, {:terminate_session, session_id})
  end
  
  @doc """
  Lists active sessions for a client.
  """
  @spec list_client_sessions(client_id()) :: [session_info()]
  def list_client_sessions(client_id) do
    GenServer.call(__MODULE__, {:list_client_sessions, client_id})
  end
  
  @doc """
  Validates session permissions for MCP operations.
  """
  @spec validate_session_permission(session_id(), atom()) :: :ok | {:error, term()}
  def validate_session_permission(session_id, required_permission) do
    case get_session(session_id) do
      {:ok, session} ->
        if required_permission in session.permissions or :all in session.permissions do
          touch_session(session_id)
          :ok
        else
          {:error, :insufficient_permissions}
        end
      
      error -> error
    end
  end
  
  ## GenServer Implementation
  
  def init(_opts) do
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_expired_sessions, @cleanup_interval)
    
    state = %{
      sessions: %{},  # session_id -> session_info
      client_sessions: %{}  # client_id -> [session_id]
    }
    
    {:ok, state}
  end
  
  def handle_call({:create_session, client_id, metadata}, _from, state) do
    case validate_client_session_limit(client_id, state) do
      :ok ->
        session_id = generate_session_id()
        permissions = get_client_permissions(client_id)
        
        session_info = %{
          session_id: session_id,
          client_id: client_id,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          permissions: permissions,
          metadata: metadata,
          mcp_connections: []
        }
        
        # Store in memory and Redis for persistence
        new_sessions = Map.put(state.sessions, session_id, session_info)
        new_client_sessions = add_client_session(state.client_sessions, client_id, session_id)
        
        # Persist to Redis with TTL
        store_session_in_redis(session_id, session_info)
        
        new_state = %{
          sessions: new_sessions,
          client_sessions: new_client_sessions
        }
        
        log_session_event(:session_created, session_info)
        {:reply, {:ok, session_id}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:get_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        # Try loading from Redis
        case load_session_from_redis(session_id) do
          {:ok, session_info} ->
            new_sessions = Map.put(state.sessions, session_id, session_info)
            new_state = %{state | sessions: new_sessions}
            {:reply, {:ok, session_info}, new_state}
          
          error ->
            {:reply, error, state}
        end
      
      session_info ->
        if session_expired?(session_info) do
          # Clean up expired session
          new_state = remove_session_from_state(state, session_id, session_info.client_id)
          {:reply, {:error, :expired}, new_state}
        else
          {:reply, {:ok, session_info}, state}
        end
    end
  end
  
  def handle_call({:touch_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      session_info ->
        updated_session = %{session_info | last_activity: DateTime.utc_now()}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        new_state = %{state | sessions: new_sessions}
        
        # Update Redis
        store_session_in_redis(session_id, updated_session)
        
        {:reply, :ok, new_state}
    end
  end
  
  def handle_call({:register_connection, session_id, connection_pid}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}
      
      session_info ->
        # Monitor the connection process
        Process.monitor(connection_pid)
        
        updated_connections = [connection_pid | session_info.mcp_connections]
        updated_session = %{session_info | mcp_connections: updated_connections}
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        new_state = %{state | sessions: new_sessions}
        
        log_session_event(:connection_registered, updated_session, %{pid: connection_pid})
        {:reply, :ok, new_state}
    end
  end
  
  def handle_call({:terminate_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, :ok, state}
      
      session_info ->
        # Terminate all MCP connections
        Enum.each(session_info.mcp_connections, fn pid ->
          if Process.alive?(pid) do
            Process.exit(pid, :session_terminated)
          end
        end)
        
        # Remove from state and Redis
        new_state = remove_session_from_state(state, session_id, session_info.client_id)
        remove_session_from_redis(session_id)
        
        log_session_event(:session_terminated, session_info)
        {:reply, :ok, new_state}
    end
  end
  
  def handle_call({:list_client_sessions, client_id}, _from, state) do
    session_ids = Map.get(state.client_sessions, client_id, [])
    sessions = Enum.map(session_ids, &Map.get(state.sessions, &1))
                |> Enum.filter(& &1)
                |> Enum.reject(&session_expired?/1)
    
    {:reply, sessions, state}
  end
  
  def handle_info(:cleanup_expired_sessions, state) do
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired_sessions, @cleanup_interval)
    
    # Find and remove expired sessions
    expired_sessions = Enum.filter(state.sessions, fn {_id, session} ->
      session_expired?(session)
    end)
    
    new_state = Enum.reduce(expired_sessions, state, fn {session_id, session_info}, acc_state ->
      # Clean up MCP connections
      Enum.each(session_info.mcp_connections, fn pid ->
        if Process.alive?(pid) do
          Process.exit(pid, :session_expired)
        end
      end)
      
      # Remove from Redis
      remove_session_from_redis(session_id)
      
      log_session_event(:session_expired, session_info)
      remove_session_from_state(acc_state, session_id, session_info.client_id)
    end)
    
    if length(expired_sessions) > 0 do
      Logger.info("Cleaned up #{length(expired_sessions)} expired sessions")
    end
    
    {:noreply, new_state}
  end
  
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove died connection from all sessions
    new_sessions = Enum.reduce(state.sessions, %{}, fn {session_id, session_info}, acc ->
      updated_connections = List.delete(session_info.mcp_connections, pid)
      updated_session = %{session_info | mcp_connections: updated_connections}
      Map.put(acc, session_id, updated_session)
    end)
    
    new_state = %{state | sessions: new_sessions}
    {:noreply, new_state}
  end
  
  ## Private Functions
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end
  
  defp validate_client_session_limit(client_id, state) do
    current_sessions = Map.get(state.client_sessions, client_id, [])
    active_count = Enum.count(current_sessions, fn session_id ->
      case Map.get(state.sessions, session_id) do
        nil -> false
        session -> not session_expired?(session)
      end
    end)
    
    if active_count >= @max_sessions_per_client do
      {:error, :session_limit_exceeded}
    else
      :ok
    end
  end
  
  defp get_client_permissions(client_id) do
    # Integrate with SecurityValidator for consistent permissions
    case SecurityValidator.authorize_client(client_id, "mcp.session.create", %{}) do
      :ok ->
        # Get detailed permissions based on client
        cond do
          String.contains?(client_id, "admin") -> [:all, :admin, :mcp]
          String.contains?(client_id, "mcp") -> [:mcp, :basic]
          SecurityValidator.is_valid_client_id?(client_id) -> [:basic]
          true -> []
        end
      
      {:error, _} -> []
    end
  end
  
  defp session_expired?(session_info) do
    expiry_time = DateTime.add(session_info.last_activity, @session_ttl)
    DateTime.compare(DateTime.utc_now(), expiry_time) == :gt
  end
  
  defp add_client_session(client_sessions, client_id, session_id) do
    current_sessions = Map.get(client_sessions, client_id, [])
    Map.put(client_sessions, client_id, [session_id | current_sessions])
  end
  
  defp remove_session_from_state(state, session_id, client_id) do
    new_sessions = Map.delete(state.sessions, session_id)
    
    current_client_sessions = Map.get(state.client_sessions, client_id, [])
    new_client_sessions = List.delete(current_client_sessions, session_id)
    updated_client_sessions = if new_client_sessions == [] do
      Map.delete(state.client_sessions, client_id)
    else
      Map.put(state.client_sessions, client_id, new_client_sessions)
    end
    
    %{
      sessions: new_sessions,
      client_sessions: updated_client_sessions
    }
  end
  
  defp store_session_in_redis(session_id, session_info) do
    key = "mcp_session:#{session_id}"
    serialized_session = :erlang.term_to_binary(session_info)
    
    case Redis.setex(key, @session_ttl, serialized_session) do
      {:ok, "OK"} -> :ok
      error -> 
        Logger.error("Failed to store session in Redis", session_id: session_id, error: error)
        error
    end
  end
  
  defp load_session_from_redis(session_id) do
    key = "mcp_session:#{session_id}"
    
    case Redis.get(key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, serialized_session} ->
        try do
          session_info = :erlang.binary_to_term(serialized_session)
          if session_expired?(session_info) do
            remove_session_from_redis(session_id)
            {:error, :expired}
          else
            {:ok, session_info}
          end
        rescue
          _ -> {:error, :invalid_session_data}
        end
      
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp remove_session_from_redis(session_id) do
    key = "mcp_session:#{session_id}"
    Redis.del(key)
  end
  
  defp log_session_event(event_type, session_info, metadata \\ %{}) do
    event = %{
      type: event_type,
      timestamp: DateTime.utc_now(),
      session_id: session_info.session_id,
      client_id: session_info.client_id,
      metadata: metadata
    }
    
    Logger.info("MCP session event", event)
    
    # Send telemetry
    :telemetry.execute([:lang, :mcp, :session, event_type], %{count: 1}, event)
  end
end