defmodule Lang.InMemory.Store do
  @moduledoc "Simple in-memory store backed by :persistent_term for demo/stub wiring."

  @store_key :lang_inmemory_store

  def get(namespace, key, default \\ nil) do
    store()
    |> Map.get(namespace, %{})
    |> Map.get(key, default)
  end

  def put(namespace, key, value) do
    update_store(fn s ->
      ns = Map.get(s, namespace, %{})
      Map.put(s, namespace, Map.put(ns, key, value))
    end)

    :ok
  end

  def delete(namespace, key) do
    update_store(fn s ->
      ns = Map.get(s, namespace, %{})
      Map.put(s, namespace, Map.delete(ns, key))
    end)

    :ok
  end

  def list(namespace) do
    store() |> Map.get(namespace, %{}) |> Enum.to_list()
  end

  defp store do
    :persistent_term.get(@store_key, %{})
  end

  defp update_store(fun) when is_function(fun, 1) do
    current = store()
    new_store = fun.(current)
    :persistent_term.put(@store_key, new_store)
  end
end
