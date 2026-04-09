defmodule Elixir.Lang.LSP.Lang.Lang.Storage.UpdateConfidence do
  @moduledoc "Update pattern confidence scores"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.storage.update_confidence"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) do
    with :ok <- require_params(params, ["pattern_id", "confidence"]) do
      id = params["pattern_id"]
      confidence = params["confidence"]

      Lang.Storage.DataHandle.execute(
        "patterns",
        "update_confidence",
        fn entry ->
          case entry.backend do
            :folder -> Lang.Storage.Folder.update_pattern_confidence(id, confidence)
            _ -> Lang.Storage.PatternStore.update_confidence(id, confidence)
          end
        end,
        ctx
      )
    else
      {:error, _} = err -> err
    end
  end

  defp require_params(map, keys) do
    missing = Enum.reject(keys, &Map.has_key?(map, &1))

    case missing do
      [] -> :ok
      _ -> {:error, -32602, "Missing required parameters: #{Enum.join(missing, ", ")}"}
    end
  end

end

defmodule Elixir.Lang.LSP.Lang.Lang.Storage.StorePatterns do
  @moduledoc "Persist learned patterns to storage"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.storage.store_patterns"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"patterns" => patterns} = _params, ctx) when is_list(patterns) do
    Lang.Storage.DataHandle.execute(
      "patterns",
      "store_patterns",
      fn entry ->
        case entry.backend do
          :folder ->
            Lang.Storage.Folder.store_patterns(patterns)

          _ ->
            with {:ok, recs} <- Lang.Storage.PatternStore.store_many(patterns) do
              {:ok, %{stored: length(recs), pattern_ids: Enum.map(recs, & &1.id)}}
            end
        end
      end,
      ctx
    )
  end

  def handle(_params, _ctx), do: {:error, -32602, "Missing required parameters: patterns"}

end

defmodule Elixir.Lang.LSP.Lang.Lang.Storage.GetPatterns do
  @moduledoc "Retrieve patterns from storage"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.storage.get_patterns"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"pattern_ids" => ids} = _params, ctx) when is_list(ids) do
    Lang.Storage.DataHandle.execute(
      "patterns",
      "get_patterns",
      fn entry ->
        case entry.backend do
          :folder ->
            Lang.Storage.Folder.get_patterns(ids)

          _ ->
            with {:ok, recs} <- Lang.Storage.PatternStore.get_many(ids) do
              {:ok,
               %{
                 patterns:
                   Enum.map(recs, fn rec ->
                     %{id: rec.id, pattern: rec.content, confidence: rec.confidence}
                   end)
               }}
            end
        end
      end,
      ctx
    )
  end

  def handle(_params, _ctx), do: {:error, -32602, "Missing required parameters: pattern_ids"}

end
