defmodule Lang.Analyses.Adapters.Stylometrics do
  @moduledoc """
  Adapter for stylometric analysis.
  """

  def compute(content) when is_binary(content) do
    # Placeholder stats; swap with real stylometry.
    words = String.split(content)
    {:ok, %{word_count: length(words), avg_word_len: avg_word_len(words)}}
  end

  defp avg_word_len([]), do: 0
  defp avg_word_len(ws), do: Enum.map(ws, &String.length/1) |> Enum.sum() |> Kernel./(length(ws))
end
