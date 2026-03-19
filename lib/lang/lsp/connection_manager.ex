defmodule Lang.LSP.ConnectionManager do
  @modledoc """
  Manages incoming LSP connections, enforcing a concurrency limit.

  This GenServer accepts new sockets from the main TCP server process,
  starts a ConnectionWorker under the ConnectionSupervisor for each,
  and monitors the workers to maintain a count of active connections.
  If the connection limit is reached, it will gracefully close new sockets
  until a spot becomes available.
  """
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def accept_socket(socket) do
    GenServer.cast(__MODULE__, {:accept_socket, socket})
  end

  @impl true
  def init(_opts) do
    max_connections = Application.get_env(:lang, :lsp_server, [])
                      |> Keyword.get(:max_connections, 100)

    Logger.info("LSP ConnectionManager started with a limit of #{max_connections} concurrent connections.")
    {:ok, %{connections: %{}, max_connections: max_connections}}
  end

  @impl true
  def handle_cast({:accept_socket, socket}, state) do
    if map_size(state.connections) >= state.max_connections do
      Logger.warn("Max connections reached (#{state.max_connections}). Rejecting new connection.")
      :gen_tcp.close(socket)
      {:noreply, state}
    else
      case Lang.LSP.ConnectionSupervisor.start_worker(socket) do
        {:ok, pid} ->
          ref = Process.monitor(pid)
          new_connections = Map.put(state.connections, ref, pid)
          {:noreply, %{state | connections: new_connections}}
        {:error, reason} ->
          Logger.error("Failed to start ConnectionWorker: #{inspect(reason)}")
          :gen_tcp.close(socket)
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    Logger.info("ConnectionWorker terminated. Reason: #{inspect(reason)}")
    new_connections = Map.delete(state.connections, ref)
    {:noreply, %{state | connections: new_connections}}
  end
end
