defmodule Elixir.Lang.LSP.Lang.Lang.Timeline.Evolution do
  @moduledoc "How code evolved over time"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.timeline.evolution"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
