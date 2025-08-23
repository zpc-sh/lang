defmodule Lang.RPC.JsonLD do
  @moduledoc false
  @context "https://lang.nocsi.com/schema/v1/lsp"

  def wrap(%{} = map), do: Map.put_new(map, "@context", @context)
end

