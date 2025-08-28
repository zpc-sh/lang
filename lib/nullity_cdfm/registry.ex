defmodule Nullity.CDFM.Registry do
  @moduledoc """
  Build a simple method→MFA registry map from normalized method specs.
  This module is framework-agnostic.
  """

  @type entry :: {module(), atom(), non_neg_integer()}

  @doc """
  Build a registry as a map: method_name (string) → {module, function, arity}.
  Ignores entries missing MFA info.
  """
  def build(specs) when is_list(specs) do
    specs
    |> Enum.reduce(%{}, fn spec, acc ->
      name = Map.get(spec, :name) || Map.get(spec, "name")
      mod = to_existing_atom(Map.get(spec, :impl_module) || Map.get(spec, "impl_module"))
      fun = to_existing_atom(Map.get(spec, :impl_function) || Map.get(spec, "impl_function"))
      arity = Map.get(spec, :impl_arity) || Map.get(spec, "impl_arity")

      if is_binary(name) and is_atom(mod) and is_atom(fun) and is_integer(arity) do
        Map.put(acc, name, {mod, fun, arity})
      else
        acc
      end
    end)
  end

  defp to_existing_atom(nil), do: nil
  defp to_existing_atom(val) when is_atom(val), do: val
  defp to_existing_atom(val) when is_binary(val) do
    try do
      String.to_existing_atom(val)
    rescue
      ArgumentError -> String.to_atom(val)
    end
  end
end

