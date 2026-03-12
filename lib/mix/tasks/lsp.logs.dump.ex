defmodule Mix.Tasks.Lsp.Logs.Dump do
  use Mix.Task

  @shortdoc "Dump recent Lang LSP measurements from the database"
  @moduledoc """
  Reads recent `Lang.LspMeasurementEvent` records via Ash and emits JSON lines.

  Options:
    --limit N        Limit number of records (default: 200)
    --out PATH       Write to file (default: stdout)

  Examples:
      mix lsp.logs.dump
      mix lsp.logs.dump --limit 1000 --out /tmp/lsp_events.jsonl
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: [limit: :integer, out: :string], aliases: [n: :limit, o: :out])
    limit = opts[:limit] || 200
    out = opts[:out]

    import Ash.Query

    events =
      Lang.LspMeasurementEvent
      |> Ash.Query.sort([created_at: :desc])
      |> Ash.Query.limit(limit)
      |> Ash.read!()

    case out do
      nil -> Enum.each(events, &print_line/1)
      path -> Enum.each(events, &append_line(path, &1))
    end
  end

  defp print_line(rec), do: IO.puts(Jason.encode!(to_map(rec)))
  defp append_line(path, rec), do: File.write!(path, Jason.encode!(to_map(rec)) <> "\n", [:append])

  defp to_map(rec) do
    %{
      id: rec.id,
      client_id: rec.client_id,
      method: rec.method,
      duration_ms: rec.duration_ms,
      created_at: Map.get(rec, :created_at),
      error: Map.get(rec, :error),
      request: safe_trunc(rec.request),
      response: safe_trunc(rec.response)
    }
  end

  defp safe_trunc(map) when is_map(map) do
    # Avoid giant payloads in dumps
    map
    |> Map.take(Enum.take(Map.keys(map), 25))
  end
  defp safe_trunc(other), do: other
end

