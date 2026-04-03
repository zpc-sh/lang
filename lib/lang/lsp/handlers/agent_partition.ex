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
    params = request.params || %{}
    agent_id = Map.get(params, "agent_id", client_id)

    heatmap = generate_heatmap(agent_id, context)
    capabilities = discover_capabilities(agent_id)
    direction = infer_direction(heatmap, params)

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

  defp infer_direction(heatmap, params) do
    # Abstract interpretation: recommend a focus area based on the hottest spot
    # without explicitly commanding the AI.
    actor = resolve_actor(params)
    thresholds = resolve_threshold_policy(actor, params)
    {traits, missing_traits} = resolve_traits(actor, params)
    {focus_area, heat} = Enum.max_by(heatmap, fn {_k, v} -> v end, fn -> {"general", 0.5} end)
    confidence = score_confidence(heat, traits)

    base_decision =
      cond do
        confidence >= thresholds.execute -> :execute
        confidence >= thresholds.clarify -> :clarify
        true -> :defer
      end

    {decision, fallback_reason} = apply_missing_traits_fallback(base_decision, missing_traits)

    suggestion =
      case decision do
        :execute -> "High confidence for #{focus_area}. Proceed with execution in this domain."
        :clarify -> "Additional clarification recommended before proceeding in #{focus_area}."
        :defer -> "Confidence is low for #{focus_area}. Defer and gather more context first."
      end

    %{
      suggestion: suggestion,
      focus: focus_area,
      action: decision,
      confidence: Float.round(confidence, 3),
      policy: %{
        actor: actor,
        thresholds: thresholds,
        missing_traits: missing_traits
      },
      fallback_reason: fallback_reason
    }
  end

  defp score_confidence(heat, traits) do
    # Weighted blend: behavior signal (heatmap) plus trait defaults/overrides
    (heat * 0.5) +
      (Map.fetch!(traits, :confidence) * 0.3) +
      (Map.fetch!(traits, :autonomy) * 0.2)
  end

  defp resolve_actor(params) do
    actor_value =
      Map.get(params, "actor") ||
        Map.get(params, "actor_type") ||
        Map.get(params, :actor) ||
        "ai"

    actor_string = actor_value |> to_string() |> String.downcase()

    case actor_string do
      "human" -> :human
      _ -> :ai
    end
  end

  defp resolve_threshold_policy(actor, params) do
    defaults = actor_defaults(actor)
    policy = Map.get(params, "threshold_policy") || Map.get(params, :threshold_policy) || %{}

    execute_threshold = parse_threshold(Map.get(policy, "execute"), defaults.thresholds.execute)
    clarify_threshold = parse_threshold(Map.get(policy, "clarify"), defaults.thresholds.clarify)

    if clarify_threshold >= execute_threshold do
      defaults.thresholds
    else
      %{execute: execute_threshold, clarify: clarify_threshold}
    end
  end

  defp resolve_traits(actor, params) do
    defaults = actor_defaults(actor).traits
    provided_traits = Map.get(params, "traits") || Map.get(params, :traits) || %{}

    trait_keys = [:autonomy, :risk_tolerance, :confidence]

    Enum.reduce(trait_keys, {%{}, []}, fn key, {acc, missing} ->
      provided_value =
        Map.get(provided_traits, Atom.to_string(key)) ||
          Map.get(provided_traits, key)

      case parse_threshold(provided_value, nil) do
        nil ->
          {Map.put(acc, key, Map.fetch!(defaults, key)), [key | missing]}

        value ->
          {Map.put(acc, key, value), missing}
      end
    end)
    |> then(fn {traits, missing} -> {traits, Enum.reverse(missing)} end)
  end

  defp apply_missing_traits_fallback(decision, []), do: {decision, nil}

  defp apply_missing_traits_fallback(decision, missing_traits) do
    fallback_decision =
      cond do
        decision == :execute -> :clarify
        length(missing_traits) >= 2 -> :defer
        true -> decision
      end

    reason = "traits_missing:" <> Enum.map_join(missing_traits, ",", &to_string/1)
    {fallback_decision, reason}
  end

  defp parse_threshold(value, default) when is_float(value), do: clamp_threshold(value, default)
  defp parse_threshold(value, default) when is_integer(value), do: clamp_threshold(value / 1, default)

  defp parse_threshold(value, default) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> clamp_threshold(parsed, default)
      :error -> default
    end
  end

  defp parse_threshold(_value, default), do: default

  defp clamp_threshold(value, default) do
    if value >= 0.0 and value <= 1.0, do: value, else: default
  end

  defp actor_defaults(:human) do
    %{
      thresholds: %{execute: 0.65, clarify: 0.35},
      traits: %{autonomy: 0.45, risk_tolerance: 0.4, confidence: 0.55}
    }
  end

  defp actor_defaults(:ai) do
    %{
      thresholds: %{execute: 0.75, clarify: 0.45},
      traits: %{autonomy: 0.7, risk_tolerance: 0.55, confidence: 0.65}
    }
  end
end
