defmodule Elixir.Lang.LSP.Lang.Lang.Generate.ServiceMesh do
  @moduledoc "Generate service mesh configs"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.generate.service_mesh"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
