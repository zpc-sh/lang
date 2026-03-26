defmodule Mix.Tasks.Lang.Agent.Partition do
  @shortdoc "Invokes the Agent Partition locally to test abstract interpretation."

  @moduledoc """
  Hits the local `Lang.LSP.Handlers.AgentPartition.handle/2` directly.
  Useful for AI agents to invoke opt-in direction finding outside standard LSP.

  ## Options

    * `--agent-id` - ID of the agent requesting partition data (default: random).

  ## Example

      mix lang.agent.partition --agent-id my_agent_1
  """

  use Mix.Task

  @impl true
  def run(args) do
    # Suppress logging clutter in stdout for clean JSON output
    Logger.configure(level: :error)

    {opts, _, _} = OptionParser.parse(args, switches: [agent_id: :string])

    agent_id = Keyword.get(opts, :agent_id, "test_agent_#{:erlang.unique_integer([:positive])}")

    request = %{
      client_id: agent_id,
      params: %{"agent_id" => agent_id}
    }

    # We load necessary apps just in case, but keep it lightweight
    # Mix.Task.run("app.start", []) is usually needed for real Ecto or full config
    # but the partition handler is pure and stateless.

    case Lang.LSP.Handlers.AgentPartition.handle(request) do
      {:reply, %{result: data}, _ctx} ->
        # Print output nicely for the CLI AI agent
        IO.puts(Jason.encode!(data, pretty: true))
      {:error, reason} ->
        IO.warn("Failed to retrieve partition data: #{inspect(reason)}")
    end
  end
end
