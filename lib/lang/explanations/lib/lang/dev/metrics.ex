defmodule Lang.Dev.Metrics do
  @moduledoc """
  Dev-only metrics aggregator for quick attachment by other agents.

  Tracks counts of select event types observed on the PubSub bus and exposes
  simple summary getters. Only active when `:dev_routes` is enabled.
  """

  use GenServer

  @name __MODULE__

  def ensure_started do
    if Application.get_env(:lang, :dev_routes) do
      case Process.whereis(@name) do
        nil -> GenServer.start_link(__MODULE__, %{}, name: @name)
        _pid -> {:ok, @name}
      end
    else
      {:error, :dev_routes_disabled}
    end
  end

  def summary do
    with {:ok, _} <- ensure_started() do
      GenServer.call(@name, :summary)
    end
  end

  @impl true
  def init(_) do
    state = %{
      started_at: DateTime.utc_now(),
      counts: %{diagnostics: 0, completions: 0, analysis_scan: 0, lsp_client: 0, lsp_metrics: 0}
    }

    # Subscribe to common dev topics; callers may add more by subscribing separately.
    topics = [
      "lsp:diagnostics:global",
      "lsp:completions:global",
      "lsp:metrics:global",
      "lsp:clients:global"
    ]
    Enum.each(topics, &safe_subscribe/1)
    {:ok, state}
  end

  @impl true
  def handle_call(:summary, _from, %{counts: counts} = state) do
    uptime = DateTime.diff(DateTime.utc_now(), state.started_at)
    {:reply, %{counts: counts, started_at: state.started_at, uptime_seconds: uptime}, state}
  end

  @impl true
  def handle_info(%{diagnostics: _} = _evt, state), do: {:noreply, inc(state, :diagnostics)}
  def handle_info(%{uri: _uri, diagnostics: _} = _evt, state), do: {:noreply, inc(state, :diagnostics)}
  def handle_info(%{position: _, completions: _} = _evt, state), do: {:noreply, inc(state, :completions)}
  def handle_info({:scan_progress, _status, _data}, state), do: {:noreply, inc(state, :analysis_scan)}

  def handle_info(%{type: type} = _evt, state) when type in [:connected, :initialized, :activity, :disconnected], do: {:noreply, inc(state, :lsp_client)}
  def handle_info(%{event: event} = _evt, state) when event in [:request, :response, :connection], do: {:noreply, inc(state, :lsp_metrics)}

  def handle_info(_msg, state), do: {:noreply, state}

  defp inc(%{counts: counts} = state, key) do
    %{state | counts: Map.update(counts, key, 1, &(&1 + 1))}
  end

  defp safe_subscribe(topic) do
    _ = try do Phoenix.PubSub.subscribe(LangWeb.Endpoint, topic) rescue _ -> :ok end
    _ = try do Phoenix.PubSub.subscribe(Lang.PubSub, topic) rescue _ -> :ok end
    :ok
  end
end
