defmodule Lang.Dev.JSONLDRenderSubscriber do
  @moduledoc """
  Subscribes to JSON-LD FS watcher events and enqueues DocRenderWorker per model.

  This keeps docs in sync when JSON-LD files change.
  """

  use GenServer
  require Logger

  @default_topic "dev:fs:jsonld"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    topic = Map.get(opts, :topic) || @default_topic
    try do
      Phoenix.PubSub.subscribe(Lang.PubSub, topic)
    rescue
      _ -> :ok
    end
    {:ok, %{topic: topic}}
  end

  @impl true
  def handle_info({:fs_event, _name, %{path: path, kind: kind}}, state) do
    if String.ends_with?(path, ".json") and kind in [:created, :modified] do
      id = Path.rootname(Path.basename(path))
      enqueue_render(id)
    end
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp enqueue_render(id) do
    if Code.ensure_loaded?(Oban) do
      args = %{id: id}
      job = Lang.Dev.Workers.DocRenderWorker.new(args, queue: :analysis, tags: ["dev", "fswatch"]) 
      case Oban.insert(job) do
        {:ok, _} -> :ok
        other -> Logger.debug("DocRender enqueue failed: #{inspect(other)}")
      end
    else
      Logger.debug("Oban not loaded; skipping DocRender for #{id}")
    end
  end
end

