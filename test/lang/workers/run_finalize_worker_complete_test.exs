defmodule Lang.Workers.RunFinalizeWorkerCompleteTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Workers.RunFinalizeWorker
  alias Lang.Analyses.{Run, File}
  alias Lang.Analysis
  alias Lang.Accounts.User

  @moduletag :integration

  test "finalize worker completes run when all files processed" do
    {:ok, user} = User.create(%{email: "finalize2@test.local", name: "Finalize2 User", organization_name: "Finalize2 Org"})
    {:ok, project} = Analysis.create_project(%{name: "Finalize2 Project", user_id: user.id})
    {:ok, run} = Run.create(%{project_id: project.id, metadata: %{}})

    # Create completed files for this run
    {:ok, f1} = File.create(%{analysis_session_id: run.id, file_name: "one.ex", file_path: "one.ex", file_extension: ".ex", file_size_bytes: 10})
    {:ok, f2} = File.create(%{analysis_session_id: run.id, file_name: "two.js", file_path: "two.js", file_extension: ".js", file_size_bytes: 20})

    {:ok, _} = File.complete(f1, %{analysis_result: %{}}, %{processing_time_ms: 5})
    {:ok, _} = File.complete(f2, %{analysis_result: %{}}, %{processing_time_ms: 7})

    # Perform finalize
    assert :ok = RunFinalizeWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})

    # Fetch run and assert completed
    {:ok, completed_run} = Run.by_id(run.id)
    assert completed_run.status == :completed
    assert completed_run.file_count == 2
    assert completed_run.total_size_bytes == 30
    # processing_time_ms is the sum from files (5 + 7)
    assert completed_run.processing_time_ms == 12
  end
end
