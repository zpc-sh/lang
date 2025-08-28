defmodule Lang.Workers.RunFinalizeWorker do
  use Oban.Worker, queue: :analysis, max_attempts: 3
  import Ash.Query

  alias Lang.Analyses.{Run, File}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => run_id}}) do
    with {:ok, run} <- Run.by_id(run_id),
         {:ok, files} <- read_files(run_id) do
      # If any files are not yet in a terminal state, reschedule and exit
      if Enum.any?(files, fn f -> not File.processed?(f) end) do
        __MODULE__.new(%{"run_id" => run_id}, scheduled_at: DateTime.add(DateTime.utc_now(), reschedule_delay()))
        |> Oban.insert()
        :ok
      else
        stats = compute_stats(files)
        {:ok, _} = Run.update_stats(run, stats)
        {:ok, _} = Run.complete(run, stats)
        :ok
      end
    else
      _ -> :ok
    end
  end

  defp read_files(run_id) do
    File
    |> filter(analysis_session_id == ^run_id)
    |> Ash.read()
  end

  defp compute_stats(files) do
    %{
      file_count: length(files),
      total_size_bytes: Enum.reduce(files, 0, &((&1.file_size_bytes || 0) + &2)),
      violations_count: Enum.reduce(files, 0, &(count_violations(&1) + &2)),
      critical_issues_count: 0,
      warnings_count: 0,
      processing_time_ms: Enum.reduce(files, 0, &((&1.processing_time_ms || 0) + &2))
    }
  end

  defp count_violations(file) do
    case Map.fetch(file, :violations) do
      {:ok, list} when is_list(list) -> length(list)
      _ -> 0
    end
  end

  defp reschedule_delay do
    Application.get_env(:lang, :analysis, [])
    |> Keyword.get(:run_finalize_reschedule_seconds, 60)
  end
end
