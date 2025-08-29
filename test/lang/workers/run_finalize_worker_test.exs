defmodule Lang.Workers.RunFinalizeWorkerTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Workers.RunFinalizeWorker
  alias Lang.Analyses.{Run, File}
  alias Lang.Analysis
  alias Lang.Accounts.User
  alias Oban.Job
  alias Lang.Repo

  @moduletag :integration

  test "finalize worker reschedules while files are not processed" do
    # Create user -> project -> run (session)
    {:ok, user} =
      User.create(%{
        email: "finalize@test.local",
        name: "Finalize User",
        organization_name: "Finalize Org"
      })

    {:ok, project} = Analysis.create_project(%{name: "Finalize Project", user_id: user.id})
    {:ok, run} = Run.create(%{project_id: project.id, metadata: %{}})

    # Create a couple of pending files
    {:ok, _f1} =
      File.create(%{
        analysis_session_id: run.id,
        file_name: "one.ex",
        file_path: "one.ex",
        file_extension: ".ex",
        file_size_bytes: 10
      })

    {:ok, _f2} =
      File.create(%{
        analysis_session_id: run.id,
        file_name: "two.js",
        file_path: "two.js",
        file_extension: ".js",
        file_size_bytes: 10
      })

    # Run finalize perform; expect it to reschedule since files are not processed
    assert :ok = RunFinalizeWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})

    jobs = Repo.all(Job)

    assert Enum.any?(jobs, fn j ->
             j.worker == "Lang.Workers.RunFinalizeWorker" and j.args["run_id"] == run.id
           end)
  end
end
