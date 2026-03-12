defmodule Lang.Refactor.ParserAudit do
  @moduledoc """
  Comprehensive audit of parser usage across the LANG codebase.

  Run with: mix run scripts/audit_parsers.exs

  Generates:
  - parser_audit.json: Detailed usage report
  - parser_dependencies.md: Human-readable dependency graph
  """

  @parsers [
    "Lang.Native.Parser",
    "Lang.Native.TreeParser",
    "Lang.Native.FSScanner",
    "Lang.GraphReasoner",
    "Lang.Parsers.Filesystem",
    "Lang.Native.PerfEngine",
    "Lang.Native.FSWatcher"
  ]

  def run do
    IO.puts("🔍 Starting parser audit...\n")

    results = audit_all_parsers()

    # Generate JSON report
    File.write!("parser_audit.json", Jason.encode!(results, pretty: true))
    IO.puts("✓ Written parser_audit.json")

    # Generate markdown report
    generate_markdown_report(results)
    IO.puts("✓ Written parser_dependencies.md")

    # Print summary
    print_summary(results)
  end

  defp audit_all_parsers do
    @parsers
    |> Enum.map(&audit_parser/1)
    |> Enum.into(%{})
  end

  defp audit_parser(parser) do
    IO.puts("Auditing #{parser}...")

    files = find_usage(parser)
    functions = analyze_functions(parser, files)
    dependencies = find_parser_dependencies(parser)

    {parser,
     %{
       usage_count: length(files),
       files: files,
       functions_used: functions,
       depends_on: dependencies,
       stats: calculate_stats(files, functions)
     }}
  end

  defp find_usage(module_name) do
    case System.cmd("git", ["grep", "-l", module_name, "--", "lib/**/*.ex", "lib/**/*.exs"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.contains?(&1, "audit_parsers.exs"))

      _ ->
        []
    end
  end

  defp analyze_functions(module_name, files) do
    files
    |> Enum.flat_map(fn file ->
      File.read!(file)
      |> extract_function_calls(module_name)
      |> Enum.map(fn func -> {func, file} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {func, files} ->
      %{
        function: func,
        call_count: length(files),
        called_from: Enum.uniq(files)
      }
    end)
    |> Enum.sort_by(& &1.call_count, :desc)
  end

  defp extract_function_calls(content, module_name) do
    # Handle both direct calls and aliased calls
    direct_regex = ~r/#{Regex.escape(module_name)}\.(\w+)/

    # Extract alias if exists
    alias_regex = ~r/alias\s+#{Regex.escape(module_name)}(?:\s*,\s*as:\s*(\w+))?/
    alias_match = Regex.run(alias_regex, content)

    direct_calls =
      Regex.scan(direct_regex, content)
      |> Enum.map(&List.last/1)

    aliased_calls =
      case alias_match do
        [_, alias_name] when is_binary(alias_name) ->
          Regex.scan(~r/#{alias_name}\.(\w+)/, content)
          |> Enum.map(&List.last/1)

        [_] ->
          # Simple alias without 'as'
          short_name = module_name |> String.split(".") |> List.last()

          Regex.scan(~r/#{short_name}\.(\w+)/, content)
          |> Enum.map(&List.last/1)

        _ ->
          []
      end

    Enum.uniq(direct_calls ++ aliased_calls)
  end

  defp find_parser_dependencies(parser) do
    parser_file = find_parser_file(parser)

    case parser_file do
      nil ->
        []

      file ->
        content = File.read!(file)

        @parsers
        |> Enum.filter(&(&1 != parser))
        |> Enum.filter(&String.contains?(content, &1))
    end
  end

  defp find_parser_file(parser) do
    module_path =
      parser
      |> String.replace(".", "/")
      |> String.downcase()

    possible_paths = [
      "lib/#{module_path}.ex",
      "lib/#{module_path}.exs"
    ]

    Enum.find(possible_paths, &File.exists?/1)
  end

  defp calculate_stats(files, functions) do
    %{
      total_files: length(files),
      total_functions: length(functions),
      total_calls: Enum.sum(Enum.map(functions, & &1.call_count)),
      most_used_function:
        case functions do
          [%{function: func, call_count: count} | _] -> "#{func} (#{count} calls)"
          [] -> "none"
        end
    }
  end

  defp generate_markdown_report(results) do
    content = """
    # Parser Dependencies Report

    Generated: #{DateTime.utc_now() |> DateTime.to_string()}

    ## Summary

    | Parser | Files Using | Total Calls | Most Used Function |
    |--------|-------------|-------------|-------------------|
    #{generate_summary_table(results)}

    ## Detailed Analysis

    #{generate_detailed_analysis(results)}

    ## Dependency Graph

    ```mermaid
    graph TD
    #{generate_mermaid_graph(results)}
    ```

    ## Migration Impact

    #{generate_migration_impact(results)}

    ## Recommendations

    #{generate_recommendations(results)}
    """

    File.write!("parser_dependencies.md", content)
  end

  defp generate_summary_table(results) do
    results
    |> Enum.map(fn {parser, data} ->
      stats = data.stats
      "| #{parser} | #{stats.total_files} | #{stats.total_calls} | #{stats.most_used_function} |"
    end)
    |> Enum.join("\n")
  end

  defp generate_detailed_analysis(results) do
    results
    |> Enum.map(fn {parser, data} ->
      """
      ### #{parser}

      **Usage Statistics:**
      - Files using this parser: #{data.stats.total_files}
      - Unique functions called: #{data.stats.total_functions}
      - Total function calls: #{data.stats.total_calls}

      **Top Functions:**
      #{format_top_functions(data.functions_used)}

      **Dependencies:**
      #{format_dependencies(data.depends_on)}

      **Used By:**
      #{format_used_by(data.files)}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_top_functions(functions) do
    functions
    |> Enum.take(5)
    |> Enum.map(fn %{function: func, call_count: count} ->
      "- `#{func}/n` - #{count} calls"
    end)
    |> Enum.join("\n")
  end

  defp format_dependencies(deps) do
    case deps do
      [] ->
        "- None"

      deps ->
        deps
        |> Enum.map(&"- #{&1}")
        |> Enum.join("\n")
    end
  end

  defp format_used_by(files) do
    files
    |> Enum.take(5)
    |> Enum.map(&"- `#{&1}`")
    |> Enum.join("\n")
    |> then(fn list ->
      if length(files) > 5 do
        list <> "\n- ... and #{length(files) - 5} more"
      else
        list
      end
    end)
  end

  defp generate_mermaid_graph(results) do
    results
    |> Enum.flat_map(fn {parser, data} ->
      short_name = parser |> String.split(".") |> List.last()

      data.depends_on
      |> Enum.map(fn dep ->
        dep_short = dep |> String.split(".") |> List.last()
        "    #{short_name} --> #{dep_short}"
      end)
    end)
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp generate_migration_impact(results) do
    high_impact =
      results
      |> Enum.filter(fn {_, data} -> data.stats.total_calls > 50 end)
      |> Enum.map(&elem(&1, 0))

    """
    ### High Impact Parsers (>50 calls)

    These parsers are heavily used and require careful migration:

    #{Enum.map(high_impact, &"- #{&1}") |> Enum.join("\n")}

    ### Circular Dependencies

    #{detect_circular_dependencies(results)}
    """
  end

  defp detect_circular_dependencies(results) do
    # Simple circular dependency detection
    circles =
      for {parser1, data1} <- results,
          parser2 <- data1.depends_on,
          data2 = Map.get(results, parser2),
          parser1 in (data2[:depends_on] || []) do
        [parser1, parser2] |> Enum.sort() |> Enum.join(" <-> ")
      end
      |> Enum.uniq()

    case circles do
      [] ->
        "None detected ✓"

      circles ->
        """
        ⚠️ Found circular dependencies:
        #{Enum.map(circles, &"- #{&1}") |> Enum.join("\n")}
        """
    end
  end

  defp generate_recommendations(results) do
    """
    1. **Start with low-impact parsers**: Migrate parsers with <10 calls first
    2. **Break circular dependencies**: Refactor before consolidating
    3. **Create compatibility layer**: For parsers with >50 calls
    4. **Focus on duplicate functionality**: FSScanner and TreeParser both do tree-sitter parsing
    5. **Consider deprecation**: Some parsers may not be needed after consolidation
    """
  end

  defp print_summary(results) do
    IO.puts("\n📊 Audit Summary:")
    IO.puts("================")

    total_files =
      results
      |> Enum.map(fn {_, data} -> data.files end)
      |> List.flatten()
      |> Enum.uniq()
      |> length()

    total_calls =
      results
      |> Enum.map(fn {_, data} -> data.stats.total_calls end)
      |> Enum.sum()

    IO.puts("Total files using parsers: #{total_files}")
    IO.puts("Total parser function calls: #{total_calls}")
    IO.puts("\nTop 3 most used parsers:")

    results
    |> Enum.sort_by(fn {_, data} -> data.stats.total_calls end, :desc)
    |> Enum.take(3)
    |> Enum.with_index(1)
    |> Enum.each(fn {{parser, data}, idx} ->
      IO.puts("  #{idx}. #{parser} (#{data.stats.total_calls} calls)")
    end)
  end
end

# Run the audit
Lang.Refactor.ParserAudit.run()
