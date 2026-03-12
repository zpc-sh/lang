defmodule Lang.Workspace.Indexer do
  @moduledoc """
  Workspace indexer: scans a workspace root and ingests symbols per file.

  - Uses Lang.Native.FSScanner for directory traversal (fast NIF)
  - Enqueues per-file symbol ingestion via Oban worker
  - Optional synchronous small-batch ingest for tiny repos
  """

  alias Lang.Native.FSScanner
  alias Lang.Workers.SymbolIngestWorker

  require Logger

  @doc """
  Scan and enqueue ingestion for all files under root.

  opts:
  - :max_depth (default: 6)
  - :sync_small (default: false) — attempt synchronous ingest for <= 50 files
  - :language_filter (optional) — list of extensions or language hints
  """
  def ingest_workspace_symbols(workspace_id, root, opts \\ []) when is_binary(root) do
    max_depth = Keyword.get(opts, :max_depth, 6)

    case FSScanner.scan(root, max_depth: max_depth) do
      {:ok, %{tree: tree}} ->
        files = collect_files(tree)
        files = filter_files(files, Keyword.get(opts, :language_filter))

        if Keyword.get(opts, :sync_small, false) and length(files) <= 50 do
          Enum.each(files, fn path ->
            _ = sync_ingest_file(workspace_id, path)
          end)
          {:ok, %{files: length(files), mode: :sync}}
        else
          Enum.each(files, fn path ->
            %{"workspace_id" => workspace_id, "file_path" => path}
            |> SymbolIngestWorker.new(queue: :lsp)
            |> Oban.insert()
          end)
          {:ok, %{files: length(files), mode: :async}}
        end

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Synchronously ingest symbols for a single file (convenience).
  """
  def sync_ingest_file(workspace_id, file_path) do
    case Lang.Native.TreeParser.extract_symbols(file_path) do
      {:ok, symbols} when is_list(symbols) ->
        Enum.each(symbols, fn sym ->
          attrs = map_symbol_attrs(sym, workspace_id, file_path)
          _ = safe_create_symbol(attrs)
        end)
        :ok

      other -> other
    end
  end

  defp collect_files(%{type: :file, path: path}), do: [path]
  defp collect_files(%{type: :dir, children: children}) when is_list(children) do
    Enum.flat_map(children, &collect_files/1)
  end
  defp collect_files(_), do: []

  defp filter_files(files, nil), do: files
  defp filter_files(files, exts) when is_list(exts) do
    Enum.filter(files, fn path ->
      Enum.any?(exts, fn ext -> String.ends_with?(String.downcase(path), String.downcase(ext)) end)
    end)
  end

  defp map_symbol_attrs(symbol_map, workspace_id, file_path) when is_map(symbol_map) do
    name = to_string(Map.get(symbol_map, "name") || Map.get(symbol_map, :name) || "")
    type =
      symbol_map
      |> Map.get("symbol_type")
      |> case do
        nil -> Map.get(symbol_map, :symbol_type)
        v -> v
      end
      |> map_symbol_type()

    {line_start, line_end, col_start, col_end} =
      case {Map.get(symbol_map, "location"), Map.get(symbol_map, :location)} do
        {%{"row" => row, "column" => col}, _} -> {row + 1, row + 1, col + 1, col + 1}
        {%{}, _} -> {nil, nil, nil, nil}
        {nil, %{row: row, column: col}} -> {row + 1, row + 1, col + 1, col + 1}
        {nil, nil} ->
          span = Map.get(symbol_map, "span") || Map.get(symbol_map, :span) || %{}
          sr = Map.get(span, "start_row") || Map.get(span, :start_row)
          er = Map.get(span, "end_row") || Map.get(span, :end_row)
          sc = Map.get(span, "start_column") || Map.get(span, :start_column)
          ec = Map.get(span, "end_column") || Map.get(span, :end_column)
          if is_integer(sr) and is_integer(er) and is_integer(sc) and is_integer(ec) do
            {sr + 1, er + 1, sc + 1, ec + 1}
          else
            {nil, nil, nil, nil}
          end
      end

    %{
      workspace_id: workspace_id,
      file_path: file_path,
      name: name,
      type: type,
      line_start: line_start,
      line_end: line_end,
      column_start: col_start,
      column_end: col_end,
      semantic_fingerprint: fingerprint(name, type, file_path)
    }
  end

  defp map_symbol_type(type) when is_binary(type) do
    case String.downcase(type) do
      "function" -> :function
      "method" -> :function
      "module" -> :module
      "class" -> :module
      "type" -> :type
      "interface" -> :type
      "variable" -> :variable
      "const" -> :variable
      "macro" -> :macro
      _ -> :function
    end
  end

  defp map_symbol_type(type) when is_atom(type), do: type
  defp map_symbol_type(_), do: :function

  defp fingerprint(name, type, file_path) do
    :crypto.hash(:sha256, "#{name}|#{type}|#{file_path}") |> Base.encode16()
  end

  defp safe_create_symbol(attrs) do
    try do
      case Lang.Workspace.Symbol.create_symbol(attrs) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end
end

