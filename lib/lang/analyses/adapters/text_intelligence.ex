defmodule Lang.Analyses.Adapters.TextIntelligence do
  @moduledoc """
  Adapter for text intelligence analysis.
  """

  def analyze(content, opts \\ []) when is_binary(content) do
    if Code.ensure_loaded?(Lang.Native.PerfEngine) and
         function_exported?(Lang.Native.PerfEngine, :analyze_text, 2) do
      Lang.Native.PerfEngine.analyze_text(content, Keyword.merge([format: :text], opts))
    else
      {:ok, %{summary: String.slice(content, 0, 120), metrics: %{bytes: byte_size(content)}}}
    end
  end
end
