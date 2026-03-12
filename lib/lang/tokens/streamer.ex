defmodule Lang.LSP.Handlers.Tokens.Stream do
  @moduledoc "Stream only deltas"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.tokens.stream"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
