defmodule Lang.LSP.Spec do
  @moduledoc """
  Centralized helpers for Language Server Protocol (LSP) spec quirks.

  References: LSP 3.17 (UTF-16 code unit offsets; zero-based line/character).

  This module converts between LSP positions (UTF-16 code unit offsets) and
  Elixir-friendly indices (zero-based codepoint indices) that String APIs expect.
  """

  @doc """
  Convert an LSP `character` (UTF-16 code unit offset) within a single line to
  a zero-based codepoint index safe for `String.slice/3` and similar.

  - `line` must be a single line (no newlines)
  - `lsp_char` is the LSP UTF-16 code unit offset (integer)
  """
  @spec lsp_character_to_codepoint(line :: String.t(), lsp_char :: non_neg_integer()) :: non_neg_integer()
  def lsp_character_to_codepoint(line, lsp_char) when is_binary(line) and is_integer(lsp_char) do
    # Iterate codepoints; accumulate UTF-16 code units
    {idx, _units} =
      line
      |> String.to_charlist()
      |> Enum.reduce_while({0, 0}, fn cp, {cp_idx, units} ->
        add = if cp > 0xFFFF, do: 2, else: 1
        next_units = units + add
        if next_units > lsp_char do
          {:halt, {cp_idx, units}}
        else
          {:cont, {cp_idx + 1, next_units}}
        end
      end)

    # If lsp_char exceeds the line's units, clamp to end of line
    min(idx, String.length(line))
  end

  @doc """
  Convert an LSP position map to a safe Elixir position map (codepoint-based).

  Expects `position` as a map like %{"line" => line, "character" => char}.
  """
  @spec lsp_position_to_elixir(text :: String.t(), position :: map()) :: map()
  def lsp_position_to_elixir(text, %{"line" => line, "character" => ch} = pos) do
    lines = String.split(text, "\n")
    line_text = Enum.at(lines, line, "")
    cp = lsp_character_to_codepoint(line_text, ch)
    %{pos | "character" => cp}
  end

  @doc """
  Convert an LSP range to codepoint indices within a single string.
  Returns a tuple {start_cp, end_cp} for the given line texts.
  """
  @spec lsp_range_line_to_elixir(start_line :: String.t(), end_line :: String.t(), range :: map()) :: {non_neg_integer(), non_neg_integer()}
  def lsp_range_line_to_elixir(start_line_text, end_line_text, %{"start" => s, "end" => e}) do
    s_cp = lsp_character_to_codepoint(start_line_text, s["character"]) 
    e_cp = lsp_character_to_codepoint(end_line_text, e["character"]) 
    {s_cp, e_cp}
  end
end

