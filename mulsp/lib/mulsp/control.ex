defmodule Mulsp.Control do
  @moduledoc """
  ETF-over-TCP control channel for receiving runtime config from Lang.

  Lang pushes partition updates via: <<size::32, etf_term::binary>>
  Supported commands:
  - {:update_partition, %Mulsp.Partition{}} — replace the live partition
  - {:get_state} — return current partition + stats

  Port is `partition.control_port` (default: lsp_port + 20).
  Only accepts connections from localhost by default.
  """
  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 7100)

    case :gen_tcp.listen(port, [:binary, {:active, false}, {:reuseaddr, true}, {:ip, {127, 0, 0, 1}}]) do
      {:ok, listen_sock} ->
        Logger.info("[mulsp:control] listening on port #{port}")
        send(self(), :accept)
        {:ok, %{listen_sock: listen_sock, port: port}}

      {:error, reason} ->
        Logger.warning("[mulsp:control] could not bind port #{port}: #{inspect(reason)}")
        {:ok, %{listen_sock: nil, port: port}}
    end
  end

  @impl true
  def handle_info(:accept, %{listen_sock: nil} = state), do: {:noreply, state}

  def handle_info(:accept, state) do
    case :gen_tcp.accept(state.listen_sock, 5_000) do
      {:ok, sock} ->
        spawn_link(fn -> handle_connection(sock) end)

      {:error, :timeout} ->
        :ok

      {:error, reason} ->
        Logger.warning("[mulsp:control] accept error: #{inspect(reason)}")
    end

    send(self(), :accept)
    {:noreply, state}
  end

  defp handle_connection(sock) do
    case :gen_tcp.recv(sock, 0, 10_000) do
      {:ok, <<length::32, payload::binary-size(length), _::binary>>} ->
        cmd = :erlang.binary_to_term(payload)
        response = handle_command(cmd)
        :gen_tcp.send(sock, response)
        :gen_tcp.close(sock)

      {:ok, data} ->
        cmd = :erlang.binary_to_term(data)
        response = handle_command(cmd)
        :gen_tcp.send(sock, response)
        :gen_tcp.close(sock)

      {:error, reason} ->
        Logger.warning("[mulsp:control] recv error: #{inspect(reason)}")
        :gen_tcp.close(sock)
    end
  end

  defp handle_command({:update_partition, partition}) do
    Mulsp.Dispatch.update_partition(partition)
    Logger.info("[mulsp:control] partition updated role=#{inspect(Map.get(partition, :role))}")
    "ok"
  end

  defp handle_command({:get_state}) do
    state = :sys.get_state(Mulsp.Dispatch)
    :erlang.term_to_binary({:ok, state})
  end

  defp handle_command(unknown) do
    Logger.warning("[mulsp:control] unknown command: #{inspect(unknown)}")
    "error:unknown_command"
  end
end
