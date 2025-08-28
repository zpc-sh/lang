defmodule Elixir.Lang.LSP.Lang.Lang.Agent.AuditTrail do
  @moduledoc "Full audit log of agent actions"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.agent.audit_trail"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
