defmodule Lang.Proxy.StreamCapture do
  @moduledoc "Debug capture for proxy stream events (dev-only recommended). Stores compact JSON in Redis when enabled."

  @enable Application.compile_env(:lang, :enable_proxy_stream_capture, false)
  @max 500

  def capture(pipeline_id, event, hop, payload) do
    if enabled?() and Lang.Redis.available?() do
      entry = %{
        ts: DateTime.utc_now() |> DateTime.to_iso8601(),
        event: event,
        hop: hop,
        payload: redact(payload)
      }

      key = "proxy:capture:" <> pipeline_id
      json = Jason.encode!(entry)
      _ = Lang.Redis.pipeline([["LPUSH", key, json], ["LTRIM", key, "0", Integer.to_string(@max - 1)], ["EXPIRE", key, Integer.to_string(3600)]])
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  def enabled?, do: @enable || Application.get_env(:lang, :enable_proxy_stream_capture, false)

  defp redact(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, redact_value(k, v)} end)
  end
  defp redact(list) when is_list(list), do: Enum.map(list, &redact/1)
  defp redact(v), do: v

  defp redact_value(k, v) do
    sk = to_string(k)
    if sk in ["intent", "token", "password", "secret", "api_key", "bearer"] do
      "[REDACTED]"
    else
      redact(v)
    end
  end
end

