defmodule Lang.Dev.SafeText do
  @moduledoc """
  Minimal sanitizer for untrusted text used in logs and docs.

  - Strips control characters (except tab/newline when requested).
  - Normalizes newlines to spaces by default.
  - Ensures single-line safe strings for YAML frontmatter.
  """

  @doc """
  Sanitize a string for single-line contexts (YAML keys, logs).
  - Removes control characters (0x00..0x1F, 0x7F) and newlines.
  - Trims surrounding whitespace.
  """
  @spec sanitize(String.t()) :: String.t()
  def sanitize(text) when is_binary(text) do
    text
    |> strip_control()
    |> String.replace(["\r", "\n"], " ")
    |> String.trim()
  end
  def sanitize(other), do: to_string(other) |> sanitize()

  defp strip_control(text) do
    for <<c <- text>>, c not in control_codes(), into: <<>>, do: <<c>>
  end

  defp control_codes do
    # 0x00..0x1F and 0x7F
    Enum.concat(Enum.to_list(0x00..0x1F), [0x7F])
  end
end

