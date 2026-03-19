defmodule Elixir.Lang.LSP.Lang.Registry.GetBlob do
  @moduledoc "LSP: registry.getBlob wrapper"
  @behaviour Lang.LSP.Handler
  @lsp_method "folder/registry.getBlob"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(%{"owner" => owner, "repo" => repo, "digest" => digest} = params, ctx) when is_map(ctx) do
    force_inline = Map.get(params, "forceInline", false)

    storage_ctx = %{
      organization_id: Map.get(ctx, :organization_id) || Map.get(ctx, "organization_id"),
      user_id: Map.get(ctx, :user_id) || Map.get(ctx, "user_id"),
      session_id: Map.get(ctx, :session_id) || Map.get(ctx, "session_id")
    }

    case Lang.Storage.registry_blob(storage_ctx, owner, repo, digest, force_inline: force_inline) do
      {:ok, %{uri: _} = info} -> {:ok, info}
      {:ok, %{content: _} = info} -> {:ok, info}
      {:error, {:billing_blocked, info}} -> {:error, -32001, "billing_blocked", info}
      {:error, {:auth_required, challenge}} -> {:error, -32011, "auth_required", %{challenge: challenge}}
      {:error, {:http_status, status, _}} when status == 404 -> {:error, -32004, "not_found"}
      {:error, reason} -> {:error, -32002, inspect(reason)}
    end
  end

    def handle(_params, _ctx), do: {:error, -32602, "missing owner/repo/digest"}
end

