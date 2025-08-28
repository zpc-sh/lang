defmodule Elixir.Lang.LSP.Lang.Lang.Agent.MergeResults do
  @moduledoc "Merge findings from multiple agents"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.agent.merge_results"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
