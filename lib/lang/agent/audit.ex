defmodule Lang.Agent.Audit do
  @moduledoc "Audit helpers for retrieving and summarizing agent events."

  alias Lang.Events.Agent, as: AgentEvents

  @doc """
  Retrieves the audit trail for a given agent.
  """
  def get_audit_trail(agent_id, opts \\ %{}) do
    AgentEvents.get_agent_history(agent_id, opts)
  end
end
