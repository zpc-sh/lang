defmodule Nullity.CDFM.Adapters.Introspection.Code do
  @moduledoc """
  Introspection adapter using Elixir's Code and kernel to check exports.
  """
  @behaviour Nullity.CDFM.Adapters.Introspection

  @impl true
  def exported?(module, function, arity) when is_atom(module) and is_atom(function) and is_integer(arity) do
    try do
      _ = Code.ensure_loaded(module)
      function_exported?(module, function, arity)
    rescue
      _ -> false
    end
  end
end

