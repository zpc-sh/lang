defmodule Lang.MCP.Broker do
  @moduledoc """
  MCP Broker Security Layer - Core server lifecycle management.

  This module provides secure lifecycle management for MCP servers, ensuring
  they never have direct internet exposure. All MCP communication is wrapped
  through Lang's authenticated endpoints with comprehensive security controls.

  ## Security Model
  - MCP servers run in isolated processes under strict supervision
  - All communication passes through authenticated Lang endpoints
  - Connection pooling with resource limits per user/session
  - Circuit breaker protection against misbehaving MCP servers
  - Allowlist-based MCP server type validation

  ## Architecture
  The broker manages MCP servers as supervised child processes, maintaining
  connection pools and enforcing security boundaries. MCP servers are treated
  as potentially hostile and sandboxed completely.
  """

  use GenServer
  require Logger

  alias Lang.MCP.{Security, Pool}
  alias Lang.Security.RateLimiter
  alias Lang.Events

  # Note: previously declared :gen_statem, but this module implements GenServer
  # callbacks only. Removing :gen_statem behaviour to avoid conflicts.

  # Server registry for tracking active MCP processes
  @registry Lang.MCP.Registry

  # Allowed MCP server types - security allowlist
  @allowed_server_types [
    "filesystem",
    "git",
    "database",
    "web_search",
    "code_analysis"
  ]

  # Connection timeouts and limits
  @default_idle_timeout :timer.minutes(10)
  @max_connections_per_user 5
  @health_check_interval :timer.seconds(30)

  @type server_type :: String.t()
  @type connection_id :: String.t()
  @type user_id :: String.t()

  @type broker_state :: %{
          connections: %{connection_id() => connection_info()},
          user_limits: %{user_id() => non_neg_integer()},
          health_checks: %{connection_id() => reference()},
          circuit_breakers: %{server_type() => circuit_breaker_state()}
        }

  @type connection_info :: %{
          server_type: server_type(),
          user_id: user_id(),
          pid: pid(),
          created_at: DateTime.t(),
          last_activity: DateTime.t(),
          session_id: String.t(),
          stream_id: String.t() | nil,
          request_count: non_neg_integer()
        }

  @type circuit_breaker_state :: %{
          state: :closed | :open | :half_open,
          failure_count: non_neg_integer(),
          last_failure: DateTime.t() | nil,
          next_attempt: DateTime.t() | nil
        }

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Maximum MCP connections allowed per user.
  """
  @spec max_connections_per_user() :: non_neg_integer()
  def max_connections_per_user, do: @max_connections_per_user

  @doc """
  Request a secure MCP server connection.

  ## Options
  - `:server_type` - Type of MCP server (must be in allowlist)
  - `:user_id` - Authenticated user requesting connection
  - `:session_id` - Session identifier for isolation
  - `:config` - MCP server configuration (validated)

  Returns `{:ok, connection_id}` or `{:error, reason}`
  """
  @spec request_connection(server_type(), user_id(), String.t(), map(), String.t() | nil) ::
          {:ok, connection_id()} | {:error, term()}
  def request_connection(server_type, user_id, session_id, config \\ %{}, auth_session_id \\ nil) do
    GenServer.call(__MODULE__, {
      :request_connection,
      server_type,
      user_id,
      session_id,
      config,
      auth_session_id
    })
  end

  @doc """
  Get connection status and health information.
  """
  @spec get_connection_status(connection_id()) ::
          {:ok, map()} | {:error, :not_found}
  def get_connection_status(connection_id) do
    GenServer.call(__MODULE__, {:get_status, connection_id})
  end

  @doc """
  Disconnect and cleanup MCP server connection.
  """
  @spec disconnect(connection_id()) :: :ok | {:error, term()}
  def disconnect(connection_id) do
    GenServer.call(__MODULE__, {:disconnect, connection_id})
  end

  @doc """
  Send secure MCP request through the broker.
  All requests are validated, rate-limited, and logged.
  """
  @spec send_mcp_request(connection_id(), map()) ::
          {:ok, term()} | {:error, term()}
  def send_mcp_request(connection_id, request) do
    GenServer.call(__MODULE__, {:mcp_request, connection_id, request})
  end

  @doc """
  Get broker statistics for monitoring.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  List active connections for a given user.

  Returns a list of maps with connection metadata including
  `:connection_id`, `:server_type`, `:status`, `:created_at`,
  `:last_activity`, `:session_id`, and `:stream_id`.
  """
  @spec list_active(user_id()) :: {:ok, [map()]}
  def list_active(user_id) do
    GenServer.call(__MODULE__, {:list_active, user_id})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting MCP Broker with security controls")

    # Create ETS table for fast connection lookups
    :ets.new(@registry, [:set, :public, :named_table])

    # Schedule periodic health checks
    Process.send_after(self(), :health_check, @health_check_interval)

    # Schedule cleanup of idle connections
    Process.send_after(self(), :cleanup_idle, @default_idle_timeout)

    {:ok,
     %{
       connections: %{},
       user_limits: %{},
       health_checks: %{},
       circuit_breakers: initialize_circuit_breakers()
     }}
  end

  @impl true
  def handle_call(
        {:request_connection, server_type, user_id, session_id, config, auth_session_id},
        _from,
        state
      ) do
    case validate_connection_request(server_type, user_id, state) do
      :ok ->
        case create_secure_connection(
               server_type,
               user_id,
               session_id,
               config,
               auth_session_id,
               state
             ) do
          {:ok, connection_id, updated_state} ->
            Events.track_event(%{
              event_type: "mcp_connection_created",
              user_id: user_id,
              metadata: %{
                server_type: server_type,
                connection_id: connection_id,
                session_id: session_id,
                auth_session_id: auth_session_id
              }
            })

            {:reply, {:ok, connection_id}, updated_state}

          {:error, reason} ->
            Logger.warning("Failed to create MCP connection",
              server_type: server_type,
              user_id: user_id,
              reason: reason
            )

            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_status, connection_id}, _from, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      connection ->
        status = build_connection_status(connection)
        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call({:disconnect, connection_id}, _from, state) do
    case disconnect_connection(connection_id, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:mcp_request, connection_id, request}, _from, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:reply, {:error, :connection_not_found}, state}

      connection ->
        case send_secure_mcp_request(connection_id, connection, request, state) do
          {:ok, response, updated_state} ->
            {:reply, {:ok, response}, updated_state}

          {:error, reason, updated_state} ->
            {:reply, {:error, reason}, updated_state}
        end
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_connections: map_size(state.connections),
      connections_by_type: get_connections_by_type(state.connections),
      active_users: map_size(state.user_limits),
      circuit_breaker_states: get_circuit_breaker_states(state.circuit_breakers),
      uptime: :erlang.monotonic_time(:second)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:list_active, user_id}, _from, state) do
    result =
      state.connections
      |> Enum.filter(fn {_id, conn} -> conn.user_id == user_id end)
      |> Enum.map(fn {connection_id, conn} ->
        status = if(Process.alive?(conn.pid), do: :alive, else: :dead)

        health =
          case Pool.health_check(conn.pid) do
            :ok -> :healthy
            _ -> :unhealthy
          end

        server_pid_masked = "pid-" <> Integer.to_string(:erlang.phash2(conn.pid))

        health_details =
          case Pool.health_details(conn.pid) do
            {:ok, details} -> details
            _ -> nil
          end

        %{
          connection_id: connection_id,
          server_type: conn.server_type,
          status: status,
          created_at: conn.created_at,
          last_activity: conn.last_activity,
          request_count: conn.request_count,
          uptime_seconds: max(0, DateTime.diff(DateTime.utc_now(), conn.created_at)),
          health: health,
          server_pid_masked: server_pid_masked,
          health_details: health_details,
          session_id: conn.session_id,
          stream_id: conn.stream_id
        }
      end)

    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    updated_state = perform_health_checks(state)

    # Schedule next health check
    Process.send_after(self(), :health_check, @health_check_interval)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:cleanup_idle, state) do
    updated_state = cleanup_idle_connections(state)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_idle, @default_idle_timeout)

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle MCP server process crash
    updated_state = handle_mcp_server_crash(pid, reason, state)
    {:noreply, updated_state}
  end

  ## Private Functions

  defp validate_connection_request(server_type, user_id, state) do
    with :ok <- validate_server_type(server_type),
         :ok <- check_user_limits(user_id, state),
         :ok <- check_circuit_breaker(server_type, state),
         :ok <- check_rate_limit(user_id, "mcp_connect") do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_server_type(server_type) do
    if server_type in @allowed_server_types do
      :ok
    else
      Logger.warning("Rejected MCP connection for disallowed server type",
        server_type: server_type,
        allowed_types: @allowed_server_types
      )

      {:error, :server_type_not_allowed}
    end
  end

  defp check_user_limits(user_id, state) do
    current_connections = Map.get(state.user_limits, user_id, 0)

    if current_connections < @max_connections_per_user do
      :ok
    else
      {:error, :user_connection_limit_exceeded}
    end
  end

  defp check_circuit_breaker(server_type, state) do
    circuit_breaker = Map.get(state.circuit_breakers, server_type)

    case circuit_breaker.state do
      :open ->
        if DateTime.compare(DateTime.utc_now(), circuit_breaker.next_attempt) == :gt do
          {:error, :circuit_breaker_open}
        else
          # Circuit breaker cooling down
          :ok
        end

      _ ->
        :ok
    end
  end

  defp check_rate_limit(user_id, operation) do
    case RateLimiter.check_rate_limit(user_id, operation) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
    end
  end

  defp create_secure_connection(server_type, user_id, session_id, config, auth_session_id, state) do
    connection_id = generate_connection_id()

    # Validate and sanitize MCP server config
    case Security.validate_mcp_config(server_type, config) do
      {:ok, safe_config} ->
        # Start MCP server process under supervision
        case start_supervised_mcp_server(server_type, safe_config) do
          {:ok, pid} ->
            # Monitor the MCP server process
            Process.monitor(pid)

            connection = %{
              server_type: server_type,
              user_id: user_id,
              pid: pid,
              created_at: DateTime.utc_now(),
              last_activity: DateTime.utc_now(),
              session_id: session_id,
              stream_id: nil,
              request_count: 0
            }

            # Persist an Ash Connection record (best-effort; ETS remains source of truth)
            _ =
              try do
                attrs = [
                  connection_id: connection_id,
                  user_id: user_id,
                  auth_session_id: auth_session_id,
                  status: :connected,
                  health_status: :unknown
                ]

                Ash.create(Lang.MCP.Connection, attrs, action: :create)
              rescue
                _ -> :ok
              end

            # Update state
            updated_connections = Map.put(state.connections, connection_id, connection)
            updated_user_limits = Map.update(state.user_limits, user_id, 1, &(&1 + 1))

            # Register in ETS for fast lookups
            :ets.insert(@registry, {connection_id, pid})

            updated_state = %{
              state
              | connections: updated_connections,
                user_limits: updated_user_limits
            }

            {:ok, connection_id, updated_state}

          {:error, reason} ->
            {:error, {:mcp_server_start_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:invalid_config, reason}}
    end
  end

  defp start_supervised_mcp_server(server_type, config) do
    # Start MCP server process with restricted environment
    case Pool.get_or_create_connection(server_type, config) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start MCP server", server_type: server_type, reason: reason)
        {:error, reason}
    end
  end

  defp send_secure_mcp_request(connection_id, connection, request, state) do
    # Rate limit MCP requests
    case RateLimiter.check_rate_limit(connection.user_id, "mcp_request") do
      :ok ->
        # Validate and sanitize the MCP request
        case Security.validate_mcp_request(connection.server_type, request) do
          {:ok, safe_request} ->
            # Send request to MCP server with timeout
            case Pool.send_request(connection.pid, safe_request, timeout: 30_000) do
              {:ok, response} ->
                # Update last activity
                updated_connection = %{
                  connection
                  | last_activity: DateTime.utc_now(),
                    request_count: connection.request_count + 1
                }

                updated_connections =
                  Map.put(state.connections, connection_id, updated_connection)

                updated_state = %{state | connections: updated_connections}

                # Log successful request
                Events.track_event(%{
                  event_type: "mcp_request_success",
                  user_id: connection.user_id,
                  metadata: %{
                    server_type: connection.server_type,
                    request_type: Map.get(safe_request, "method", "unknown")
                  }
                })

                {:ok, response, updated_state}

              {:error, reason} ->
                Logger.warning("MCP request failed",
                  server_type: connection.server_type,
                  user_id: connection.user_id,
                  reason: reason
                )

                # Update circuit breaker on failure
                updated_state = update_circuit_breaker_on_failure(connection.server_type, state)

                {:error, reason, updated_state}
            end

          {:error, reason} ->
            Logger.warning("Invalid MCP request rejected",
              server_type: connection.server_type,
              reason: reason
            )

            {:error, {:invalid_request, reason}, state}
        end

      {:error, :rate_limited} ->
        {:error, :rate_limited, state}
    end
  end

  defp disconnect_connection(connection_id, state) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:error, :not_found}

      connection ->
        # Gracefully stop MCP server
        Pool.disconnect(connection.pid)

        # Clean up state
        updated_connections = Map.delete(state.connections, connection_id)

        updated_user_limits =
          Map.update(state.user_limits, connection.user_id, 0, &max(&1 - 1, 0))

        # Remove from ETS
        :ets.delete(@registry, connection_id)

        updated_state = %{
          state
          | connections: updated_connections,
            user_limits: updated_user_limits
        }

        Events.track_event(%{
          event_type: "mcp_connection_disconnected",
          user_id: connection.user_id,
          metadata: %{
            server_type: connection.server_type,
            connection_id: connection_id,
            duration_seconds: DateTime.diff(DateTime.utc_now(), connection.created_at)
          }
        })

        {:ok, updated_state}
    end
  end

  defp perform_health_checks(state) do
    Enum.reduce(state.connections, state, fn {connection_id, connection}, acc_state ->
      case Pool.health_check(connection.pid) do
        :ok ->
          acc_state

        {:error, reason} ->
          Logger.warning("MCP connection health check failed",
            connection_id: connection_id,
            server_type: connection.server_type,
            reason: reason
          )

          # Disconnect unhealthy connection
          case disconnect_connection(connection_id, acc_state) do
            {:ok, updated_state} -> updated_state
            {:error, _} -> acc_state
          end
      end
    end)
  end

  defp cleanup_idle_connections(state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -@default_idle_timeout, :millisecond)

    idle_connections =
      state.connections
      |> Enum.filter(fn {_id, connection} ->
        DateTime.compare(connection.last_activity, cutoff_time) == :lt
      end)

    Enum.reduce(idle_connections, state, fn {connection_id, _connection}, acc_state ->
      Logger.info("Disconnecting idle MCP connection", connection_id: connection_id)

      case disconnect_connection(connection_id, acc_state) do
        {:ok, updated_state} -> updated_state
        {:error, _} -> acc_state
      end
    end)
  end

  defp handle_mcp_server_crash(pid, reason, state) do
    Logger.error("MCP server process crashed", pid: pid, reason: reason)

    # Find connection by PID
    crashed_connection =
      Enum.find(state.connections, fn {_id, connection} ->
        connection.pid == pid
      end)

    case crashed_connection do
      {connection_id, connection} ->
        # Update circuit breaker
        updated_state = update_circuit_breaker_on_failure(connection.server_type, state)

        # Clean up connection
        case disconnect_connection(connection_id, updated_state) do
          {:ok, final_state} -> final_state
          {:error, _} -> updated_state
        end

      nil ->
        state
    end
  end

  defp initialize_circuit_breakers do
    Enum.reduce(@allowed_server_types, %{}, fn server_type, acc ->
      Map.put(acc, server_type, %{
        state: :closed,
        failure_count: 0,
        last_failure: nil,
        next_attempt: nil
      })
    end)
  end

  defp update_circuit_breaker_on_failure(server_type, state) do
    circuit_breaker = Map.get(state.circuit_breakers, server_type)
    failure_count = circuit_breaker.failure_count + 1
    now = DateTime.utc_now()

    updated_circuit_breaker =
      if failure_count >= 5 do
        # Open circuit breaker
        %{
          state: :open,
          failure_count: failure_count,
          last_failure: now,
          # 1 minute cooldown
          next_attempt: DateTime.add(now, 60, :second)
        }
      else
        %{circuit_breaker | failure_count: failure_count, last_failure: now}
      end

    updated_circuit_breakers =
      Map.put(state.circuit_breakers, server_type, updated_circuit_breaker)

    %{state | circuit_breakers: updated_circuit_breakers}
  end

  defp build_connection_status(connection) do
    health =
      case Pool.health_check(connection.pid) do
        :ok -> :healthy
        _ -> :unhealthy
      end

    server_pid_masked = "pid-" <> Integer.to_string(:erlang.phash2(connection.pid))

    health_details =
      case Pool.health_details(connection.pid) do
        {:ok, details} -> details
        _ -> nil
      end

    %{
      server_type: connection.server_type,
      created_at: connection.created_at,
      last_activity: connection.last_activity,
      request_count: connection.request_count,
      uptime_seconds: max(0, DateTime.diff(DateTime.utc_now(), connection.created_at)),
      health: health,
      server_pid_masked: server_pid_masked,
      health_details: health_details,
      user_id: connection.user_id,
      session_id: connection.session_id,
      stream_id: connection.stream_id,
      status: if(Process.alive?(connection.pid), do: :alive, else: :dead)
    }
  end

  defp get_connections_by_type(connections) do
    connections
    |> Enum.group_by(fn {_id, connection} -> connection.server_type end)
    |> Enum.map(fn {type, conns} -> {type, length(conns)} end)
    |> Enum.into(%{})
  end

  defp get_circuit_breaker_states(circuit_breakers) do
    Enum.map(circuit_breakers, fn {type, breaker} ->
      {type, breaker.state}
    end)
    |> Enum.into(%{})
  end

  defp generate_connection_id do
    "mcp_conn_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
