defmodule Lang.Dev.DevFSWatcher do
  @moduledoc """
  Dev-only filesystem watcher based on periodic NIF scans.

  - Polls a directory at a fixed interval.
  - When the set of files changes, broadcasts a PubSub message to the given topic.
  - Intended for use only when `:dev_routes` is enabled.
  """

  use GenServer
  require Logger

  @type opts :: %{
          required(:name) => atom(),
          required(:path) => String.t(),
          required(:topic) => String.t(),
          optional(:interval_ms) => non_neg_integer()
        }

  def start_link(opts) when is_map(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_name(opts.name))
  end

  defp via_name(name) when is_atom(name), do: Module.concat(__MODULE__, name)

  @impl true
  def handle_info(:poll, %{path: path, topic: topic, interval: interval} = state) do
    files = list_json_files(path)
    hash = :erlang.phash2(files)
    state =
      case state.last_hash do
        ^hash -> state
        _ ->
          # Broadcast a simple change signal with the file list
          _ = safe_broadcast(topic, {:changed, files})
          %{state | last_hash: hash}
      end

    Process.send_after(self(), :poll, interval)
    {:noreply, state}
  end

  defp list_json_files(dir) do
    case Lang.Native.FSScanner.scan(dir, max_depth: 1) do
      {:ok, %{tree: tree}} ->
        tree
        |> Enum.flat_map(fn
          %{"name" => name, "type" => "file"} -> [name]
          %{name: name, type: "file"} -> [name]
          %{name: name, type: :file} -> [name]
          _ -> []
        end)
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()

      _ -> []
    end
  end

  defp safe_broadcast(topic, msg) do
    try do
      Phoenix.PubSub.broadcast(Lang.PubSub, topic, msg)
    rescue
      _ -> :ok
    end
  end
end
