defmodule Elixir.Lang.LSP.Lang.Lang.Think.TraceFlow do
  @moduledoc "AI-powered execution flow tracing"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.think.trace_flow"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
