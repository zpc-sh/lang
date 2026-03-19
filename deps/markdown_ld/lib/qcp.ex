defmodule QCP do
  @moduledoc """
  Quad-Channel Prompting (QCP) parser utilities.

  Parses a QCP-formatted prompt into channels: :task, :resources, :diagnostics, :meta.
  Missing channels are returned as empty strings. Order independent.
  """

  @channels ~w(task resources diagnostics meta)a

  @typedoc "Parsed QCP channels as strings"
  @type t :: %{optional(:task) => String.t(), optional(:resources) => String.t(),
               optional(:diagnostics) => String.t(), optional(:meta) => String.t()}

  @doc """
  Parse a QCP document string into channel map.

      iex> QCP.parse("""
      ```task\nDo X\n```\n```resources\nRef\n```\n""")
      %{task: "Do X", resources: "Ref", diagnostics: "", meta: ""}
  """
  @spec parse(String.t()) :: t()
  def parse(text) when is_binary(text) do
    # Extract all channel blocks using non-greedy capture across lines
    re = ~r/```\s*(task|resources|diagnostics|meta)\s*\n([\s\S]*?)```/m
    caps = Regex.scan(re, text)

    initial = Enum.into(@channels, %{}, fn ch -> {ch, ""} end)

    Enum.reduce(caps, initial, fn
      [_, name, body], acc ->
        ch = String.to_existing_atom(name)
        # Append if multiple blocks exist for the same channel
        body = String.trim_trailing(String.trim(body))
        Map.update!(acc, ch, fn prev ->
          cond do
            prev == "" -> body
            body == "" -> prev
            true -> prev <> "\n\n" <> body
          end
        end)
      _, acc -> acc
    end)
  end
end

