defmodule Elixir.Lang.LSP.Lang.FS.Search do
  @moduledoc "LSP: folder/fs.search (safe stub via Lang.Storage.search)"
  @behaviour Lang.LSP.Handler
  @lsp_method "folder/fs.search"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"workspaceId" => wid, "query" => query} = params, ctx) when is_map(ctx) and is_binary(query) do
    team_id = team_from_ctx(ctx) || Map.get(params, "teamId")
    if is_binary(team_id) do
      # For LocalFS adapter, search runs on local root; for FolderAdapter, it may return :not_implemented
      storage_ctx = %{
        organization_id: Map.get(ctx, :organization_id) || Map.get(ctx, "organization_id"),
        user_id: Map.get(ctx, :user_id) || Map.get(ctx, "user_id"),
        session_id: Map.get(ctx, :session_id) || Map.get(ctx, "session_id")
      }

      case Lang.Storage.search(storage_ctx, query, max_results: 50) do
        {:ok, results} when is_list(results) -> {:ok, %{results: format(results)}}
        {:error, {:billing_blocked, info}} -> {:error, -32001, "billing_blocked", info}
        {:error, :not_implemented} -> {:error, -32012, "fs_search_not_implemented"}
        {:error, reason} -> {:error, -32002, inspect(reason)}
      end
    else
      {:error, -32602, "missing teamId (derive from auth)"}
    end
  end

  def handle(_params, _ctx), do: {:error, -32602, "missing workspaceId or query"}

  defp team_from_ctx(ctx) do
    case ctx do
      %{current_org: %{id: id}} when is_binary(id) -> id
      %{"team_id" => id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp format(results) do
    Enum.map(results, fn r ->
      %{
        filePath: r[:path] || r["path"] || r[:uri] || r["uri"],
        line: r[:line_number] || r["line_number"],
        excerpt: r[:line_text] || r["line_text"]
      }
    end)
  end
end

