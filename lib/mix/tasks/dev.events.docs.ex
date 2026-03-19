
defmodule Mix.Tasks.Dev.Events.Docs do
  use Mix.Task
  @shortdoc "Generate docs/architecture/events.md from the TypeRegistry"

  @moduledoc """
  Generates a canonical documentation page for event types and their categories
  based on `Lang.Events.TypeRegistry` and configured extensions.

      mix dev.events.docs
  """

  def run(_args) do
    Mix.Task.run("app.start")
    {exact, prefixes} = Lang.Events.TypeRegistry.export()

    lines = [
      "---",
      "trusted: true",
      "---
",
      "# Event Types Registry
",
      "This document is generated from `Lang.Events.TypeRegistry`.
",
      "## Exact Types
",
      render_table(exact),
      "
## Prefix Categories
",
      render_prefixes(prefixes)
    ]

    path = Path.join(["docs", "architecture", "events.md"]) |> Path.expand()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Enum.join(lines, "
"))
    Mix.shell().info("Wrote #{path}")
  end

  defp render_table(map) when is_map(map) do
    rows = map |> Enum.sort_by(fn {k, _} -> k end)
    header = "| event_type | category |
|---|---|
"
    body =
      rows
      |> Enum.map(fn {k, v} -> "| `#{k}` | `#{v}` |" end)
      |> Enum.join("
")
    header <> body <> "
"
  end

  defp render_prefixes(map) when is_map(map) do
    rows = map |> Enum.sort_by(fn {k, _} -> k end)
    header = "| prefix | category |
|---|---|
"
    body =
      rows
      |> Enum.map(fn {k, v} -> "| `#{k}` | `#{v}` |" end)
      |> Enum.join("
")
    header <> body <> "
"
  end
end
