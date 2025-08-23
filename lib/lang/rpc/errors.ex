defmodule Lang.RPC.Errors do
  @moduledoc false

  def error(id, code, message, data) do
    base = %{"jsonrpc" => "2.0", "error" => %{"code" => code, "message" => message}}
    base = if is_nil(id), do: base, else: Map.put(base, "id", id)
    if is_nil(data), do: base, else: put_in(base, ["error", "data"], data)
  end
end

