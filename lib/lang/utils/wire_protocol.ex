defmodule Lang.Utils.WireProtocol do
  @moduledoc """
  Minimal JSON-RPC wire protocol helpers (Content-Length framing with CRLF).

  Compatible with LSP, MCP, and DAP transports that use the same framing.

  Features:
  - encode/1: map -> iodata with Content-Length header
  - next_frame/1: parse a message from a buffer, return decoded map and rest
  - parse_many/1: parse as many complete frames from a buffer as possible

  This module is transport-agnostic: callers are responsible for reading from
  sockets or STDIO into a binary buffer, then feeding it to `next_frame/1` or
  `parse_many/1`.
  """

  @type json :: map()

  @crlf "\r\n"
  @crlfcrlf @crlf <> @crlf

  @doc """
  Encode a JSON-RPC map as iodata with a Content-Length header.
  """
  @spec encode(json()) :: iodata()
  def encode(map) when is_map(map) do
    body = Jason.encode!(map)
    ["Content-Length: ", Integer.to_string(byte_size(body)), @crlfcrlf, body]
  end

  @doc """
  Parse the next frame from a buffer.

  Returns:
  - {:ok, map, rest}
  - {:more, needed} when more bytes are required
  - {:error, reason}
  """
  @spec next_frame(binary()) ::
          {:ok, json(), binary()} | {:more, non_neg_integer()} | {:error, term()}
  def next_frame(buffer) when is_binary(buffer) do
    with {:ok, content_len, rest} <- parse_headers(buffer),
         true <- byte_size(rest) >= content_len or {:more, content_len - byte_size(rest)} do
      <<body::binary-size(content_len), leftover::binary>> = rest

      case Jason.decode(body) do
        {:ok, map} when is_map(map) -> {:ok, map, leftover}
        error -> {:error, {:invalid_json, error}}
      end
    else
      {:more, needed} -> {:more, needed}
      {:error, reason} -> {:error, reason}
      other -> other
    end
  end

  @doc """
  Parse as many complete frames as possible from a buffer.

  Returns {messages, rest}.
  """
  @spec parse_many(binary()) :: {[json()], binary()}
  def parse_many(buffer) do
    do_parse_many(buffer, [])
  end

  defp do_parse_many(buffer, acc) do
    case next_frame(buffer) do
      {:ok, msg, rest} -> do_parse_many(rest, [msg | acc])
      {:more, _} -> {Enum.reverse(acc), buffer}
      {:error, _} -> {Enum.reverse(acc), buffer}
    end
  end

  @doc false
  @spec parse_headers(binary()) ::
          {:ok, non_neg_integer(), binary()} | {:more, non_neg_integer()} | {:error, term()}
  def parse_headers(buffer) do
    case :binary.match(buffer, @crlfcrlf) do
      {idx, 4} ->
        <<headers::binary-size(idx), _sep::binary-size(4), rest::binary>> = buffer

        case extract_content_length(headers) do
          {:ok, len} -> {:ok, len, rest}
          {:error, _} = err -> err
        end

      :nomatch ->
        {:more, 1}
    end
  end

  defp extract_content_length(headers) do
    headers
    |> String.split(@crlf, trim: true)
    |> Enum.reduce_while(nil, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [k, v] ->
          key = k |> String.trim() |> String.downcase()

          if key == "content-length" do
            case Integer.parse(String.trim(v)) do
              {i, _} when i >= 0 -> {:halt, {:ok, i}}
              _ -> {:halt, {:error, :invalid_content_length}}
            end
          else
            {:cont, acc}
          end

        _ ->
          {:cont, acc}
      end
    end)
    |> case do
      {:ok, i} -> {:ok, i}
      nil -> {:error, :missing_content_length}
      other -> other
    end
  end
end
