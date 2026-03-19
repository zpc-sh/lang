defmodule Lang.Analyses.Pipeline do
  @moduledoc """
  Orchestrates an analysis run: file discovery, ingest, parsing, analysis, and finalize.
  """

  alias Lang.Analyses.Run

  def start_run(workspace_id, attrs \\ %{}) do
    Run.create(Map.merge(%{workspace_id: workspace_id}, attrs))
  end

  def enqueue_files(_run_id, file_ids_or_args) do
    Enum.each(file_ids_or_args, fn item ->
      args =
        case item do
          id when is_binary(id) -> %{file_id: id}
          %{} = m -> m
        end

      %{worker: Lang.Workers.FileAnalyzeWorker, args: args}
      |> Oban.Job.new(queue: :analysis)
      |> Oban.insert()
    end)

    :ok
  end

  def finalize_run(%Run{} = run) do
    Run.complete(run, %{})
  end
end
