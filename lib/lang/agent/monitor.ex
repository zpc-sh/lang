defmodule Lang.Agent.Monitor do
  @moduledoc "Monitoring helpers for agent performance and health."

  alias Lang.Agent.Supervisor
  alias Lang.Events.Agent, as: AgentEvents

  def monitor_performance(agent_id, _duration_ms \\ 60_000) do
    case Supervisor.get_agent_status(agent_id) do
      {:ok, status} ->
        qcp = %{"load" => status[:message_queue_len] || 0, "memory_mb" => status[:memory_mb] || 0.0}
        AgentEvents.track_cognitive_load(agent_id, qcp, 0.5, %{})
        {:ok, status}
      err -> err
    end
  end
end
