defmodule Lang.Dev.History do
  @moduledoc """
  Fetch and format model history with optional diffs between snapshots.
  """

  import Ash.Query
  alias Lang.Dev.ModelState
  alias Lang.Dev.Diff

  @type history_item :: %{
          id: String.t(),
          model_id: String.t(),
          version: String.t(),
          hash: String.t(),
          status: String.t() | nil,
          actor: String.t() | nil,
          path: String.t() | nil,
          event_type: String.t(),
          at: DateTime.t(),
          diff: map() | nil
        }

  @doc """
  Return a chronological history for a model. If with_diff is true, compute diffs
  between consecutive snapshots.
  """
  @spec history(String.t(), keyword()) :: [history_item]
  def history(model_id, opts \\ []) do
    with_diff = Keyword.get(opts, :with_diff, false)

    case ModelState |> filter(model_id == ^model_id) |> Ash.read() do
      {:ok, list} ->
        ordered = Enum.sort_by(list, & &1.at, DateTime)
        if with_diff do
          attach_diffs(ordered)
        else
          Enum.map(ordered, &to_item(&1, nil))
        end
      _ -> []
    end
  end

  defp attach_diffs(list) do
    {items, _prev} =
      Enum.map_reduce(list, nil, fn entry, prev ->
        diff = if prev, do: Diff.diff(prev.snapshot, entry.snapshot), else: nil
        {to_item(entry, diff), entry}
      end)

    items
  end

  defp to_item(entry, diff) do
    %{
      id: entry.id,
      model_id: entry.model_id,
      version: entry.version,
      hash: entry.hash,
      status: entry.status,
      actor: entry.actor,
      path: entry.path,
      event_type: entry.event_type,
      at: entry.at,
      diff: diff
    }
  end
end
