defmodule Elixir.Lang.LSP.Lang.Lang.Timeline.PredictChanges do
  @moduledoc "Predict likely future changes"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.timeline.predict_changes"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
