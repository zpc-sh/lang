defmodule Elixir.Lang.LSP.Lang.Lang.Timeline.RegressionRisk do
  @moduledoc "What might break if changed"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.timeline.regression_risk"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
