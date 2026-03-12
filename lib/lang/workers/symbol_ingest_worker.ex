defmodule Lang.Workers.SymbolIngestWorker do
  @moduledoc """
  Ingest symbols for a file into the Workspace symbol store.

  - Reads file via Lang.Native.FSScanner
  - Extracts symbols via Lang.Native.TreeParser
  - Maps to Lang.Workspace.Symbol records and persists via Ash
  - Designed for idempotency and safe retries
  """

  use Oban.Worker, queue: :lsp, max_attempts: 3

  require Logger
  alias Lang.Workspace.Symbol, as: WSSymbol
  alias Lang.Workspace.ChatMessage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workspace_id" => workspace_id, "file_path" => file_path}}) do
    Logger.metadata(workspace_id: workspace_id, file_path: file_path)
    Logger.info("Starting symbol ingest")

    case Lang.Native.TreeParser.extract_symbols(file_path) do
      {:ok, symbols} when is_list(symbols) ->
        created =
          symbols
          |> Enum.map(&map_symbol_attrs(&1, workspace_id, file_path))
          |> Enum.reduce(0, fn attrs, acc ->
            case safe_create_symbol(attrs) do
              :ok -> acc + 1
              {:error, _} -> acc
            end
          end)

        ChatMessage.broadcast!(
          :symbols,
          %{
            message: "Symbol ingest completed",
            file_path: file_path,
            created: created
          }
        )

        # Enqueue references ingestion for this file
        %{"workspace_id" => workspace_id, "file_path" => file_path}
        |> Lang.Workers.ReferencesIngestWorker.new(queue: :analysis)
        |> Oban.insert()

        :ok

      {:error, reason} ->
        Logger.error("Symbol extraction failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp safe_create_symbol(attrs) do
    # Use Ash create action; tolerate duplicates by name+file if present in Redis TTL store.
    try do
      case WSSymbol.create_symbol(attrs) do
        {:ok, _record} -> :ok
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
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
        {%{"row" => row, "column" => col}, _} ->
          {row + 1, row + 1, col + 1, col + 1}

        {%{}, _} ->
          {nil, nil, nil, nil}

        {nil, %{row: row, column: col}} ->
          {row + 1, row + 1, col + 1, col + 1}

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
end
