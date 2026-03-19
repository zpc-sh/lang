#!/usr/bin/env elixir

# Oban Table Fix Script for LANG Platform
# This script specifically addresses the "oban_jobs table does not exist" error

defmodule ObanTableFix do
  @moduledoc """
  Focused fix for the missing oban_jobs table that's causing GenServer crashes.

  Error: (Postgrex.Error) ERROR 42P01 (undefined_table) relation "public.oban_jobs" does not exist
  """

  def run do
    IO.puts("🔧 OBAN TABLE FIX - LANG Platform")
    IO.puts("=" |> String.duplicate(60))

    IO.puts("Issue: Oban GenServer terminating due to missing oban_jobs table")
    IO.puts("Solution: Run the existing Oban migration that's already created\n")

    check_migration_exists()
  end

  defp check_migration_exists do
    migration_path = "priv/repo/migrations/20250828223901_add_oban_jobs_table.exs"

    case File.exists?(migration_path) do
      true ->
        IO.puts("✅ Oban migration found: #{migration_path}")
        read_migration_content(migration_path)

      false ->
        IO.puts("❌ Oban migration not found!")
        create_migration_instructions()
    end
  end

  defp read_migration_content(path) do
    case File.read(path) do
      {:ok, content} ->
        IO.puts("📄 Migration content:")
        IO.puts("   #{String.replace(content, "\n", "\n   ")}")

        if String.contains?(content, "Oban.Migration.up") do
          IO.puts("✅ Migration looks correct - uses Oban.Migration.up")
          provide_solution()
        else
          IO.puts("⚠️  Migration may need updating")
          show_correct_migration()
        end

      {:error, reason} ->
        IO.puts("❌ Could not read migration: #{inspect(reason)}")
    end
  end

  defp provide_solution do
    IO.puts("\n🚀 SOLUTION:")
    IO.puts("The migration exists but hasn't been run. Execute these commands:")
    IO.puts("")
    IO.puts("1. Run the migration (this will create the oban_jobs table):")
    IO.puts("   cd lang && mix ecto.migrate")
    IO.puts("")
    IO.puts("2. If that fails, try resetting the database:")
    IO.puts("   cd lang && mix ecto.reset")
    IO.puts("")
    IO.puts("3. Verify the fix by checking if the table exists:")
    IO.puts("   cd lang && mix run -e \"")

    IO.puts(
      "   case Ecto.Adapters.SQL.query(Lang.Repo, \\\"SELECT 1 FROM oban_jobs LIMIT 1\\\", []) do"
    )

    IO.puts("     {:ok, _} -> IO.puts(\\\"✅ oban_jobs table exists!\\\");")
    IO.puts("     {:error, _} -> IO.puts(\\\"❌ Table still missing\\\")")
    IO.puts("   end\"")
    IO.puts("")

    IO.puts(
      "4. After the table is created, Oban should start normally and background jobs will work!"
    )

    explain_what_this_fixes()
  end

  defp explain_what_this_fixes do
    IO.puts("\n📋 This will fix:")
    IO.puts("• GenServer {Oban.Registry, {Oban, {:producer, \"default\"}}} terminating")
    IO.puts("• Postgrex.Error ERROR 42P01 (undefined_table)")
    IO.puts("• Background job processing failures")
    IO.puts("• FileSystemScanWorker not being able to queue jobs")
    IO.puts("• All Oban-based background processing in the LANG platform")

    IO.puts("\n🎯 After fix, these will work:")
    IO.puts("• Lang.Workers.FileSystemScanWorker.scan_async/4")
    IO.puts("• Background file system scans")
    IO.puts("• Oban job queues: :analysis, :lsp, :metrics, :cleanup, :billing")
    IO.puts("• Real-time progress updates via PubSub")
  end

  defp show_correct_migration do
    IO.puts("\n📝 Correct migration should contain:")

    IO.puts(~s"""
    defmodule Lang.Repo.Migrations.AddObanJobsTable do
      use Ecto.Migration

      def up do
        Oban.Migration.up(version: 11)
      end

      def down do
        Oban.Migration.down(version: 1)
      end
    end
    """)
  end

  defp create_migration_instructions do
    IO.puts("\n🆕 Create the Oban migration:")
    IO.puts("1. Generate migration: mix ecto.gen.migration add_oban_jobs_table")
    IO.puts("2. Edit the file with the correct content (see above)")
    IO.puts("3. Run migration: mix ecto.migrate")
  end
end

# Handle different ways this script might be run
if System.argv() == [] do
  ObanTableFix.run()
else
  case System.argv() do
    ["--help"] ->
      IO.puts("Usage: elixir fix_oban_table.exs")
      IO.puts("       mix run fix_oban_table.exs")

    ["--quick-fix"] ->
      IO.puts("🚀 QUICK FIX: Run this command to fix the Oban table:")
      IO.puts("cd lang && mix ecto.migrate")

    _ ->
      ObanTableFix.run()
  end
end
