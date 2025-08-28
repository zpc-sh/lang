defmodule Lang.LSP.Server do
  @moduledoc """
  The main LSP server implementation that handles TCP/stdio connections and JSON-RPC protocol.

  This server supports both TCP socket connections and stdio mode for VSCode integration.
  It handles the full LSP lifecycle and routes messages to appropriate handlers.
  """

  use GenServer
  require Logger

  alias Lang.LSP.{Dispatch, Registry, StreamingProtocol, PhoenixIntegration}
  alias Lang.TextIntelligence.AnalysisEngine

  @default_port 4001
  @read_timeout 60_000

  defstruct [
    :mode,
    :port,
    :listen_socket,
    :clients,
    :documents,
    :initialized,
    :root_uri,
    :capabilities,
    :shutdown_requested
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def stop(reason \\ :normal) do
    GenServer.stop(__MODULE__, reason)
  end

  def get_info do
    GenServer.call(__MODULE__, :get_info)
  end

  def get_document(uri) do
    GenServer.call(__MODULE__, {:get_document, uri})
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    mode = Keyword.get(opts, :mode, :tcp)
    port = Keyword.get(opts, :port, @default_port)

    state = %__MODULE__{
      mode: mode,
      port: port,
      clients: %{},
      documents: %{},
      initialized: false,
      shutdown_requested: false
    }

    case mode do
      :tcp ->
        {:ok, state, {:continue, :start_tcp_server}}
      :stdio ->
        {:ok, state, {:continue, :start_stdio_server}}
      _ ->
        {:stop, {:invalid_mode, mode}}
    end
  end

  @impl true
  def handle_continue(:start_tcp_server, state) do
    case :gen_tcp.listen(state.port, [
      :binary,
      packet: :raw,
      active: false,
      reuseaddr: true,
      keepalive: true
    ]) do
      {:ok, listen_socket} ->
        Logger.info("LSP Server listening on port #{state.port}")
        # Start accepting connections
        spawn_link(fn -> accept_loop(listen_socket) end)
        {:noreply, %{state | listen_socket: listen_socket}}

      {:error, reason} ->
        Logger.error("Failed to start LSP server: #{inspect(reason)}")
        {:stop, {:listen_failed, reason}, state}
    end
  end

  @impl true
  def handle_continue(:start_stdio_server, state) do
    Logger.info("LSP Server starting in stdio mode")
    # Start reading from stdin
    spawn_link(fn -> stdio_loop() end)
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      mode: state.mode,
      port: state.port,
      initialized: state.initialized,
      root_uri: state.root_uri,
      active_documents: map_size(state.documents),
      connected_clients: map_size(state.clients),
      version: "1.0.0"
    }
    {:reply, info, state}
  end

  @impl true
  def handle_call({:get_document, uri}, _from, state) do
    {:reply, Map.get(state.documents, uri), state}
  end

  @impl true
  def handle_info({:lsp_request, client_id, request}, state) do
    state = handle_lsp_request(client_id, request, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:client_connected, client_id, socket}, state) do
    Logger.info("LSP client connected: #{client_id}")
    PhoenixIntegration.report_metrics(:connection, %{client_count: map_size(state.clients) + 1}, %{action: :connect})

    clients = Map.put(state.clients, client_id, %{
      socket: socket,
      buffer: "",
      initialized: false
    })

    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info({:client_disconnected, client_id}, state) do
    Logger.info("LSP client disconnected: #{client_id}")
    PhoenixIntegration.report_metrics(:connection, %{client_count: map_size(state.clients) - 1}, %{action: :disconnect})

    clients = Map.delete(state.clients, client_id)
    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("LSP Server terminating: #{inspect(reason)}")

    # Close all client connections
    Enum.each(state.clients, fn {_id, %{socket: socket}} ->
      :gen_tcp.close(socket)
    end)

    # Close listen socket
    if state.listen_socket do
      :gen_tcp.close(state.listen_socket)
    end

    :ok
  end

  # Private functions

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        client_id = generate_client_id()

        # Configure socket
        :inet.setopts(client_socket, [
          active: true,
          nodelay: true,
          keepalive: true
        ])

        # Notify server of new connection
        send(self(), {:client_connected, client_id, client_socket})

        # Start client handler
        spawn_link(fn -> client_loop(client_id, client_socket, "") end)

        # Continue accepting
        accept_loop(listen_socket)

      {:error, :closed} ->
        Logger.info("LSP server socket closed")
        :ok

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        Process.sleep(1000)
        accept_loop(listen_socket)
    end
  end

  defp client_loop(client_id, socket, buffer) do
    receive do
      {:tcp, ^socket, data} ->
        buffer = buffer <> data
        {messages, remaining_buffer} = extract_messages(buffer)

        Enum.each(messages, fn msg ->
          send(Lang.LSP.Server, {:lsp_request, client_id, msg})
        end)

        client_loop(client_id, socket, remaining_buffer)

      {:tcp_closed, ^socket} ->
        send(Lang.LSP.Server, {:client_disconnected, client_id})
        :ok

      {:tcp_error, ^socket, reason} ->
        Logger.error("TCP error for client #{client_id}: #{inspect(reason)}")
        send(Lang.LSP.Server, {:client_disconnected, client_id})
        :ok

        
      {:send_response, response} ->
        send_json_rpc(