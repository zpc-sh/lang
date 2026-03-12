defmodule Lang.Observability do
  @moduledoc """
  Thin wrapper for optional error reporting backends (e.g., Sentry).

  Avoids hard dependency: only calls Sentry if available and configured.
  """

  require Logger

  @spec capture(String.t(), map()) :: :ok
  def capture(message, context \\ %{}) when is_binary(message) and is_map(context) do
    cond do
      sentry_available?() ->
        try do
          Sentry.capture_message(message, extra: context)
          :ok
        rescue
          e ->
            Logger.debug("Sentry capture failed", error: e)
            :ok
        end

      true -> :ok
    end
  end

  defp sentry_available? do
    Code.ensure_loaded?(Sentry) and sentry_configured?()
  end

  defp sentry_configured? do
    case Application.get_env(:sentry, :dsn) do
      nil -> false
      "" -> false
      _ -> true
    end
  end
end

