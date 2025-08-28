defmodule Elixir.Lang.LSP.Lang.Lang.Storage.UpdateUserContext do
  @moduledoc "Update user context in Kyozo"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.storage.update_user_context"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
