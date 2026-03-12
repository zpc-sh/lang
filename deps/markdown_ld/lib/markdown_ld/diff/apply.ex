defmodule MarkdownLd.Diff.Apply do
  @moduledoc """
  Apply MarkdownLd diff patches to raw markdown text.

  Currently supports block-level insert/delete/update operations. Inline
  operations are used only for diagnostics; the `after` payload drives updates.
  """

  alias MarkdownLd.Diff

  @doc """
  Apply a patch to a markdown string, returning the updated text.
  """
  @spec apply_to_text(String.t(), Diff.Patch.t()) :: String.t()
  def apply_to_text(old_text, %Diff.Patch{changes: changes}) do
    blocks = MarkdownLd.Diff.Block.segment(old_text)
    texts = Enum.map(blocks, & &1.text)

    {inserts, deletes, updates} =
      Enum.reduce(changes, {[], MapSet.new(), %{}}, fn ch, {ins, del, upd} ->
        case ch.kind do
          :insert_block -> { [{List.last(ch.path || [0]) || 0, ch.payload[:text]} | ins], del, upd }
          :delete_block -> { ins, MapSet.put(del, List.last(ch.path || [0]) || 0), upd }
          :update_block -> { ins, del, Map.put(upd, List.last(ch.path || [0]) || 0, ch.payload[:after]) }
          _ -> {ins, del, upd}
        end
      end)

    kept =
      texts
      |> Enum.with_index()
      |> Enum.reject(fn {_b, i} -> MapSet.member?(deletes, i) end)
      |> Enum.map(fn {b, i} -> Map.get(updates, i, b) end)

    with_inserts =
      inserts
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce(kept, fn {idx, text}, acc -> List.insert_at(acc, idx, text) end)

    Enum.join(with_inserts, "\n\n")
  end
end

