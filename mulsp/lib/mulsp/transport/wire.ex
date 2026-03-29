defmodule Mulsp.Transport.Wire do
  @moduledoc """
  LSP wire protocol: Content-Length delimited messages over TCP/stdio.

  We intentionally avoid JSON as the inner format. Messages are Erlang
  terms (ETF) between mulsp nodes, and MUON (canonical text) when
  bridging to external systems. For LSP client compatibility, the
  Content-Length framing is preserved but the body is term_to_binary
  for internal traffic.

  For standard LSP clients that need JSON: those requests go through
  the full Lang platform, not directly through mulsp. mulsp is
  AI-to-AI and platform-to-servelet.
  """

  @doc "Encode a message with Content-Length header."
  def encode(term) when is_binary(term) do
    "Content-Length: #{byte_size(term)}\r\n\r\n#{term}"
  end

  def encode(term) do
    body = :erlang.term_to_binary(term)
    header = "Content-Length: #{byte_size(body)}\r\nContent-Type: application/erlang-etf\r\n\r\n"
    header <> body
  end

  @doc """
  Decode a Content-Length framed message from a binary buffer.
  Returns {:ok, body, rest} or {:incomplete, buffer}.
  """
  def decode(buffer) when is_binary(buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [header_section, rest] ->
        case parse_content_length(header_section) do
          {:ok, length} ->
            if byte_size(rest) >= length do
              <<body::binary-size(length), remaining::binary>> = rest
              {:ok, body, remaining}
            else
              {:incomplete, buffer}
            end

          :error ->
            {:error, :invalid_header}
        end

      [_incomplete] ->
        {:incomplete, buffer}
    end
  end

  @doc "Parse Content-Length from headers."
  def parse_content_length(headers) do
    headers
    |> String.split("\r\n")
    |> Enum.find_value(:error, fn line ->
      case String.split(line, ": ", parts: 2) do
        ["Content-Length", value] ->
          case Integer.parse(String.trim(value)) do
            {n, _} -> {:ok, n}
            :error -> nil
          end

        _ ->
          nil
      end
    end)
  end
end
