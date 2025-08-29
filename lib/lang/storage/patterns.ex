defmodule Elixir.Lang.LSP.Lang.Lang.Storage.UpdateConfidence do
  @moduledoc "Update pattern confidence scores"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.storage.update_confidence"

  require Logger

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, _ctx) when is_map(params) do
    with :ok <- require_params(params, ["pattern_id", "confidence"]) do
      id = params["pattern_id"]
      confidence = params["confidence"]

      result =
        if dirup_enabled?() do
          Lang.Storage.Dirup.update_pattern_confidence(id, confidence)
        else
          Lang.Storage.PatternStore.update_confidence(id, confidence)
        end

      result
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

  defp dirup_enabled? do
    val = System.get_env("DIRUP_ENABLED") || System.get_env("LANG_DIRUP_ENABLED") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end
end

defmodule Elixir.Lang.LSP.Lang.Lang.Storage.StorePatterns do
  @moduledoc "Persist learned patterns to storage"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.storage.store_patterns"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"patterns" => patterns} = _params, _ctx) when is_list(patterns) do
    result =
      if dirup_enabled?() do
        Lang.Storage.Dirup.store_patterns(patterns)
      else
        with {:ok, recs} <- Lang.Storage.PatternStore.store_many(patterns) do
          {:ok, %{stored: length(recs), pattern_ids: Enum.map(recs, & &1.id)}}
        end
      end

    result
  end

  def handle(_params, _ctx), do: {:error, -32602, "Missing required parameters: patterns"}

  defp dirup_enabled? do
    val = System.get_env("DIRUP_ENABLED") || System.get_env("LANG_DIRUP_ENABLED") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end
end

defmodule Elixir.Lang.LSP.Lang.Lang.Storage.GetPatterns do
  @moduledoc "Retrieve patterns from storage"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.storage.get_patterns"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"pattern_ids" => ids} = _params, _ctx) when is_list(ids) do
    result =
      if dirup_enabled?() do
        Lang.Storage.Dirup.get_patterns(ids)
      else
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

    result
  end

  def handle(_params, _ctx), do: {:error, -32602, "Missing required parameters: pattern_ids"}

  defp dirup_enabled? do
    val = System.get_env("DIRUP_ENABLED") || System.get_env("LANG_DIRUP_ENABLED") || "0"
    String.downcase(val) in ["1", "true", "yes", "on"]
  end
end
