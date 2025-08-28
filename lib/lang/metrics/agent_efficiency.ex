defmodule Elixir.Lang.LSP.Lang.Lang.Metrics.AgentEfficiency do
  @moduledoc "Agent resource usage"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.metrics.agent_efficiency"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
