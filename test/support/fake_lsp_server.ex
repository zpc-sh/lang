defmodule FakeLSPServer do
  @moduledoc """
  Minimal TCP LSP-like server for testing multiplexing.

  - Speaks JSON-RPC over Content-Length framing
  - Replies to initialize with a basic result
  - Echo method "test.echo" responds with params after optional delay_ms
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def start(port \\ 0), do: GenServer.call(__MODULE__, {:start, port})

  @impl true
  def init(_opts) do
    {:ok, %{lsock: nil, port: nil}}
  end

  @impl true
  def handle_call({:start, port}, _from, state) do
    {:ok, lsock} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, actual_port} = :inet.port(lsock)
    Task.start_link(fn -> accept_loop(lsock) end)
    {:reply, {:ok, actual_port}, %{state | lsock: lsock, port: actual_port}}
  end

  defp accept_loop(lsock) do
    case :gen_tcp.accept(lsock) do
      {:ok, sock} ->
        Task.start_link(fn -> conn_loop(sock) end)
        accept_loop(lsock)
      {:error, _} -> :ok
    end
  end

  defp conn_loop(sock) do
    case recv_until_header(sock, "") do
      {:ok, len, rest} ->
        case recv_body(sock, len, rest) do
          {:ok, %{"method" => "initialize", "id" => id}} ->
            send_json(sock, %{"jsonrpc" => "2.0", "id" => id, "result" => %{"capabilities" => %{}}})
            conn_loop(sock)

          {:ok, %{"method" => "initialized"}} ->
            # ignore
            conn_loop(sock)

          {:ok, %{"method" => "test.echo", "id" => id, "params" => params}} ->
            delay = params["delay_ms"] || 0
            :timer.sleep(delay)
            send_json(sock, %{"jsonrpc" => "2.0", "id" => id, "result" => params})
            conn_loop(sock)

          {:ok, %{"id" => id}} ->
            send_json(sock, %{"jsonrpc" => "2.0", "id" => id, "result" => %{}})
            conn_loop(sock)

          {:ok, _other} ->
            conn_loop(sock)

          {:error, _} -> :gen_tcp.close(sock)
        end

      {:error, _} -> :gen_tcp.close(sock)
    end
  end

  defp recv_until_header(sock, acc) do
    case :gen_tcp.recv(sock, 0, 5_000) do
      {:ok, data} ->
        buf = acc <> data
        case :binary.match(buf, "\r\n\r\n") do
          {hdr_end, 4} ->
            headers = :binary.part(buf, 0, hdr_end)
            rest = :binary.part(buf, hdr_end + 4, byte_size(buf) - (hdr_end + 4))
            case parse_len(headers) do
              {:ok, len} -> {:ok, len, rest}
              _ -> recv_until_header(sock, buf)
            end
          :nomatch -> recv_until_header(sock, buf)
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_len(headers) do
    case :binary.match(headers, "Content-Length: ") do
      {pos, _} ->
        start = pos + byte_size("Content-Length: ")
        suffix = :binary.part(headers, start, byte_size(headers) - start)
        case :binary.match(suffix, "\r\n") do
          {eol, _} ->
            case Integer.parse(:binary.part(suffix, 0, eol)) do
              {int, _} -> {:ok, int}
              :error -> {:error, :invalid}
            end
          :nomatch -> {:error, :invalid}
        end
      :nomatch -> {:error, :invalid}
    end
  end

  defp recv_body(sock, 0, rest), do: Jason.decode(rest)
  defp recv_body(sock, len, rest) do
    have = byte_size(rest)
    cond do
      have == len -> Jason.decode(rest)
      have > len -> Jason.decode(:binary.part(rest, 0, len))
      true ->
        rem = len - have
        case :gen_tcp.recv(sock, rem, 5_000) do
          {:ok, data} -> Jason.decode(rest <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp send_json(sock, map) do
    {:ok, io} = Jason.encode_to_iodata(map)
    len = :erlang.iolist_size(io)
    :gen_tcp.send(sock, ["Content-Length: ", Integer.to_string(len), "\r\n\r\n", io])
  end
end

