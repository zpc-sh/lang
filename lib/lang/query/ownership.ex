defmodule Elixir.Lang.LSP.Lang.Lang.Query.Ownership do
  @moduledoc "\"Who owns this code?\""
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.query.ownership"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
