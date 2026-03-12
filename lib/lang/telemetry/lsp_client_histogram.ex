defmodule Lang.Telemetry.LSPClientHistogram do
  @moduledoc """
  Simple in-process histogram logger for LSP client durations.

  Creates an ETS table and logs counts per duration bucket every N events.
  Enabled when `LSP_TELEMETRY_LOG=1` (attached by LSPClientLogger).
  """

  @event_stop [:lang, :lsp, :client, :request, :stop]
  @table :lsp_client_hist
  @buckets [10, 50, 100, 250, 500, 1000, 2000]
  @log_every 100

  def ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, {:read_concurrency, true}])
      _ -> @table
    end
  end

  def attach do
    ensure_table()
    id = "lsp-client-hist"
    :telemetry.attach(id, @event_stop, &__MODULE__.handle_event/4, %{})
  rescue
    _ -> :ok
  end

  def handle_event(@event_stop, %{duration_ms: dur}, %{method: method} = _meta, _cfg)
      when is_integer(dur) do
    ensure_table()
    b = bucket(dur)
    :ets.update_counter(@table, {:total, method}, 1, {{:total, method}, 0})
    :ets.update_counter(@table, {b, method}, 1, {{b, method}, 0})

    case :ets.lookup(@table, {:total, method}) do
      [{_, total}] when rem(total, @log_every) == 0 -> log_counts(method)
      _ -> :ok
    end
  end

  def handle_event(_evt, _meas, _meta, _cfg), do: :ok

  defp bucket(ms) do
    Enum.find(@buckets, fn b -> ms <= b end) || :gt_2000
  end

  defp log_counts(method) do
    counts =
      for b <- @buckets ++ [:gt_2000] do
        case :ets.lookup(@table, {b, method}) do
          [{_, c}] -> {b, c}
          [] -> {b, 0}
        end
      end

    total =
      case :ets.lookup(@table, {:total, method}) do
        [{_, t}] -> t
        _ -> 0
      end

    require Logger
    Logger.info("LSP request histogram", method: method, total: total, buckets: counts)
  end
end
