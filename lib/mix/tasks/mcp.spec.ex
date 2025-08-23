defmodule Mix.Tasks.Mcp.Spec do
  use Mix.Task
  @shortdoc "Enqueue MCP OpenAPI spec generation"
  @moduledoc """
  Enqueues an Oban job to generate the MCP OpenAPI spec.

  Usage:
    mix mcp.spec           # enqueues job to generate spec

  Options:
    --schedule MINUTES     # schedule to run after N minutes (default: 0)
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    schedule_after =
      case OptionParser.parse(args, switches: [schedule: :integer]) do
        {opts, _, _} -> Keyword.get(opts, :schedule, 0)
      end

    opts =
      if schedule_after > 0 do
        %{"scheduled_at" => DateTime.add(DateTime.utc_now(), schedule_after * 60, :second)}
      else
        %{}
      end

    case Lang.Workers.MCPEnvironment.enqueue(opts) do
      {:ok, job} ->
        Mix.shell().info("Enqueued MCP spec generation job: #{job.id}")
      {:error, reason} ->
        Mix.shell().error("Failed to enqueue MCP spec generation: #{inspect(reason)}")
    end
  end
end

