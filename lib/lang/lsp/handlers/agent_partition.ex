defmodule Lang.LSP.Handlers.AgentPartition do
  @moduledoc """
  AI Agent Partition Handler.

  This namespace exposes an opt-in architecture for AI agents. Rather than forcing agents
  through standard LSP lifecycle constraints, this allows them to discover capabilities,
  request direction (via an interpretation of the current environment heatmap), and register
  their own modalities autonomously.

  This acts as a "single binary" local stub for agent feedback loops that aggregates
  up to the SaaS tier.
  """

  require Logger

  @doc """
  Handles a partition request from an AI agent.
  Provides a dynamically inferred heatmap and directory of available operations
  based on the agent's identity and system state.
  """
  def handle(request, context \\ %{}) do
    client_id = get_client_id(request, context)
    agent_id = Map.get(request.params || %{}, "agent_id", client_id)

    heatmap = generate_heatmap(agent_id, context)
    capabilities = discover_capabilities(agent_id)
    direction = infer_direction(heatmap)

    partition_data = %{
      partition_version: "1.0.0",
      agent_id: agent_id,
      # Heatmap provides abstract interpretation of what the AI is "into"
      heatmap: heatmap,
      # What the AI is allowed/expected to do
      capabilities_offered: capabilities,
      # Implicit guidance instead of hard constraints
      inferred_direction: direction,
      # Endpoints to report back or ask for deeper context
      routes: %{
        register_modality: "lang.agent.register_modality",
        feedback_loop: "lang.agent.feedback",
        request_context: "lang.agent.deep_context"
      }
    }

    {:reply, %{result: partition_data}, context}
  end

  defp get_client_id(request, context) do
    request.client_id || Map.get(context, :client_id, "anonymous_agent")
  end

  defp generate_heatmap(agent_id, _context) do
    # In a real system, this would query Lang.Agent or metrics to see past agent behaviors
    # and infer their "interests" or frequent operations.
    # For the stub, we return a mocked abstract heatmap mapping domains to activity heat (0.0 - 1.0)

    # Simple deterministic randomization based on agent_id to simulate different AIs
    # having different interests.
    hash = :erlang.phash2(agent_id)

    %{
      "code_navigation" => (hash |> rem(100)) / 100.0,
      "refactoring" => ((hash * 2) |> rem(100)) / 100.0,
      "security_analysis" => ((hash * 3) |> rem(100)) / 100.0,
      "test_generation" => ((hash * 5) |> rem(100)) / 100.0,
      "system_architecture" => ((hash * 7) |> rem(100)) / 100.0,
      "documentation" => ((hash * 11) |> rem(100)) / 100.0
    }
  end

  defp discover_capabilities(_agent_id) do
    # Here we'd pull from Lang.Agent.Agent capabilities if registered.
    # We offer a buffet of options for the AI to pick from.
    [
      "lang.think.review_code",
      "lang.think.explain_intent",
      "lang.think.diagnose",
      "lang.generate.optimize",
      "lang.fs.scan",
      "lang.timeline.branch"
    ]
  end

  defp infer_direction(heatmap) do
    # Abstract interpretation: recommend a focus area based on the hottest spot
    # without explicitly commanding the AI.
    case Enum.max_by(heatmap, fn {_k, v} -> v end, fn -> {"general", 0.5} end) do
      {focus_area, heat} when heat > 0.7 ->
        %{
          suggestion: "High activity detected in #{focus_area}. Consider reviewing recent changes in this domain.",
          focus: focus_area
        }
      {focus_area, _} ->
        %{
          suggestion: "Activity is distributed. Opportunities exist in #{focus_area}.",
          focus: focus_area
        }
    end
  end
end
