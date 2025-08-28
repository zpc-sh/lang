defmodule Elixir.Lang.LSP.Lang.Lang.Storage.SyncSession do
  @moduledoc "Sync active session with Kyozo"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.storage.sync_session"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
