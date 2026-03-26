defmodule Mix.Tasks.Lang.Audit.Parsers do
  @moduledoc """
  Audit parser usage across the LANG codebase.

  Generates detailed reports about parser dependencies and usage patterns.

  ## Usage

      mix lang.audit.parsers
      
  ## Options

      --format FORMAT    Output format: json, md, or both (default: both)
      --output DIR       Output directory (default: current directory)
      
  ## Examples

      mix lang.audit.parsers
      mix lang.audit.parsers --format json
      mix lang.audit.parsers --output reports/
  """

  use Mix.Task

  @shortdoc "Audit parser usage and dependencies"

  @parsers [
    "Lang.Native.Parser",
    "Lang.Native.TreeParser",
    "Lang.Native.FSScanner",
    "Lang.GraphReasoner",
    "Lang.Parsers.Filesystem",
    "Lang.Native.PerfEngine",
    "Lang.Native.FSWatcher"
  ]

  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [format: :string, output: :string]
      )

    format = Keyword.get(opts, :format, "both")
    output_dir = Keyword.get(opts, :output, ".")

    Mix.shell().info("🔍 Starting parser audit...")

    results = audit_all_parsers()

    case format do
      "json" ->
        write_json(results, output_dir)

      "md" ->
        write_markdown(results, output_dir)

      "both" ->
        write_json(results, output_dir)
        write_markdown(results, output_dir)

      _ ->
        Mix.raise("Invalid format: #{format}. Use json, md, or both.")
    end

    print_summary(results)
  end

  defp audit_all_parsers do
    @parsers
    |> Enum.map(&audit_parser/1)
    |> Enum.into(%{})
  end

  defp audit_parser(parser) do
    Mix.shell().info("Auditing #{parser}...")

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
        |> Enum.reject(&String.contains?(&1, "mix/tasks"))

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
    direct_regex = ~r/#{Regex.escape(module_name)}\.(\w+)/
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
      total_calls: Enum.reduce(functions, 0, fn x, acc -> acc + x.call_count end),
      most_used_function:
        case functions do
          [%{function: func, call_count: count} | _] -> "#{func} (#{count} calls)"
          [] -> "none"
        end
    }
  end

  defp write_json(results, output_dir) do
    path = Path.join(output_dir, "parser_audit.json")
    File.write!(path, Jason.encode!(results, pretty: true))
    Mix.shell().info("✓ Written #{path}")
  end

  defp write_markdown(results, output_dir) do
    content = generate_markdown_report(results)
    path = Path.join(output_dir, "parser_dependencies.md")
    File.write!(path, content)
    Mix.shell().info("✓ Written #{path}")
  end

  defp generate_markdown_report(results) do
    """
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
    """
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

    #{Enum.map(high_impact, &"- #{&1}") |> Enum.join("\n")}
    """
  end

  defp print_summary(results) do
    Mix.shell().info("\n📊 Audit Summary:")
    Mix.shell().info("================")

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

    Mix.shell().info("Total files using parsers: #{total_files}")
    Mix.shell().info("Total parser function calls: #{total_calls}")
    Mix.shell().info("\nTop 3 most used parsers:")

    results
    |> Enum.sort_by(fn {_, data} -> data.stats.total_calls end, :desc)
    |> Enum.take(3)
    |> Enum.with_index(1)
    |> Enum.each(fn {{parser, data}, idx} ->
      Mix.shell().info("  #{idx}. #{parser} (#{data.stats.total_calls} calls)")
    end)
  end
end
