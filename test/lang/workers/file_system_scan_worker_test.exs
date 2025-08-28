defmodule Lang.Workers.FileSystemScanWorkerTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Workers.FileSystemScanWorker
  alias Lang.Analyses.{Run, File}
  alias Lang.Analysis
  alias Lang.Accounts.User
  alias Oban.Job
  alias Lang.Repo

  @moduletag :integration

  test "scan worker ingests files and enqueues per-file analysis" do
    # Prepare temp directory with a couple files
    temp_dir = System.tmp_dir!() |> Path.join("scan_worker_test")
    File.mkdir_p!(temp_dir)
    File.write!(Path.join(temp_dir, "a.ex"), "defmodule A do\nend\n")
    File.write!(Path.join(temp_dir, "b.js"), "function b(){}\n")

    on_exit(fn -> File.rm_rf!(temp_dir) end)

    # Create user -> project -> run (session)
    {:ok, user} = User.create(%{email: "scan@test.local", name: "Scan User", organization_name: "Scan Org"})
    {:ok, project} = Analysis.create_project(%{name: "Scan Project", user_id: user.id})
    {:ok, run} = Run.create(%{project_id: project.id, metadata: %{}})

    # Perform job directly to avoid scheduling complexities
    args = %{
      "path" => temp_dir,
      "opts" => %{},
      "session_id" => run.id,
      "project_id" => project.id,
      "user_id" => user.id
    }

    assert {:ok, _} = FileSystemScanWorker.perform(%Oban.Job{args: args})

    # Verify files ingested
    files =
      File
      |> Ash.Query.filter(analysis_session_id == ^run.id)
      |> Ash.read!()

    assert length(files) >= 2

    # Verify per-file analysis jobs were enqueued
    jobs = Repo.all(Job)
    workers = jobs |> Enum.map(& &1.worker) |> Enum.uniq()
    assert "Lang.Workers.FileAnalyzeWorker" in workers

    # Verify finalize worker job was scheduled
    assert Enum.any?(jobs, fn j ->
             j.worker == "Lang.Workers.RunFinalizeWorker" and j.args["run_id"] == run.id
           end)
  end
end
