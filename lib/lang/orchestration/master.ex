defmodule Elixir.Lang.LSP.Lang.Lang.Orchestration.Status do
  @moduledoc "Monitor progress"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.orchestration.status"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
