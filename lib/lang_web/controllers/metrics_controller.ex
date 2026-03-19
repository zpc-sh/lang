defmodule LangWeb.MetricsController do
  use LangWeb, :controller

  @doc """
  Aggregate metrics exposition (Prometheus text format).
  Currently includes provider credential resolution counters.
  """
  def index(conn, _params) do
    body = providers_body()

    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, body)
  end

  @doc """
  Prometheus exposition for provider credential resolution metrics.
  Secured via :browser_json_admin pipeline.
  """
  def providers(conn, _params) do
    body = providers_body()
    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> send_resp(200, body)
  end

  defp providers_body do
    metrics = Lang.Providers.CredentialsTelemetry.snapshot()

    counters = [
      "# HELP lang_provider_credentials_resolution_total Total credential resolution attempts",
      "# TYPE lang_provider_credentials_resolution_total counter"
    ] ++ Enum.flat_map(metrics, fn
      {{:provider_resolution_total, provider, status}, count} ->
        status_label = if status == :ok, do: "ok", else: "error"
        [
          "lang_provider_credentials_resolution_total{provider=\"#{provider}\",status=\"#{status_label}\"} #{count}"
        ]
      _ -> []
    end)

    # Histogram exposition
    buckets = [1, 5, 10, 25, 50, 100, 250, 500, 1000, :inf]
    providers =
      metrics
      |> Map.keys()
      |> Enum.reduce(MapSet.new(), fn
        {:provider_resolution_latency_sum, provider}, acc -> MapSet.put(acc, provider)
        _other, acc -> acc
      end)
      |> MapSet.to_list()

    hist_header = [
      "# HELP lang_provider_credentials_resolution_latency_seconds Credential resolution latency",
      "# TYPE lang_provider_credentials_resolution_latency_seconds histogram"
    ]

    hist = Enum.flat_map(providers, fn provider ->
      # Build cumulative counts
      {counts_map, sum, cnt} =
        { %{}, Map.get(metrics, {:provider_resolution_latency_sum, provider}, 0.0), Map.get(metrics, {:provider_resolution_latency_count, provider}, 0)}

      raw_counts = Enum.map(buckets, fn b ->
        {b, Map.get(metrics, {:provider_resolution_latency_bucket, provider, b}, 0)}
      end)

      cumulative =
        raw_counts
        |> Enum.reduce({[], 0}, fn {b, c}, {acc, total} ->
          new_total = total + c
          {[{b, new_total} | acc], new_total}
        end)
        |> elem(0)
        |> Enum.reverse()

      bucket_lines = Enum.map(cumulative, fn {b, cval} ->
        le = if b == :inf, do: "+Inf", else: to_string(b / 1000)
        "lang_provider_credentials_resolution_latency_seconds_bucket{provider=\"#{provider}\",le=\"#{le}\"} #{cval}"
      end)

      sum_line = "lang_provider_credentials_resolution_latency_seconds_sum{provider=\"#{provider}\"} #{sum / 1000}"
      cnt_line = "lang_provider_credentials_resolution_latency_seconds_count{provider=\"#{provider}\"} #{cnt}"

      bucket_lines ++ [sum_line, cnt_line]
    end)

    Enum.join(counters ++ hist_header ++ hist, "\n") <> "\n"
  end
end
