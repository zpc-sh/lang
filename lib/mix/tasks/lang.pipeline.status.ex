defmodule Mix.Tasks.Lang.Pipeline.Status do
  use Mix.Task
  @shortdoc "Show status of an analysis run: files and results"

  @moduledoc """
  Usage:
      mix lang.pipeline.status RUN_ID [--violations] [--json] [--only VALUE]

  Prints a summary and details for a specific analysis run, including
  file counts and per-file statuses. Uses Ash resources — no raw SQL.

  Options:
    --violations   Include a summary of violations by severity
    --json         Output machine-readable JSON
    --only VALUE   Filter: file status (pending|processing|completed|failed|skipped)
                   or violation severity (critical|high|medium|low|info)
  """

  alias Lang.Analyses.{Run, File, Violation}
  require Ash.Query

  @impl true
  def run(argv) do
    {opts, rest, _} =
      OptionParser.parse(argv, switches: [violations: :boolean, json: :boolean, only: :string])

    case rest do
      [run_id] when is_binary(run_id) ->
        Mix.Task.run("app.start")

        case Run.by_id(run_id) do
          {:ok, nil} ->
            Mix.shell().error("Run not found: #{run_id}")

          {:ok, run} ->
            if opts[:json] do
              output_json(run, opts)
            else
              print_run_summary(run)
              print_files(run.id, opts)
              if opts[:violations], do: print_violations_summary(run.id, opts)
            end

          {:error, err} ->
            Mix.shell().error("Failed to load run: #{inspect(err)}")
        end

      _ ->
        Mix.shell().info(
          "Usage: mix lang.pipeline.status RUN_ID [--violations] [--json] [--only VALUE]"
        )
    end
  end

  defp print_run_summary(run) do
    summary = Run.summary(run)
    Mix.shell().info("Run: #{summary.id}")
    Mix.shell().info("Status: #{summary.status}")
    Mix.shell().info("Files: #{summary.file_count}")

    Mix.shell().info(
      "Warnings: #{summary.warnings_count}  Critical: #{summary.critical_issues_count}  Violations: #{summary.violations_count}"
    )

    Mix.shell().info("Duration: #{summary.duration_ms}ms")
    Mix.shell().info("")
  end

  defp output_json(run, opts) do
    run_summary = Run.summary(run)

    files_query =
      File
      |> Ash.Query.filter(analysis_session_id == ^run.id)
      |> Ash.Query.sort([{:status, :asc}, {:file_path, :asc}])
      |> Ash.Query.load([:violations])

    {:ok, files0} = Ash.read(files_query)
    files = maybe_filter_files(files0, opts[:only])

    files_json =
      Enum.map(files, fn f ->
        v = f.violations || []
        counts = reduce_severity_counts(v)

        %{
          id: f.id,
          status: f.status,
          file_path: f.file_path,
          file_size_bytes: f.file_size_bytes,
          human_file_size: Lang.Analyses.File.human_file_size(f),
          violations_count: length(v),
          violations_by_severity: maybe_filter_counts(counts, opts[:only])
        }
      end)

    violations_summary =
      if opts[:violations] do
        q = Violation |> Ash.Query.filter(analyzed_file.analysis_session_id == ^run.id)

        case Ash.read(q) do
          {:ok, violations} ->
            {_total, counts} = summarize_violations(violations, opts[:only])
            counts

          _ ->
            nil
        end
      else
        nil
      end

    payload =
      %{
        run: run_summary,
        files: files_json,
        violations_by_severity: violations_summary
      }

    IO.puts(Jason.encode!(payload))
  end

  defp print_files(run_id, opts) do
    files_query =
      File
      |> Ash.Query.filter(analysis_session_id == ^run_id)
      |> Ash.Query.sort([{:status, :asc}, {:file_path, :asc}])
      |> Ash.Query.load([:violations])

    case Ash.read(files_query) do
      {:ok, files0} ->
        files = maybe_filter_files(files0, opts[:only])
        total = length(files)

        {completed, failed, skipped} =
          Enum.reduce(files, {0, 0, 0}, fn f, {c, f2, s} ->
            case f.status do
              :completed -> {c + 1, f2, s}
              :failed -> {c, f2 + 1, s}
              :skipped -> {c, f2, s + 1}
              _ -> {c, f2, s}
            end
          end)

        Mix.shell().info(
          "Files (#{total}) - completed: #{completed}, failed: #{failed}, skipped: #{skipped}"
        )

        Enum.each(files, fn f ->
          viol_count = length(f.violations || [])
          size = Lang.Analyses.File.human_file_size(f)
          Mix.shell().info("- [#{f.status}] #{f.file_path}  (#{size})  violations: #{viol_count}")
        end)

      {:error, err} ->
        Mix.shell().error("Failed to list files: #{inspect(err)}")
    end
  end

  defp print_violations_summary(run_id, opts) do
    q =
      Violation
      |> Ash.Query.filter(analyzed_file.analysis_session_id == ^run_id)

    case Ash.read(q) do
      {:ok, violations} ->
        {total, counts} = summarize_violations(violations, opts[:only])

        Mix.shell().info("")
        Mix.shell().info("Violations (#{total}) by severity:")
        print_counts(counts)

      {:error, err} ->
        Mix.shell().error("Failed to load violations: #{inspect(err)}")
    end
  end

  # Helpers
  defp maybe_filter_files(files, only) when is_binary(only) do
    status = parse_status(only)
    if status, do: Enum.filter(files, &(&1.status == status)), else: files
  end

  defp maybe_filter_files(files, _), do: files

  defp parse_status(str) do
    case String.downcase(str) do
      "pending" -> :pending
      "processing" -> :processing
      "completed" -> :completed
      "failed" -> :failed
      "skipped" -> :skipped
      _ -> nil
    end
  end

  defp parse_severity(str) do
    case String.downcase(str) do
      s when s in ["critical", "high", "medium", "low", "info"] -> String.to_existing_atom(s)
      _ -> nil
    end
  end

  defp reduce_severity_counts(violations) do
    Enum.reduce(violations, %{critical: 0, high: 0, medium: 0, low: 0, info: 0}, fn vv, acc ->
      Map.update!(acc, vv.severity, &(&1 + 1))
    end)
  end

  defp maybe_filter_counts(counts, only) when is_binary(only) do
    case parse_severity(only) do
      nil -> counts
      sev -> Map.take(counts, [sev])
    end
  end

  defp maybe_filter_counts(counts, _), do: counts

  defp summarize_violations(violations, only) do
    counts = reduce_severity_counts(violations)

    case parse_severity(to_string(only || "")) do
      nil ->
        {length(violations), counts}

      sev ->
        filtered_total = Enum.count(violations, &(&1.severity == sev))
        {filtered_total, Map.take(counts, [sev])}
    end
  end

  defp print_counts(%{critical: c, high: h, medium: m, low: l, info: i}) do
    Mix.shell().info("  critical: #{c}")
    Mix.shell().info("  high:     #{h}")
    Mix.shell().info("  medium:   #{m}")
    Mix.shell().info("  low:      #{l}")
    Mix.shell().info("  info:     #{i}")
  end

  defp print_counts(map) when is_map(map) do
    Enum.each(map, fn {k, v} -> Mix.shell().info("  #{k}: #{v}") end)
  end
end
