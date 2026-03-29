defmodule Mulsp.Transport.Tcp do
  @moduledoc """
  TCP transport GenServer. Accepts connections and feeds messages
  to the dispatcher. Used for JSON-RPC over TCP (LSP wire) and
  as the backbone for inter-mulsp communication.

  Each connected client gets its own handler process.
  """
  use GenServer

  require Logger

  def start_link(opts) do
    port = Keyword.get(opts, :port, 7080)
    GenServer.start_link(__MODULE__, %{port: port}, name: __MODULE__)
  end

  @impl true
  def init(%{port: port}) do
    case :gen_tcp.listen(port, [
           :binary,
           {:active, false},
           {:reuseaddr, true},
           {:packet, :raw}
         ]) do
      {:ok, listen_socket} ->
        spawn_link(fn -> accept_loop(listen_socket) end)
        Logger.info("[mulsp:tcp] listening on port #{port}")
        {:ok, %{listen_socket: listen_socket, port: port, clients: %{}}}

      {:error, reason} ->
        Logger.warning("[mulsp:tcp] failed to bind port #{port}: #{inspect(reason)}")
        {:ok, %{port: port, clients: %{}}}
    end
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        spawn(fn -> client_loop(client, <<>>) end)
        accept_loop(listen_socket)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept_loop(listen_socket)
    end
  end

  defp client_loop(socket, buffer) do
    case :gen_tcp.recv(socket, 0, 30_000) do
      {:ok, data} ->
        new_buffer = buffer <> data
        {new_buffer, _responses} = process_buffer(socket, new_buffer)
        client_loop(socket, new_buffer)

      {:error, :timeout} ->
        # Keep connection alive
        client_loop(socket, buffer)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end

  defp process_buffer(socket, buffer) do
    case Mulsp.Transport.Wire.decode(buffer) do
      {:ok, body, rest} ->
        response = handle_message(body)

        if response do
          encoded = Mulsp.Transport.Wire.encode(response)
          :gen_tcp.send(socket, encoded)
        end

        process_buffer(socket, rest)

      {:incomplete, buffer} ->
        {buffer, []}

      {:error, _reason} ->
        {<<>>, []}
    end
  end

  defp handle_message(body) do
    # Try to decode as Erlang term first (internal mulsp traffic)
    request =
      try do
        :erlang.binary_to_term(body)
      rescue
        _ ->
          # Fall back to treating as text (MUON or raw)
          %{method: "raw", params: body, id: nil}
      end

    case request do
      %{method: method, params: params, id: id} ->
        case Mulsp.Dispatch.dispatch(method, params, id) do
          {:ok, result} -> %{id: id, result: result}
          {:error, code, message} -> %{id: id, error: %{code: code, message: message}}
        end

      # Erlang tuple format from internal traffic
      {method, params} when is_binary(method) ->
        case Mulsp.Dispatch.dispatch(method, params) do
          {:ok, result} -> {:ok, result}
          {:error, _, _} = err -> err
        end

      _ ->
        nil
    end
  end
end
