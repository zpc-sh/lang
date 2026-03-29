defmodule Lang.Analyses.Adapters.Parser do
  @moduledoc """
  Thin adapter over parsers. Detects format and parses content.
  """

  def detect(content) when is_binary(content) do
    # If you have a real detector, call it here.
    cond do
      String.starts_with?(content, ["{", "["]) -> {:ok, :json}
      String.contains?(content, ["def ", "end"]) -> {:ok, :elixir}
      true -> {:ok, :text}
    end
  end

  def parse(content, format) do
    {:ok, %{format: format, length: byte_size(content)}}
  end
end
