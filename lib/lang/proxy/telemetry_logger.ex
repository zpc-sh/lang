defmodule Lang.Proxy.TelemetryLogger do
  @moduledoc "Simple console logger for proxy telemetry events (dev/test)."

  @id "proxy-telemetry-logger"

  def maybe_attach do
    # Attach in non-prod by default; configurable via :enable_proxy_telemetry_logger
    if attach?() do
      events = [
        [:lang, :proxy, :heuristic_block],
        [:lang, :proxy, :policy_denied]
      ]

      :telemetry.attach_many(@id, events, &__MODULE__.handle_event/4, %{})
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  def handle_event(event, measurements, meta, _config) do
    IO.puts("[proxy] #{inspect(event)} measurements=#{inspect(measurements)} meta=#{inspect(meta)}")
  end

  defp attach? do
    case Application.get_env(:lang, :enable_proxy_telemetry_logger) do
      true -> true
      false -> false
      _ -> Mix.env() != :prod
    end
  end
end

