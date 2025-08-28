defmodule Elixir.Lang.LSP.Lang.Lang.Storage.UpdateConfidence do
  @moduledoc "Update pattern confidence scores"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.storage.update_confidence"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
