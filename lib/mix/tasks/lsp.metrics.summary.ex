defmodule Mix.Tasks.Lsp.Metrics.Summary do
  use Mix.Task

  @shortdoc "Summarize recent LSP metrics (per method avg/p95/count)"
  @moduledoc """
  Reads recent `Lang.LspMeasurementEvent` rows and prints a per-method summary:
  count, avg ms, p95 ms. Intended for quick optimization loops.

  Options:
    --since-minutes N   Time window (default: 60)
    --method NAME       Filter by method name (e.g., textDocument/completion)
    --limit N           Max records to load (default: 2000)

  Examples:
    mix lsp.metrics.summary
    mix lsp.metrics.summary --since-minutes 15 --method textDocument/completion
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [since_minutes: :integer, method: :string, limit: :integer],
        aliases: [m: :method]
      )

    since_min = opts[:since_minutes] || 60
    limit = opts[:limit] || 2000
    method_filter = opts[:method]
    from = DateTime.add(DateTime.utc_now(), -since_min * 60, :second)

    import Ash.Query

    q =
      Lang.LspMeasurementEvent
      |> Ash.Query.filter(created_at >= ^from)
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(limit)

    events = Ash.read!(q)

    events =
      case method_filter do
        nil -> events
        m -> Enum.filter(events, &(&1.method == m))
      end

    groups = Enum.group_by(events, & &1.method)

    rows =
      for {method, list} <- groups do
        durs =
          list
          |> Enum.map(&(&1.duration_ms || 0))
          |> Enum.sort()

        count = length(durs)
        avg = if count > 0, do: Enum.sum(durs) / count, else: 0
        p95 = percentile(durs, 0.95)
        %{method: method, count: count, avg_ms: Float.round(avg, 2), p95_ms: p95}
      end
      |> Enum.sort_by(& &1.p95_ms, :desc)

    print_table(rows)
  end

  defp percentile([], _p), do: 0
  defp percentile(vals, p) do
    idx = max(0, min(length(vals) - 1, round(p * (length(vals) - 1))))
    Enum.at(vals, idx) || 0
  end

  defp print_table(rows) do
    IO.puts("method,count,avg_ms,p95_ms")
    Enum.each(rows, fn r ->
      IO.puts(Enum.join([r.method, r.count, r.avg_ms, r.p95_ms], ","))
    end)
  end
end

