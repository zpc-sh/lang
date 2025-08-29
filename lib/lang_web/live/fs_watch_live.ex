defmodule LangWeb.FSWatchLive do
  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Filesystem Watch (Demo)")
     |> assign(:path, System.cwd!())
     |> assign(:interval_ms, 3000)
     |> assign(:duration_ms, 15000)
     |> assign(:stream_id, nil)
     |> assign(:topic, nil)
     |> assign(:snapshots_count, 0)
     |> assign(:last_seq, nil)
     |> assign(:watching?, false)
     |> stream(:snapshots, [])}
  end

  @impl true
  def handle_event("start", params, socket) do
    path = Map.get(params, "path", socket.assigns.path)
    interval_ms = parse_int(params["interval_ms"], socket.assigns.interval_ms)
    duration_ms = parse_int(params["duration_ms"], socket.assigns.duration_ms)

    req = %{
      "jsonrpc" => "2.0",
      "id" => Ecto.UUID.generate(),
      "method" => "lang.fs.watch",
      "params" => %{
        "path" => path,
        "interval_ms" => interval_ms,
        "duration_ms" => duration_ms
      }
    }

    case Lang.LSP.Dispatch.process(req) do
      %{"result" => %{"stream_id" => sid, "topic" => topic}} ->
        Phoenix.PubSub.subscribe(Lang.PubSub, topic)
        {:noreply, assign(socket, stream_id: sid, topic: topic, watching?: true, path: path, interval_ms: interval_ms, duration_ms: duration_ms)}

      %{"error" => err} ->
        {:noreply, put_flash(socket, :error, "Failed to start watch: #{inspect(err)}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Unexpected response starting watch")}
    end
  end

  @impl true
  def handle_info({:fs_snapshot, sid, %{seq: seq, result: result}}, socket) do
    if sid == socket.assigns.stream_id do
      {:noreply,
       socket
       |> assign(:snapshots_count, socket.assigns.snapshots_count + 1)
       |> assign(:last_seq, seq)
       |> stream_insert(:snapshots, %{id: "#{sid}-#{seq}", seq: seq, stats: result[:stats] || result["stats"], at: DateTime.utc_now()})}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:fs_error, sid, payload}, socket) do
    if sid == socket.assigns.stream_id do
      {:noreply, put_flash(socket, :error, "Watch error: #{inspect(payload[:reason] || payload["reason"])}")}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:fs_watch_complete, sid}, socket) do
    if sid == socket.assigns.stream_id do
      {:noreply,
       socket
       |> assign(:watching?, false)
       |> put_flash(:info, "Watch complete")}
    else
      {:noreply, socket}
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> default
    end
  end
  defp parse_int(val, _default) when is_integer(val), do: val
end
