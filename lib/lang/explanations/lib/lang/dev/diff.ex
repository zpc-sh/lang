defmodule Lang.Dev.Diff do
  @moduledoc """
  Helpers for computing diffs between JSON‑LD snapshots.

  Prefers native semantic diff when available, with a JSON fallback.
  """

  @doc """
  Compute a semantic diff between two JSON‑LD maps.
  Returns a map with either native diff output or a simple structural diff.
  """
  @spec diff(map() | nil, map() | nil) :: map()
  def diff(nil, new), do: %{type: :added, after: new}
  def diff(old, nil), do: %{type: :removed, before: old}
  def diff(old, new) when is_map(old) and is_map(new) do
    old_json = Jason.encode!(old)
    new_json = Jason.encode!(new)

    native = native_diff(old_json, new_json)
    case native do
      {:ok, native_diff} -> %{type: :changed, native: native_diff}
      _ -> %{type: :changed, json: map_diff(old, new)}
    end
  end

  defp native_diff(old_s, new_s) do
    try do
      case Code.ensure_loaded(Lang.Native.PerfEngine) do
        {:module, _} -> Lang.Native.PerfEngine.semantic_diff(old_s, new_s, :json)
        _ -> {:error, :no_native}
      end
    rescue
      _ -> {:error, :native_error}
    end
  end

  # Simple structural diff for JSON maps: keys added/removed/changed with before/after values
  defp map_diff(a, b) do
    a_keys = Map.keys(a) |> MapSet.new()
    b_keys = Map.keys(b) |> MapSet.new()
    added = MapSet.difference(b_keys, a_keys) |> Enum.map(&{&1, Map.get(b, &1)})
    removed = MapSet.difference(a_keys, b_keys) |> Enum.map(&{&1, Map.get(a, &1)})
    common = MapSet.intersection(a_keys, b_keys)

    changed =
      common
      |> Enum.flat_map(fn k ->
        va = Map.get(a, k)
        vb = Map.get(b, k)
        if va == vb, do: [], else: [{k, %{before: va, after: vb}}]
      end)

    %{added: Map.new(added), removed: Map.new(removed), changed: Map.new(changed)}
  end
end

