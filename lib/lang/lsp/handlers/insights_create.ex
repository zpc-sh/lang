defmodule Elixir.Lang.LSP.Lang.Insights.Create do
  @moduledoc "LSP: create an Insight (embedded Ash resource)"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.insights/create"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    attrs = %{
      title: Map.get(params, "title"),
      content: Map.get(params, "content"),
      tags: Map.get(params, "tags", []),
      lang: Map.get(params, "lang", "en"),
      source_uri: Map.get(params, "sourceUri"),
      owner_id: owner_from_ctx(ctx) || Map.get(params, "ownerId"),
      workspace_id: Map.get(params, "workspaceId"),
      layer_type: Map.get(params, "layerType"),
      metadata: Map.get(params, "metadata", %{})
    }

    with {:ok, rec} <- Lang.Semantic.Insights.Store.upsert(attrs) do
      {:ok, %{id: rec.id, title: rec.title}}
    else
      {:error, reason} -> {:error, -32002, inspect(reason)}
    end
  end

  def handle(_params, _ctx), do: {:error, -32602, "missing params"}

  defp owner_from_ctx(%{current_org: %{id: id}}), do: id
  defp owner_from_ctx(%{"team_id" => id}) when is_binary(id), do: id
  defp owner_from_ctx(_), do: nil
end

