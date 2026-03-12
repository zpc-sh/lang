defmodule Mix.Tasks.Openapi.Systems do
  use Mix.Task
  @shortdoc "Enqueue Systems environment OpenAPI spec generation"
  @moduledoc """
  Enqueues an Oban job to generate the Systems environment OpenAPI spec.

  Usage:
    mix openapi.systems           # enqueues job to generate spec

  Options:
    --schedule MINUTES            # schedule to run after N minutes (default: 0)
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

    case Lang.Workers.SystemsEnvironment.new(args) |> Oban.insert() do
      {:ok, job} -> Mix.shell().info("Enqueued Systems spec generation job: #{job.id}")
      {:error, reason} -> Mix.shell().error("Failed to enqueue Systems spec generation: #{inspect(reason)}")
    end
  end

  defp maybe_schedule(map, minutes) when is_integer(minutes) and minutes > 0 do
    Map.put(map, "scheduled_at", DateTime.add(DateTime.utc_now(), minutes * 60, :second))
  end
  defp maybe_schedule(map, _), do: map
end

