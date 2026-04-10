defmodule Lang.Mulsp.Registry do
  @moduledoc """
  Registry of live mulsp/muyata instances owned by this Lang node.

  Backed by a DynamicSupervisor for crash-resilient instance management
  and an ETS table for fast partition lookups.

  Each entry tracks:
  - node_id → the mulsp's unique ID
  - pid → the supervised process (BEAM mode)
  - role → what context this instance was built for
  - partition → the full partition config
  - kind → :mulsp | :muyata
  - mode → :beam | :atomvm (for packbeam deployments, pid is nil)
  - target → {host, port} for :atomvm deployments
  """
  use GenServer

  require Logger

  @table :lang_mulsp_registry

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register a newly spawned mulsp/muyata instance."
  def register(node_id, entry) do
    GenServer.call(__MODULE__, {:register, node_id, entry})
  end

  @doc "Look up a running instance by node_id."
  def lookup(node_id) do
    case :ets.lookup(@table, node_id) do
      [{^node_id, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  @doc "List all registered instances, optionally filtered by role or kind."
  def list(filter \\ []) do
    :ets.tab2list(@table)
    |> Enum.map(fn {_id, entry} -> entry end)
    |> apply_filter(filter)
  end

  @doc "Deregister an instance (called on shutdown or crash)."
  def deregister(node_id) do
    GenServer.call(__MODULE__, {:deregister, node_id})
  end

  @doc "Push a new partition config to a live BEAM instance."
  def update_partition(node_id, partition) do
    case lookup(node_id) do
      {:ok, %{mode: :beam, control_port: port}} when not is_nil(port) ->
        push_partition(port, partition)

      {:ok, %{mode: :atomvm}} ->
        {:error, :atomvm_runtime_update_not_supported}

      {:error, _} = err ->
        err
    end
  end

  # --- Server ---

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, node_id, entry}, _from, state) do
    :ets.insert(@table, {node_id, entry})
    Logger.info("[Lang.Mulsp.Registry] registered #{entry.kind} #{node_id} role=#{entry.role} mode=#{entry.mode}")
    {:reply, :ok, state}
  end

  def handle_call({:deregister, node_id}, _from, state) do
    :ets.delete(@table, node_id)
    Logger.info("[Lang.Mulsp.Registry] deregistered #{node_id}")
    {:reply, :ok, state}
  end

  defp apply_filter(entries, []), do: entries

  defp apply_filter(entries, filter) do
    Enum.filter(entries, fn entry ->
      Enum.all?(filter, fn
        {:role, role} -> entry.role == role
        {:kind, kind} -> entry.kind == kind
        {:mode, mode} -> entry.mode == mode
        _ -> true
      end)
    end)
  end

  defp push_partition(control_port, partition) do
    case :gen_tcp.connect(~c"127.0.0.1", control_port, [:binary, {:active, false}, {:packet, :raw}], 3_000) do
      {:ok, socket} ->
        msg = :erlang.term_to_binary({:update_partition, partition})
        :gen_tcp.send(socket, <<byte_size(msg)::32, msg::binary>>)

        result =
          case :gen_tcp.recv(socket, 5, 5_000) do
            {:ok, <<"ok", _::binary>>} -> :ok
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end

        :gen_tcp.close(socket)
        result

      {:error, reason} ->
        {:error, {:connect_failed, reason}}
    end
  end
end
