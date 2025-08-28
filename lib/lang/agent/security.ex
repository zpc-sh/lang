defmodule Elixir.Lang.LSP.Lang.Lang.Agent.VerifyProfile do
  @moduledoc "Check agent against expected behavior profile"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.agent.verify_profile"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
