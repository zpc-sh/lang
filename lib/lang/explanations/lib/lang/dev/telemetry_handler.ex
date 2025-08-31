defmodule Lang.Dev.TelemetryHandler do
  @moduledoc """
  Attaches telemetry handlers for the dev model pipeline spans and logs concise entries.

  Handlers are idempotent by name and safe to call multiple times.
  """

  require Logger

  @id "dev-models-telemetry"
  @events [
    [:lang, :dev_models, :render, :start],
    [:lang, :dev_models, :render, :stop],
    [:lang, :dev_models, :render, :exception],
    [:lang, :dev_models, :ingest, :start],
    [:lang, :dev_models, :ingest, :stop],
    [:lang, :dev_models, :ingest, :exception]
  ]

  def attach do
    try do
      :telemetry.attach_many(@id, @events, &__MODULE__.handle_event/4, %{})
      :ok
    rescue
      _ -> :ok
    end
  end

  def detach do
    try do
      :telemetry.detach(@id)
      :ok
    rescue
      _ -> :ok
    end
  end

  def handle_event([:lang, :dev_models, stage, :start], _measure, meta, _config) do
    Logger.debug("dev_models #{stage} start id=#{meta[:id]}")
    Phoenix.PubSub.broadcast(Lang.PubSub, "dev:models", {:telemetry, stage, :start, Map.take(meta, [:id]) , 0})
  end
  def handle_event([:lang, :dev_models, stage, :stop], meas, meta, _config) do
    ms = trunc((meas[:duration] || 0) / 1_000)
    Logger.info("dev_models #{stage} stop id=#{meta[:id]} duration_ms=#{ms}")
    Phoenix.PubSub.broadcast(Lang.PubSub, "dev:models", {:telemetry, stage, :stop, Map.take(meta, [:id]) , ms})
  end
  def handle_event([:lang, :dev_models, stage, :exception], meas, meta, _config) do
    ms = trunc((meas[:duration] || 0) / 1_000)
    Logger.error("dev_models #{stage} exception id=#{meta[:id]} duration_ms=#{ms} error=#{inspect(meta[:kind])}")
    Phoenix.PubSub.broadcast(Lang.PubSub, "dev:models", {:telemetry, stage, :exception, Map.take(meta, [:id, :kind, :reason, :stacktrace]) , ms})
  end
end
