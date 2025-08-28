defmodule Lang.Workspace.Store do
  @moduledoc """
  Redis-backed ephemeral workspace/session state for agents.

  Structure (namespaced keys per session_id):
  - ws:<session_id>:context         -> JSON map with root_path, file_tree_hash, active_files, symbols_index, import_graph
  - ws:<session_id>:analysis_cache  -> JSON map with security_issues, type_signatures, test_coverage
  - ws:<session_id>:mcp_connections -> JSON map like %{filesystem: "...", git: "..."}

  Notes:
  - Keep entries reasonably small; use Kyozo for large/durable artifacts.
  - TTL defaults to 2 hours; adjust via opts.
  - For large indices, consider splitting by segment (e.g., symbols_index:*), but start simple.
  """

  alias Lang.Redis

  @prefix "ws:"
  # 2 hours
  @default_ttl 7_200

  # Public API

  def get_workspace(session_id) do
    with {:ok, context} <- get_context(session_id),
         {:ok, analysis} <- get_analysis_cache(session_id),
         {:ok, mcp} <- get_mcp_connections(session_id) do
      {:ok,
       %{
         "workspace_context" => context,
         "analysis_cache" => analysis,
         "mcp_connections" => mcp
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def get_context(session_id) do
    get_json(context_key(session_id))
  end

  def put_context(session_id, map, opts \\ []) when is_map(map) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    set_json(context_key(session_id), map, ttl)
  end

  def update_context(session_id, fun, opts \\ []) when is_function(fun, 1) do
    with {:ok, ctx} <- get_context(session_id) do
      ctx = fun.(ctx || %{})
      put_context(session_id, ctx, opts)
    end
  end

  # Large sub-documents stored separately to keep context small
  def get_symbols_index(session_id), do: get_json(symbols_key(session_id))

  def put_symbols_index(session_id, map, opts \\ []) when is_map(map) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    set_json(symbols_key(session_id), map, ttl)
  end

  def get_import_graph(session_id), do: get_json(import_graph_key(session_id))

  def put_import_graph(session_id, map, opts \\ []) when is_map(map) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    set_json(import_graph_key(session_id), map, ttl)
  end

  def get_analysis_cache(session_id) do
    get_json(analysis_key(session_id))
  end

  def put_analysis_cache(session_id, map, opts \\ []) when is_map(map) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    set_json(analysis_key(session_id), map, ttl)
  end

  def merge_analysis_cache(session_id, update, opts \\ []) when is_map(update) do
    with {:ok, current} <- get_analysis_cache(session_id) do
      put_analysis_cache(session_id, Map.merge(current || %{}, update), opts)
    end
  end

  def get_mcp_connections(session_id) do
    get_json(mcp_key(session_id))
  end

  def put_mcp_connection(session_id, name, conn_id, opts \\ []) when is_binary(name) do
    with {:ok, current} <- get_mcp_connections(session_id) do
      map = Map.put(current || %{}, name, conn_id)
      ttl = Keyword.get(opts, :ttl, @default_ttl)
      set_json(mcp_key(session_id), map, ttl)
    end
  end

  # Invalidate analysis cache if file_tree_hash changed; update context hash.
  def invalidate_on_tree_change(session_id, new_hash, opts \\ []) when is_binary(new_hash) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    {:ok, ctx} = get_context(session_id)
    old_hash = get_in(ctx || %{}, ["file_tree_hash"]) || get_in(ctx || %{}, [:file_tree_hash])

    if old_hash == new_hash do
      :ok
    else
      # clear analysis cache and update context hash
      _ = Redis.cmd(["DEL", analysis_key(session_id)])
      new_ctx = Map.put(ctx || %{}, "file_tree_hash", new_hash)
      set_json(context_key(session_id), new_ctx, ttl)
    end
  end

  def clear(session_id) do
    Redis.cmd([
      "DEL",
      context_key(session_id),
      analysis_key(session_id),
      mcp_key(session_id),
      symbols_key(session_id),
      import_graph_key(session_id)
    ])

    :ok
  end

  # Internal helpers
  defp context_key(session_id), do: @prefix <> to_string(session_id) <> ":context"
  defp analysis_key(session_id), do: @prefix <> to_string(session_id) <> ":analysis_cache"
  defp mcp_key(session_id), do: @prefix <> to_string(session_id) <> ":mcp_connections"
  defp symbols_key(session_id), do: @prefix <> to_string(session_id) <> ":context:symbols_index"

  defp import_graph_key(session_id),
    do: @prefix <> to_string(session_id) <> ":context:import_graph"

  defp get_json(key) do
    case Redis.get(key) do
      {:ok, nil} -> {:ok, %{}}
      {:ok, json} -> Jason.decode(json)
      {:error, reason} -> {:error, reason}
    end
  end

  defp set_json(key, map, ttl) do
    with {:ok, json} <- Jason.encode(map),
         {:ok, _} <- Redis.setex(key, ttl, json) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :store_failed}
    end
  end
end
