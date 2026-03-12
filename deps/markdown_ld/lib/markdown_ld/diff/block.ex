defmodule MarkdownLd.Diff.Block do
  @moduledoc """
  Block-level segmentation and diffing for Markdown.

  This module provides a lightweight block segmenter and a simple LCS-based
  differ that emits `MarkdownLd.Diff.Change` operations suitable for
  higher-level patches and merges.
  """

  alias MarkdownLd.Diff

  @enforce_keys [:type, :text]
  defstruct [:type, :text, :attrs]

  @type t :: %__MODULE__{type: Diff.block_type(), text: String.t(), attrs: map() | nil}

  @doc """
  Segment raw markdown into a list of block structs. This is intentionally
  simple and deterministic for diff purposes, not a full Markdown AST.
  """
  @spec segment(String.t()) :: [t()]
  def segment(text) when is_binary(text) do
    lines = String.split(text, "\n", trim: false)
    do_segment(lines, [], :paragraph, []) |> Enum.reverse()
  end

  defp do_segment([], acc_blocks, :paragraph, cur_par) do
    flush_paragraph(acc_blocks, cur_par)
  end

  defp do_segment([], acc_blocks, {:code, lang, start_line}, cur_par) do
    acc_blocks = flush_paragraph(acc_blocks, cur_par)
    # Unclosed code fence: treat remaining as code
    code_text = Enum.join(["```" <> lang | []], "\n")
    [%__MODULE__{type: :code_block, text: code_text, attrs: %{language: lang}} | acc_blocks]
  end

  defp do_segment([line | rest], acc_blocks, {:code, lang, start_line}, cur_par) do
    case fence_lang(line) do
      {:fence, _end_lang} ->
        code_text = Enum.join(Enum.reverse(cur_par), "\n")
        block = %__MODULE__{type: :code_block, text: code_text, attrs: %{language: lang, start: start_line}}
        do_segment(rest, [block | acc_blocks], :paragraph, [])

      :no_fence ->
        do_segment(rest, acc_blocks, {:code, lang, start_line}, [line | cur_par])
    end
  end

  defp do_segment([line | rest], acc_blocks, :paragraph, cur_par) do
    case heading(line) do
      {level, text} ->
        acc_blocks = flush_paragraph(acc_blocks, cur_par)
        block = %__MODULE__{type: :heading, text: String.trim(text), attrs: %{level: level}}
        do_segment(rest, [block | acc_blocks], :paragraph, [])
      _ ->
        case task_item(line) do
          {completed, text} ->
            acc_blocks = flush_paragraph(acc_blocks, cur_par)
            block = %__MODULE__{type: :list_item, text: String.trim(text), attrs: %{task: true, completed: completed}}
            do_segment(rest, [block | acc_blocks], :paragraph, [])
          _ ->
            case fence_lang(line) do
              {:fence, lang} ->
                acc_blocks = flush_paragraph(acc_blocks, cur_par)
                do_segment(rest, acc_blocks, {:code, lang, 0}, [])
              :no_fence ->
                if String.trim(line) == "" do
                  acc_blocks = flush_paragraph(acc_blocks, cur_par)
                  do_segment(rest, acc_blocks, :paragraph, [])
                else
                  do_segment(rest, acc_blocks, :paragraph, [line | cur_par])
                end
            end
        end
    end
  end

  defp flush_paragraph(acc, []), do: acc
  defp flush_paragraph(acc, lines) do
    text = lines |> Enum.reverse() |> Enum.join("\n")
    [%__MODULE__{type: :paragraph, text: text, attrs: %{}} | acc]
  end

  defp heading(line) do
    case Regex.run(~r/^(#+)\s+(.*)$/, line) do
      [_, hashes, text] -> {min(String.length(hashes), 6), text}
      _ -> nil
    end
  end

  defp task_item(line) do
    case Regex.run(~r/^\s*[-*]\s*\[( |x|X)\]\s+(.*)$/, line) do
      [_, " ", text] -> {false, text}
      [_, _x, text] -> {true, text}
      _ -> nil
    end
  end

  defp fence_lang(line) do
    case Regex.run(~r/^```\s*([A-Za-z0-9_+-]*)\s*$/, line) do
      [_, lang] -> {:fence, lang}
      _ -> :no_fence
    end
  end

  # ——— Diff ———

  @doc """
  Compute a block-level diff between two markdown strings, returning a list of
  `MarkdownLd.Diff.Change` operations. Insert/delete/update are emitted. Update
  is used when blocks are similar (same type and token overlap >= threshold).
  """
  @spec diff(String.t(), String.t(), keyword()) :: [Diff.Change.t()]
  def diff(old_text, new_text, opts \\ []) do
    old_blocks = segment(old_text)
    new_blocks = segment(new_text)
    threshold = Keyword.get(opts, :similarity_threshold, 0.5)

    pairs = lcs_pairs(old_blocks, new_blocks)
    old_matched = MapSet.new(Enum.map(pairs, fn {i, _j} -> i end))
    new_matched = MapSet.new(Enum.map(pairs, fn {_i, j} -> j end))

    deletes =
      old_blocks
      |> Enum.with_index()
      |> Enum.reject(fn {_b, i} -> MapSet.member?(old_matched, i) end)
      |> Enum.map(fn {b, i} ->
        Diff.change(:delete_block, [i], %{type: b.type, text: b.text})
      end)

    inserts =
      new_blocks
      |> Enum.with_index()
      |> Enum.reject(fn {_b, j} -> MapSet.member?(new_matched, j) end)
      |> Enum.map(fn {b, j} ->
        Diff.change(:insert_block, [j], %{type: b.type, text: b.text})
      end)

    # Try to coalesce delete+insert at similar indices into updates
    {updates, residual_deletes, residual_inserts} = coalesce_updates(deletes, inserts, old_blocks, new_blocks, threshold)

    updates ++ residual_deletes ++ residual_inserts
  end

  @doc "Wrap diff into a Patch with from/to revisions"
  @spec diff_patch(String.t(), String.t(), Diff.rev(), Diff.rev(), keyword()) :: Diff.Patch.t()
  def diff_patch(old_text, new_text, from_rev, to_rev, opts \\ []) do
    changes = diff(old_text, new_text, opts)
    Diff.patch(from_rev, to_rev, changes)
  end

  # LCS based on exact block equality (type + normalized text)
  defp lcs_pairs(a, b) do
    eq = fn x, y -> x.type == y.type and norm(x.text) == norm(y.text) end
    n = length(a)
    m = length(b)
    if n == 0 or m == 0, do: [], else: (
    table = %{}
    table =
      Enum.reduce(1..n, %{}, fn i, t ->
        Enum.reduce(1..m, t, fn j, t2 ->
          ai = Enum.at(a, i - 1)
          bj = Enum.at(b, j - 1)
          val = if eq.(ai, bj), do: Map.get(t2, {i - 1, j - 1}, 0) + 1,
                                 else: max(Map.get(t2, {i, j - 1}, 0), Map.get(t2, {i - 1, j}, 0))
          Map.put(t2, {i, j}, val)
        end)
      end)
    backtrack_pairs(a, b, n, m, table, eq, [])
    )
  end

  defp backtrack_pairs(_a, _b, 0, _m, _t, _eq, acc), do: Enum.reverse(acc)
  defp backtrack_pairs(_a, _b, _n, 0, _t, _eq, acc), do: Enum.reverse(acc)
  defp backtrack_pairs(a, b, i, j, t, eq, acc) do
    ai = Enum.at(a, i - 1)
    bj = Enum.at(b, j - 1)
    cond do
      eq.(ai, bj) -> backtrack_pairs(a, b, i - 1, j - 1, t, eq, [{i - 1, j - 1} | acc])
      Map.get(t, {i, j - 1}, 0) >= Map.get(t, {i - 1, j}, 0) -> backtrack_pairs(a, b, i, j - 1, t, eq, acc)
      true -> backtrack_pairs(a, b, i - 1, j, t, eq, acc)
    end
  end

  defp norm(text) do
    text |> String.trim() |> String.replace(~r/\s+/, " ")
  end

  defp coalesce_updates(deletes, inserts, old_blocks, new_blocks, threshold) do
    {updates, dels, ins} = Enum.reduce(deletes, {[], [], inserts}, fn d, {ups, ds, ins_acc} ->
      {kind, path, payload} = {d.kind, d.path, d.payload}
      i = List.last(path || [0]) || 0
      ob = Enum.at(old_blocks, i)

      {match, rest} = pick_best_match(ob, ins_acc, new_blocks, threshold)
      case match do
        nil -> {ups, [d | ds], ins_acc}
        {j, nb, ins_change} ->
          inline_ops = inline_ops_for(nb.type, ob.text, nb.text)
          update = Diff.change(:update_block, [j], %{
            type: nb.type,
            before: ob.text,
            after: nb.text,
            inline_ops: inline_ops
          })
          { [update | ups], ds, rest }
      end
    end)

    {Enum.reverse(updates), dels, ins}
  end

  defp pick_best_match(nil, inserts, _new_blocks, _threshold), do: {nil, inserts}
    
  defp pick_best_match(ob, inserts, new_blocks, threshold) do
    candidates =
      inserts
      |> Enum.map(fn ins_change ->
        j = List.last(ins_change.path || [0]) || 0
        nb = Enum.at(new_blocks, j)
        score = if ob.type == nb.type, do: similarity(ob.text, nb.text), else: 0.0
        {score, j, nb, ins_change}
      end)
      |> Enum.sort_by(fn {s, _j, _nb, _c} -> -s end)

    case candidates do
      [] -> {nil, inserts}
      [{best, j, nb, ins_change} | _] when best >= threshold ->
        rest = List.delete(inserts, ins_change)
        {{j, nb, ins_change}, rest}
      _ -> {nil, inserts}
    end
  end

  defp inline_ops_for(type, old_text, new_text) do
    # Perform inline diff for text-like blocks
    case type do
      :paragraph -> MarkdownLd.Diff.Inline.diff(old_text, new_text)
      :heading -> MarkdownLd.Diff.Inline.diff(old_text, new_text)
      :list_item -> MarkdownLd.Diff.Inline.diff(old_text, new_text)
      _ -> []
    end
  end

  # Token-overlap similarity (Dice coefficient over sets)
  defp similarity(a, b) do
    sa = tokenize(a)
    sb = tokenize(b)
    inter = MapSet.size(MapSet.intersection(sa, sb))
    denom = MapSet.size(sa) + MapSet.size(sb)
    if denom == 0, do: 1.0, else: 2.0 * inter / denom
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_\s]+/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end
end
