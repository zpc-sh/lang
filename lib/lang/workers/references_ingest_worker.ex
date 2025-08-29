defmodule Lang.Workers.ReferencesIngestWorker do
  @moduledoc """
  Ingest code references for a file within a workspace using Engine adapter
  and persist them as Lang.Workspace.Reference records.
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger
  alias Lang.Workspace.{Reference, Symbol}
  alias Lang.LSP.EngineAdapter
  import Ash.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workspace_id" => ws_id, "file_path" => file_path} = args}) do
    Logger.metadata(workspace_id: ws_id, file_path: file_path)

    params = Map.drop(args, ["workspace_id"]) |> Map.put("file_path", file_path)

    case EngineAdapter.references(params) do
      {:ok, refs} when is_list(refs) ->
        {:ok, syms_by_name} = load_symbols_by_name(ws_id, file_path)

        refs
        |> Enum.each(fn ref ->
          from_name = get_in(ref, ["from", "name"]) || ref["from_name"] || ref[:from_name]
          to_name = get_in(ref, ["to", "name"]) || ref["to_name"] || ref[:to_name]
          type = (ref["type"] || ref[:type] || "call") |> map_ref_type()
          line = ref["line"] || ref[:line]

          with {:ok, from_id} <- fetch_symbol_id(syms_by_name, from_name),
               {:ok, to_id} <- fetch_symbol_id(syms_by_name, to_name) do
            _ = Reference.track(%{
              from_symbol_id: from_id,
              to_symbol_id: to_id,
              reference_type: type,
              file_path: file_path,
              line: line
            })
          else
            _ -> :noop
          end
        end)

        :ok

      {:error, reason} ->
        Logger.warning("Engine references unavailable", reason: inspect(reason))
        :ok
    end
  end

  defp load_symbols_by_name(ws_id, file_path) do
    case Symbol |> filter(workspace_id == ^ws_id and file_path == ^file_path) |> Ash.read() do
      {:ok, syms} -> {:ok, Map.new(syms, fn s -> {s.name, s.id} end)}
      other -> other
    end
  end

  defp fetch_symbol_id(map, name) when is_binary(name) do
    case Map.get(map, name) do
      nil -> {:error, :not_found}
      id -> {:ok, id}
    end
  end

  defp fetch_symbol_id(_, _), do: {:error, :invalid_name}

  defp map_ref_type(t) when is_binary(t) do
    case String.downcase(t) do
      "call" -> :call
      "import" -> :import
      "extend" -> :extend
      "implement" -> :implement
      "compose" -> :compose
      _ -> :call
    end
  end

  defp map_ref_type(t) when is_atom(t), do: t
  defp map_ref_type(_), do: :call
end

