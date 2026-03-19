@@ SNAPSHOT of test/lang/orchestration/master_test.exs @@
defmodule Lang.Orchestration.MasterTest do
  use ExUnit.Case, async: false
  use Lang.DataCase

  alias Lang.Orchestration.Master
  alias Oban.Job

  @moduletag :integration

  describe "orchestration master" do
    setup do
      # Clean up any existing jobs before each test
      Oban.drain_queue(queue: :analysis)
      Oban.drain_queue(queue: :lsp)
      Oban.drain_queue(queue: :metrics)
      Oban.drain_queue(queue: :default)

      :ok
    end

    test "starts successfully and maintains state" do
      # Master should be started as part of the application supervision tree
      pid = GenServer.whereis(Lang.Orchestration.Master)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "get_status/0 returns current orchestration status" do
      status = Master.get_status()

      assert %{
               active_jobs: active_jobs,
               completed_jobs: completed_jobs,
               failed_jobs: failed_jobs,
               metrics: metrics,
               last_orchestration: last_orchestration
             } = status

      assert is_integer(active_jobs) and active_jobs >= 0
      assert is_integer(completed_jobs) and completed_jobs >= 0
      assert is_integer(failed_jobs) and failed_jobs >= 0

      assert %{
               total_orchestrations: total,
               successful_orchestrations: successful,
               failed_orchestrations: failed
             } = metrics

      assert is_integer(total) and total >= 0
      assert is_integer(successful) and successful >= 0
      assert is_integer(failed) and failed >= 0

      assert is_nil(last_orchestration) or match?(%DateTime{}, last_orchestration)
    end

    test "orchestrate_environment/1 creates jobs for specific environment" do
      {:ok, result} = Master.orchestrate_environment(:text)

      assert %{
               environment: :text,
               job_ids: job_ids,
               started_at: started_at
             } = result

      assert is_list(job_ids)
      assert length(job_ids) > 0
      assert match?(%DateTime{}, started_at)

      # Verify jobs were created
      jobs = Oban.Job |> Repo.all()
      text_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "text" end)
      assert length(text_jobs) > 0

      # Verify job structure
      sample_job = List.first(text_jobs)
      assert sample_job.worker == "Lang.Workers.OrchestratorWorker"
      assert sample_job.queue == "analysis"
      assert Map.has_key?(sample_job.args, "task")
      assert Map.has_key?(sample_job.args, "environment")
    end
  end
end
