defmodule Elixir.Lang.LSP.Lang.FS.List do
  @moduledoc "LSP: folder/fs.list -> list VFS entries"
  @behaviour Lang.LSP.Handler
  @lsp_method "folder/fs.list"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"workspaceId" => wid} = params, ctx) when is_map(ctx) do
    team_id = team_from_ctx(ctx) || Map.get(params, "teamId")
    if is_binary(team_id) do
      path = Map.get(params, "path", ".")
      uri = "vfs://team/#{team_id}/workspace/#{wid}/#{path}"
      storage_ctx = %{
        organization_id: Map.get(ctx, :organization_id) || Map.get(ctx, "organization_id"),
        user_id: Map.get(ctx, :user_id) || Map.get(ctx, "user_id"),
        session_id: Map.get(ctx, :session_id) || Map.get(ctx, "session_id")
      }

      case Lang.Storage.list(storage_ctx, uri, depth: 1) do
        {:ok, entries} -> {:ok, %{entries: massage(entries)}}
        {:error, {:billing_blocked, info}} -> {:error, -32001, "billing_blocked", info}
        {:error, reason} -> {:error, -32002, inspect(reason)}
      end
    else
      {:error, -32602, "missing teamId (derive from auth)"}
    end
  end

  def handle(_params, _ctx), do: {:error, -32602, "missing workspaceId"}

  defp team_from_ctx(ctx) do
    case ctx do
      %{current_org: %{id: id}} when is_binary(id) -> id
      %{"team_id" => id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp massage(entries) when is_list(entries) do
    Enum.map(entries, fn e ->
      %{
        name: e[:name] || e["name"],
        path: e[:uri] || e["uri"],
        type: (case e[:kind] || e["kind"] do :directory -> "dir"; _ -> "file" end),
        size: e[:size] || e["size"],
        mtime: e[:mtime] || e["mtime"]
      }
    end)
  end
end

