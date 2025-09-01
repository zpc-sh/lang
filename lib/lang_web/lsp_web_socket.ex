defmodule LangWeb.LspWebSocket do
  @behaviour WebSock

  defp upstream() do
    cfg = Application.get_env(:lang, :lsp_upstream, host: "127.0.0.1", port: 4001)
    host = Keyword.get(cfg, :host, "127.0.0.1")
    port = Keyword.get(cfg, :port, 4001)
    {resolve_host(host), port}
  end

  defp resolve_host({a, b, c, d} = tuple) when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d), do: tuple
  defp resolve_host(host) when is_binary(host) do
    case :inet.getaddr(String.to_charlist(host), :inet) do
      {:ok, addr} -> addr
      _ -> {127, 0, 0, 1}
    end
  end

  # Initialize TCP connection to internal LSP and buffer
  def init(state) do
    {host, port} = upstream()
    case :gen_tcp.connect(host, port, [:binary, active: true, packet: :raw]) do
      {:ok, sock} -> {:ok, state |> Map.put(:upstream, sock) |> Map.put(:buf, "")}
      {:error, reason} -> {:ok, Map.put(state, :error, {:upstream_connect_failed, reason})}
    end
  end

  # From client → upstream: wrap as LSP Content-Length framed payload
  def handle_in({data, _opcode}, %{upstream: sock} = state) when is_binary(data) do
    frame = encode_lsp(data)
    _ = :gen_tcp.send(sock, frame)
    {:ok, state}
  end
  def handle_in(_other, state), do: {:ok, state}

  # From upstream → client: parse LSP frames and push each JSON payload
  def handle_info({:tcp, _sock, data}, %{buf: buf} = state) do
    new_buf = buf <> data
    {messages, rest} = decode_lsp(new_buf, [])
    replies = Enum.map(messages, fn msg -> {:text, msg} end)
    case replies do
      [] -> {:ok, %{state | buf: rest}}
      _ -> {:reply, replies, %{state | buf: rest}}
    end
  end
  def handle_info({:tcp_closed, _sock}, state), do: {:stop, :normal, state}
  def handle_info(_msg, state), do: {:ok, state}

  def handle_control(_frame, state), do: {:ok, state}
  def terminate(_reason, %{upstream: sock}) do
    _ = :gen_tcp.close(sock)
    :ok
  end
  def terminate(_reason, _state), do: :ok

  # Helpers
  defp encode_lsp(json) when is_binary(json) do
    "Content-Length: " <> Integer.to_string(byte_size(json)) <> "\r\n\r\n" <> json
  end

  defp decode_lsp(<<>>, acc), do: {Enum.reverse(acc), ""}
  defp decode_lsp(bin, acc) do
    case :binary.match(bin, "\r\n\r\n") do
      :nomatch -> {Enum.reverse(acc), bin}
      {hdr_end, 4} ->
        headers = binary_part(bin, 0, hdr_end)
        rest = binary_part(bin, hdr_end + 4, byte_size(bin) - hdr_end - 4)
        len = content_length(headers)
        cond do
          len == nil -> {Enum.reverse(acc), bin}
          byte_size(rest) < len -> {Enum.reverse(acc), bin}
          true ->
            msg = binary_part(rest, 0, len)
            decode_lsp(binary_part(rest, len, byte_size(rest) - len), [msg | acc])
        end
    end
  end

  defp content_length(headers) do
    headers
    |> String.split(["\r\n", "\n"]) 
    |> Enum.find_value(fn line ->
      case String.split(line, ":", parts: 2) do
        [k, v] ->
          kk = k |> String.trim() |> String.downcase()
          if kk == "content-length" do
            case Integer.parse(String.trim(v)) do
              {n, _} -> n
              :error -> nil
            end
          else
            nil
          end
        _ -> nil
      end
    end)
  end
end
