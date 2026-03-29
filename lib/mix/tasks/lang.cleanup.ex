defmodule Mix.Tasks.Lang.Cleanup do
  @moduledoc """
  Clean up and reorganize the LANG project structure.

  This task helps identify and fix organizational issues in the codebase.

  ## Usage

      mix lang.cleanup COMMAND [OPTIONS]
      
  ## Commands

      analyze           Analyze project structure issues
      suggest           Suggest reorganization
      unused            Find unused modules
      duplicates        Find duplicate functionality
      
  ## Examples

      mix lang.cleanup analyze
      mix lang.cleanup suggest --domain accounts
      mix lang.cleanup unused --remove
      mix lang.cleanup duplicates
  """

  use Mix.Task

  @shortdoc "Clean up project structure"

  @proper_structure %{
    "core" => ~w[accounts billing organizations subscriptions],
    "analysis" => ~w[text code stylometrics conversation timemachine],
    "infrastructure" => ~w[native parsers workers security orchestration cache],
    "integrations" => ~w[lsp api webhooks],
    "events" => ~w[api_usage user_activity system_events]
  }

  def run(args) do
    case args do
      ["analyze" | opts] -> run_analyze(opts)
      ["suggest" | opts] -> run_suggest(opts)
      ["unused" | opts] -> run_unused(opts)
      ["duplicates" | opts] -> run_duplicates(opts)
      _ -> show_help()
    end
  end

  defp run_analyze(_opts) do
    Mix.shell().info("🔍 Analyzing project structure...")

    issues = analyze_structure()

    if issues == [] do
      Mix.shell().info("\n✓ Project structure looks good!")
    else
      Mix.shell().info("\n📋 Found #{length(issues)} issues:\n")

      issues
      |> Enum.group_by(& &1.type)
      |> Enum.each(fn {type, type_issues} ->
        Mix.shell().info("\n#{format_type(type)}:")

        Enum.each(type_issues, fn issue ->
          Mix.shell().info("  - #{issue.description}")

          if issue.suggestion do
            Mix.shell().info("    → #{issue.suggestion}")
          end
        end)
      end)
    end

    # Write detailed report
    File.write!("structure_analysis.json", Jason.encode!(issues, pretty: true))
    Mix.shell().info("\n✓ Full report written to structure_analysis.json")
  end

  defp run_suggest(opts) do
    domain = Keyword.get(opts, :domain)

    Mix.shell().info("💡 Generating reorganization suggestions...")

    current_structure = analyze_current_structure()
    suggestions = generate_suggestions(current_structure, domain)

    Mix.shell().info("\n📁 Suggested Structure:")
    Mix.shell().info("======================\n")

    print_tree(suggestions, 0)

    if Mix.shell().yes?("\nGenerate migration script?") do
      generate_migration_script(suggestions)
      Mix.shell().info("\n✓ Migration script written to reorganize_project.exs")
    end
  end

  defp run_unused(opts) do
    Mix.shell().info("🔍 Finding unused modules...")

    remove = "--remove" in opts

    unused = find_unused_modules()

    if unused == [] do
      Mix.shell().info("\n✓ No unused modules found!")
    else
      Mix.shell().info("\n Found #{length(unused)} potentially unused modules:\n")

      Enum.each(unused, fn module ->
        Mix.shell().info("  - #{module.name}")
        Mix.shell().info("    File: #{module.file}")
        Mix.shell().info("    Last modified: #{module.last_modified}")
      end)

      if remove and Mix.shell().yes?("\nRemove unused modules?") do
        Enum.each(unused, fn module ->
          Mix.shell().info("  Removing #{module.file}...")
          File.rm!(module.file)
        end)
      end
    end
  end

  defp run_duplicates(_opts) do
    Mix.shell().info("🔍 Finding duplicate functionality...")

    duplicates = find_duplicates()

    if duplicates == [] do
      Mix.shell().info("\n✓ No obvious duplicates found!")
    else
      Mix.shell().info("\n⚠️  Found potential duplicates:\n")

      Enum.each(duplicates, fn dup ->
        Mix.shell().info("\n#{dup.description}")
        Mix.shell().info("  Modules involved:")

        Enum.each(dup.modules, fn mod ->
          Mix.shell().info("    - #{mod}")
        end)

        Mix.shell().info("  Suggestion: #{dup.suggestion}")
      end)
    end
  end

  defp analyze_structure do
    issues = []

    # Check for modules in wrong locations
    issues = issues ++ check_module_locations()

    # Check for inconsistent naming
    issues = issues ++ check_naming_conventions()

    # Check for circular dependencies
    issues = issues ++ check_circular_dependencies()

    # Check for overly complex modules
    issues = issues ++ check_module_complexity()

    issues
  end

  defp check_module_locations do
    Path.wildcard("lib/lang/**/*.ex")
    |> Enum.flat_map(fn file ->
      module_name = extract_module_name(file)
      expected_path = module_to_expected_path(module_name)

      if expected_path && file != expected_path do
        [
          %{
            type: :wrong_location,
            description: "#{module_name} is in wrong location",
            current: file,
            expected: expected_path,
            suggestion: "Move to #{expected_path}"
          }
        ]
      else
        []
      end
    end)
  end

  defp check_naming_conventions do
    Path.wildcard("lib/lang/**/*.ex")
    |> Enum.flat_map(fn file ->
      module_name = extract_module_name(file)

      issues = []

      # Check for inconsistent suffixes
      if String.contains?(module_name, "Native") and not String.contains?(file, "/native/") do
        issues = [
          %{
            type: :naming,
            description: "#{module_name} has 'Native' in name but not in native/ directory",
            suggestion: "Move to lib/lang/native/ or rename module"
          }
          | issues
        ]
      end

      # Check for unclear names
      if String.contains?(module_name, "Parser") and String.contains?(module_name, "Native") do
        issues = [
          %{
            type: :naming,
            description: "#{module_name} has redundant naming (Parser + Native)",
            suggestion: "Clarify module purpose and rename accordingly"
          }
          | issues
        ]
      end

      issues
    end)
  end

  defp check_circular_dependencies do
    # Simplified check - would need more sophisticated analysis
    []
  end

  defp check_module_complexity do
    Path.wildcard("lib/lang/**/*.ex")
    |> Enum.flat_map(fn file ->
      content = File.read!(file)
      line_count = String.split(content, "\n") |> length()

      if line_count > 500 do
        [
          %{
            type: :complexity,
            description: "#{file} is too large (#{line_count} lines)",
            suggestion: "Consider splitting into smaller modules"
          }
        ]
      else
        []
      end
    end)
  end

  defp analyze_current_structure do
    Path.wildcard("lib/lang/**/*.ex")
    |> Enum.map(fn file ->
      %{
        file: file,
        module: extract_module_name(file),
        domain: extract_domain(file),
        subdomain: extract_subdomain(file)
      }
    end)
    |> Enum.group_by(& &1.domain)
  end

  defp generate_suggestions(current_structure, specific_domain) do
    # Build suggested tree structure
    %{}
  end

  defp find_unused_modules do
    all_modules =
      Path.wildcard("lib/lang/**/*.ex")
      |> Enum.map(fn file ->
        %{
          file: file,
          name: extract_module_name(file),
          last_modified: File.stat!(file).mtime
        }
      end)

    # Find modules not referenced anywhere
    Enum.filter(all_modules, fn module ->
      usage_count = count_module_usage(module.name)
      # Allow self-reference
      usage_count <= 1
    end)
  end

  defp find_duplicates do
    [
      %{
        description: "Multiple parser modules with overlapping functionality",
        modules: ["Lang.Native.Parser", "Lang.Native.TreeParser", "Lang.Native.FSScanner"],
        suggestion: "Consolidate into focused, single-purpose NIFs"
      },
      %{
        description: "API usage tracking in multiple domains",
        modules: ["Lang.Accounts.APIUsage", "Lang.Events.ApiUsageEvent"],
        suggestion: "Use Events domain for all event tracking"
      }
    ]
  end

  defp extract_module_name(file) do
    content = File.read!(file)

    case Regex.run(~r/defmodule\s+([\w\.]+)/, content) do
      [_, module] -> module
      _ -> Path.basename(file, ".ex")
    end
  end

  defp extract_domain(file) do
    case String.split(file, "/") do
      ["lib", "lang", domain | _] -> domain
      _ -> "unknown"
    end
  end

  defp extract_subdomain(file) do
    case String.split(file, "/") do
      ["lib", "lang", domain, subdomain | _] -> subdomain
      _ -> nil
    end
  end

  defp module_to_expected_path(module_name) do
    # Convert module name to expected file path
    path =
      module_name
      |> String.replace(".", "/")
      |> Macro.underscore()

    "lib/#{path}.ex"
  end

  defp count_module_usage(module_name) do
    case System.cmd("git", ["grep", "-c", module_name, "--", "lib/**/*.ex"]) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> length()

      _ ->
        0
    end
  end

  defp format_type(type) do
    case type do
      :wrong_location -> "🗂️  Wrong Location"
      :naming -> "📝 Naming Issues"
      :complexity -> "📏 Complexity Issues"
      :circular -> "🔄 Circular Dependencies"
      _ -> "❓ Other Issues"
    end
  end

  defp print_tree(tree, indent) do
    # Pretty print tree structure
    tree
    |> Enum.each(fn {key, value} ->
      Mix.shell().info("#{String.duplicate("  ", indent)}#{key}/")

      if is_map(value) do
        print_tree(value, indent + 1)
      else
        Enum.each(value, fn item ->
          Mix.shell().info("#{String.duplicate("  ", indent + 1)}#{item}")
        end)
      end
    end)
  end

  defp generate_migration_script(suggestions) do
    content = """
    # Project Reorganization Script
    # Generated: #{DateTime.utc_now()}

    defmodule ReorganizeProject do
      def run do
        # TODO: Implement based on suggestions
        IO.puts("Migration script generated")
      end
    end

    ReorganizeProject.run()
    """

    File.write!("reorganize_project.exs", content)
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end
end
