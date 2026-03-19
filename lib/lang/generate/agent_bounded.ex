defmodule Elixir.Lang.LSP.Lang.Lang.Generate.Agent.Documentation do
  @moduledoc "Generate only in docs/, *.md"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.generate.agent.documentation"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
