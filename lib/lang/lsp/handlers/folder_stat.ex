defmodule Elixir.Lang.LSP.Lang.Folder.Stat do
  @moduledoc "LSP: stat a file or directory"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.folder/stat"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    uri = Map.get(params, "uri")
    storage_ctx = %{
      organization_id: Map.get(ctx, :organization_id) || Map.get(ctx, "organization_id"),
      user_id: Map.get(ctx, :user_id) || Map.get(ctx, "user_id"),
      session_id: Map.get(ctx, :session_id) || Map.get(ctx, "session_id"),
      root: root_dir_from_uri(uri)
    }

    path = rel_from_uri(uri)

    case Lang.Storage.stat(storage_ctx, path) do
      {:ok, stat} -> {:ok, stat}
      {:error, {:billing_blocked, info}} -> {:error, -32001, "billing_blocked", info}
      {:error, reason} -> {:error, -32002, inspect(reason)}
    end
  end

  defp root_dir_from_uri("file://" <> full) do
    Path.dirname(full)
  end
  defp root_dir_from_uri(_), do: File.cwd!()

  defp rel_from_uri("file://" <> full), do: Path.basename(full)
  defp rel_from_uri(other), do: other
end

