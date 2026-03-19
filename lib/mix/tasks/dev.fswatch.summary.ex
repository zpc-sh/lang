defmodule Mix.Tasks.Dev.Fswatch.Summary do
  use Mix.Task
  @shortdoc "Print a summary of dev FS watcher events"

  @moduledoc """
  Prints a one-line (or JSON) summary of FS watcher events seen so far.

      mix dev.fswatch.summary
      mix dev.fswatch.summary --json

  Options:
    --json   Output JSON instead of human-readable text
  """

  @switches [json: :boolean]

  def run(args) do
    Mix.Task.run("app.start")
    {opts, _argv, _} = OptionParser.parse(args, switches: @switches)

    summary = safe_summary()

    if opts[:json] do
      IO.puts(Jason.encode!(summary))
    else
      IO.puts("[fswatch] topic=#{summary.topic} total=#{summary.total} by_kind=#{inspect(summary.by_kind)}")
    end
  end

  defp safe_summary do
    try do
      Lang.Dev.FSWatcherLogger.summary()
    catch
      _, _ -> %{topic: "dev:fs:jsonld", total: 0, by_kind: %{created: 0, modified: 0, deleted: 0}}
    end
  end
end

