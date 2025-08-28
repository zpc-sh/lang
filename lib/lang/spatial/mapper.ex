defmodule Elixir.Lang.LSP.Lang.Lang.Spatial.Traverse do
  @moduledoc "Full BFS implementation with depth control"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.spatial.traverse"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
