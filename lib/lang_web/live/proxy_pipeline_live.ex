defmodule LangWeb.ProxyPipelineLive do
  use LangWeb, :live_view

  alias Lang.Proxy.StreamBridge

  @impl true
  def mount(%{"pipeline_id" => pid}, _session, socket) do
    topic = StreamBridge.topic(pid)
    if connected?(socket), do: Phoenix.PubSub.subscribe(Lang.PubSub, topic)

    {:ok,
     socket
     |> assign(:pipeline_id, pid)
     |> stream(:events, [])}
  end

  @impl true
  def handle_info({:hop_start, hop}, socket) do
    {:noreply, stream_insert(socket, :events, row(:start, hop))}
  end

  def handle_info({:hop_stop, hop, summary}, socket) do
    {:noreply, stream_insert(socket, :events, row(:stop, hop, summary))}
  end

  def handle_info({:hop_error, hop, err}, socket) do
    {:noreply, stream_insert(socket, :events, row(:error, hop, err))}
  end

  def handle_info({:hop_partial, hop, partial}, socket) do
    {:noreply, stream_insert(socket, :events, row(:partial, hop, partial))}
  end

  defp row(type, hop, meta \\ %{}) do
    %{
      id: System.unique_integer([:positive, :monotonic]),
      type: type,
      hop: hop,
      meta: meta,
      ts: DateTime.utc_now()
    }
  end
end

