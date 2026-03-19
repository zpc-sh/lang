defmodule Lang.Orchestration.CommunicationHub do
  @moduledoc """
  Central hub for agent communication in LANG's multi-agent orchestration.

  This GenServer manages message routing between agents using Phoenix.PubSub.
  Supports task delegation and response handling. Follows LANG guidelines:
  - Uses PubSub for real-time routing
  - Avoids long-running processes
  - Integrates with Ash/Oban if needed for persistence (extendable)
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  # Public API -----------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Sends a task to a specific agent.
  """
  def send_task_to_agent(from_agent, to_agent, task_data) do
    GenServer.call(__MODULE__, {:send_task, from_agent, to_agent, task_data})
  end

  @doc """
  Handles a response from an agent for a given message_id.
  """
  def handle_agent_response(message_id, response_data) do
    GenServer.call(__MODULE__, {:handle_response, message_id, response_data})
  end

  # GenServer Callbacks --------------------------------------------------------

  @impl true
  def init(_state) do
    # State tracks pending messages: %{message_id => %{from, to, task, status}}
    {:ok, %{pending: %{}}}
  end

  @impl true
  def handle_call({:send_task, from, to, task_data}, _from, state) do
    message = build_message(from, to, task_data)

    new_pending =
      Map.put(state.pending, message.message_id, %{
        from: from,
        to: to,
        task: task_data,
        status: :sent
      })

    case route_message(message) do
      :ok ->
        Logger.info("Task sent to agent", message_id: message.message_id, to: to)
        {:reply, {:ok, message.message_id}, %{state | pending: new_pending}}

      error ->
        Logger.error("Failed to route message", error: error)
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:handle_response, message_id, response_data}, _from, state) do
    case Map.get(state.pending, message_id) do
      nil ->
        Logger.warn("No pending message for response", message_id: message_id)
        {:reply, {:error, :not_found}, state}

      msg ->
        # Process response (e.g., could broadcast or store)
        PubSub.broadcast(
          Lang.PubSub,
          "orchestration:responses",
          {:agent_response, message_id, response_data}
        )

        new_pending = Map.delete(state.pending, message_id)
        Logger.info("Response handled", message_id: message_id, from: msg.to)

        {:reply, :ok, %{state | pending: new_pending}}
    end
  end

  # Private Helpers ------------------------------------------------------------

  defp build_message(from, to, task_data) do
    %{
      message_id: Ecto.UUID.generate(),
      from_agent: from,
      to_agent: to,
      message_type: "task_delegation",
      task: task_data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      priority: Map.get(task_data, :priority, "medium")
    }
  end

  defp route_message(message) do
    PubSub.broadcast(
      Lang.PubSub,
      "agent:#{message.to_agent}",
      {:task_assignment, message}
    )
  end
end
