defmodule Nullity.CDFM.Sync do
  @moduledoc """
  Compute derived LSP method statuses from filesystem and code introspection
  and persist back via the Store adapter (Ash).
  """

  alias Nullity.CDFM.Adapters.FileAdapter
  alias Nullity.CDFM.Adapters.Store
  alias Nullity.CDFM.Adapters.Introspection

  @doc """
  Recompute derived_status for all methods from the store and persist updates.
  """
  def sync_all(opts \\ []) do
    file = Keyword.fetch!(opts, :file_adapter)
    store = Keyword.fetch!(opts, :store)
    introspection = Keyword.fetch!(opts, :introspection)

    with {:ok, methods} <- store.read_all_methods() do
      methods
      |> Enum.map(&derive_status(&1, file, introspection))
      |> Enum.each(fn m ->
        _ = store.upsert_method(Map.put(m, :derived_status, m[:derived_status]))
      end)

      :ok
    end
  end

  defp derive_status(method, file_adapter, introspection) do
    impl_file = method[:impl_file]
    mod = to_atom(method[:impl_module])
    fun = to_atom(method[:impl_function] || :handle)
    arity = method[:impl_arity] || 2

    file_exists? = is_binary(impl_file) && file_adapter.exists?(impl_file)

    exported? =
      file_exists? && is_atom(mod) && is_atom(fun) && is_integer(arity) &&
        safe_exported?(introspection, mod, fun, arity)

    derived =
      cond do
        exported? -> :implemented
        file_exists? -> :in_progress
        true -> :not_started
      end

    Map.put(method, :derived_status, derived)
  end

  defp safe_exported?(introspection, mod, fun, arity) do
    try do
      introspection.exported?(mod, fun, arity)
    rescue
      _ -> false
    end
  end

  defp to_atom(nil), do: nil
  defp to_atom(v) when is_atom(v), do: v
  defp to_atom(v) when is_binary(v), do: String.to_atom(v)
end
