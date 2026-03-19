defmodule QCP.Stream do
  @moduledoc """
  Streaming parser for QCP.

  Processes a line stream, chunking by channel fences and emitting
  `{channel, content}` tuples lazily.
  """

  @type channel :: :task | :resources | :diagnostics | :meta | :unknown
  @type event :: {channel(), String.t()}

  @doc """
  Process a stream (of lines) and emit channel tuples.
  """
  @spec process(Enumerable.t()) :: Enumerable.t()
  def process(line_stream) do
    Stream.transform(line_stream, {:none, []}, fn line, {cur, buf} ->
      case detect_channel(line) do
        {:open, ch} ->
          {[], {ch, []}}
        :close ->
          content = buf |> Enum.reverse() |> Enum.join("") |> String.trim_trailing()
          {[{cur, content}], {:none, []}}
        :none ->
          if cur == :none do
            {[], {cur, buf}}
          else
            {[], {cur, [line | buf]}}
          end
      end
    end)
  end

  @doc "Detect channel fence open/close for a given line"
  @spec detect_channel(String.t()) :: {:open, channel()} | :close | :none
  def detect_channel(line) do
    with [_, name] <- Regex.run(~r/^```\s*([a-zA-Z0-9_-]+)\s*\n?$/, line),
         ch <- to_channel(name) do
      {:open, ch}
    else
      _ -> if Regex.match?(~r/^```\s*\n?$/, line), do: :close, else: :none
    end
  end

  defp to_channel(name) do
    case String.downcase(name) do
      "task" -> :task
      "resources" -> :resources
      "diagnostics" -> :diagnostics
      "meta" -> :meta
      _ -> :unknown
    end
  end
end

