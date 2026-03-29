defmodule Lang.Agent.Lifecycle do
  @moduledoc """
  Lifecycle operations for agents: spawn, delegate, coordinate, merge, terminate, status.

  This module bridges LSP dispatch to Ash resources and runtime processes managed
  by `Lang.Agent.Supervisor` and `Lang.Agent.Runtime`.
  """

  alias Lang.Agent.Agent
  alias Lang.Agent.Supervisor, as: AgentSup
  alias Lang.Agent.Runtime
  alias Lang.Events.Agent, as: AgentEvents

  require Logger

  @doc """
  Spawn a new agent and start its runtime.
  """
  def spawn(capabilities, constraints, ctx \\ %{})
      when is_list(capabilities) and is_map(constraints) do
    attrs = %{
      capabilities: capabilities,
      constraints: constraints,
      session_id: Map.get(ctx, :session_id),
      spawned_by: Map.get(ctx, :spawned_by, "system"),
      sandbox_config: Map.get(ctx, :sandbox_config, %{}),
      metadata: Map.get(ctx, :metadata, %{})
    }

    with {:ok, agent} <- Agent.spawn(attrs),
         {:ok, _pid} <- AgentSup.start_agent(agent.id, capabilities, constraints) do
      {:ok, agent}
    else
      {:error, reason} = err ->
        Logger.error("Failed to spawn agent", reason: inspect(reason))
        err
    end
  end

  @doc """
  Delegate a task to an agent.
  """
  def delegate(agent_id, task) when is_binary(agent_id) and is_map(task) do
    with {:ok, pid} <- find_agent_pid(agent_id) do
      AgentEvents.track_delegation("lsp", agent_id, task)
      Runtime.execute_task(pid, atomize_keys(task))
    else
      {:error, :not_found} -> {:error, :agent_not_running}
      other -> other
    end
  end

  @doc """
  Coordinate a task across multiple agents and return aggregated result.
  """
  def coordinate(agent_ids, task) when is_list(agent_ids) and is_map(task) do
    task = atomize_keys(task)
    strategy = Map.get(task, :strategy, :fanout)

    case Lang.Agent.Coordinator.coordinate(agent_ids, task, strategy) do
      {:ok, %{results: _} = res} -> {:ok, res}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Merge multiple agent results into a single summary.
  """
  def merge_results(results) when is_list(results) do
    {:ok, do_merge_results(results)}
  end

  @doc """
  Terminate an agent and stop its runtime.
  """
  def terminate(agent_id, reason \\ "normal") when is_binary(agent_id) do
    with {:ok, agent} <- Agent.read_by_id(agent_id),
         {:ok, final} <- Agent.terminate(agent, %{reason: reason}),
         :ok <- AgentSup.stop_agent(agent_id) do
      AgentEvents.track_termination(agent_id, reason, :terminated)
      {:ok, %{agent_id: agent_id, state: :terminated, reason: reason, metadata: final.metadata}}
    else
      {:error, _} = err -> err
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Get current status of an agent combining DB and runtime info.
  """
  def get_status(agent_id) when is_binary(agent_id) do
    db = Agent.read_by_id(agent_id)

    runtime =
      case AgentSup.get_agent_status(agent_id) do
        {:ok, status} -> status
        _ -> %{status: :stopped}
      end

    case db do
      {:ok, agent} ->
        {:ok,
         %{
           agent_id: agent.id,
           state: agent.state,
           trust_score: agent.trust_score,
           capability_track: agent.capability_track,
           runtime: runtime
         }}

      _ ->
        {:ok, %{agent_id: agent_id, state: :unknown, runtime: runtime}}
    end
  end

  # Internal helpers
  defp find_agent_pid(agent_id) do
    DynamicSupervisor.which_children(Lang.Agent.Supervisor)
    |> Enum.find_value(fn {id, pid, _type, _mods} -> if id == agent_id, do: pid, else: nil end)
    |> case do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp do_merge_results(results) do
    # Produce a lightweight summary
    success = Enum.count(results, &match?(%{result: {:ok, _}}, &1))
    errors = Enum.count(results, &match?(%{result: {:error, _}}, &1))

    %{
      total: length(results),
      success: success,
      errors: errors
    }
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key =
        if is_binary(k) do
          try do
            String.to_existing_atom(k)
          rescue
            ArgumentError -> k
          end
        else
          k
        end

      val = if is_map(v), do: atomize_keys(v), else: v
      {key, val}
    end)
  end
end
