defmodule Lang.LSP.ConnectionWorker do
  @moduledoc """
  A GenServer that handles a single client TCP socket connection to the LSP server.
  """
  use GenServer
  require Logger

  def start_link(socket) do
    GenServer.start_link(__MODULE__, socket)
  end

  @impl true
  def init(socket) do
    client_id = "client_#{:erlang.unique_integer([:positive])}"
    Logger.info("ConnectionWorker #{inspect(self())} started for client #{client_id}")

    # Take control of the socket
    :gen_tcp.controlling_process(socket, self())

    # Notify the main server of the new client
    send(Lang.LSP.Server, {:client_connected, client_id, self()})

    {:ok, %{socket: socket, client_id: client_id, buffer: ""}}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket, buffer: buffer, client_id: client_id} = state) do
    new_buffer = buffer <> data
    {messages, remaining_buffer} = extract_messages(new_buffer)

    Enum.each(messages, fn msg ->
      send(Lang.LSP.Server, {:lsp_request, client_id, msg})
    end)

    {:noreply, %{state | buffer: remaining_buffer}}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %{socket: socket, client_id: client_id} = state) do
    Logger.info("Client #{client_id} disconnected (TCP closed).")
    send(Lang.LSP.Server, {:client_disconnected, client_id})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, %{socket: socket, client_id: client_id} = state) do
    Logger.error("TCP error for client #{client_id}: #{inspect(reason)}")
    send(Lang.LSP.Server, {:client_disconnected, client_id})
    {:stop, {:tcp_error, reason}, state}
  end

  @impl true
  def handle_cast({:send_response, response}, state) do
    send_json_rpc(state.socket, response)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %{socket: socket, client_id: client_id}) do
    Logger.info("ConnectionWorker for client #{client_id} terminating. Reason: #{inspect(reason)}")
    # Ensure the main server is notified on termination
    send(Lang.LSP.Server, {:client_disconnected, client_id})
    :gen_tcp.close(socket)
    :ok
  end

  defp extract_messages(buffer) do
    case Regex.run(~r/Content-Length: (\d+)\r\n\r\n/U, buffer) do
      [full_match, length_str] ->
        header_length = byte_size(full_match)
        content_length = String.to_integer(length_str)
        total_length = header_length + content_length

        if byte_size(buffer) >= total_length do
          <<_header::binary-size(header_length), json::binary-size(content_length), rest::binary>> = buffer

          case Jason.decode(json) do
            {:ok, message} ->
              {messages, remaining} = extract_messages(rest)
              {[message | messages], remaining}
            {:error, _reason} ->
              Logger.warn("Failed to decode JSON, skipping message.")
              extract_messages(rest)
          end
        else
          {[], buffer}
        end
      nil ->
        {[], buffer}
    end
  end

  defp send_json_rpc(socket, message) do
    json = Jason.encode!(message)
    content_length = byte_size(json)
    header = "Content-Length: #{content_length}\r\n\r\n"
    :gen_tcp.send(socket, header <> json)
  end
end
