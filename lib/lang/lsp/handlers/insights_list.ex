defmodule Elixir.Lang.LSP.Lang.Insights.List do
  @moduledoc "LSP: list Insights with optional filters"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.insights/list"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, _ctx) when is_map(params) do
    filters =
      %{}
      |> maybe_put(:workspace_id, Map.get(params, "workspaceId"))
      |> maybe_put(:owner_id, Map.get(params, "ownerId"))
      |> maybe_put(:tag, Map.get(params, "tag"))

    case Lang.Semantic.Insights.Store.list(filters) do
      {:ok, list} ->
        {:ok,
         %{insights: Enum.map(list, fn r -> %{id: r.id, title: r.title, tags: r.tags, lang: r.lang} end)}}

      {:error, reason} ->
        {:error, -32002, inspect(reason)}
    end
  end

  def handle(_params, _ctx), do: {:error, -32602, "missing params"}

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end

