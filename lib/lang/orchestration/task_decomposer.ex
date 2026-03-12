defmodule Lang.Orchestration.TaskDecomposer do
  @moduledoc """
  Task decomposition engine for LANG's multi-agent orchestration.

  Analyzes complex tasks, breaks them into subtasks, assigns agents based on capabilities,
  and generates execution plans. Follows LANG guidelines: uses Ash for queries, integrates
  with PubSub for updates, and avoids long-running processes.
  """

  alias Lang.Agent.Capabilities
  # Assuming this exists from planning
  alias Lang.Orchestration.CommunicationHub
  require Logger

  @task_complexity_keywords %{
    simple: ~w(basic explain describe list),
    complex: ~w(optimize analyze refactor design implement),
    specialized: ~w(performance security mathematical database crypto)
  }

  @doc """
  Analyzes a task request and returns an execution strategy.

  Returns:
  - {:single_agent, agent_id} for simple tasks
  - {:multi_agent, execution_plan} for complex tasks
  - {:specialized, [agent_ids]} for specialized tasks
  """
  def analyze_task(human_request, context \\ %{}) do
    complexity = classify_task_complexity(human_request)

    case complexity do
      :simple -> {:single_agent, :claude}
      :complex -> decompose_complex_task(human_request, context)
      :specialized -> identify_specialist_agents(human_request)
    end
  end

  defp classify_task_complexity(request) do
    words = String.downcase(request) |> String.split(~r/\s+/)

    cond do
      Enum.any?(words, &(&1 in @task_complexity_keywords.specialized)) -> :specialized
      Enum.any?(words, &(&1 in @task_complexity_keywords.complex)) -> :complex
      true -> :simple
    end
  end

  defp decompose_complex_task(request, context) do
    subtasks = extract_subtasks(request)
    agent_assignments = assign_agents_to_subtasks(subtasks)
    execution_plan = create_execution_plan(agent_assignments, context)

    {:multi_agent, execution_plan}
  end

  defp extract_subtasks(request) do
    # Simple keyword-based extraction; could be enhanced with NLP via a provider
    case classify_task_complexity(request) do
      :complex ->
        # Example: Break "Optimize codebase" into profile, analyze, recommend
        [
          %{id: 1, type: :profile_system, description: "Profile performance"},
          %{id: 2, type: :analyze_data, description: "Analyze profiling data", depends_on: [1]},
          %{
            id: 3,
            type: :generate_recommendations,
            description: "Generate optimizations",
            depends_on: [2]
          }
        ]

      _ ->
        []
    end
  end

  defp assign_agents_to_subtasks(subtasks) do
    Enum.map(subtasks, fn subtask ->
      matching_agents = find_agents_for_task(subtask.type)
      best_agent = select_best_agent(matching_agents, subtask)
      {subtask.id, best_agent}
    end)
  end

  defp find_agents_for_task(task_type) do
    # Use the registry to find agents with matching capabilities
    all_caps = Capabilities.all_agent_capabilities()

    Enum.filter(all_caps, fn {_, caps} ->
      Enum.any?(caps, &task_matches_capability?(&1, task_type))
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp task_matches_capability?(cap, task_type) do
    # Simple matching; extend as needed
    case task_type do
      :performance_analysis -> cap in [:performance, :optimization]
      :mathematical_optimization -> cap in [:mathematics, :algorithm_design]
      _ -> false
    end
  end

  defp select_best_agent(agents, _subtask) do
    # For now, pick first or specific; could use proficiency scores
    case agents do
      # Fallback
      [] -> :claude
      [agent | _] -> agent
    end
  end

  defp create_execution_plan(assignments, context) do
    # Generate plan with parallel/sequential based on dependencies
    %{
      assignments: assignments,
      context: context,
      # Seconds, placeholder
      estimated_time: length(assignments) * 30,
      parallel_tasks: Enum.filter(assignments, &no_dependencies?/1),
      sequential_tasks: Enum.filter(assignments, &has_dependencies?/1)
    }
  end

  # Placeholder; check subtask deps
  defp no_dependencies?({_, _}), do: true
  defp has_dependencies?({_, _}), do: false

  defp identify_specialist_agents(request) do
    # Match keywords to specialists
    words = String.downcase(request) |> String.split(~r/\s+/)

    agents =
      cond do
        "mathematical" in words -> [:qwen]
        "performance" in words -> [:performance_agent, :qwen]
        "security" in words -> [:security_agent]
        true -> []
      end

    {:specialized, agents}
  end

  @doc """
  Example usage: Decompose and delegate a task.
  """
  def example_decompose_and_delegate(request) do
    case analyze_task(request) do
      {:multi_agent, plan} ->
        # Delegate via CommunicationHub
        Enum.each(plan.assignments, fn {subtask_id, agent} ->
          CommunicationHub.send_task_to_agent("claude", agent, %{subtask_id: subtask_id})
        end)

        {:ok, plan}

      _ ->
        {:error, :unsupported}
    end
  end
end
