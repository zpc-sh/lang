#!/usr/bin/env elixir

# Simple Oban Tables Check Script
# This script checks if Oban tables exist in the database

IO.puts("🔍 Checking Oban Tables in Database")
IO.puts("=" |> String.duplicate(40))

# Start minimal dependencies
Application.put_env(:lang, Lang.Repo,
  username: System.get_env("DB_USERNAME", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  database: System.get_env("DB_NAME", "lang_dev"),
  port: String.to_integer(System.get_env("DB_PORT", "5432"))
)

# Start required applications
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto)

# Define a simple repo for direct queries
defmodule SimpleRepo do
  def query(sql, params \\ []) do
    config = Application.get_env(:lang, Lang.Repo)
    {:ok, pid} = Postgrex.start_link(config)

    try do
      Postgrex.query(pid, sql, params)
    after
      GenServer.stop(pid)
    end
  end
end

# Check for Oban tables
oban_tables = [
  "oban_jobs",
  "oban_peers"
]

IO.puts("Checking for Oban tables...")

Enum.each(oban_tables, fn table ->
  case SimpleRepo.query("SELECT COUNT(*) FROM information_schema.tables WHERE table_name = $1", [
         table
       ]) do
    {:ok, %{rows: [[1]]}} ->
      # Table exists, check row count
      case SimpleRepo.query("SELECT COUNT(*) FROM #{table}") do
        {:ok, %{rows: [[count]]}} ->
          IO.puts("✅ #{table} exists with #{count} rows")

        {:error, reason} ->
          IO.puts("⚠️  #{table} exists but couldn't query: #{inspect(reason)}")
      end

    {:ok, %{rows: [[0]]}} ->
      IO.puts("❌ #{table} does not exist")

    {:error, reason} ->
      IO.puts("❌ Error checking #{table}: #{inspect(reason)}")
  end
end)

# Check if any migrations are pending
IO.puts("\nChecking migration status...")

case SimpleRepo.query("SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1") do
  {:ok, %{rows: [[latest_version]]}} ->
    IO.puts("📊 Latest migration: #{latest_version}")

    if String.contains?(latest_version, "20250828223901") do
      IO.puts("✅ Oban migration (20250828223901) appears to be applied")
    else
      IO.puts("⚠️  Oban migration (20250828223901) may not be applied yet")
    end

  {:error, reason} ->
    IO.puts("❌ Could not check migrations: #{inspect(reason)}")
end

IO.puts(("\n" <> "=") |> String.duplicate(40))
IO.puts("Database check complete!")
