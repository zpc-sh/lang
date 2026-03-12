defmodule Lang.Agent.Trust do
  @moduledoc "Trust score helpers for agents."

  alias Lang.Agent.Agent
  alias Lang.Events.Agent, as: AgentEvents

  def update_trust(agent_id, new_score, reason \\ "update") do
    with {:ok, agent} <- Agent.read_by_id(agent_id),
         {:ok, updated} <-
           agent
           |> Ash.Changeset.for_update(:update_trust_score, %{
             new_score: Decimal.from_float(new_score),
             reason: reason
           })
           |> Ash.update() do
      AgentEvents.track_trust_update(
        agent_id,
        agent.trust_score,
        updated.trust_score,
        reason,
        %{}
      )

      {:ok, updated}
    else
      nil -> {:error, :not_found}
      {:error, _} = err -> err
    end
  end
end
