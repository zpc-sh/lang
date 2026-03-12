defmodule MarkdownLd.Merge do
  @moduledoc "Merge ergonomics for MarkdownLd."

  @spec merge_texts(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t(), MarkdownLd.Diff.Patch.t()} | {:conflict, [MarkdownLd.Diff.Conflict.t()]}
  def merge_texts(base_text, ours_text, theirs_text, opts \\ []) do
    {:ok, ours_patch} = MarkdownLd.diff(base_text, ours_text, opts)
    {:ok, theirs_patch} = MarkdownLd.diff(base_text, theirs_text, opts)
    base_rev = :crypto.hash(:sha256, base_text) |> Base.encode16(case: :lower)
    base_patch = MarkdownLd.Diff.patch(base_rev, base_rev, [])

    result = MarkdownLd.Diff.three_way_merge(base_patch, ours_patch, theirs_patch)
    case result do
      %MarkdownLd.Diff.MergeResult{merged: %MarkdownLd.Diff.Patch{} = merged, conflicts: []} ->
        text = MarkdownLd.Diff.Apply.apply_to_text(base_text, merged)
        {:ok, text, merged}
      %MarkdownLd.Diff.MergeResult{conflicts: conflicts} -> {:conflict, conflicts}
    end
  end
end

