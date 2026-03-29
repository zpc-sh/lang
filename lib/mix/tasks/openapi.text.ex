defmodule Mix.Tasks.Openapi.Text do
  use Mix.Task
  @shortdoc "Enqueue Text environment OpenAPI spec generation"
  @moduledoc """
  Enqueues an Oban job to generate the Text environment OpenAPI spec.

  Usage:
    mix openapi.text           # enqueues job to generate spec

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

    args =
      %{"task" => "generate_spec"}
      |> maybe_schedule(schedule_after)

    case Lang.Workers.TextEnvironment.new(args) |> Oban.insert() do
      {:ok, job} -> Mix.shell().info("Enqueued Text spec generation job: #{job.id}")
      {:error, reason} -> Mix.shell().error("Failed to enqueue Text spec generation: #{inspect(reason)}")
    end
  end

  defp maybe_schedule(map, minutes) when is_integer(minutes) and minutes > 0 do
    Map.put(map, "scheduled_at", DateTime.add(DateTime.utc_now(), minutes * 60, :second))
  end
  defp maybe_schedule(map, _), do: map
end

