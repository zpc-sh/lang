defmodule Elixir.Lang.LSP.Lang.Lang.Generate.MaintainStyle do
  @moduledoc "Match directory-specific style"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.generate.maintain_style"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
