defmodule Mix.Tasks.Openapi.All do
  use Mix.Task
  @shortdoc "Enqueue OpenAPI spec generation for all environments"
  @moduledoc """
  Enqueues Oban jobs to generate OpenAPI specs for Text, Filesystem, Cloud, and Systems environments.

  Usage:
    mix openapi.all
  """

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    tasks = [
      {Lang.Workers.TextEnvironment, %{"task" => "generate_spec"}},
      {Lang.Workers.FilesystemEnvironment, %{"task" => "generate_spec"}},
      {Lang.Workers.CloudEnvironment, %{"task" => "generate_spec"}},
      {Lang.Workers.SystemsEnvironment, %{"task" => "generate_spec"}}
    ]

    Enum.each(tasks, fn {mod, args} ->
      case mod.new(args) |> Oban.insert() do
        {:ok, job} -> Mix.shell().info("Enqueued #{inspect(mod)} job: #{job.id}")
        {:error, reason} -> Mix.shell().error("Failed to enqueue #{inspect(mod)}: #{inspect(reason)}")
      end
    end)
  end
end

