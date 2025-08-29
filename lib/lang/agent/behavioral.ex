defmodule Lang.Agent.Behavioral do
  @moduledoc "Behavioral utilities for baselines and anomaly sampling."

  alias Lang.Agent.BehavioralSample
  alias Lang.Events.Agent, as: AgentEvents

  def baseline(agent_id, baseline_data \\ %{}, context \\ %{}) do
    with {:ok, _sample} <-
           BehavioralSample
           |> Ash.Changeset.for_create(:record_baseline, %{
             agent_id: agent_id,
             baseline_data: baseline_data,
             context: context
           })
           |> Ash.create() do
      AgentEvents.track_baseline_establishment(agent_id, baseline_data, context)
      {:ok, :recorded}
    end
  end

  def record_anomaly_sample(agent_id, anomaly_data, severity \\ :medium) do
    BehavioralSample
    |> Ash.Changeset.for_create(:record_anomaly, %{
      agent_id: agent_id,
      anomaly_data: anomaly_data,
      severity: severity
    })
    |> Ash.create()
  end
end
