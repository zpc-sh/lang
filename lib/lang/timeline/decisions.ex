defmodule Elixir.Lang.LSP.Lang.Lang.Timeline.FindDecisions do
  @moduledoc "Key architectural decision points"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.timeline.find_decisions"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
