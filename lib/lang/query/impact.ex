defmodule Elixir.Lang.LSP.Lang.Lang.Query.Impact do
  @moduledoc "\"What breaks if I change X?\""
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.query.impact"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
