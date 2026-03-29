defmodule Mulsp.Bridge.Lang do
  @moduledoc """
  Bridge to the full Lang Elixir platform.

  When a mulsp receives a method in its lang_methods partition
  (e.g., lang.workspace.*, lang.graph.*, lang.cloud.*), it forwards
  via TCP to the full Lang platform.

  Uses gen_tcp to connect to Lang's LSP/RPC port. Messages are
  Erlang terms (ETF) when both sides are BEAM, or Content-Length
  framed text when bridging to Lang's HTTP/WebSocket interface.

  The Lang SaaS birthed this mulsp — it knows how to reach home.
  """
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{socket: nil, buffer: <<>>}}
  end

  @doc "Forward a request to the full Lang platform."
  def forward(request) do
    case GenServer.whereis(__MODULE__) do
      nil -> {:error, :bridge_unavailable, "Lang bridge not started"}
      _pid -> GenServer.call(__MODULE__, {:forward, request}, 30_000)
    end
  end

  @impl true
  def handle_call({:forward, request}, _from, state) do
    partition = get_partition()

    cond do
      is_nil(partition.lang_host) ->
        {:reply, {:error, :not_configured, "lang_host not set in partition"}, state}

      true ->
        result = do_forward(partition.lang_host, partition.lang_port || 4000, request)
        {:reply, result, state}
    end
  end

  defp do_forward(host, port, request) do
    host_charlist = to_charlist(host)

    case :gen_tcp.connect(host_charlist, port, [:binary, {:active, false}, {:packet, :raw}], 5_000) do
      {:ok, socket} ->
        # Send as ETF
        payload = :erlang.term_to_binary(request)
        :gen_tcp.send(socket, <<byte_size(payload)::32, payload::binary>>)

        # Wait for response
        result =
          case :gen_tcp.recv(socket, 0, 10_000) do
            {:ok, <<length::32, data::binary-size(length), _rest::binary>>} ->
              {:ok, :erlang.binary_to_term(data)}

            {:ok, data} ->
              {:ok, data}

            {:error, reason} ->
              {:error, :recv_failed, inspect(reason)}
          end

        :gen_tcp.close(socket)
        result

      {:error, reason} ->
        {:error, :connect_failed, "cannot reach Lang at #{host}:#{port}: #{inspect(reason)}"}
    end
  end

  defp get_partition do
    case GenServer.whereis(Mulsp.Dispatch) do
      nil -> Mulsp.Partition.load()
      _pid -> Mulsp.Dispatch |> :sys.get_state() |> Map.get(:partition)
    end
  end
end
