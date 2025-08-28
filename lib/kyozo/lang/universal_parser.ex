defmodule Elixir.Lang.LSP.Lang.Lang.Parser.ParseStream do
  @moduledoc "Streaming parser"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.parser.parse_stream"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # TODO: implement
    {:error, :not_implemented}
  end
end
