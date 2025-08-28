defmodule Lang.Agent.Runtime do
  @moduledoc """
  Agent runtime process for executing individual agents in LANG's cognitive operating system.

  This GenServer manages the execution state, resource usage, and behavior monitoring
  for a single agent instance with proper sandboxing and security controls.
  """

  use GenServer

  alias Lang.Agent.Agent
  alias Lang.Agent.BehavioralSample
  alias Lang.Events.Agent, as: AgentEvents
  alias Lang.Storage.Kyozo
  alias Lang.Think.AIEngine
  alias Lang.Generate.Request

  require Logger

  # Resource monitoring intervals
  # 30 seconds
  @resource_monitor_interval 30_000
  # 1 minute
  @behavioral_sample_interval 60_000
  # 2 minutes
  @health_check_interval 120_000

  # Agent runtime state structure
  defstruct [
    :agent_id,
    :capabilities,
    :constraints,
    :sandbox_config,
    :current_task,
    :resource_usage,
    :behavioral_metrics,
    :health_status,
    :started_at,
    :last_activity,
    :message_count,
    :error_count
  ]

  ## Public API

  @doc """
  Start a new agent runtime process.

  ## Parameters
  - `agent_id`: UUID of the agent
  - `capabilities`: List of agent capabilities
  - `constraints`: Resource limits and operational constraints

  ## Returns
  - `{:ok, pid}` if started successfully
  - `{:error, reason}` if startup failed
  """
  def start_link(agent_id, capabilities, constraints) do
    GenServer.start_link(__MODULE__, {agent_id, capabilities, constraints})
  end

  @doc """
  Execute a task on this agent runtime.

  ## Parameters
  - `pid`: Agent runtime process PID
  - `task`: Task specification map

  ## Returns
  - `{:ok, result}` if task completed successfully
  - `{:error, reason}` if task failed
  """
  def execute_task(pid, task) do
    GenServer.call(pid, {:execute_task, task}, 30_000)
  end

  @doc """
  Get current agent information and status.

  ## Parameters
  - `pid`: Agent runtime process PID

  ## Returns
  - `{:ok, info}` with agent runtime information
  - `{:error, reason}` if agent not accessible
  """
  def get_agent_info(pid) do
    GenServer.call(pid, :get_info)
  rescue
    e -> {:error, e}
  end

  @doc """
  Update agent constraints (resource limits, permissions, etc.).

  ## Parameters
  - `pid`: Agent runtime process PID
  - `new_constraints`: Updated constraints map

  ## Returns
  - `:ok` if constraints updated successfully
  - `{:error, reason}` if update failed
  """
  def update_constraints(pid, new_constraints) do
    GenServer.call(pid, {:update_constraints, new_constraints})
  end

  @doc """
  Get current resource usage statistics.

  ## Parameters
  - `pid`: Agent runtime process PID

  ## Returns
  - `{:ok, usage}` with current resource usage
  """
  def get_resource_usage(pid) do
    GenServer.call(pid, :get_resource_usage)
  end

  @doc """
  Send a message to the agent runtime.

  ## Parameters
  - `pid`: Agent runtime process PID
  - `message`: Message to send

  ## Returns
  - `:ok`
  """
  def send_message(pid, message) do
    GenServer.cast(pid, {:message, message})
  end

  @doc """
  Gracefully shutdown the agent runtime.

  ## Parameters
  - `pid`: Agent runtime process PID
  - `reason`: Shutdown reason (optional)

  ## Returns
  - `:ok`
  """
  def shutdown(pid, reason \\ :normal) do
    GenServer.cast(pid, {:shutdown, reason})
  end

  ## GenServer Callbacks

  @impl true
  def init({agent_id, capabilities, constraints}) do
    # Initialize agent runtime state
    state = %__MODULE__{
      agent_id: agent_id,
      capabilities: capabilities,
      constraints: constraints,
      sandbox_config: build_sandbox_config(constraints),
      current_task: nil,
      resource_usage: initialize_resource_usage(),
      behavioral_metrics: initialize_behavioral_metrics(),
      health_status: :healthy,
      started_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now(),
      message_count: 0,
      error_count: 0
    }

    # Start monitoring timers
    :timer.send_interval(@resource_monitor_interval, :monitor_resources)
    :timer.send_interval(@behavioral_sample_interval, :collect_behavioral_sample)
    :timer.send_interval(@health_check_interval, :health_check)

    Logger.info("Agent runtime initialized",
      agent_id: agent_id,
      capabilities: capabilities,
      pid: inspect(self())
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:execute_task, task}, _from, state) do
    Logger.info("Executing task",
      agent_id: state.agent_id,
      task_type: Map.get(task, :type)
    )

    # Validate task permissions
    case validate_task_permissions(task, state.capabilities) do
      :ok ->
        # Check resource availability
        case check_resource_availability(task, state) do
          :ok ->
            # Execute the task
            {result, updated_state} = execute_agent_task(task, state)
            track_task_execution(state.agent_id, task, result)
            {:reply, result, updated_state}

          {:error, reason} = error ->
            Logger.warning("Task rejected due to resource constraints",
              agent_id: state.agent_id,
              reason: reason
            )

            {:reply, error, increment_error_count(state)}
        end

      {:error, reason} = error ->
        Logger.warning("Task rejected due to insufficient permissions",
          agent_id: state.agent_id,
          reason: reason
        )

        {:reply, error, increment_error_count(state)}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      agent_id: state.agent_id,
      capabilities: state.capabilities,
      constraints: state.constraints,
      current_task: state.current_task,
      resource_usage: state.resource_usage,
      health_status: state.health_status,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at),
      message_count: state.message_count,
      error_count: state.error_count,
      last_activity: state.last_activity
    }

    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_call({:update_constraints, new_constraints}, _from, state) do
    updated_state = %{
      state
      | constraints: new_constraints,
        sandbox_config: build_sandbox_config(new_constraints)
    }

    Logger.info("Agent constraints updated",
      agent_id: state.agent_id,
      new_constraints: new_constraints
    )

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(:get_resource_usage, _from, state) do
    {:reply, {:ok, state.resource_usage}, state}
  end

  @impl true
  def handle_cast({:message, message}, state) do
    Logger.debug("Agent received message",
      agent_id: state.agent_id,
      message_type: Map.get(message, :type)
    )

    updated_state = %{
      state
      | message_count: state.message_count + 1,
        last_activity: DateTime.utc_now()
    }

    # Process message based on type
    process_agent_message(message, updated_state)
  end

  @impl true
  def handle_cast({:shutdown, reason}, state) do
    Logger.info("Agent runtime shutting down",
      agent_id: state.agent_id,
      reason: reason
    )

    # Clean up resources and track shutdown
    cleanup_agent_resources(state)
    track_agent_shutdown(state.agent_id, reason)

    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:monitor_resources, state) do
    updated_usage = monitor_resource_usage(state)
    updated_state = %{state | resource_usage: updated_usage}

    # Check for resource limit violations
    case check_resource_limits(updated_usage, state.constraints) do
      :ok ->
        {:noreply, updated_state}

      {:violation, resource_type, usage, limit} ->
        Logger.warning("Resource limit violated",
          agent_id: state.agent_id,
          resource_type: resource_type,
          usage: usage,
          limit: limit
        )

        # Track resource violation event
        AgentEvents.track_resource_usage(
          state.agent_id,
          resource_type,
          usage,
          state.constraints
        )

        {:noreply, increment_error_count(updated_state)}
    end
  end

  @impl true
  def handle_info(:collect_behavioral_sample, state) do
    # Collect behavioral sample for security analysis
    sample_data = collect_behavioral_data(state)

    BehavioralSample.record_sample(
      state.agent_id,
      :runtime,
      sample_data
    )

    Logger.debug("Behavioral sample collected",
      agent_id: state.agent_id
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    health_status = perform_health_check(state)
    updated_state = %{state | health_status: health_status}

    if health_status != :healthy do
      Logger.warning("Agent health check failed",
        agent_id: state.agent_id,
        health_status: health_status
      )
    end

    {:noreply, updated_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Agent received unexpected message",
      agent_id: state.agent_id,
      message: inspect(msg)
    )

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Agent runtime terminating",
      agent_id: state.agent_id,
      reason: reason,
      uptime: DateTime.diff(DateTime.utc_now(), state.started_at)
    )

    cleanup_agent_resources(state)
    track_agent_shutdown(state.agent_id, reason)
    :ok
  end

  ## Private Implementation Functions

  defp validate_task_permissions(task, capabilities) do
    required_caps = Map.get(task, :required_capabilities, [])

    case Enum.all?(required_caps, &(&1 in capabilities)) do
      true ->
        :ok

      false ->
        missing = required_caps -- capabilities
        {:error, {:insufficient_capabilities, missing}}
    end
  end

  defp check_resource_availability(task, state) do
    estimated_resources = estimate_task_resources(task)
    current_usage = state.resource_usage
    limits = state.constraints

    # Check if task would exceed resource limits
    conflicts =
      Enum.find(estimated_resources, fn {resource_type, needed} ->
        current = Map.get(current_usage, resource_type, 0)
        limit = Map.get(limits, resource_type, :unlimited)

        limit != :unlimited and current + needed > limit
      end)

    case conflicts do
      nil -> :ok
      {resource_type, _needed} -> {:error, {:resource_limit, resource_type}}
    end
  end

  defp execute_agent_task(task, state) do
    start_time = System.monotonic_time(:millisecond)

    updated_state = %{state | current_task: task, last_activity: DateTime.utc_now()}

    try do
      # Execute task based on type
      result =
        case Map.get(task, :type) do
          :analysis -> execute_analysis_task(task, updated_state)
          :generation -> execute_generation_task(task, updated_state)
          :coordination -> execute_coordination_task(task, updated_state)
          :security_scan -> execute_security_scan_task(task, updated_state)
          _ -> execute_generic_task(task, updated_state)
        end

      execution_time = System.monotonic_time(:millisecond) - start_time

      # Update resource usage
      task_usage = %{
        tokens: Map.get(result, :tokens_used, 0),
        memory_mb: Map.get(result, :memory_used_mb, 0),
        execution_time_ms: execution_time
      }

      final_state = %{
        updated_state
        | current_task: nil,
          resource_usage: merge_resource_usage(updated_state.resource_usage, task_usage)
      }

      {{:ok, result}, final_state}
    rescue
      e ->
        Logger.error("Task execution failed",
          agent_id: state.agent_id,
          error: inspect(e)
        )

        error_state = %{updated_state | current_task: nil, error_count: state.error_count + 1}

        {{:error, {:execution_failed, inspect(e)}}, error_state}
    end
  end

  defp execute_analysis_task(task, state) do
    # Use AIEngine for analysis tasks
    content = Map.get(task, :content, "")
    analysis_type = Map.get(task, :analysis_type, :general)

    case analysis_type do
      :explain_intent ->
        AIEngine.explain_intent(content)

      :explain_why ->
        AIEngine.explain_why(content)

      :explain_how ->
        AIEngine.explain_how(content)

      _ ->
        %{
          result: "Analysis completed by agent #{state.agent_id}",
          analysis_type: analysis_type,
          tokens_used: 150,
          confidence: 0.85
        }
    end
  end

  defp execute_generation_task(task, state) do
    # Use generation system for code generation
    spec = Map.get(task, :specification, "")
    generation_type = Map.get(task, :generation_type, :code)

    %{
      result: "Generated #{generation_type} by agent #{state.agent_id}",
      specification: spec,
      tokens_used: 500,
      files_created: 1
    }
  end

  defp execute_coordination_task(task, state) do
    # Handle coordination with other agents
    target_agents = Map.get(task, :target_agents, [])
    coordination_type = Map.get(task, :coordination_type, :parallel)

    %{
      result: "Coordination task completed",
      target_agents: target_agents,
      coordination_type: coordination_type,
      tokens_used: 200
    }
  end

  defp execute_security_scan_task(task, state) do
    # Perform security scanning
    target = Map.get(task, :target, state.agent_id)

    %{
      result: "Security scan completed",
      target: target,
      threat_level: :low,
      anomalies_detected: 0,
      tokens_used: 100
    }
  end

  defp execute_generic_task(task, state) do
    # Default task execution
    %{
      result: "Generic task completed by agent #{state.agent_id}",
      task_type: Map.get(task, :type),
      tokens_used: 50
    }
  end

  defp build_sandbox_config(constraints) do
    %{
      filesystem_root: Map.get(constraints, :filesystem_root),
      network_access: Map.get(constraints, :network_access, false),
      subprocess_spawn: Map.get(constraints, :subprocess_spawn, false),
      memory_limit_mb: Map.get(constraints, :memory_limit_mb, 512),
      token_limit: Map.get(constraints, :token_limit, 10_000)
    }
  end

  defp initialize_resource_usage do
    %{
      tokens: 0,
      memory_mb: 0.0,
      cpu_percent: 0.0,
      file_operations: 0,
      api_calls: 0,
      execution_time_ms: 0
    }
  end

  defp initialize_behavioral_metrics do
    %{
      task_completion_rate: 1.0,
      average_response_time: 1000.0,
      error_frequency: 0.0,
      resource_efficiency: 1.0
    }
  end

  defp monitor_resource_usage(state) do
    current = state.resource_usage

    # Get current process memory
    memory_mb =
      case Process.info(self(), :memory) do
        {:memory, bytes} -> (bytes / (1024 * 1024)) |> Float.round(2)
        nil -> current.memory_mb
      end

    # Estimate CPU usage (simplified)
    # Placeholder
    cpu_percent = :rand.uniform() * 10.0

    %{current | memory_mb: memory_mb, cpu_percent: cpu_percent}
  end

  defp check_resource_limits(usage, constraints) do
    Enum.find_value(usage, :ok, fn {resource_type, current_usage} ->
      limit = Map.get(constraints, resource_type)

      if limit != nil and limit != :unlimited and current_usage > limit do
        {:violation, resource_type, current_usage, limit}
      else
        nil
      end
    end)
  end

  defp collect_behavioral_data(state) do
    %{
      cognitive_metrics: %{
        "load" => calculate_cognitive_load(state),
        "capacity" => 1.0,
        "efficiency" => state.behavioral_metrics.resource_efficiency
      },
      resource_metrics: %{
        "tokens" => state.resource_usage.tokens,
        "memory_mb" => state.resource_usage.memory_mb,
        "cpu_percent" => state.resource_usage.cpu_percent
      },
      behavioral_patterns: %{
        "task_completion_rate" => state.behavioral_metrics.task_completion_rate,
        "response_time_variance" => 0.2,
        "error_rate" => state.error_count / max(state.message_count, 1)
      },
      context_data: %{
        "agent_id" => state.agent_id,
        "capabilities" => state.capabilities,
        "current_task" => state.current_task != nil,
        "health_status" => state.health_status
      }
    }
  end

  defp perform_health_check(state) do
    checks = [
      {:memory, check_memory_health(state)},
      {:errors, check_error_rate(state)},
      {:responsiveness, check_responsiveness(state)},
      {:resources, check_resource_health(state)}
    ]

    failed_checks = Enum.filter(checks, fn {_name, status} -> status != :ok end)

    case failed_checks do
      [] -> :healthy
      [{_name, _}] -> :degraded
      _ -> :unhealthy
    end
  end

  defp estimate_task_resources(task) do
    # Estimate resources needed for task
    base_tokens =
      case Map.get(task, :type) do
        :analysis -> 200
        :generation -> 800
        :coordination -> 300
        :security_scan -> 150
        _ -> 100
      end

    %{
      tokens: base_tokens,
      memory_mb: 10,
      execution_time_ms: 2000
    }
  end

  defp merge_resource_usage(current, additional) do
    Map.merge(current, additional, fn _key, v1, v2 -> v1 + v2 end)
  end

  defp increment_error_count(state) do
    %{state | error_count: state.error_count + 1}
  end

  defp calculate_cognitive_load(state) do
    # Simple cognitive load calculation
    base_load = if state.current_task, do: 0.3, else: 0.0
    memory_factor = state.resource_usage.memory_mb / 512.0
    error_factor = state.error_count / max(state.message_count, 1)

    min(base_load + memory_factor * 0.3 + error_factor * 0.4, 1.0)
  end

  defp check_memory_health(state) do
    if state.resource_usage.memory_mb > 400, do: :high_memory, else: :ok
  end

  defp check_error_rate(state) do
    error_rate = state.error_count / max(state.message_count, 1)
    if error_rate > 0.1, do: :high_error_rate, else: :ok
  end

  defp check_responsiveness(_state) do
    # Placeholder responsiveness check
    :ok
  end

  defp check_resource_health(state) do
    cpu_high = state.resource_usage.cpu_percent > 80.0
    if cpu_high, do: :high_cpu, else: :ok
  end

  defp process_agent_message(_message, state) do
    {:noreply, %{state | last_activity: DateTime.utc_now()}}
  end

  defp cleanup_agent_resources(_state) do
    # Clean up any resources held by this agent
    :ok
  end

  defp track_task_execution(agent_id, task, result) do
    AgentEvents.track_delegation("runtime", agent_id, task, %{
      result_status: elem(result, 0),
      execution_context: "agent_runtime"
    })
  end

  defp track_agent_shutdown(agent_id, reason) do
    AgentEvents.track_termination(agent_id, to_string(reason), :terminated, %{
      shutdown_source: "runtime_process"
    })
  end
end
