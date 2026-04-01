defmodule Lang.Workers.OrchestratorWorkerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Lang.Workers.OrchestratorWorker
  alias Oban.Job

  describe "perform/1 security" do
    test "successfully converts existing environment and task strings" do
      # Ensure these atoms exist in the VM
      _ = :text
      _ = :generate_spec

      args = %{
        "environment" => "text",
        "task" => "generate_spec",
        "job_id" => "test-job-id"
      }

      # We don't necessarily need the whole job to succeed (it might fail on Master.notify or File.write)
      # but it should NOT fail with the security ArgumentError rescue block if atoms exist.

      log = capture_log(fn ->
        OrchestratorWorker.perform(%Job{args: args})
      end)

      # If it reached the stage where it tries to call Master, it passed atom conversion.
      # We check that our specific security warning is NOT in the log.
      refute log =~ "Security warning: Invalid environment or task provided"
    end

    test "handles non-existent environment string with security warning" do
      # Use a random string that definitely isn't an atom
      invalid_env = "env_#{[:erlang.system_time(), :erlang.unique_integer()] |> Enum.join("_")}"

      args = %{
        "environment" => invalid_env,
        "task" => "generate_spec",
        "job_id" => "test-job-id"
      }

      log = capture_log(fn ->
        result = OrchestratorWorker.perform(%Job{args: args})
        assert {:error, %ArgumentError{}} = result
      end)

      assert log =~ "Security warning: Invalid environment or task provided"
      assert log =~ invalid_env
    end

    test "handles non-existent task string with security warning" do
      # Use a random string that definitely isn't an atom
      invalid_task = "task_#{[:erlang.system_time(), :erlang.unique_integer()] |> Enum.join("_")}"

      args = %{
        "environment" => "text",
        "task" => invalid_task,
        "job_id" => "test-job-id"
      }

      log = capture_log(fn ->
        result = OrchestratorWorker.perform(%Job{args: args})
        assert {:error, %ArgumentError{}} = result
      end)

      assert log =~ "Security warning: Invalid environment or task provided"
      assert log =~ invalid_task
    end
  end
end
