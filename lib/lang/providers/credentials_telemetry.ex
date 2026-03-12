defmodule Lang.Providers.CredentialsTelemetry do
  @moduledoc """
  Telemetry handler for provider credential resolution.

  - Logs resolution success/failure
  - Emits Ash events via Lang.Events for auditing
  Attach on app boot (PerformanceMonitor calls attach/0).
  """

  require Logger

  @event [:lang, :providers, :credentials, :resolve, :stop]
  @table :lang_provider_metrics

  def attach do
    :telemetry.attach({__MODULE__, :stop}, @event, &__MODULE__.handle/4, %{})
  rescue
    ArgumentError -> :ok
  end

  def handle(_event, measurements, metadata, _config) do
    status = Map.get(measurements, :status, false)
    duration_ns = Map.get(measurements, :duration)
    provider = Map.get(metadata, :provider)
    org_id = Map.get(metadata, :organization_id)
    user_id = Map.get(metadata, :user_id)

    case status do
      true ->
        Logger.info("Provider credentials resolved", provider: provider, organization_id: org_id, user_id: user_id)
        _ = Lang.Events.track_event(%{
          event_type: "provider_credentials_resolved",
          organization_id: org_id,
          user_id: user_id,
          metadata: %{provider: provider}
        })
        inc(provider, :ok)
        inc_latency(provider, duration_ns)

      false ->
        Logger.warning("Provider credentials resolution FAILED", provider: provider, organization_id: org_id, user_id: user_id)
        _ = Lang.Events.track_event(%{
          event_type: "provider_credentials_resolution_failed",
          organization_id: org_id,
          user_id: user_id,
          metadata: %{provider: provider}
        })
        _ = Lang.Observability.capture("provider_credentials_resolution_failed", %{provider: provider, organization_id: org_id, user_id: user_id})
        inc(provider, :error)
        inc_latency(provider, duration_ns)
    end

    :ok
  end

  def inc(provider, status) do
    ensure_table()
    key = {:provider_resolution_total, provider, status}
    case :ets.lookup(@table, key) do
      [{^key, count}] -> :ets.insert(@table, {key, count + 1})
      [] -> :ets.insert(@table, {key, 1})
    end
  end

  def snapshot do
    ensure_table()
    :ets.tab2list(@table)
    |> Enum.into(%{})
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
      _ -> @table
    end
  end

  # Latency histogram storage (ms)
  defp inc_latency(_provider, nil), do: :ok
  defp inc_latency(provider, duration_ns) when is_integer(duration_ns) do
    ensure_table()
    ms = duration_ns / 1_000_000
    bucket = pick_bucket(ms)
    bkey = {:provider_resolution_latency_bucket, provider, bucket}
    sum_key = {:provider_resolution_latency_sum, provider}
    cnt_key = {:provider_resolution_latency_count, provider}

    # bucket count
    case :ets.lookup(@table, bkey) do
      [{^bkey, count}] -> :ets.insert(@table, {bkey, count + 1})
      [] -> :ets.insert(@table, {bkey, 1})
    end

    # sum and count
    case :ets.lookup(@table, sum_key) do
      [{^sum_key, sum}] -> :ets.insert(@table, {sum_key, sum + ms})
      [] -> :ets.insert(@table, {sum_key, ms})
    end

    case :ets.lookup(@table, cnt_key) do
      [{^cnt_key, c}] -> :ets.insert(@table, {cnt_key, c + 1})
      [] -> :ets.insert(@table, {cnt_key, 1})
    end
  end

  defp pick_bucket(ms) do
    cond do
      ms <= 1 -> 1
      ms <= 5 -> 5
      ms <= 10 -> 10
      ms <= 25 -> 25
      ms <= 50 -> 50
      ms <= 100 -> 100
      ms <= 250 -> 250
      ms <= 500 -> 500
      ms <= 1000 -> 1000
      true -> :inf
    end
  end
end
