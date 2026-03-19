defmodule Lang.Agent.Resources do
  @moduledoc "Resource and constraint helpers for agents."

  alias Lang.Agent.Supervisor
  alias Lang.Agent.Runtime

  def limit_resources(agent_id, resource_limits) when is_map(resource_limits) do
    case Supervisor.find_agent_pid(agent_id) do
      {:ok, pid} ->
        :ok = Runtime.update_constraints(pid, resource_limits)
        :ok

      _ ->
        {:error, :agent_not_running}
    end
  end
end
