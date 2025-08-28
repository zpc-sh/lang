defmodule Lang.Analyses.PipelineTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Analyses.Pipeline
  alias Lang.Repo
  alias Oban.Job

  describe "enqueue_files/2" do
    setup do
      Oban.drain_queue(queue: :analysis)
      :ok
    end

    test "enqueues FileAnalyzeWorker jobs for each file arg" do
      files = [
        "file-abc-123",
        %{"file_id" => "file-def-456"}
      ]

      assert :ok == Pipeline.enqueue_files("run-id-ignored", files)

      jobs = Repo.all(Job)
      assert length(jobs) >= 2

      workers = Enum.map(jobs, & &1.worker) |> Enum.uniq()
      assert "Lang.Workers.FileAnalyzeWorker" in workers

      # Ensure queued on analysis queue
      assert Enum.any?(jobs, &(&1.queue == "analysis"))
    end
  end
end

