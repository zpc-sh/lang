defmodule Elixir.Lang.LSP.Lang.Lang.Agent.TrackUsage do
  @moduledoc "Track token/resource usage per agent"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.agent.track_usage"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
