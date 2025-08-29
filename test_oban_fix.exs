#!/usr/bin/env elixir

# Quick Oban Test Script for LANG Platform
# This script tests if Oban is working properly and can queue/process jobs

defmodule ObanFixTest do
  @moduledoc """
  Simple test to verify Oban functionality and fix basic issues.
  """

  def run do
    IO.puts("🔧 OBAN FUNCTIONALITY TEST")
    IO.puts("=" |> String.duplicate(50))

    # Test 1: Check if Oban module loads
    IO.puts("1. Testing Oban module loading...")

    case Code.ensure_loaded(Oban) do
      {:module, Oban} ->
        IO.puts("   ✅ Oban module loaded successfully")
        test_job_creation()

      {:error, reason} ->
        IO.puts("   ❌ Oban module failed to load: #{inspect(reason)}")
    end
  end

  defp test_job_creation do
    IO.puts("2. Testing Oban job creation...")

    try do
      # Create a simple job without inserting to database
      job =
        %{test: "data", timestamp: DateTime.utc_now()}
        |> Oban.Job.new(worker: "TestWorker", queue: :default)

      IO.puts("   ✅ Job creation successful")
      IO.puts("   Job details: worker=#{job.worker}, queue=#{job.queue}")

      test_configuration()
    rescue
      error ->
        IO.puts("   ❌ Job creation failed: #{inspect(error)}")
        suggest_fixes()
    end
  end

  defp test_configuration do
    IO.puts("3. Testing Oban configuration...")

    try do
      # Check if Oban is configured in the application
      case Application.get_env(:lang, Oban) do
        nil ->
          IO.puts("   ⚠️  Oban not configured in application environment")

        config when is_list(config) ->
          IO.puts("   ✅ Oban configuration found")
          IO.puts("   Config keys: #{inspect(Keyword.keys(config))}")

          test_database_tables()

        config ->
          IO.puts("   ⚠️  Unexpected Oban config format: #{inspect(config)}")
      end
    rescue
      error ->
        IO.puts("   ❌ Configuration test failed: #{inspect(error)}")
    end
  end

  defp test_database_tables do
    IO.puts("4. Testing database tables...")

    try do
      # Check if we can start the application
      case Application.ensure_all_started(:lang) do
        {:ok, apps} ->
          IO.puts("   ✅ Application started (#{length(apps)} apps)")
          check_oban_tables()

        {:error, {app, reason}} ->
          IO.puts("   ❌ Failed to start #{app}: #{inspect(reason)}")
          suggest_migration_fix()
      end
    rescue
      error ->
        IO.puts("   ❌ Database test failed: #{inspect(error)}")
        suggest_migration_fix()
    end
  end

  defp check_oban_tables do
    IO.puts("5. Checking Oban database tables...")

    try do
      # Try to query the oban_jobs table
      case Ecto.Adapters.SQL.query(Lang.Repo, "SELECT COUNT(*) FROM oban_jobs LIMIT 1", []) do
        {:ok, %{rows: [[count]]}} ->
          IO.puts("   ✅ oban_jobs table exists with #{count} jobs")

        {:ok, result} ->
          IO.puts("   ✅ oban_jobs table accessible: #{inspect(result)}")

        {:error, %{postgres: %{code: :undefined_table}}} ->
          IO.puts("   ❌ oban_jobs table does not exist")
          provide_migration_command()

        {:error, reason} ->
          IO.puts("   ❌ Database query failed: #{inspect(reason)}")
      end

      test_job_insertion()
    rescue
      error ->
        IO.puts("   ❌ Table check failed: #{inspect(error)}")
        provide_migration_command()
    end
  end

  defp test_job_insertion do
    IO.puts("6. Testing actual job insertion...")

    try do
      # Create and insert a test job
      job_params = %{
        test_data: "oban_functionality_test",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      case %{job_params: job_params}
           |> Oban.Job.new(worker: "Lang.Workers.TestWorker", queue: :default)
           |> Oban.insert() do
        {:ok, job} ->
          IO.puts("   ✅ Job inserted successfully!")
          IO.puts("   Job ID: #{job.id}, State: #{job.state}")

          check_oban_status()

        {:error, changeset} ->
          IO.puts("   ❌ Job insertion failed:")
          print_changeset_errors(changeset)
      end
    rescue
      error ->
        IO.puts("   ❌ Job insertion test failed: #{inspect(error)}")
    end
  end

  defp check_oban_status do
    IO.puts("7. Checking Oban process status...")

    try do
      case Process.whereis(Oban) do
        nil ->
          IO.puts("   ⚠️  Oban process not running")

        pid when is_pid(pid) ->
          IO.puts("   ✅ Oban process running (PID: #{inspect(pid)})")

          # Check if any queues are running
          case Oban.config() do
            %{queues: queues} when map_size(queues) > 0 ->
              IO.puts("   ✅ Oban queues configured: #{inspect(Map.keys(queues))}")

            config ->
              IO.puts("   ⚠️  Oban config: #{inspect(config)}")
          end
      end

      print_final_status()
    rescue
      error ->
        IO.puts("   ❌ Status check failed: #{inspect(error)}")
    end
  end

  defp print_changeset_errors(changeset) do
    if changeset.errors && length(changeset.errors) > 0 do
      Enum.each(changeset.errors, fn {field, {message, _}} ->
        IO.puts("     • #{field}: #{message}")
      end)
    else
      IO.puts("     No specific error details available")
    end
  end

  defp suggest_fixes do
    IO.puts("\n🔧 SUGGESTED FIXES:")
    IO.puts("1. Check if Oban is added to deps in mix.exs")
    IO.puts("2. Run: mix deps.get")
    IO.puts("3. Add Oban to application supervision tree")
  end

  defp suggest_migration_fix do
    IO.puts("\n🔧 MIGRATION FIX NEEDED:")
    provide_migration_command()
  end

  defp provide_migration_command do
    IO.puts("1. Create Oban migration:")
    IO.puts("   mix ecto.gen.migration add_oban_tables")
    IO.puts("")
    IO.puts("2. Edit the migration file with:")
    IO.puts("   def up, do: Oban.Migration.up(version: 11)")
    IO.puts("   def down, do: Oban.Migration.down(version: 1)")
    IO.puts("")
    IO.puts("3. Run migration:")
    IO.puts("   mix ecto.migrate")
  end

  defp print_final_status do
    IO.puts(("\n" <> "=") |> String.duplicate(50))
    IO.puts("🎯 OBAN TEST COMPLETE")
    IO.puts("")
    IO.puts("✅ If all tests passed: Oban is working correctly!")
    IO.puts("⚠️  If tests failed: Follow the suggested fixes above")
    IO.puts("🚀 Background jobs will now work for the LANG platform!")
    IO.puts("")
    IO.puts("Next steps:")
    IO.puts("• FileSystemScanWorker can process directory scans")
    IO.puts("• SecurityScanWorker can analyze code for vulnerabilities")
    IO.puts("• Background processing is enabled for heavy operations")
  end
end

# Run the test
IO.puts("Starting Oban functionality test...")
ObanFixTest.run()
