defmodule Elixir.Lang.LSP.Lang.Lang.Timeline.BlameSemantic do
  @moduledoc "Who introduced this concept (not line)"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.timeline.blame_semantic"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
