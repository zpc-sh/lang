defmodule Elixir.Lang.LSP.Lang.Lang.Generate.FromDiagram do
  @moduledoc "Architecture diagram → boilerplate"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.generate.from_diagram"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
