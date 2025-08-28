defmodule Elixir.Lang.LSP.Lang.Lang.Spatial.WaypointSet do
  @moduledoc "Ash resource implemented"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.spatial.waypoint_set"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
