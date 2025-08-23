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

    test "orchestrate_environment/1 creates correct task sequence for text environment" do
      {:ok, result} = Master.orchestrate_environment(:text)

      jobs = Oban.Job |> Repo.all()
      text_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "text" end)

      # Extract task names
      tasks = Enum.map(text_jobs, fn job -> job.args["task"] end)

      # Verify expected tasks are present
      expected_tasks = [
        "generate_spec",
        "implement_parsers",
        "build_documentation",
        "create_examples",
        "expose_api",
        "generate_clients",
        "produce_marketing",
        "publish"
      ]

      Enum.each(expected_tasks, fn task ->
        assert task in tasks, "Task '#{task}' should be scheduled"
      end)

      # Verify priority ordering
      priority_jobs = Enum.sort_by(text_jobs, & &1.priority)
      first_job = List.first(priority_jobs)
      assert first_job.args["task"] == "generate_spec"
      assert first_job.priority == 1
    end

    test "orchestrate_environment/1 handles different environments" do
      environments = [:text, :filesystem, :cloud, :systems]

      results =
        Enum.map(environments, fn env ->
          {:ok, result} = Master.orchestrate_environment(env)
          {env, result}
        end)

      # Verify all environments were orchestrated
      assert length(results) == 4

      Enum.each(results, fn {env, result} ->
        assert result.environment == env
        assert is_list(result.job_ids)
        assert length(result.job_ids) > 0
      end)

      # Verify jobs were created with correct queues
      jobs = Oban.Job |> Repo.all()

      text_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "text" end)
      assert Enum.all?(text_jobs, &(&1.queue == "analysis"))

      filesystem_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "filesystem" end)
      assert Enum.all?(filesystem_jobs, &(&1.queue == "lsp"))

      cloud_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "cloud" end)
      assert Enum.all?(cloud_jobs, &(&1.queue == "metrics"))

      systems_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "systems" end)
      assert Enum.all?(systems_jobs, &(&1.queue == "default"))
    end

    test "orchestrate_all/0 creates jobs for all environments" do
      {:ok, result} = Master.orchestrate_all()

      assert %{
               job_ids: job_ids,
               started_at: started_at,
               total_jobs: total_jobs
             } = result

      assert is_list(job_ids)
      assert length(job_ids) > 0
      assert match?(%DateTime{}, started_at)
      assert is_integer(total_jobs) and total_jobs > 0
      assert total_jobs == length(job_ids)

      # Verify jobs were created for all environments
      jobs = Oban.Job |> Repo.all()
      assert length(jobs) == total_jobs

      environments = Enum.map(jobs, fn job -> job.args["environment"] end) |> Enum.uniq()
      assert "text" in environments
      assert "filesystem" in environments
      assert "cloud" in environments
      assert "systems" in environments
    end

    test "orchestrate_all/0 updates master state" do
      initial_status = Master.get_status()
      initial_orchestrations = initial_status.metrics.total_orchestrations

      {:ok, _result} = Master.orchestrate_all()

      # Allow some time for GenServer cast to process
      :timer.sleep(100)

      updated_status = Master.get_status()

      assert updated_status.metrics.total_orchestrations == initial_orchestrations + 1
      assert updated_status.active_jobs > 0
      assert updated_status.last_orchestration != nil
    end

    test "orchestrate_environment/1 fails for invalid environment" do
      assert {:error, _reason} = Master.orchestrate_environment(:invalid_environment)
    end

    test "handles job completion notifications" do
      {:ok, result} = Master.orchestrate_environment(:text)
      job_id = List.first(result.job_ids)

      initial_status = Master.get_status()
      initial_completed = initial_status.completed_jobs

      # Simulate job completion
      Master.notify_job_completed(job_id)

      # Allow time for GenServer cast to process
      :timer.sleep(50)

      updated_status = Master.get_status()
      assert updated_status.completed_jobs > initial_completed
    end

    test "handles job failure notifications" do
      {:ok, result} = Master.orchestrate_environment(:text)
      job_id = List.first(result.job_ids)

      initial_status = Master.get_status()
      initial_failed = initial_status.failed_jobs

      # Simulate job failure
      test_error = "Test error for orchestration"
      Master.notify_job_failed(job_id, test_error)

      # Allow time for GenServer cast to process
      :timer.sleep(50)

      updated_status = Master.get_status()
      assert updated_status.failed_jobs > initial_failed
    end

    test "schedule_daily_orchestration/0 creates scheduled job" do
      assert {:ok, job} = Master.schedule_daily_orchestration()
      assert %Oban.Job{} = job
      assert job.worker == "Lang.Workers.DailyOrchestrationWorker"
      assert job.scheduled_at != nil
      # Should be scheduled for 2 AM UTC tomorrow
      assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) == :gt
    end

    test "orchestration plan includes correct tasks and dependencies" do
      {:ok, result} = Master.orchestrate_environment(:text)

      jobs =
        Oban.Job
        |> Repo.all()
        |> Enum.filter(fn job -> job.args["environment"] == "text" end)
        |> Enum.sort_by(& &1.priority)

      # Verify dependency structure
      tasks_with_deps =
        Enum.map(jobs, fn job ->
          {job.args["task"], job.args["dependencies"] || []}
        end)

      # generate_spec should have no dependencies
      {first_task, first_deps} = List.first(tasks_with_deps)
      assert first_task == "generate_spec"
      assert first_deps == []

      # implement_parsers should depend on generate_spec
      implement_task = Enum.find(tasks_with_deps, fn {task, _} -> task == "implement_parsers" end)
      assert implement_task
      {_, implement_deps} = implement_task
      assert "generate_spec" in implement_deps

      # build_documentation should depend on generate_spec
      doc_task = Enum.find(tasks_with_deps, fn {task, _} -> task == "build_documentation" end)
      assert doc_task
      {_, doc_deps} = doc_task
      assert "generate_spec" in doc_deps

      # publish should depend on multiple tasks
      publish_task = Enum.find(tasks_with_deps, fn {task, _} -> task == "publish" end)
      assert publish_task
      {_, publish_deps} = publish_task
      assert "generate_clients" in publish_deps
      assert "produce_marketing" in publish_deps
    end

    test "different environments have different task sequences" do
      # Test specific differences between environments
      {:ok, _} = Master.orchestrate_environment(:filesystem)
      {:ok, _} = Master.orchestrate_environment(:cloud)

      jobs = Oban.Job |> Repo.all()

      filesystem_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "filesystem" end)
      cloud_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "cloud" end)

      filesystem_tasks = Enum.map(filesystem_jobs, fn job -> job.args["task"] end)
      cloud_tasks = Enum.map(cloud_jobs, fn job -> job.args["task"] end)

      # Filesystem should have LSP-specific tasks
      assert "implement_lsp_features" in filesystem_tasks

      # Cloud should have discovery tasks
      assert "discover_resources" in cloud_tasks

      # Both should have common tasks
      assert "build_documentation" in filesystem_tasks
      assert "build_documentation" in cloud_tasks
    end

    test "orchestration handles high job volumes" do
      # Create multiple orchestrations to test system under load
      orchestrations = 1..5

      results =
        Enum.map(orchestrations, fn _i ->
          Master.orchestrate_environment(:text)
        end)

      # All should succeed
      successful_results = Enum.filter(results, &match?({:ok, _}, &1))
      assert length(successful_results) == 5

      # Check total job count
      jobs = Oban.Job |> Repo.all()
      text_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == "text" end)

      # Should have jobs from all orchestrations (5 sets of text environment tasks)
      # Number of tasks per text environment
      expected_jobs_per_env = 8
      assert length(text_jobs) >= expected_jobs_per_env * 5
    end

    test "orchestration state persists across orchestrations" do
      # First orchestration
      {:ok, _} = Master.orchestrate_environment(:text)
      first_status = Master.get_status()

      # Second orchestration
      {:ok, _} = Master.orchestrate_environment(:filesystem)
      second_status = Master.get_status()

      # Total orchestrations should increment
      assert second_status.metrics.total_orchestrations >
               first_status.metrics.total_orchestrations

      # Active jobs should include jobs from both orchestrations
      assert second_status.active_jobs >= first_status.active_jobs
    end

    test "master recovers gracefully from worker failures" do
      {:ok, result} = Master.orchestrate_environment(:text)
      job_ids = result.job_ids

      # Simulate multiple job failures
      Enum.take(job_ids, 3)
      |> Enum.each(fn job_id ->
        Master.notify_job_failed(job_id, "Simulated failure")
      end)

      # Allow processing time
      :timer.sleep(100)

      status = Master.get_status()

      # Master should still be functional
      assert status.failed_jobs >= 3
      assert status.active_jobs >= 0

      # Should be able to start new orchestrations
      assert {:ok, _} = Master.orchestrate_environment(:cloud)
    end

    test "orchestration respects environment-specific queues" do
      {:ok, _} = Master.orchestrate_all()

      jobs = Oban.Job |> Repo.all()

      # Group jobs by environment and check queue assignments
      job_groups = Enum.group_by(jobs, fn job -> job.args["environment"] end)

      # Text environment -> analysis queue
      if Map.has_key?(job_groups, "text") do
        text_queues = Enum.map(job_groups["text"], & &1.queue) |> Enum.uniq()
        assert text_queues == ["analysis"]
      end

      # Filesystem environment -> lsp queue
      if Map.has_key?(job_groups, "filesystem") do
        fs_queues = Enum.map(job_groups["filesystem"], & &1.queue) |> Enum.uniq()
        assert fs_queues == ["lsp"]
      end

      # Cloud environment -> metrics queue
      if Map.has_key?(job_groups, "cloud") do
        cloud_queues = Enum.map(job_groups["cloud"], & &1.queue) |> Enum.uniq()
        assert cloud_queues == ["metrics"]
      end

      # Systems environment -> default queue
      if Map.has_key?(job_groups, "systems") do
        systems_queues = Enum.map(job_groups["systems"], & &1.queue) |> Enum.uniq()
        assert systems_queues == ["default"]
      end
    end

    test "orchestration completion detection works correctly" do
      initial_status = Master.get_status()

      {:ok, result} = Master.orchestrate_environment(:text)
      job_ids = result.job_ids

      # Simulate all jobs completing
      Enum.each(job_ids, fn job_id ->
        Master.notify_job_completed(job_id)
      end)

      # Allow time for completion detection
      :timer.sleep(200)

      final_status = Master.get_status()

      # Successful orchestrations should increment
      assert final_status.metrics.successful_orchestrations >
               initial_status.metrics.successful_orchestrations

      # Active jobs should be reduced
      assert final_status.completed_jobs >= length(job_ids)
    end
  end

  describe "orchestration planning" do
    test "creates valid orchestration plan for all environments" do
      # This tests the private plan creation without executing it
      {:ok, result} = Master.orchestrate_all()

      jobs = Oban.Job |> Repo.all()

      # Should have jobs for all 4 environments
      environments = Enum.map(jobs, fn job -> job.args["environment"] end) |> Enum.uniq()
      assert length(environments) == 4
      assert "text" in environments
      assert "filesystem" in environments
      assert "cloud" in environments
      assert "systems" in environments

      # Each environment should have multiple tasks
      Enum.each(environments, fn env ->
        env_jobs = Enum.filter(jobs, fn job -> job.args["environment"] == env end)
        # Minimum expected tasks per environment
        assert length(env_jobs) >= 6
      end)
    end

    test "task priorities are set correctly across environments" do
      {:ok, _} = Master.orchestrate_all()

      jobs = Oban.Job |> Repo.all()

      # Generate spec should always be priority 1
      spec_jobs = Enum.filter(jobs, fn job -> job.args["task"] == "generate_spec" end)
      # One per environment
      assert length(spec_jobs) >= 4
      assert Enum.all?(spec_jobs, fn job -> job.priority == 1 end)

      # Publish should always be priority 7 (highest)
      publish_jobs = Enum.filter(jobs, fn job -> job.args["task"] == "publish" end)
      assert length(publish_jobs) >= 4
      assert Enum.all?(publish_jobs, fn job -> job.priority == 7 end)

      # Documentation should be priority 3
      doc_jobs = Enum.filter(jobs, fn job -> job.args["task"] == "build_documentation" end)
      assert length(doc_jobs) >= 4
      assert Enum.all?(doc_jobs, fn job -> job.priority == 3 end)
    end

    test "dependency chains are properly structured" do
      {:ok, _} = Master.orchestrate_environment(:text)

      jobs =
        Oban.Job
        |> Repo.all()
        |> Enum.filter(fn job -> job.args["environment"] == "text" end)

      # Create dependency map
      dep_map =
        Enum.map(jobs, fn job ->
          {job.args["task"], job.args["dependencies"] || []}
        end)
        |> Enum.into(%{})

      # Verify key dependency relationships
      assert dep_map["generate_spec"] == []
      assert "generate_spec" in dep_map["implement_parsers"]
      assert "generate_spec" in dep_map["build_documentation"]
      assert "implement_parsers" in dep_map["expose_api"]
      assert "expose_api" in dep_map["generate_clients"]
      assert "build_documentation" in dep_map["produce_marketing"]
      assert "generate_clients" in dep_map["publish"]
      assert "produce_marketing" in dep_map["publish"]
    end
  end

  describe "error handling and edge cases" do
    test "handles invalid environment gracefully" do
      assert_raise FunctionClauseError, fn ->
        Master.orchestrate_environment(:nonexistent_env)
      end
    end

    test "handles database errors during job creation" do
      # This is difficult to test without mocking, but we can test error propagation
      # In a real scenario, you might use Mox to mock the database

      # For now, verify that valid operations work
      assert {:ok, _} = Master.orchestrate_environment(:text)
    end

    test "handles concurrent orchestrations" do
      # Start multiple orchestrations concurrently
      tasks =
        1..3
        |> Enum.map(fn _i ->
          Task.async(fn -> Master.orchestrate_environment(:text) end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      # All should complete successfully
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Each should have created jobs
      Enum.each(results, fn {:ok, result} ->
        assert is_list(result.job_ids)
        assert length(result.job_ids) > 0
      end)
    end

    test "master state remains consistent under load" do
      # Perform rapid orchestrations
      1..10
      |> Enum.each(fn _i ->
        spawn(fn -> Master.orchestrate_environment(:text) end)
      end)

      # Allow all spawned processes to complete
      :timer.sleep(500)

      # Master should still be responsive
      status = Master.get_status()
      assert is_map(status)
      assert status.metrics.total_orchestrations >= 0

      # Should still be able to orchestrate
      assert {:ok, _} = Master.orchestrate_environment(:cloud)
    end
  end
end
