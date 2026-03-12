defmodule MarkdownLd.Diff.Inline do
  @moduledoc """
  Inline diff utilities for block text content.

  Implements a simple token-based LCS diff to produce ops suitable for
  rendering and merging: :keep, :insert, :delete.
  """

  @type op() :: {:keep, String.t()} | {:insert, String.t()} | {:delete, String.t()}

  @doc """
  Compute inline diff ops using token LCS. Tokens are words and numbers; punctuation
  is treated as separators.
  """
  @spec diff(String.t(), String.t()) :: [op()]
  def diff(a, b) do
    ta = tokenize(a)
    tb = tokenize(b)
    pairs = lcs_pairs(ta, tb)
    build_ops(ta, tb, MapSet.new(Enum.map(pairs, &elem(&1, 0))), MapSet.new(Enum.map(pairs, &elem(&1, 1))))
  end

  defp tokenize(text) do
    text
    |> String.replace(~r/[^\p{L}\p{N}_]+/u, " ")
    |> String.split(~r/\s+/, trim: true)
  end

  defp lcs_pairs(a, b) do
    n = length(a)
    m = length(b)
    if n == 0 or m == 0, do: [], else: (
    eq = fn x, y -> x == y end
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

    backtrack_pairs(a, b, n, m, table, [])
    )
  end

  defp backtrack_pairs(_a, _b, 0, _m, _t, acc), do: Enum.reverse(acc)
  defp backtrack_pairs(_a, _b, _n, 0, _t, acc), do: Enum.reverse(acc)
  defp backtrack_pairs(a, b, i, j, t, acc) do
    ai = Enum.at(a, i - 1)
    bj = Enum.at(b, j - 1)
    cond do
      ai == bj -> backtrack_pairs(a, b, i - 1, j - 1, t, [{i - 1, j - 1} | acc])
      Map.get(t, {i, j - 1}, 0) >= Map.get(t, {i - 1, j}, 0) -> backtrack_pairs(a, b, i, j - 1, t, acc)
      true -> backtrack_pairs(a, b, i - 1, j, t, acc)
    end
  end

  defp build_ops(ta, tb, a_keep, b_keep) do
    # Walk through ta and tb simultaneously using keep sets
    ops = do_ops(ta, tb, 0, 0, a_keep, b_keep, [])
    Enum.reverse(ops)
  end

  defp do_ops(ta, tb, i, j, a_keep, b_keep, acc) do
    cond do
      i >= length(ta) and j >= length(tb) -> acc
      i < length(ta) and MapSet.member?(a_keep, i) and j < length(tb) and MapSet.member?(b_keep, j) and Enum.at(ta, i) == Enum.at(tb, j) ->
        do_ops(ta, tb, i + 1, j + 1, a_keep, b_keep, [{:keep, Enum.at(tb, j)} | acc])
      j < length(tb) and MapSet.member?(b_keep, j) ->
        # Next token in tb is kept, so delete tokens from ta until we sync
        do_ops(ta, tb, i + 1, j, a_keep, b_keep, if(i < length(ta), do: [{:delete, Enum.at(ta, i)} | acc], else: acc))
      i < length(ta) and MapSet.member?(a_keep, i) ->
        # Next token in ta is kept, so insert tokens from tb until we sync
        do_ops(ta, tb, i, j + 1, a_keep, b_keep, if(j < length(tb), do: [{:insert, Enum.at(tb, j)} | acc], else: acc))
      i < length(ta) and j < length(tb) ->
        # Neither are kept: choose insert or delete to progress; prefer substitutions as delete+insert
        do_ops(ta, tb, i + 1, j + 1, a_keep, b_keep, [{:delete, Enum.at(ta, i)}, {:insert, Enum.at(tb, j)} | acc])
      i < length(ta) ->
        do_ops(ta, tb, i + 1, j, a_keep, b_keep, [{:delete, Enum.at(ta, i)} | acc])
      j < length(tb) ->
        do_ops(ta, tb, i, j + 1, a_keep, b_keep, [{:insert, Enum.at(tb, j)} | acc])
    end
  end
end
