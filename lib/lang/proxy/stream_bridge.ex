defmodule Lang.Proxy.StreamBridge do
  @moduledoc "PubSub bridge for proxy pipeline events"

  @prefix "proxy:pipeline:"

  def topic(pipeline_id) when is_binary(pipeline_id), do: @prefix <> pipeline_id

  def hop_start(pipeline_id, hop), do: hop_start(pipeline_id, hop, %{})

  def hop_start(pipeline_id, hop, meta) do
    Phoenix.PubSub.broadcast(Lang.PubSub, topic(pipeline_id), {:hop_start, hop})
    Lang.Proxy.StreamCapture.capture(pipeline_id, :hop_start, hop, meta || %{})
  end

  def hop_stop(pipeline_id, hop, result), do: hop_stop(pipeline_id, hop, result, %{})

  def hop_stop(pipeline_id, hop, result, meta) do
    summary = summarize(result)
    Phoenix.PubSub.broadcast(Lang.PubSub, topic(pipeline_id), {:hop_stop, hop, summary})
    Lang.Proxy.StreamCapture.capture(pipeline_id, :hop_stop, hop, Map.merge(summary, meta || %{}))
  end

  def hop_error(pipeline_id, hop, code, message, data), do: hop_error(pipeline_id, hop, code, message, data, %{})

  def hop_error(pipeline_id, hop, code, message, data, meta) do
    payload = %{code: code, message: message, data: data}
    Phoenix.PubSub.broadcast(Lang.PubSub, topic(pipeline_id), {:hop_error, hop, payload})
    Lang.Proxy.StreamCapture.capture(pipeline_id, :hop_error, hop, Map.merge(payload, meta || %{}))
  end

  def hop_partial(pipeline_id, hop, payload) do
    summary = summarize(payload)
    Phoenix.PubSub.broadcast(Lang.PubSub, topic(pipeline_id), {:hop_partial, hop, summary})
    Lang.Proxy.StreamCapture.capture(pipeline_id, :hop_partial, hop, summary)
  end

  defp summarize(%{} = map), do: Map.take(map, [:status, :count, :file_path])
  defp summarize(list) when is_list(list), do: %{count: length(list)}
  defp summarize(other), do: %{value: inspect(other)}
end
