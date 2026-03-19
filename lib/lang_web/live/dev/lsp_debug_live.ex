defmodule LangWeb.Dev.LspDebugLive do
  use LangWeb, :live_view
  require Logger

  @refresh_lines 200

  def mount(_params, _session, socket) do
    debug_path = System.get_env("LSP_DEBUG_LOG")
    metrics_path = System.get_env("LSP_METRICS_LOG")

    socket =
      socket
      |> assign(:debug_path, debug_path)
      |> assign(:metrics_path, metrics_path)
      |> assign(:stream_id, "")
      |> assign(:subscribed?, false)
      |> assign(:last_refreshed_at, nil)
      |> stream(:logs, [])
      |> stream(:metrics, [])
      |> stream(:reviews, [])

    {:ok, maybe_refresh(socket), temporary_assigns: [logs: [], metrics: [], reviews: []]}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, maybe_refresh(socket)}
  end

  def handle_event("subscribe", %{"stream_id" => stream_id}, socket) do
    stream_id = String.trim(to_string(stream_id))

    if stream_id != "" do
      topic = "lsp:review:" <> stream_id
      Phoenix.PubSub.subscribe(Lang.PubSub, topic)
      {:noreply, assign(socket, stream_id: stream_id, subscribed?: true)}
    else
      {:noreply, assign(socket, stream_id: stream_id, subscribed?: false)}
    end
  end

  # Review streaming events
  def handle_info({:review_code, phase, payload}, socket) do
    item = %{
      at: DateTime.utc_now(),
      phase: phase,
      text: Map.get(payload || %{}, :text) || Map.get(payload || %{}, "text") || inspect(payload)
    }

    {:noreply, stream_insert(socket, :reviews, item)}
  end

  def handle_info({:review_code, :completed, payload}, socket) do
    item = %{
      at: DateTime.utc_now(),
      phase: :completed,
      text: "Completed in #{(payload || %{})[:duration_ms] || (payload || %{})["duration_ms"]} ms"
    }

    {:noreply, stream_insert(socket, :reviews, item)}
  end

  defp maybe_refresh(socket) do
    socket
    |> load_debug()
    |> load_metrics()
    |> assign(:last_refreshed_at, DateTime.utc_now())
  end

  defp load_debug(%{assigns: %{debug_path: nil}} = socket), do: socket
  defp load_debug(%{assigns: %{debug_path: path}} = socket) do
    case Lang.Native.FSScanner.preview(path, max_lines: @refresh_lines) do
      {:ok, lines} ->
        items =
          lines
          |> List.wrap()
          |> Enum.map(&parse_jsonl/1)
          |> Enum.map(fn m -> Map.put(m, :_id, make_ref()) end)

        stream(socket, :logs, items, reset: true)

      {:error, _} -> socket
    end
  end

  defp load_metrics(%{assigns: %{metrics_path: nil}} = socket), do: socket
  defp load_metrics(%{assigns: %{metrics_path: path}} = socket) do
    case Lang.Native.FSScanner.preview(path, max_lines: @refresh_lines) do
      {:ok, lines} ->
        items =
          lines
          |> List.wrap()
          |> Enum.map(&parse_jsonl/1)
          |> Enum.map(fn m -> Map.put(m, :_id, make_ref()) end)

        stream(socket, :metrics, items, reset: true)

      {:error, _} -> socket
    end
  end

  defp parse_jsonl(line) when is_binary(line) do
    case Jason.decode(line) do
      {:ok, map} -> map
      _ -> %{raw: line}
    end
  end
end

