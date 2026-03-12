defmodule MarkdownLd.Diff.Preview do
  @moduledoc """
  Render inline ops into a preview string for UI.

  Styles:
  - :markers (default): inserts `{+ +}`, deletes `{- -}`
  - :ansi: wraps with ANSI green/red (without assuming a renderer)
  """

  @type op :: {:keep, String.t()} | {:insert, String.t()} | {:delete, String.t()}

  @spec render_ops([op()], keyword()) :: String.t()
  def render_ops(ops, opts \\ []) do
    style = Keyword.get(opts, :style, :markers)
    joiner = Keyword.get(opts, :joiner, " ")

    ops
    |> Enum.map(fn
      {:keep, t} -> t
      {:insert, t} -> wrap(:insert, t, style)
      {:delete, t} -> wrap(:delete, t, style)
    end)
    |> Enum.join(joiner)
  end

  defp wrap(:insert, t, :markers), do: "{+" <> t <> "+}"
  defp wrap(:delete, t, :markers), do: "{-" <> t <> "-}"
  defp wrap(:insert, t, :ansi), do: IO.ANSI.green() <> t <> IO.ANSI.reset()
  defp wrap(:delete, t, :ansi), do: IO.ANSI.red() <> t <> IO.ANSI.reset()
end

