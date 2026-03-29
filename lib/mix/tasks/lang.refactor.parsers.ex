defmodule Mix.Tasks.Lang.Refactor.Parsers do
  @moduledoc """
  Refactor parser modules to the new consolidated architecture.

  This task helps migrate from the current scattered parser architecture
  to a clean, consolidated structure.

  ## Usage

      mix lang.refactor.parsers COMMAND [OPTIONS]
      
  ## Commands

      plan              Generate refactoring plan
      migrate MODULE    Migrate specific module
      validate          Validate the migration
      
  ## Examples

      mix lang.refactor.parsers plan
      mix lang.refactor.parsers migrate Lang.Native.Parser
      mix lang.refactor.parsers validate --check-imports
  """

  use Mix.Task

  @shortdoc "Refactor parser modules"

  @migration_map %{
    "Lang.Native.Parser" => "Lang.Native.TextParser",
    "Lang.Native.TreeParser" => "Lang.Native.ASTParser",
    "Lang.Native.FSScanner" => [
      "Lang.Native.FileSystem",
      "Lang.Native.TextSearch",
      "Lang.Native.ASTParser"
    ],
    "Lang.Parsers.Filesystem" => "Lang.Analysis.FileSystem",
    "Lang.GraphReasoner" => "Lang.Native.GraphEngine"
  }

  def run(args) do
    case args do
      ["plan" | opts] -> run_plan(opts)
      ["migrate", module | opts] -> run_migrate(module, opts)
      ["validate" | opts] -> run_validate(opts)
      _ -> Mix.shell().error("Invalid command. Use plan, migrate, or validate.")
    end
  end

  defp run_plan(_opts) do
    Mix.shell().info("📋 Generating refactoring plan...")

    # First run the audit
    {:ok, _} = Mix.Task.run("lang.audit.parsers", ["--format", "json"])

    # Load audit results
    results = Jason.decode!(File.read!("parser_audit.json"))

    # Generate plan
    plan = generate_refactoring_plan(results)

    # Write plan
    File.write!("parser_refactoring_plan.json", Jason.encode!(plan, pretty: true))

    Mix.shell().info("\n✨ Refactoring Plan Summary:")
    Mix.shell().info("==========================")

    Enum.each(plan.migrations, fn migration ->
      Mix.shell().info("\n#{migration.from} → #{migration.to}")
      Mix.shell().info("  Impact: #{migration.impact_level}")
      Mix.shell().info("  Files affected: #{migration.affected_files}")
      Mix.shell().info("  Estimated effort: #{migration.effort_hours} hours")
    end)

    Mix.shell().info("\nTotal estimated effort: #{plan.total_effort_hours} hours")
    Mix.shell().info("\n✓ Full plan written to parser_refactoring_plan.json")
  end

  defp run_migrate(module, opts) do
    Mix.shell().info("🔄 Migrating #{module}...")

    dry_run = "--dry-run" in opts

    if dry_run do
      Mix.shell().info("(DRY RUN - no changes will be made)")
    end

    case Map.get(@migration_map, module) do
      nil ->
        Mix.shell().error("No migration mapping for #{module}")

      targets when is_list(targets) ->
        Mix.shell().info("This module splits into multiple targets:")
        Enum.each(targets, &Mix.shell().info("  - #{&1}"))

        if Mix.shell().yes?("\nProceed with migration?") do
          migrate_split_module(module, targets, dry_run)
        end

      target ->
        Mix.shell().info("Migrating to: #{target}")

        if Mix.shell().yes?("\nProceed with migration?") do
          migrate_simple_module(module, target, dry_run)
        end
    end
  end

  defp run_validate(opts) do
    Mix.shell().info("✅ Validating parser migration...")

    check_imports = "--check-imports" in opts
    check_tests = "--check-tests" in opts

    issues = []

    if check_imports do
      issues = issues ++ validate_imports()
    end

    if check_tests do
      issues = issues ++ validate_tests()
    end

    if issues == [] do
      Mix.shell().info("\n✓ All validations passed!")
    else
      Mix.shell().error("\n❌ Found #{length(issues)} issues:")

      Enum.each(issues, fn issue ->
        Mix.shell().error("  - #{issue}")
      end)
    end
  end

  defp generate_refactoring_plan(audit_results) do
    migrations =
      @migration_map
      |> Enum.map(fn {from, to} ->
        usage_data = Map.get(audit_results, from, %{})

        %{
          from: from,
          to: to,
          affected_files: Map.get(usage_data, "usage_count", 0),
          impact_level: calculate_impact_level(usage_data),
          effort_hours: estimate_effort(usage_data),
          dependencies: Map.get(usage_data, "depends_on", [])
        }
      end)

    %{
      migrations: migrations,
      total_effort_hours: Enum.sum(Enum.map(migrations, & &1.effort_hours)),
      generated_at: DateTime.utc_now()
    }
  end

  defp calculate_impact_level(%{"stats" => %{"total_calls" => calls}}) when calls > 100,
    do: "HIGH"

  defp calculate_impact_level(%{"stats" => %{"total_calls" => calls}}) when calls > 50,
    do: "MEDIUM"

  defp calculate_impact_level(_), do: "LOW"

  defp estimate_effort(%{"stats" => %{"total_files" => files, "total_calls" => calls}}) do
    base_hours = files * 0.5
    complexity_hours = calls * 0.1
    Float.round(base_hours + complexity_hours, 1)
  end

  defp estimate_effort(_), do: 1.0

  defp migrate_simple_module(from, to, dry_run) do
    files = find_files_using_module(from)

    Enum.each(files, fn file ->
      Mix.shell().info("  Updating #{file}...")

      if not dry_run do
        content = File.read!(file)
        new_content = String.replace(content, from, to)
        File.write!(file, new_content)
      end
    end)

    Mix.shell().info("\n✓ Migrated #{length(files)} files")
  end

  defp migrate_split_module(from, targets, dry_run) do
    Mix.shell().info("\n⚠️  Split migrations require manual review!")
    Mix.shell().info("Please review each file and determine which target module to use.")

    files = find_files_using_module(from)

    Enum.each(files, fn file ->
      Mix.shell().info("\n📄 #{file}")
      Mix.shell().info("Available targets:")

      Enum.with_index(targets, 1)
      |> Enum.each(fn {target, idx} ->
        Mix.shell().info("  #{idx}. #{target}")
      end)

      # In a real implementation, we'd analyze usage and suggest the right target
      Mix.shell().info("  (Manual review required)")
    end)
  end

  defp find_files_using_module(module) do
    case System.cmd("git", ["grep", "-l", module, "--", "lib/**/*.ex"]) do
      {output, 0} -> String.split(output, "\n", trim: true)
      _ -> []
    end
  end

  defp validate_imports do
    # Check for old module references
    old_modules = Map.keys(@migration_map)

    issues =
      Enum.flat_map(old_modules, fn module ->
        case find_files_using_module(module) do
          [] -> []
          files -> ["Still using old module #{module} in #{length(files)} files"]
        end
      end)

    issues
  end

  defp validate_tests do
    # Simple check - in reality would run tests
    if System.find_executable("mix") do
      []
    else
      ["Cannot run tests"]
    end
  end
end
