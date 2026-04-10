defmodule Muyata.DC.Peer do
  @moduledoc """
  DC protocol peer — share learnings with mulsp mesh.

  Connects to mulsp DC hubs or other muyata instances to:
  - Send bloom offers of observed patterns
  - Transfer sparse tree snapshots of learned protocol knowledge
  - Receive trees from peers (merge protocol knowledge)

  Uses the same wire format as Mulsp.DC.Protocol:
  1-byte tag + 4-byte length + ETF payload.
  """
  use GenServer

  require Logger

  # DC protocol message tags (compatible with mulsp)
  @bloom_offer 0x01
  @bloom_accept 0x03
  @bloom_reject 0x04
  @ping 0xF0
  @pong 0xF1
  @bye 0xFF

  def start_link(opts) do
    port = Keyword.get(opts, :port, 7171)
    GenServer.start_link(__MODULE__, %{port: port}, name: __MODULE__)
  end

  @doc "Connect to a mulsp DC hub or another muyata peer."
  def connect_peer(host, port) do
    GenServer.cast(__MODULE__, {:connect_peer, host, port})
  end

  @doc "Send our bloom sketch to connected peers."
  def offer_bloom do
    GenServer.cast(__MODULE__, :offer_bloom)
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
        Logger.info("[muyata:dc] listening on port #{port}")
        {:ok, %{listen_socket: listen_socket, port: port, connections: %{}}}

      {:error, reason} ->
        Logger.warning("[muyata:dc] failed to bind port #{port}: #{inspect(reason)}")
        {:ok, %{port: port, connections: %{}}}
    end
  end

  @impl true
  def handle_cast({:connect_peer, host, port}, state) do
    host_charlist = to_charlist(host)

    case :gen_tcp.connect(host_charlist, port, [:binary, {:active, false}], 5_000) do
      {:ok, socket} ->
        id = "peer-#{System.unique_integer([:positive])}"
        spawn(fn -> peer_loop(socket) end)
        Logger.info("[muyata:dc] connected to #{host}:#{port}")
        {:noreply, %{state | connections: Map.put(state.connections, id, socket)}}

      {:error, reason} ->
        Logger.warning("[muyata:dc] connect failed to #{host}:#{port}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast(:offer_bloom, state) do
    bloom_bits = Muyata.Substrate.Bloom.bits()
    bloom_stats = Muyata.Substrate.Bloom.stats()
    message = encode_message(@bloom_offer, %{sketch: bloom_bits, tokens: bloom_stats.items})

    for {_id, socket} <- state.connections do
      :gen_tcp.send(socket, message)
    end

    {:noreply, state}
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        spawn(fn -> peer_loop(client) end)
        accept_loop(listen_socket)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept_loop(listen_socket)
    end
  end

  defp peer_loop(socket) do
    case :gen_tcp.recv(socket, 0, 30_000) do
      {:ok, data} ->
        handle_dc_message(socket, data)
        peer_loop(socket)

      {:error, :timeout} ->
        :gen_tcp.send(socket, encode_message(@ping, %{}))
        peer_loop(socket)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end

  defp handle_dc_message(socket, <<tag::8, len::32, rest::binary>>) when byte_size(rest) >= len do
    <<payload::binary-size(len), _remaining::binary>> = rest
    decoded = :erlang.binary_to_term(payload)

    case tag do
      @ping -> :gen_tcp.send(socket, encode_message(@pong, %{}))
      @pong -> :ok
      @bloom_offer -> handle_bloom_offer(socket, decoded)
      @bloom_accept -> Logger.info("[muyata:dc] bloom accepted")
      @bloom_reject -> Logger.info("[muyata:dc] bloom rejected")
      @bye -> :gen_tcp.close(socket)
      _ -> :ok
    end
  end

  defp handle_dc_message(_socket, _data), do: :ok

  defp handle_bloom_offer(socket, _payload) do
    # Accept all bloom offers for now (like mulsp's stub)
    :gen_tcp.send(socket, encode_message(@bloom_accept, %{}))
  end

  defp encode_message(tag, payload) do
    body = :erlang.term_to_binary(payload)
    <<tag::8, byte_size(body)::32, body::binary>>
  end
end
