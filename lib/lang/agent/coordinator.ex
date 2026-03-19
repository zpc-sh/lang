defmodule Lang.Agent.Coordinator do
  @moduledoc "Multi-agent coordination strategies and merging."

  alias Lang.Agent.Lifecycle
  alias Lang.Agent.Agent
  alias Lang.Events.Agent, as: AgentEvents
  alias Lang.InMemory.Store

  @doc """
  Coordinates a task across multiple agents using a specified strategy.

  ## Parameters
    - `agent_ids`: A list of agent IDs to coordinate.
    - `task`: A map describing the task to be performed.
    - `strategy`: The coordination strategy to use. Can be `:fanout`, `:first_success`, or `:map_reduce`. Defaults to `:fanout`.

  ## Strategies
    - `:fanout`: Delegates the task to all agents in parallel and merges the results.
    - `:first_success`: Delegates the task to agents sequentially until one succeeds.
    - `:map_reduce`: Delegates the task to all agents in parallel and then reduces the results.
  """
  def coordinate(agent_ids, task, strategy \\ :fanout) do
    # Prefer certain agents based on task characteristics (e.g., prefer "codex" for compute-heavy)
    agent_ids = prefer_agents(agent_ids, task)

    case strategy do
      :fanout ->
        delegate_fun = Map.get(task, :delegate_fun, &Lifecycle.delegate/2)

        results = 
          agent_ids
          |> Task.async_stream(fn id -> {id, delegate_fun.(id, task)} end, timeout: 30_000)
          |> Enum.map(&unwrap_result/1)

        merged = 
          merge_results(Enum.map(results, fn {id, res} -> %{agent_id: id, result: res} end))

        AgentEvents.track_coordination("coordinator", agent_ids, task, %{strategy: strategy})
        _ = save_summary(agent_ids, task, %{strategy: strategy, merged: merged})
        {:ok, %{results: results, merged: merged}}

      :first_success ->
        delegate_fun = Map.get(task, :delegate_fun, &Lifecycle.delegate/2)
        {results, winner} = try_until_success(agent_ids, task, delegate_fun)

        merged = 
          merge_results(Enum.map(results, fn {id, res} -> %{agent_id: id, result: res} end))

        AgentEvents.track_coordination("coordinator", agent_ids, task, %{
          strategy: strategy,
          winner: winner
        })

        _ = save_summary(agent_ids, task, %{strategy: strategy, merged: merged, winner: winner})
        {:ok, %{results: results, merged: merged, winner: winner}}

      :map_reduce ->
        delegate_fun = Map.get(task, :delegate_fun, &Lifecycle.delegate/2)
        reduce_fun = Map.get(task, :reduce_fun)

        results = 
          agent_ids
          |> Task.async_stream(fn id -> {id, delegate_fun.(id, task)} end, timeout: 30_000)
          |> Enum.map(&unwrap_result/1)

        base = map_reduce_merge(results)

        merged = 
          case reduce_fun do
            fun when is_function(fun, 1) -> Map.put(base, :reduced, fun.(base[:merged_payloads]))
            _ -> base
          end

        AgentEvents.track_coordination("coordinator", agent_ids, task, %{strategy: strategy})
        _ = save_summary(agent_ids, task, %{strategy: strategy, merged: merged})
        {:ok, %{results: results, merged: merged}}
    end
  end

  @doc """
  Merges the results from multiple agent executions.
  """
  def merge_results(results) when is_list(results) do
    successes = Enum.filter(results, &match?(%{result: {:ok, _}}, &1))
    errors = Enum.filter(results, &match?(%{result: {:error, _}}, &1))

    %{ 
      total: length(results),
      success: length(successes),
      errors: length(errors)
    }
  end

  @doc """
  Saves a summary of the coordination task.
  """
  # Persistence of summaries (in-memory)
  def save_summary(agent_ids, task, summary) do
    # Try DB persistence first
    case Lang.Agent.CoordinationSummary.record(agent_ids, task, summary) do
      {:ok, _rec} ->
        :ok

      _ ->
        key = coordination_key(agent_ids, task)
        Store.put(:agent_coordination, key, %{summary: summary, at: DateTime.utc_now()})
    end
  end

  @doc """
  Gets the summary of a coordination task.
  """
  def get_summary(agent_ids, task) do
    key = coordination_key(agent_ids, task)
    Store.get(:agent_coordination, key)
  end

  defp coordination_key(agent_ids, task) do
    task_fingerprint = :erlang.phash2(Map.take(task, [:type, :goal, :strategy]))
    {Enum.sort(agent_ids), task_fingerprint}
  end

  defp unwrap_result({:ok, {id, {:ok, res}}}), do: {id, {:ok, res}}
  defp unwrap_result({:ok, {id, {:error, reason}}}), do: {id, {:error, reason}}
  defp unwrap_result(_), do: {nil, {:error, :failed}}

  defp try_until_success(agent_ids, task, delegate_fun) do
    Enum.reduce_while(agent_ids, {[], nil}, fn id, {acc, _} ->
      case delegate_fun.(id, task) do
        {:ok, res} -> {:halt, {acc ++ [{id, {:ok, res}}], id}}
        {:error, reason} -> {:cont, {acc ++ [{id, {:error, reason}}], nil}}
      end
    end)
  end

  # Preference heuristics ------------------------------------------------------
  # Prefer agents suited for compute-heavy tasks (e.g., a "codex" agent).
  defp prefer_agents(agent_ids, task) when is_list(agent_ids) and is_map(task) do
    cond do
      compute_heavy?(task) ->
        scored =
          Enum.map(agent_ids, fn id ->
            score = agent_score_for_compute(id)
            {id, score}
          end)

        scored
        |> Enum.sort_by(fn {_id, score} -> -score end)
        |> Enum.map(&elem(&1, 0))

      coordination_heavy?(task) ->
        scored =
          Enum.map(agent_ids, fn id ->
            score = agent_score_for_coordination(id)
            {id, score}
          end)

        scored
        |> Enum.sort_by(fn {_id, score} -> -score end)
        |> Enum.map(&elem(&1, 0))

      true ->
        agent_ids
    end
  end

  defp prefer_agents(agent_ids, _task), do: agent_ids

  defp compute_heavy?(task) do
    type = Map.get(task, :type)
    analysis_type = Map.get(task, :analysis_type)
    goal = Map.get(task, :goal, "") |> to_string()

    cond do
      type in [:generation, :security_scan] -> true
      analysis_type in [:mathematical_modeling, :performance_modeling, :optimization] -> true
      String.contains?(String.downcase(goal), "optimiz") -> true
      true -> false
    end
  end

  defp agent_score_for_compute(agent_id) do
    case Agent.read_by_id(agent_id) do
      {:ok, agent} ->
        name = (agent.name || "") |> String.downcase()
        caps = MapSet.new(agent.capabilities || [])

        base = 0
        base = if String.contains?(name, "codex"), do: base + 100, else: base
        base = if :single_file_edit in caps, do: base + 20, else: base
        base = if :analysis in caps, do: base + 10, else: base
        base

      _ ->
        0
    end
  end

  defp coordination_heavy?(task) do
    type = Map.get(task, :type)
    strategy = Map.get(task, :strategy)
    type == :coordination or strategy in [:fanout, :map_reduce]
  end

  defp agent_score_for_coordination(agent_id) do
    case Agent.read_by_id(agent_id) do
      {:ok, agent} ->
        name = (agent.name || "") |> String.downcase()
        caps = MapSet.new(agent.capabilities || [])

        base = 0
        base = if String.contains?(name, "claude"), do: base + 100, else: base
        base = if :multi_file_coordination in caps, do: base + 30, else: base
        base = if :analysis in caps, do: base + 10, else: base
        base

      _ ->
        0
    end
  end

  defp map_reduce_merge(results) do
    # Aggregate by outcome
    totals = merge_results(Enum.map(results, fn {id, res} -> %{agent_id: id, result: res} end))
    # Collect only successful payloads (if they are maps)
    payloads =
      results
      |> Enum.flat_map(fn
        {_id, {:ok, %{} = map}} -> [map]
        {_id, {:ok, other}} when is_list(other) -> other
        _ -> []
      end)

    %{totals: totals, merged_payloads: payloads}
  end
end
