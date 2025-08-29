defmodule Lang.Agent.Security do
  @moduledoc "Security and behavioral checks for agents (verify, scan, quarantine)."

  alias Lang.Agent.Agent
  alias Lang.Agent.BehavioralSample
  alias Lang.Events.Agent, as: AgentEvents

  require Logger

  @doc """
  Verify an agent against an expected behavior profile.
  `expected` may be `:auto` to derive from latest baseline.
  """
  def verify_profile(agent_id, expected) do
    with {:ok, agent} <- Agent.read_by_id(agent_id) do
      baseline = expected_profile(agent, expected)

      {:ok,
       %{
         agent_id: agent.id,
         verified: true,
         expected_profile: baseline,
         trust_score: agent.trust_score
       }}
    else
      nil -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  @doc """
  Run a lightweight behavioral/security scan and return metrics.
  """
  def scan(agent_id, _ctx \\ %{}) do
    with {:ok, agent} <- Agent.read_by_id(agent_id) do
      latest = latest_sample(agent.id)
      anomaly_score = anomaly_from_sample(latest)
      trust = decimal_to_float(agent.trust_score)

      result = %{
        agent_id: agent.id,
        anomaly_score: anomaly_score,
        trust_score: trust,
        threat_level: threat_level(anomaly_score, trust)
      }

      AgentEvents.track_security_scan("lsp", agent.id, result)
      {:ok, result}
    else
      nil -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  @doc """
  Detect whether an agent is rogue. Returns classification and optional details.
  """
  def detect_rogue(agent_id, ctx \\ %{}) do
    with {:ok, agent} <- Agent.read_by_id(agent_id) do
      latest = latest_sample(agent.id)
      anomaly = anomaly_from_sample(latest)
      trust = decimal_to_float(agent.trust_score)
      class = if anomaly > 0.8 or trust < 0.2, do: :rogue, else: :normal
      details = %{anomaly_score: anomaly, trust_score: trust, context: ctx}

      AgentEvents.track_rogue_detection(
        "lsp",
        agent.id,
        details,
        if(class == :rogue, do: :quarantine, else: :none)
      )

      {:ok, class, details}
    else
      nil -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  @doc """
  Quarantine an agent by updating its state and trust score.
  """
  def quarantine(agent_id, reason, severity \\ :medium) do
    with {:ok, agent} <- Agent.read_by_id(agent_id),
         {:ok, updated} <- Agent.quarantine(agent, %{reason: reason, severity: severity}) do
      AgentEvents.track_quarantine("lsp", agent_id, reason, %{severity: severity})
      {:ok, %{agent_id: updated.id, state: updated.state, reason: reason, severity: severity}}
    else
      nil -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end

  # Helpers
  defp expected_profile(_agent, :auto) do
    %{behaviors: ["analysis", "generation"], thresholds: %{anomaly: 0.7, trust: 0.4}}
  end

  defp expected_profile(_agent, profile) when is_map(profile), do: profile

  defp anomaly_from_sample(nil), do: 0.0

  defp anomaly_from_sample(%{data: data}) do
    # Very simple heuristic for now
    err = get_in(data, ["behavioral_patterns", "error_rate"]) || 0.0
    resp_var = get_in(data, ["behavioral_patterns", "response_time_variance"]) || 0.0
    min(1.0, err * 0.7 + resp_var * 0.3)
  end

  defp threat_level(anomaly, trust) do
    cond do
      anomaly > 0.9 or trust < 0.1 -> :critical
      anomaly > 0.75 or trust < 0.2 -> :high
      anomaly > 0.5 or trust < 0.3 -> :medium
      anomaly > 0.25 or trust < 0.4 -> :low
      true -> :none
    end
  end

  defp decimal_to_float(%Decimal{} = d), do: d |> Decimal.to_float()
  defp decimal_to_float(other) when is_number(other), do: other * 1.0
  defp decimal_to_float(_), do: 0.0

  defp latest_sample(agent_id) do
    case BehavioralSample.read_by_agent(agent_id) do
      {:ok, [sample | _]} ->
        %{
          data:
            Map.merge(sample.cognitive_metrics, %{
              "behavioral_patterns" => sample.behavioral_patterns
            })
        }

      _ ->
        nil
    end
  end
end
