defmodule Lang.Telemetry.LSPClientLogger do
  @moduledoc """
  Simple telemetry logger for LSP client timings.

  Attach by calling `maybe_attach/0`, which checks `LSP_TELEMETRY_LOG` env.
  Emits start/stop events with method and duration.
  """

  require Logger

  @event_start [:lang, :lsp, :client, :request, :start]
  @event_stop [:lang, :lsp, :client, :request, :stop]

  def maybe_attach do
    v = System.get_env("LSP_TELEMETRY_LOG") || "0"
    if String.downcase(v) in ["1", "true", "yes", "on"], do: attach(), else: :ok
  end

  def attach do
    id = "lsp-client-logger"
    :telemetry.attach_many(id, [@event_start, @event_stop], &__MODULE__.handle_event/4, %{})
    Lang.Telemetry.LSPClientHistogram.attach()
    :ok
  rescue
    _ -> :ok
  end

  def handle_event(@event_start, _measures, metadata, _config) do
    method = metadata[:method] || metadata["method"]
    Logger.debug("LSP request start", method: method, id: metadata[:id])
  end

  def handle_event(@event_stop, measures, metadata, _config) do
    method = metadata[:method] || metadata["method"]
    Logger.debug("LSP request stop", method: method, id: metadata[:id], timeout: metadata[:timeout], recv_error: metadata[:recv_error], duration_ms: measures[:duration_ms])
  end

  def handle_event(_evt, _measures, _metadata, _config), do: :ok
end
