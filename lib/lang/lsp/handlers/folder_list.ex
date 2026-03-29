defmodule Elixir.Lang.LSP.Lang.Folder.List do
  @moduledoc "LSP: list folder entries"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.folder/list"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    root = Map.get(params, "rootUri") || Map.get(ctx, :root)
    path = Map.get(params, "path", ".")
    depth = Map.get(params, "depth", 1)

    storage_ctx = %{
      organization_id: Map.get(ctx, :organization_id) || Map.get(ctx, "organization_id"),
      user_id: Map.get(ctx, :user_id) || Map.get(ctx, "user_id"),
      session_id: Map.get(ctx, :session_id) || Map.get(ctx, "session_id"),
      root: root_from_uri(root)
    }

    case Lang.Storage.list(storage_ctx, path, depth: depth) do
      {:ok, entries} -> {:ok, %{entries: entries}}
      {:error, {:billing_blocked, info}} -> {:error, -32001, "billing_blocked", info}
      {:error, reason} -> {:error, -32002, inspect(reason)}
    end
  end

  defp root_from_uri(nil), do: File.cwd!()
  defp root_from_uri("file://" <> path), do: path
  defp root_from_uri(path), do: path
end

