defmodule Lang.Agent.Supervisor do
  @moduledoc """
  Supervisor for managing agent runtime processes in LANG's cognitive operating system.

  This supervisor manages the lifecycle of agent runtime processes, ensuring proper
  isolation, resource management, and clean shutdown of agents.
  """

  use DynamicSupervisor

  alias Lang.Agent.Runtime
  alias Lang.Events.Agent, as: AgentEvents

  require Logger

  @name __MODULE__

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: @name)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 3, max_seconds: 5)
  end

  @doc """
  Start a new agent runtime process with specified capabilities and constraints.

  ## Parameters
  - `agent_id`: UUID of the agent
  - `capabilities`: List of agent capabilities
  - `constraints`: Resource limits and operational constraints

  ## Returns
  - `{:ok, pid}` if agent started successfully
  - `{:error, reason}` if agent failed to start
  """
  def start_agent(agent_id, capabilities, constraints) do
    agent_spec = %{
      id: agent_id,
      start: {Runtime, :start_link, [agent_id, capabilities, constraints]},
      restart: :temporary,
      shutdown: 5000,
      type: :worker
    }

    case DynamicSupervisor.start_child(@name, agent_spec) do
      {:ok, pid} ->
        Logger.info("Agent runtime started",
          agent_id: agent_id,
          pid: inspect(pid),
          capabilities: capabilities
        )

        # Track agent runtime start event
        AgentEvents.track_spawn(agent_id, capabilities, constraints, %{
          runtime_pid: inspect(pid),
          supervisor: @name
        })

        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.info("Agent runtime already running",
          agent_id: agent_id,
          pid: inspect(pid)
        )

        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start agent runtime",
          agent_id: agent_id,
          reason: reason
        )

        error
    end
  end

  @doc """
  Stop an agent runtime process gracefully.

  ## Parameters
  - `agent_id`: UUID of the agent to stop

  ## Returns
  - `:ok` if agent stopped successfully
  - `{:error, reason}` if agent failed to stop or not found
  """
  def stop_agent(agent_id) do
    case find_agent_process(agent_id) do
      {:ok, pid} ->
        case DynamicSupervisor.terminate_child(@name, pid) do
          :ok ->
            Logger.info("Agent runtime stopped",
              agent_id: agent_id,
              pid: inspect(pid)
            )

            :ok

          {:error, reason} = error ->
            Logger.error("Failed to stop agent runtime",
              agent_id: agent_id,
              pid: inspect(pid),
              reason: reason
            )

            error
        end

      {:error, :not_found} ->
        Logger.warning("Agent runtime not found",
          agent_id: agent_id
        )

        {:error, :agent_not_running}
    end
  end

  @doc """
  Get the runtime status of an agent.

  ## Parameters
  - `agent_id`: UUID of the agent

  ## Returns
  - `{:ok, status}` with runtime information
  - `{:error, reason}` if agent not found
  """
  def get_agent_status(agent_id) do
    case find_agent_process(agent_id) do
      {:ok, pid} ->
        status = %{
          agent_id: agent_id,
          pid: inspect(pid),
          status: :running,
          memory_mb: get_process_memory(pid),
          message_queue_len: get_message_queue_length(pid),
          uptime_seconds: get_process_uptime(pid)
        }

        {:ok, status}

      {:error, :not_found} ->
        {:error, :agent_not_running}
    end
  end

  @doc """
  List all currently running agent processes.

  ## Returns
  - List of agent runtime information
  """
  def list_running_agents do
    DynamicSupervisor.which_children(@name)
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      case Runtime.get_agent_info(pid) do
        {:ok, info} -> info
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Find the runtime pid for a given `agent_id`.

  Returns `{:ok, pid}` or `{:error, :not_found}`.
  """
  def find_agent_pid(agent_id) do
    DynamicSupervisor.which_children(@name)
    |> Enum.find_value(fn {id, pid, _type, _modules} ->
      if id == agent_id and Process.alive?(pid) do
        {:ok, pid}
      else
        nil
      end
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  end

  @doc """
  Get count of currently running agents.

  ## Returns
  - Integer count of running agents
  """
  def count_running_agents do
    DynamicSupervisor.count_children(@name).active
  end

  @doc """
  Restart an agent runtime process.

  ## Parameters
  - `agent_id`: UUID of the agent to restart

  ## Returns
  - `{:ok, new_pid}` if agent restarted successfully
  - `{:error, reason}` if restart failed
  """
  def restart_agent(agent_id) do
    with {:ok, old_pid} <- find_agent_process(agent_id),
         {:ok, info} <- Runtime.get_agent_info(old_pid),
         :ok <- stop_agent(agent_id),
         {:ok, new_pid} <-
           start_agent(agent_id, info.capabilities, info.constraints) do
      Logger.info("Agent runtime restarted",
        agent_id: agent_id,
        old_pid: inspect(old_pid),
        new_pid: inspect(new_pid)
      )

      {:ok, new_pid}
    else
      {:error, reason} = error ->
        Logger.error("Failed to restart agent runtime",
          agent_id: agent_id,
          reason: reason
        )

        error
    end
  end

  @doc """
  Gracefully shutdown all agent runtime processes.

  ## Parameters
  - `timeout`: Timeout in milliseconds for shutdown (default: 10 seconds)

  ## Returns
  - `:ok` when all agents are shutdown
  """
  def shutdown_all_agents(timeout \\ 10_000) do
    running_agents = list_running_agents()
    agent_count = length(running_agents)

    Logger.info("Shutting down all agent runtimes",
      agent_count: agent_count,
      timeout: timeout
    )

    # Stop all agents concurrently
    shutdown_tasks =
      Enum.map(running_agents, fn agent_info ->
        Task.async(fn ->
          case stop_agent(agent_info.agent_id) do
            :ok -> {:ok, agent_info.agent_id}
            error -> {:error, agent_info.agent_id, error}
          end
        end)
      end)

    # Wait for all shutdowns to complete
    results = Task.await_many(shutdown_tasks, timeout)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = agent_count - successful

    if failed > 0 do
      Logger.warning("Some agents failed to shutdown gracefully",
        successful: successful,
        failed: failed
      )
    else
      Logger.info("All agent runtimes shutdown successfully",
        agent_count: agent_count
      )
    end

    :ok
  end

  @doc """
  Send a message to a specific agent runtime process.

  ## Parameters
  - `agent_id`: UUID of the target agent
  - `message`: Message to send to the agent

  ## Returns
  - `:ok` if message sent successfully
  - `{:error, reason}` if agent not found or message failed
  """
  def send_message_to_agent(agent_id, message) do
    case find_agent_process(agent_id) do
      {:ok, pid} ->
        GenServer.cast(pid, {:message, message})
        :ok

      {:error, :not_found} ->
        {:error, :agent_not_running}
    end
  end

  @doc """
  Monitor agent resource usage across all running agents.

  ## Returns
  - Map of resource usage statistics
  """
  def get_resource_usage_stats do
    running_agents = list_running_agents()

    total_memory =
      Enum.reduce(running_agents, 0, fn agent, acc ->
        case get_agent_status(agent.agent_id) do
          {:ok, status} -> acc + status.memory_mb
          _ -> acc
        end
      end)

    %{
      total_agents: length(running_agents),
      total_memory_mb: total_memory,
      average_memory_mb:
        if(length(running_agents) > 0, do: total_memory / length(running_agents), else: 0),
      supervisor_pid: inspect(Process.whereis(@name))
    }
  end

  # Private helper functions

  defp find_agent_process(agent_id) do
    DynamicSupervisor.which_children(@name)
    |> Enum.find_value(fn {id, pid, _type, _modules} ->
      if id == agent_id and Process.alive?(pid) do
        {:ok, pid}
      else
        nil
      end
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  end

  defp get_process_memory(pid) do
    case Process.info(pid, :memory) do
      {:memory, bytes} -> (bytes / (1024 * 1024)) |> Float.round(2)
      nil -> 0.0
    end
  end

  defp get_message_queue_length(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      nil -> 0
    end
  end

  defp get_process_uptime(pid) do
    case Process.info(pid, :registered_name) do
      nil ->
        # Calculate uptime based on process creation time
        # This is approximate since we don't store exact start time
        0

      _ ->
        # Would need to track start times for accurate uptime
        0
    end
  end
end
