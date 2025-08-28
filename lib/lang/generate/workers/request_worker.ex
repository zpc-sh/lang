defmodule Elixir.Lang.LSP.Lang.Lang.Generate.Variations do
  @moduledoc "Queued via Ash/Oban; working stub"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.generate.variations"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
