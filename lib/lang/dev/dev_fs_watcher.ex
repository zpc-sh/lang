defmodule Lang.Dev.DevFSWatcher do
  @moduledoc """
  Simple polling filesystem watcher for dev JSON-LD directory.

  - Uses `Lang.Native.FSScanner` to enumerate files quickly (NIF),
    falling back to `File.ls/1` if unavailable.
  - Emits PubSub events on the configured topic:
      {:fs_event, name, %{path: path, kind: :created | :modified | :deleted}}
  - Options:
      :name        - atom used in events to identify the watcher (required)
      :path        - directory to watch (required)
      :topic       - PubSub topic to broadcast to (required)
      :interval_ms - poll interval (default: 2_000)
  """

  use GenServer
  require Logger

  @type opts :: %{
          required(:name) => atom(),
          required(:path) => String.t(),
          required(:topic) => String.t(),
          optional(:interval_ms) => non_neg_integer()
        }

  def start_link(%{name: name} = opts) when is_atom(name) do
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(%{path: path, topic: topic} = opts) do
    interval = Map.get(opts, :interval_ms, 2_000)
    state = %{
      name: Map.fetch!(opts, :name),
      path: Path.expand(path),
      topic: topic,
      interval_ms: interval,
      snapshot: %{}
    }

    {:ok, snapshot} = take_snapshot(state.path)
    _ = Process.send_after(self(), :tick, interval)
    {:ok, %{state | snapshot: snapshot}}
  end

  @impl true
  def handle_info(:tick, %{interval_ms: ms} = state) do
    state = emit_diffs(state)
    _ = Process.send_after(self(), :tick, ms)
    {:noreply, state}
  end

  defp emit_diffs(%{path: path, snapshot: prev, name: name, topic: topic} = state) do
    case take_snapshot(path) do
      {:ok, curr} ->
        {created, deleted, modified} = diff(prev, curr)
        Enum.each(created, &broadcast(topic, {:fs_event, name, %{path: &1, kind: :created}}))
        Enum.each(modified, &broadcast(topic, {:fs_event, name, %{path: &1, kind: :modified}}))
        Enum.each(deleted, &broadcast(topic, {:fs_event, name, %{path: &1, kind: :deleted}}))
        %{state | snapshot: curr}

      {:error, reason} ->
        Logger.debug("DevFSWatcher snapshot error: #{inspect(reason)}")
        state
    end
  end

  defp broadcast(topic, msg) do
    try do
      Phoenix.PubSub.broadcast(Lang.PubSub, topic, msg)
    rescue
      _ -> :ok
    end
  end

  defp take_snapshot(dir) do
    with {:ok, files} <- list_files(dir) do
      stats =
        files
        |> Enum.map(fn p -> {p, file_mtime(p)} end)
        |> Enum.into(%{})

      {:ok, stats}
    end
  end

  defp list_files(dir) do
    case Code.ensure_loaded(Lang.Native.FSScanner) do
      {:module, _} ->
        case Lang.Native.FSScanner.scan(dir, max_depth: 8) do
          {:ok, %{tree: tree}} -> {:ok, flatten_tree(dir, tree)}
          other -> fallback_list(dir, other)
        end

      _ ->
        fallback_list(dir, :nif_unavailable)
    end
  end

  defp flatten_tree(dir, tree) when is_list(tree) do
    Enum.flat_map(tree, &flatten_tree(dir, &1))
  end

  defp flatten_tree(dir, entry) when is_map(entry) do
    type =
      Map.get(entry, "type") ||
        Map.get(entry, :type) ||
        Map.get(entry, :node_type)

    name = Map.get(entry, "name") || Map.get(entry, :name)
    path = Map.get(entry, "path") || Map.get(entry, :path) || (if is_binary(name), do: Path.join(dir, name))
    children =
      case (Map.get(entry, "children") || Map.get(entry, :children) || []) do
        l when is_list(l) -> l
        _ -> []
      end

    case type do
      "file" -> if is_binary(path), do: [path], else: if is_binary(name), do: [Path.join(dir, name)], else: []
      :file -> if is_binary(path), do: [path], else: if is_binary(name), do: [Path.join(dir, name)], else: []
      "dir" -> flatten_tree(path || Path.join(dir, to_string(name)), children)
      :dir -> flatten_tree(path || Path.join(dir, to_string(name)), children)
      :directory -> flatten_tree(path || Path.join(dir, to_string(name)), children)
      _ ->
        # Unknown type — try to descend if children exist
        if is_list(children) and children != [] do
          flatten_tree(path || dir, children)
        else
          # As a fallback, if a path with a regular file is provided, include it
          if is_binary(path) do
            case File.stat(path) do
              {:ok, %File.Stat{type: :regular}} -> [path]
              _ -> []
            end
          else
            []
          end
        end
    end
  end

  # Gracefully ignore unexpected node shapes
  defp flatten_tree(_dir, _other), do: []

  defp fallback_list(dir, _reason) do
    try do
      {:ok,
       dir
       |> Path.expand()
       |> do_list_recursive()}
    rescue
      e -> {:error, e}
    end
  end

  defp do_list_recursive(dir) do
    case File.ls(dir) do
      {:ok, items} ->
        Enum.flat_map(items, fn name ->
          path = Path.join(dir, name)
          case File.stat(path) do
            {:ok, %File.Stat{type: :regular}} -> [path]
            {:ok, %File.Stat{type: :directory}} -> do_list_recursive(path)
            _ -> []
          end
        end)

      _ -> []
    end
  end

  defp file_mtime(path) do
    case File.stat(path) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      _ -> 0
    end
  end

  defp diff(prev, curr) do
    prev_paths = Map.keys(prev) |> MapSet.new()
    curr_paths = Map.keys(curr) |> MapSet.new()

    created = MapSet.difference(curr_paths, prev_paths) |> MapSet.to_list()
    deleted = MapSet.difference(prev_paths, curr_paths) |> MapSet.to_list()

    modified =
      MapSet.intersection(prev_paths, curr_paths)
      |> Enum.filter(fn p -> Map.get(prev, p) != Map.get(curr, p) end)

    {created, deleted, modified}
  end
end
