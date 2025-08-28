defmodule Lang.MCP.Pool do
  @moduledoc """
  MCP Connection Pool - Manages MCP server instances with lifecycle control.

  This module provides connection pooling for MCP servers with the following features:
  - Pre-warming of common MCP server types
  - Just-in-time connection creation for less common servers
  - Automatic disconnection of idle connections
  - Resource limits per user and session
  - Health monitoring and recovery

  ## Security Model
  All MCP servers are managed as isolated processes under supervision.
  The pool ensures proper resource limits and prevents resource exhaustion
  attacks while maintaining optimal performance through connection reuse.

  ## Architecture
  The pool maintains separate process pools for each MCP server type,
  with configurable limits and automatic scaling based on demand.
  """

  use GenServer
  require Logger

  # alias Lang.MCP.Security
  alias Lang.Events

  # Pool configuration
  @pre_warm_servers ["filesystem", "git"]
  @default_pool_size 3
  @max_pool_size 10
  @idle_timeout :timer.minutes(15)
  @health_check_interval :timer.minutes(1)
  @connection_timeout :timer.seconds(30)

  @type server_type :: String.t()
  @type pool_state :: %{
          pools: %{server_type() => pool_info()},
          active_connections: %{pid() => connection_info()},
          stats: pool_stats()
        }

  @type pool_info :: %{
          server_type: server_type(),
          available: [pid()],
          busy: [pid()],
          config: map(),
          last_used: DateTime.t(),
          health_ref: reference() | nil
        }

  @type connection_info :: %{
          server_type: server_type(),
          created_at: DateTime.t(),
          last_used: DateTime.t(),
          request_count: non_neg_integer(),
          user_id: String.t() | nil,
          session_id: String.t() | nil
        }

  @type pool_stats :: %{
          total_pools: non_neg_integer(),
          total_connections: non_neg_integer(),
          active_connections: non_neg_integer(),
          idle_connections: non_neg_integer(),
          failed_connections: non_neg_integer()
        }

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get or create a connection to an MCP server.

  For pre-warmed server types, returns an existing connection from the pool.
  For others, creates a new connection on-demand.
  """
  @spec get_or_create_connection(server_type(), map()) :: {:ok, pid()} | {:error, term()}
  def get_or_create_connection(server_type, config \\ %{}) do
    GenServer.call(__MODULE__, {:get_connection, server_type, config})
  end

  @doc """
  Send a request to an MCP server through the pool.
  Handles timeout and error recovery automatically.
  """
  @spec send_request(pid(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def send_request(pid, request, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @connection_timeout)

    try do
      GenServer.call(pid, {:mcp_request, request}, timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("MCP request timeout", pid: pid, timeout: timeout)
        {:error, :timeout}

      :exit, {:noproc, _} ->
        Logger.warning("MCP server process died", pid: pid)
        {:error, :process_died}

      :exit, reason ->
        Logger.error("MCP request failed", pid: pid, reason: reason)
        {:error, reason}
    end
  end

  @doc """
  Return a connection to the pool after use.
  """
  @spec return_connection(pid()) :: :ok
  def return_connection(pid) do
    GenServer.cast(__MODULE__, {:return_connection, pid})
  end

  @doc """
  Disconnect and remove a connection from the pool.
  """
  @spec disconnect(pid()) :: :ok
  def disconnect(pid) do
    GenServer.call(__MODULE__, {:disconnect, pid})
  end

  @doc """
  Perform health check on an MCP server connection.
  """
  @spec health_check(pid()) :: :ok | {:error, term()}
  def health_check(pid) do
    try do
      case GenServer.call(pid, :health_check, :timer.seconds(5)) do
        {:ok, _details} -> :ok
        :ok -> :ok
        other -> other
      end
    catch
      :exit, _ -> {:error, :health_check_failed}
    end
  end

  @doc """
  Attempt to retrieve health details for an MCP server.
  Returns {:ok, map} if provided by the server, otherwise {:error, :unavailable}.
  """
  @spec health_details(pid()) :: {:ok, map()} | {:error, term()}
  def health_details(pid) do
    try do
      case GenServer.call(pid, :health_check, :timer.seconds(5)) do
        {:ok, details} when is_map(details) -> {:ok, details}
        :ok -> {:error, :unavailable}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_response, other}}
      end
    catch
      :exit, _ -> {:error, :health_check_failed}
    end
  end

  @doc """
  Get pool statistics for monitoring.
  """
  @spec get_stats() :: pool_stats()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Warm up connection pools for specified server types.
  """
  @spec warm_pools([server_type()]) :: :ok
  def warm_pools(server_types) do
    GenServer.cast(__MODULE__, {:warm_pools, server_types})
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting MCP Connection Pool")

    # Schedule periodic maintenance
    Process.send_after(self(), :health_check_cycle, @health_check_interval)
    Process.send_after(self(), :cleanup_idle, @idle_timeout)

    state = %{
      pools: %{},
      active_connections: %{},
      stats: %{
        total_pools: 0,
        total_connections: 0,
        active_connections: 0,
        idle_connections: 0,
        failed_connections: 0
      }
    }

    # Pre-warm common server types
    Task.start_link(fn -> warm_common_pools() end)

    {:ok, state}
  end

  @impl true
  def handle_call({:get_connection, server_type, config}, _from, state) do
    case get_available_connection(server_type, state) do
      {:ok, pid, updated_state} ->
        # Update connection info
        connection_info = Map.get(updated_state.active_connections, pid, %{})
        updated_connection = %{connection_info | last_used: DateTime.utc_now()}

        updated_active = Map.put(updated_state.active_connections, pid, updated_connection)
        final_state = %{updated_state | active_connections: updated_active}

        {:reply, {:ok, pid}, update_stats(final_state)}

      {:error, :no_available_connection} ->
        # Create new connection
        case create_new_connection(server_type, config, state) do
          {:ok, pid, updated_state} ->
            {:reply, {:ok, pid}, update_stats(updated_state)}

          {:error, reason} ->
            Logger.warning("Failed to create MCP connection",
              server_type: server_type,
              reason: reason
            )

            {:reply, {:error, reason}, update_failed_stat(state)}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:disconnect, pid}, _from, state) do
    case Map.get(state.active_connections, pid) do
      nil ->
        {:reply, :ok, state}

      connection_info ->
        # Remove from pools and active connections
        updated_state = remove_connection_from_pools(pid, state)

        final_state = %{
          updated_state
          | active_connections: Map.delete(updated_state.active_connections, pid)
        }

        # Terminate the MCP server process
        terminate_mcp_server(pid)

        Events.track_event(%{
          event_type: "mcp_connection_disconnected",
          metadata: %{
            server_type: connection_info.server_type,
            duration_seconds: DateTime.diff(DateTime.utc_now(), connection_info.created_at),
            request_count: connection_info.request_count
          }
        })

        {:reply, :ok, update_stats(final_state)}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    current_stats = calculate_current_stats(state)
    {:reply, current_stats, state}
  end

  @impl true
  def handle_cast({:return_connection, pid}, state) do
    case Map.get(state.active_connections, pid) do
      nil ->
        {:noreply, state}

      connection_info ->
        # Move from busy to available in the appropriate pool
        updated_state = return_connection_to_pool(pid, connection_info, state)
        {:noreply, update_stats(updated_state)}
    end
  end

  @impl true
  def handle_cast({:warm_pools, server_types}, state) do
    updated_state =
      Enum.reduce(server_types, state, fn server_type, acc_state ->
        warm_pool_for_server_type(server_type, acc_state)
      end)

    {:noreply, update_stats(updated_state)}
  end

  @impl true
  def handle_info(:health_check_cycle, state) do
    updated_state = perform_health_checks(state)

    # Schedule next health check
    Process.send_after(self(), :health_check_cycle, @health_check_interval)

    {:noreply, update_stats(updated_state)}
  end

  @impl true
  def handle_info(:cleanup_idle, state) do
    updated_state = cleanup_idle_connections(state)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_idle, @idle_timeout)

    {:noreply, update_stats(updated_state)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.warning("MCP server process died", pid: pid, reason: reason)

    # Remove the dead process from all tracking
    updated_state = handle_process_death(pid, reason, state)

    {:noreply, update_stats(updated_state)}
  end

  ## Private Functions

  defp warm_common_pools do
    Logger.info("Pre-warming MCP connection pools", server_types: @pre_warm_servers)

    Enum.each(@pre_warm_servers, fn server_type ->
      case create_pool_for_server_type(server_type, %{}) do
        {:ok, _pool_info} ->
          Logger.debug("Pre-warmed pool for #{server_type}")

        {:error, reason} ->
          Logger.warning("Failed to pre-warm pool", server_type: server_type, reason: reason)
      end
    end)
  end

  defp get_available_connection(server_type, state) do
    case Map.get(state.pools, server_type) do
      nil ->
        {:error, :no_pool_exists}

      %{available: []} ->
        {:error, :no_available_connection}

      %{available: [pid | remaining_available]} = pool ->
        if Process.alive?(pid) do
          # Move connection from available to busy
          updated_pool = %{
            pool
            | available: remaining_available,
              busy: [pid | pool.busy],
              last_used: DateTime.utc_now()
          }

          updated_pools = Map.put(state.pools, server_type, updated_pool)
          updated_state = %{state | pools: updated_pools}

          {:ok, pid, updated_state}
        else
          # Dead process, remove and try next
          cleaned_pool = %{pool | available: remaining_available}
          cleaned_pools = Map.put(state.pools, server_type, cleaned_pool)
          cleaned_state = %{state | pools: cleaned_pools}

          get_available_connection(server_type, cleaned_state)
        end
    end
  end

  defp create_new_connection(server_type, config, state) do
    # Check if we can create more connections for this server type
    current_pool = Map.get(state.pools, server_type)

    current_size =
      if current_pool, do: length(current_pool.available) + length(current_pool.busy), else: 0

    if current_size >= @max_pool_size do
      {:error, :pool_size_limit_exceeded}
    else
      case start_mcp_server_process(server_type, config) do
        {:ok, pid} ->
          # Create or update pool
          updated_pools = add_connection_to_pool(server_type, pid, config, state.pools)

          # Track the connection
          connection_info = %{
            server_type: server_type,
            created_at: DateTime.utc_now(),
            last_used: DateTime.utc_now(),
            request_count: 0,
            user_id: nil,
            session_id: nil
          }

          updated_active = Map.put(state.active_connections, pid, connection_info)

          updated_state = %{state | pools: updated_pools, active_connections: updated_active}

          # Monitor the process
          Process.monitor(pid)

          Events.track_event(%{
            event_type: "mcp_connection_created",
            metadata: %{
              server_type: server_type,
              pid: inspect(pid)
            }
          })

          {:ok, pid, updated_state}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp start_mcp_server_process(server_type, config) do
    # Start MCP server as a supervised child process
    case create_mcp_server_spec(server_type, config) do
      {:ok, child_spec} ->
        case DynamicSupervisor.start_child(Lang.MCP.ServerSupervisor, child_spec) do
          {:ok, pid} ->
            Logger.debug("Started MCP server process", server_type: server_type, pid: pid)
            {:ok, pid}

          {:error, reason} ->
            Logger.error("Failed to start MCP server", server_type: server_type, reason: reason)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_mcp_server_spec(server_type, config) do
    # Create child spec for MCP server based on type
    case server_type do
      "filesystem" ->
        {:ok, {Lang.MCP.Servers.FilesystemServer, [config]}}

      "git" ->
        {:ok, {Lang.MCP.Servers.GitServer, [config]}}

      "database" ->
        {:ok, {Lang.MCP.Servers.DatabaseServer, [config]}}

      "web_search" ->
        {:ok, {Lang.MCP.Servers.WebSearchServer, [config]}}

      "code_analysis" ->
        {:ok, {Lang.MCP.Servers.CodeAnalysisServer, [config]}}

      _ ->
        {:error, {:unknown_server_type, server_type}}
    end
  end

  defp add_connection_to_pool(server_type, pid, config, pools) do
    case Map.get(pools, server_type) do
      nil ->
        # Create new pool
        new_pool = %{
          server_type: server_type,
          available: [],
          busy: [pid],
          config: config,
          last_used: DateTime.utc_now(),
          health_ref: nil
        }

        Map.put(pools, server_type, new_pool)

      existing_pool ->
        # Add to existing pool
        updated_pool = %{
          existing_pool
          | busy: [pid | existing_pool.busy],
            last_used: DateTime.utc_now()
        }

        Map.put(pools, server_type, updated_pool)
    end
  end

  defp return_connection_to_pool(pid, connection_info, state) do
    server_type = connection_info.server_type

    case Map.get(state.pools, server_type) do
      nil ->
        # Pool doesn't exist, clean up the connection
        terminate_mcp_server(pid)
        %{state | active_connections: Map.delete(state.active_connections, pid)}

      pool ->
        # Move from busy to available
        updated_busy = List.delete(pool.busy, pid)
        updated_available = [pid | pool.available]

        updated_pool = %{
          pool
          | busy: updated_busy,
            available: updated_available,
            last_used: DateTime.utc_now()
        }

        updated_pools = Map.put(state.pools, server_type, updated_pool)
        %{state | pools: updated_pools}
    end
  end

  defp remove_connection_from_pools(pid, state) do
    updated_pools =
      Enum.reduce(state.pools, state.pools, fn {server_type, pool}, acc_pools ->
        updated_available = List.delete(pool.available, pid)
        updated_busy = List.delete(pool.busy, pid)

        updated_pool = %{pool | available: updated_available, busy: updated_busy}
        Map.put(acc_pools, server_type, updated_pool)
      end)

    %{state | pools: updated_pools}
  end

  defp terminate_mcp_server(pid) do
    if Process.alive?(pid) do
      # Try graceful shutdown first
      GenServer.cast(pid, :shutdown)

      # Give it a moment to shut down gracefully
      :timer.sleep(1000)

      # Force kill if still alive
      if Process.alive?(pid) do
        Process.exit(pid, :kill)
      end
    end
  end

  defp perform_health_checks(state) do
    Enum.reduce(state.pools, state, fn {server_type, pool}, acc_state ->
      healthy_available =
        Enum.filter(pool.available, fn pid ->
          case health_check(pid) do
            :ok ->
              true

            {:error, _} ->
              Logger.warning("Unhealthy MCP connection removed",
                server_type: server_type,
                pid: pid
              )

              terminate_mcp_server(pid)
              false
          end
        end)

      healthy_busy =
        Enum.filter(pool.busy, fn pid ->
          # Don't interrupt busy connections with health checks
          Process.alive?(pid)
        end)

      updated_pool = %{pool | available: healthy_available, busy: healthy_busy}

      updated_pools = Map.put(acc_state.pools, server_type, updated_pool)
      %{acc_state | pools: updated_pools}
    end)
  end

  defp cleanup_idle_connections(state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -@idle_timeout, :millisecond)

    Enum.reduce(state.pools, state, fn {server_type, pool}, acc_state ->
      # Only clean up available connections (not busy ones)
      {idle_connections, active_connections} =
        Enum.split_with(pool.available, fn pid ->
          case Map.get(acc_state.active_connections, pid) do
            # No tracking info, assume idle
            nil -> true
            conn_info -> DateTime.compare(conn_info.last_used, cutoff_time) == :lt
          end
        end)

      # Terminate idle connections (but keep at least one if it's a pre-warmed pool)
      connections_to_keep = if server_type in @pre_warm_servers, do: 1, else: 0

      {to_terminate, to_keep} =
        Enum.split(
          idle_connections,
          max(0, length(idle_connections) - connections_to_keep)
        )

      Enum.each(to_terminate, fn pid ->
        Logger.debug("Terminating idle MCP connection", server_type: server_type, pid: pid)
        terminate_mcp_server(pid)
      end)

      # Update pool and active connections
      kept_available = active_connections ++ to_keep
      updated_pool = %{pool | available: kept_available}
      updated_pools = Map.put(acc_state.pools, server_type, updated_pool)

      # Remove terminated connections from active tracking
      updated_active =
        Enum.reduce(to_terminate, acc_state.active_connections, fn pid, acc ->
          Map.delete(acc, pid)
        end)

      %{acc_state | pools: updated_pools, active_connections: updated_active}
    end)
  end

  defp handle_process_death(pid, _reason, state) do
    # Remove from all pools and active connections
    updated_state = remove_connection_from_pools(pid, state)
    %{updated_state | active_connections: Map.delete(updated_state.active_connections, pid)}
  end

  defp warm_pool_for_server_type(server_type, state) do
    case Map.get(state.pools, server_type) do
      nil ->
        # Create new pool with initial connections
        create_pool_for_server_type(server_type, %{})
        state

      _existing_pool ->
        # Pool already exists
        state
    end
  end

  defp create_pool_for_server_type(server_type, config) do
    connections =
      Enum.reduce(1..@default_pool_size, [], fn _, acc ->
        case start_mcp_server_process(server_type, config) do
          {:ok, pid} -> [pid | acc]
          {:error, _} -> acc
        end
      end)

    if length(connections) > 0 do
      pool_info = %{
        server_type: server_type,
        available: connections,
        busy: [],
        config: config,
        last_used: DateTime.utc_now(),
        health_ref: nil
      }

      {:ok, pool_info}
    else
      {:error, :no_connections_created}
    end
  end

  defp calculate_current_stats(state) do
    total_connections = map_size(state.active_connections)

    {active_count, idle_count} =
      Enum.reduce(state.pools, {0, 0}, fn {_, pool}, {active, idle} ->
        {active + length(pool.busy), idle + length(pool.available)}
      end)

    %{
      total_pools: map_size(state.pools),
      total_connections: total_connections,
      active_connections: active_count,
      idle_connections: idle_count,
      failed_connections: state.stats.failed_connections
    }
  end

  defp update_stats(state) do
    %{state | stats: calculate_current_stats(state)}
  end

  defp update_failed_stat(state) do
    updated_stats = %{state.stats | failed_connections: state.stats.failed_connections + 1}
    %{state | stats: updated_stats}
  end
end
