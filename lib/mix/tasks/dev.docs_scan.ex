defmodule Mix.Tasks.Dev.DocsScan do
  use Mix.Task
  @shortdoc "Scan docs for prompt-injection patterns"

  @moduledoc """
  Scans documentation/content files for prompt-injection patterns and prints a report.

      mix dev.docs_scan
      mix dev.docs_scan --paths docs,AGENTS.md --fail-on high

  Options:
    --paths   Comma-separated list of paths (default: docs,AGENTS.md,AGENTS.codex.md,CONTRIBUTING.md,README.md,priv/secret)
    --fail-on one of: none|low|medium|high (default: none)
    --format  table|json (default: table)
  """

  @switches [paths: :string, fail_on: :string, format: :string]

  def run(args) do
    Mix.Task.run("app.start")
    {opts, _argv, _} = OptionParser.parse(args, switches: @switches)

    paths =
      case opts[:paths] do
        nil -> nil
        str -> String.split(str, ",", trim: true)
      end

    findings = Lang.Dev.DocSanitizer.scan(paths || default_paths())
    format = (opts[:format] || "table") |> String.downcase()
    fail_on = parse_level(opts[:fail_on] || "none")

    case format do
      "json" -> IO.puts(Jason.encode!(%{count: length(findings), findings: findings}, pretty: true))
      _ -> print_table(findings)
    end

    if should_fail?(findings, fail_on) do
      Mix.raise("doc scan found findings at or above: #{fail_on}")
    end
  end

  defp default_paths, do: ["docs", "AGENTS.md", "AGENTS.codex.md", "CONTRIBUTING.md", "README.md", "priv/secret"]

  defp parse_level("none"), do: :none
  defp parse_level("low"), do: :low
  defp parse_level("medium"), do: :medium
  defp parse_level("high"), do: :high
  defp parse_level(_), do: :none

  defp level_value(:low), do: 1
  defp level_value(:medium), do: 2
  defp level_value(:high), do: 3
  defp level_value(:none), do: 0

  defp finding_level_value(%{severity: s}), do: level_value(s)

  defp should_fail?(findings, :none), do: false
  defp should_fail?(findings, level) do
    min = level_value(level)
    Enum.any?(findings, fn f -> finding_level_value(f) >= min end)
  end

  defp print_table(findings) do
    if findings == [] do
      IO.puts("No injection patterns found.")
    else
      IO.puts("Potential prompt-injection patterns found:\n")
      Enum.each(findings, fn f ->
        IO.puts("#{f.file}:#{f.line} [#{f.severity}] #{f.type} -> #{String.trim(f.snippet)}")
      end)
      IO.puts("\nTotal: #{length(findings)}")
    end
  end
end

