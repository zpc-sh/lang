defmodule Mix.Tasks.Lang.Pipeline.Run do
  use Mix.Task
  @shortdoc "Run the analysis pipeline: scan → ingest → analyze → finalize"

  @moduledoc """
  Runs the analysis pipeline for a given path.

  Usage:
      mix lang.pipeline.run /path/to/project [--email EMAIL] [--name NAME]

  Creates a user (if provided), project, and analysis run, then enqueues a
  filesystem scan which ingests files and schedules per-file analysis and finalize.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv, _} =
      OptionParser.parse(args,
        strict: [
          email: :string,
          name: :string,
          project_name: :string,
          max_depth: :integer,
          analysis_types: :string
        ]
      )

    path =
      case argv do
        [p | _] ->
          p

        _ ->
          Mix.raise("Usage: mix lang.pipeline.run /path/to/project [--email EMAIL] [--name NAME]")
      end

    email = opts[:email] || "dev+pipeline@lang.local"
    name = opts[:name] || "Pipeline User"
    project_name = opts[:project_name] || "Pipeline: #{Path.basename(path)}"

    analysis_types =
      (opts[:analysis_types] || "content_search,semantic_analysis")
      |> String.split([",", " "], trim: true)
      |> Enum.reject(&(&1 == ""))

    max_depth = opts[:max_depth] || 8

    {:ok, user} =
      Lang.Accounts.User.create(%{email: email, name: name, organization_name: "Dev Org"})

    {:ok, project} = Lang.Analysis.create_project(%{name: project_name, user_id: user.id})

    {:ok, run} =
      Lang.Analyses.Run.create(%{project_id: project.id, metadata: %{source: :mix_task}})

    {:ok, _job} =
      Lang.Workers.FileSystemScanWorker.scan_async(path, run.id, project.id, user.id,
        analysis_types: analysis_types,
        max_depth: max_depth
      )

    Mix.shell().info("Enqueued scan for #{path}. Run ID: #{run.id}")
    if Code.ensure_loaded?(Oban.Web), do: Mix.shell().info("Visit /oban (dev) to monitor jobs")
    Mix.shell().info("You can also inspect via: Oban.Job |> Lang.Repo.all()")
  end
end
