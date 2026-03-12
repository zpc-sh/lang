defmodule Lang.Workspace.Service do
  @moduledoc """
  High-level helpers for Workspace operations: FS scan, VFS ingest, JSON-LD updates.
  """

  alias Lang.Workspace.Workspace

  def list_files(root, opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 3)

    case Lang.Native.FSScanner.scan(root, max_depth: max_depth) do
      {:ok, %{tree: tree}} -> {:ok, tree}
      other -> other
    end
  end

  def put_file(workspace_id, path, content, attrs \\ %{}) when is_binary(content) do
    vfs_uri = Lang.Storage.VFS.put(content)
    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    node = %{
      "@id" => "file:" <> to_string(path),
      "type" => ["File"],
      "vfsUri" => vfs_uri,
      "contentHash" => hash,
      "size" => byte_size(content),
      "language" => Map.get(attrs, :language),
      "contentType" => Map.get(attrs, :content_type)
    }

    merge_graph(workspace_id, [node])
    {:ok, %{vfs_uri: vfs_uri, content_hash: hash}}
  end

  def merge_graph(workspace_id, nodes) when is_list(nodes) do
    case Workspace.by_id(workspace_id) do
      {:ok, ws} ->
        incoming = %{"@graph" => nodes}
        Workspace.merge_ld(ws, %{jsonld: incoming})

      other ->
        other
    end
  end

  @doc "Queue async symbol ingestion for a file in a workspace"
  def ingest_symbols_async(workspace_id, file_path) when is_binary(file_path) do
    %{"workspace_id" => workspace_id, "file_path" => file_path}
    |> Lang.Workers.SymbolIngestWorker.new(queue: :lsp)
    |> Oban.insert()
  end

  @doc """
  Scan a workspace root and ingest symbols for all files.

  opts: see Lang.Workspace.Indexer.ingest_workspace_symbols/3
  """
  def ingest_all_symbols(workspace_id, root, opts \\ []) do
    Lang.Workspace.Indexer.ingest_workspace_symbols(workspace_id, root, opts)
  end

  @doc """
  Ingest symbols for a single file synchronously.
  """
  def ingest_file_symbols_now(workspace_id, file_path) do
    Lang.Workspace.Indexer.sync_ingest_file(workspace_id, file_path)
  end

  def snapshot(workspace_id) do
    with {:ok, ws} <- Workspace.by_id(workspace_id) do
      Workspace.snapshot_state(ws)
    end
  end
end
