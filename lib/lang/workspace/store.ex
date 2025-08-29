defmodule Lang.Workspace.Store do
  @moduledoc """
  Store and retrieve workspace state, including:
  - Symbol data
  - Memory persistence
  - Working sets
  - LLM-generated insights
  """
  alias Lang.Workspace.Symbol
  alias Lang.Workspace.WorkingSet
  # alias Lang.Workspace.Reference
  alias Lang.Workspace.Pattern

  @doc """
  Saves the current workspace state to persistent storage
  """
  def save_workspace(workspace_id, metadata \\ %{}) do
    with {:ok, _workspace} <- Lang.Workspace.Workspace.get(workspace_id),
         {:ok, active_symbols} <- Symbol.list_by_workspace(workspace_id),
         {:ok, working_sets} <- WorkingSet.list_by_workspace(workspace_id),
         {:ok, patterns} <- Pattern.list_by_workspace(workspace_id) do
      # Create a snapshot of the workspace state
      snapshot = %{
        workspace_id: workspace_id,
        timestamp: DateTime.utc_now(),
        metadata: metadata,
        symbols_count: length(active_symbols),
        working_sets_count: length(working_sets),
        patterns_count: length(patterns)
      }

      # Save to Redis with longer TTL for persistence
      {:ok, _} =
        Lang.Redis.setex(
          "workspace:snapshots:#{workspace_id}",
          # 1 week TTL
          86400 * 7,
          Jason.encode!(snapshot)
        )

      # Notify clients
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "workspace:#{workspace_id}",
        {:workspace_saved, snapshot}
      )

      {:ok, snapshot}
    end
  end

  @doc """
  Loads a workspace state from persistent storage
  """
  def load_workspace(workspace_id) do
    with {:ok, json} <- Lang.Redis.get("workspace:snapshots:#{workspace_id}"),
         {:ok, snapshot} <- Jason.decode(json) do
      # Convert string keys to atoms
      snapshot = for {key, val} <- snapshot, into: %{}, do: {String.to_atom(key), val}

      # Notify clients
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "workspace:#{workspace_id}",
        {:workspace_loaded, snapshot}
      )

      {:ok, snapshot}
    else
      {:error, :not_found} ->
        {:error, :no_snapshot_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Store LLM-generated insights about a workspace
  """
  def store_insight(workspace_id, insight) do
    insight_data =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          workspace_id: workspace_id,
          timestamp: DateTime.utc_now()
        },
        insight
      )

    key = "workspace:insights:#{workspace_id}:#{insight_data.id}"

    with {:ok, json} <- Jason.encode(insight_data),
         # 30 days TTL
         {:ok, _} <- Lang.Redis.setex(key, 86400 * 30, json) do
      # Add to insight index
      {:ok, _} = Lang.Redis.sadd("workspace:insights:#{workspace_id}", key)

      # Notify clients
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "workspace:#{workspace_id}",
        {:new_insight, insight_data}
      )

      {:ok, insight_data}
    end
  end

  @doc """
  List insights for a workspace
  """
  def list_insights(workspace_id) do
    with {:ok, keys} <- Lang.Redis.smembers("workspace:insights:#{workspace_id}") do
      insights =
        Enum.map(keys, fn key ->
          case Lang.Redis.get(key) do
            {:ok, json} -> Jason.decode(json, keys: :atoms)
            _ -> nil
          end
        end)
        |> Enum.filter(&(&1 != nil))
        |> Enum.map(fn {:ok, data} -> data end)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

      {:ok, insights}
    end
  end

  @doc """
  Store a memory for a specific file or symbol in the workspace
  """
  def store_memory(workspace_id, type, key, memory) do
    memory_data = %{
      id: Ecto.UUID.generate(),
      workspace_id: workspace_id,
      type: type,
      key: key,
      content: memory,
      created_at: DateTime.utc_now()
    }

    redis_key = "workspace:memories:#{workspace_id}:#{type}:#{key}"

    with {:ok, json} <- Jason.encode(memory_data),
         # 30 days TTL
         {:ok, _} <- Lang.Redis.setex(redis_key, 86400 * 30, json) do
      {:ok, memory_data}
    end
  end

  @doc """
  Retrieve a memory by type and key
  """
  def get_memory(workspace_id, type, key) do
    redis_key = "workspace:memories:#{workspace_id}:#{type}:#{key}"

    with {:ok, json} <- Lang.Redis.get(redis_key),
         {:ok, memory} <- Jason.decode(json, keys: :atoms) do
      {:ok, memory}
    else
      {:error, :not_found} -> {:error, :memory_not_found}
      error -> error
    end
  end

  @doc """
  LSP method implementation for lang.workspace.save
  """
  def handle_save(params, ctx) when is_map(params) and is_map(ctx) do
    workspace_id = params["workspace_id"]
    metadata = params["metadata"] || %{}

    case save_workspace(workspace_id, metadata) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, reason} -> {:error, reason}
    end
  end
end
