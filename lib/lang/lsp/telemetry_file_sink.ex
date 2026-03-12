defmodule Lang.LSP.TelemetryFileSink do
  @moduledoc """
  Minimal telemetry sink to write LSP client/server metrics and maintain light aggregates.

  Usage (auto): set `LSP_METRICS_LOG=/tmp/lsp_metrics.jsonl` before running `mix lsp.smoke`.
  Usage (manual): `Lang.LSP.TelemetryFileSink.attach(path)`
  """

  @events [
    [:lang, :lsp, :client, :connect],
    [:lang, :lsp, :client, :initialize],
    [:lang, :lsp, :client, :request],
    [:lang, :lsp, :client, :ping],
    [:lang, :lsp, :server, :request],
    # Folder adapter events
    [:lang, :folder, :registry, :manifest],
    [:lang, :folder, :registry, :blob]
  ]

  @table :lsp_metrics_agg
  @hist :lsp_metrics_hist
  @buckets [10, 25, 50, 100, 200, 400, 800, 1600, 3200, 6400, 12800]

  def attach(path \\ nil) do
    path = path || System.get_env("LSP_METRICS_LOG")
    if path do
      ensure()
      id = handler_id()
      :telemetry.attach_many(id, @events, &__MODULE__.handle_event/4, %{path: path})
      # Optional periodic rollup flush
      interval = env_int("LSP_METRICS_FLUSH_MS", 5_000)
      if interval > 0 do
        parent = self()
        spawn_link(fn -> flush_loop(path, interval, parent) end)
      end
      :ok
    else
      :noop
    end
  rescue
    _ -> :error
  end

  def detach do
    :telemetry.detach(handler_id())
  rescue
    _ -> :ok
  end

  def handle_event(event, meas, meta, %{path: path}) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601()
    data = %{ts: ts, event: Enum.join(event, "."), measurements: meas, metadata: shrink(meta)}
    write_line(path, Jason.encode!(data))
    aggregate(event, meas, meta)
  rescue
    _ -> :ok
  end

  defp shrink(meta) when is_map(meta) do
    Map.take(meta, Enum.take(Map.keys(meta), 8))
  end
  defp shrink(other), do: other

  defp write_line(path, line) do
    try do
      File.write!(path, line <> "\n", [:append])
    rescue
      _ -> :ok
    end
  end

  defp aggregate([:lang, :lsp, :server, :request], %{duration: dur}, %{method: m}), do: bump({:srv, m}, dur)
  defp aggregate([:lang, :lsp, :client, :request], %{duration: dur}, %{method: m}), do: bump({:cli, m}, dur)
  defp aggregate(_e, _m, _md), do: :ok

  defp bump(key, dur) when is_number(dur) do
    ensure()
    :ets.update_counter(@table, key, [{2, 1}, {3, dur}], {key, 0, 0})
    # Update histogram bucket count
    b = bucket_for(dur)
    :ets.update_counter(@hist, {key, b}, {3, 1}, {{key, b}, b, 0})
  end

  defp ensure do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
      _ -> :ok
    end
    case :ets.whereis(@hist) do
      :undefined -> :ets.new(@hist, [:named_table, :public, :set, write_concurrency: true])
      _ -> :ok
    end
  end

  defp handler_id, do: {__MODULE__, self()}

  defp flush_loop(path, interval, parent) do
    receive do
      {:EXIT, ^parent, _} -> :ok
    after
      interval ->
        flush_rollups(path)
        flush_loop(path, interval, parent)
    end
  end

  def flush_rollups(path) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601()
    stats =
      for {key, count, sum} <- :ets.tab2list(@table) do
        avg = if count > 0, do: sum / count, else: 0
        p95 = approx_p95(key, count)
        %{key: key, count: count, avg_ms: Float.round(avg, 2), sum_ms: sum, p95_ms: p95}
      end
    write_line(path, Jason.encode!(%{ts: ts, event: "rollup", stats: stats}))
  end

  defp approx_p95(key, count) when count > 0 do
    buckets = Enum.sort_by(:ets.match_object(@hist, {{key, :_}, :_, :_}), fn {{_, b}, _, _} -> b end)
    total = Enum.reduce(buckets, 0, fn {{_, _}, _, c}, acc -> acc + c end)
    target = trunc(total * 0.95)
    {acc, val} =
      Enum.reduce_while(buckets, {0, 0}, fn {{_, b}, _bucket_val, c}, {a, _} ->
        na = a + c
        if na >= target, do: {:halt, {na, b}}, else: {:cont, {na, b}}
      end)
    _ = acc
    val
  rescue
    _ -> nil
  end

  defp bucket_for(dur) do
    Enum.find(@buckets, List.last(@buckets), fn edge -> dur <= edge end)
  end

  defp env_int(var, default) do
    case System.get_env(var) do
      nil -> default
      v ->
        case Integer.parse(v) do
          {i, _} -> i
          _ -> default
        end
    end
  end
end
