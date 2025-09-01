defmodule Lang.Dev.FSWatcherLogger do
  @moduledoc """
  Dev visibility consumer for FS watcher events.

  Subscribes to a PubSub topic (default: "dev:fs:jsonld") and logs concise
  file change events. Purely for developer visibility and diagnostics.
  """

  use GenServer
  require Logger

  @default_topic "dev:fs:jsonld"
  @default_level :debug

  def start_link(opts \\ %{}) do
    name =
      cond do
        is_map(opts) -> Map.get(opts, :name)
        is_list(opts) -> Keyword.get(opts, :name)
        true -> nil
      end || __MODULE__

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    cfg = Application.get_env(:lang, :fswatcher_logger, [])

    opt_topic = if is_map(opts), do: Map.get(opts, :topic), else: Keyword.get(opts, :topic)
    cfg_topic = if is_list(cfg), do: Keyword.get(cfg, :topic), else: nil
    topic = opt_topic || cfg_topic || @default_topic

    opt_level = if is_map(opts), do: Map.get(opts, :level), else: Keyword.get(opts, :level)
    cfg_level = if is_list(cfg), do: Keyword.get(cfg, :level), else: nil
    level = opt_level || cfg_level || @default_level

    opt_kinds = if is_map(opts), do: Map.get(opts, :kinds), else: Keyword.get(opts, :kinds)
    cfg_kinds = if is_list(cfg), do: Keyword.get(cfg, :kinds), else: nil
    kinds = opt_kinds || cfg_kinds

    opt_color = if is_map(opts), do: Map.get(opts, :color), else: Keyword.get(opts, :color)
    cfg_color = if is_list(cfg), do: Keyword.get(cfg, :color), else: nil
    color? = if is_boolean(opt_color), do: opt_color, else: (if is_boolean(cfg_color), do: cfg_color, else: true)

    # Optional format preset support (mirrors the watch task)
    preset = Application.get_env(:lang, :fswatcher_preset)
    ts_preset = Application.get_env(:lang, :fswatcher_timestamp, false)

    opt_format = if is_map(opts), do: Map.get(opts, :format), else: Keyword.get(opts, :format)
    cfg_format = if is_list(cfg), do: Keyword.get(cfg, :format), else: nil
    format =
      cond do
        opt_format in [:json, :align, :line] -> opt_format
        cfg_format in [:json, :align, :line] -> cfg_format
        preset in [:json, "json", :machine, "machine"] -> :json
        preset in [:align, "align", :compact, "compact"] -> :align
        true -> :line
      end

    opt_cols = if is_map(opts), do: Map.get(opts, :cols), else: Keyword.get(opts, :cols)
    cfg_cols = if is_list(cfg), do: Keyword.get(cfg, :cols), else: nil
    cols_default = if preset in [:compact, "compact"], do: 80, else: 100
    cols = opt_cols or cfg_cols or cols_default

    opt_ts = if is_map(opts), do: Map.get(opts, :timestamp), else: Keyword.get(opts, :timestamp)
    cfg_ts = if is_list(cfg), do: Keyword.get(cfg, :timestamp), else: nil
    timestamp? =
      cond do
        is_boolean(opt_ts) -> opt_ts
        is_boolean(cfg_ts) -> cfg_ts
        preset in [:machine, "machine"] -> true
        true -> ts_preset
      end
    try do
      Phoenix.PubSub.subscribe(Lang.PubSub, topic)
    rescue
      _ -> :ok
    end
    {:ok, %{topic: topic, level: level, kinds: kinds, color: color?, format: format, cols: cols, timestamp: timestamp?, count: 0, counts: %{:created => 0, :modified => 0, :deleted => 0}}}
  end

  @impl true
  def handle_info({:fs_event, name, %{path: path, kind: kind}} = _msg, state) do
    # Apply optional kind filtering and colorized formatting
    kinds = Map.get(state, :kinds)
    color? = Map.get(state, :color, true)
    if Lang.Dev.FSWatch.Util.allow_kind?(kind, kinds) do
      ev = %{name: name, kind: kind, path: path, topic: Map.get(state, :topic)}
      case render(ev, state) do
        nil -> :ok
        io -> Logger.log(state.level, IO.iodata_to_binary(io))
      end
    end
    counts = Map.update(state.counts, kind, 1, &(&1 + 1))
    {:noreply, %{state | count: state.count + 1, counts: counts}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @doc """
  Returns a summary map: %{topic: ..., total: n, by_kind: %{created: x, modified: y, deleted: z}}
  """
  def summary(pid \\ __MODULE__) do
    GenServer.call(pid, :summary)
  end

  @impl true
  def handle_call(:summary, _from, %{topic: topic, count: count, counts: counts} = state) do
    {:reply, %{topic: topic, total: count, by_kind: counts}, state}
  end

  # Backwards-compat helper kept for any external references
  defp relative(path), do: Lang.Dev.FSWatch.Util.relative(path)
  # Render using middlewares based on the chosen format preset
  defp render(ev, %{kinds: kinds, color: color?, format: :json, timestamp: ts?}) do
    Lang.Dev.FSWatch.Pipeline.run(ev, %{middlewares: [Lang.Dev.FSWatch.MW.FilterKinds, Lang.Dev.FSWatch.MW.JsonLine], kinds: kinds, color: color?, timestamp: ts?})
  end

  defp render(ev, %{kinds: kinds, color: color?, format: :align, cols: cols, timestamp: ts?}) do
    mws = [Lang.Dev.FSWatch.MW.FilterKinds]
    mws = mws ++ (if ts?, do: [Lang.Dev.FSWatch.MW.Timestamp], else: [])
    mws = mws ++ [{Lang.Dev.FSWatch.MW.Align, [color: color?, path_width: cols]}]
    Lang.Dev.FSWatch.Pipeline.run(ev, %{middlewares: mws, kinds: kinds, color: color?})
  end

  defp render(ev, %{kinds: kinds, color: color?, format: :line, timestamp: ts?}) do
    mws = [Lang.Dev.FSWatch.MW.FilterKinds]
    mws = mws ++ (if ts?, do: [Lang.Dev.FSWatch.MW.Timestamp], else: [])
    mws = mws ++ [{Lang.Dev.FSWatch.MW.FormatLine, [color: color?]}]
    Lang.Dev.FSWatch.Pipeline.run(ev, %{middlewares: mws, kinds: kinds, color: color?})
  end

end
