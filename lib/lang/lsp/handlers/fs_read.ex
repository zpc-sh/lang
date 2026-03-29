defmodule Elixir.Lang.LSP.Lang.FS.Read do
  @moduledoc "LSP: folder/fs.read -> read VFS content"
  @behaviour Lang.LSP.Handler
  @lsp_method "folder/fs.read"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"workspaceId" => wid} = params, ctx) when is_map(ctx) do
    team_id = team_from_ctx(ctx) || Map.get(params, "teamId")
    if is_binary(team_id) do
      path = Map.get(params, "path")
      id = Map.get(params, "id")
      cond do
        is_binary(path) -> do_read(team_id, wid, path, ctx)
        is_binary(id) -> {:error, -32005, "read by id not implemented"}
        true -> {:error, -32602, "path or id required"}
      end
    else
      {:error, -32602, "missing teamId (derive from auth)"}
    end
  end

  def handle(_params, _ctx), do: {:error, -32602, "missing workspaceId"}

  defp do_read(team_id, wid, path, ctx) do
    uri = "vfs://team/#{team_id}/workspace/#{wid}/#{path}"
    storage_ctx = %{
      organization_id: Map.get(ctx, :organization_id) || Map.get(ctx, "organization_id"),
      user_id: Map.get(ctx, :user_id) || Map.get(ctx, "user_id"),
      session_id: Map.get(ctx, :session_id) || Map.get(ctx, "session_id")
    }

    case Lang.Storage.read(storage_ctx, uri, max_lines: Lang.Storage.Config.preview_max_lines()) do
      {:ok, content} when is_binary(content) -> {:ok, %{content: content, contentType: "text/plain"}}
      {:ok, lines} when is_list(lines) -> {:ok, %{content: Enum.join(lines, "\n"), contentType: "text/plain"}}
      {:error, {:billing_blocked, info}} -> {:error, -32001, "billing_blocked", info}
      {:error, reason} -> {:error, -32002, inspect(reason)}
    end
  end

  defp team_from_ctx(ctx) do
    case ctx do
      %{current_org: %{id: id}} when is_binary(id) -> id
      %{"team_id" => id} when is_binary(id) -> id
      _ -> nil
    end
  end
end

