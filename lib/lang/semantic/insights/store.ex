defmodule Lang.Semantic.Insights.Store do
  @moduledoc """
  Lightweight ETS-backed store for Insights using Ash resource for shape/validation.
  """

  alias Lang.Semantic.Insights.Insight

  def upsert(attrs) when is_map(attrs) do
    case Ash.create(Insight, Map.to_list(attrs)) do
      {:ok, rec} -> {:ok, rec}
      {:error, err} -> {:error, err}
    end
  end

  def list(filters \\ %{}) do
    case Ash.read(Insight) do
      {:ok, list} ->
        {:ok,
         list
         |> maybe_filter(&(&1.workspace_id == &2), Map.get(filters, :workspace_id))
         |> maybe_filter(&(&1.owner_id == &2), Map.get(filters, :owner_id))
         |> maybe_filter(fn r, tag -> is_list(r.tags) and tag in r.tags end, Map.get(filters, :tag))}

      other -> other
    end
  end

  defp maybe_filter(list, _fun, nil), do: list
  defp maybe_filter(list, fun, val), do: Enum.filter(list, &fun.(&1, val))

  def get(id) do
    Ash.read(Insight |> Ash.Query.for_read(:by_id, %{id: id}))
  end
end
