defmodule Elixir.Lang.LSP.Lang.Lang.Agent.BehaviorBaseline do
  @moduledoc "Establish normal behavior patterns"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.agent.behavior_baseline"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
