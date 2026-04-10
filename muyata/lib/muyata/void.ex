defmodule Muyata.Void do
  @moduledoc """
  The void state — muyata's anti-partition.

  Where mulsp's Partition is born full (DNA that determines behavior),
  the Void is born empty and grows through observation. It tracks what
  muyata has learned: how many patterns seen, bytes observed, current
  epoch, and the target service configuration.

  The Void is the single source of truth for muyata's emergent state.
  """
  use GenServer

  defstruct [
    :node_id,
    # Target service (what we sit in front of)
    listen_port: 5432,
    upstream_host: "127.0.0.1",
    upstream_port: 5433,
    # Emergent state (grows from nothing)
    epoch: 0,
    patterns_seen: 0,
    bytes_observed: 0,
    connections_seen: 0,
    # Protocol surfaces
    gopher_port: 7170,
    finger_port: 7179,
    dc_port: 7171,
    gopher_enabled: true,
    finger_enabled: true,
    dc_enabled: true
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the current void state."
  def state, do: GenServer.call(__MODULE__, :state)

  @doc "Record observed bytes."
  def observe_bytes(count) when is_integer(count) do
    GenServer.cast(__MODULE__, {:observe_bytes, count})
  end

  @doc "Record a new distinct pattern."
  def new_pattern do
    GenServer.cast(__MODULE__, :new_pattern)
  end

  @doc "Record a new connection."
  def new_connection do
    GenServer.cast(__MODULE__, :new_connection)
  end

  @doc "Advance to the next epoch."
  def advance_epoch do
    GenServer.call(__MODULE__, :advance_epoch)
  end

  # --- Server ---

  @impl true
  def init(opts) do
    void = %__MODULE__{
      node_id: generate_node_id(),
      listen_port: Keyword.get(opts, :listen_port, 5432),
      upstream_host: Keyword.get(opts, :upstream_host, "127.0.0.1"),
      upstream_port: Keyword.get(opts, :upstream_port, 5433),
      gopher_port: Keyword.get(opts, :gopher_port, 7170),
      finger_port: Keyword.get(opts, :finger_port, 7179),
      dc_port: Keyword.get(opts, :dc_port, 7171)
    }

    {:ok, void}
  end

  @impl true
  def handle_call(:state, _from, void), do: {:reply, void, void}

  def handle_call(:advance_epoch, _from, void) do
    new_void = %{void | epoch: void.epoch + 1}
    {:reply, {:ok, new_void.epoch}, new_void}
  end

  @impl true
  def handle_cast({:observe_bytes, count}, void) do
    {:noreply, %{void | bytes_observed: void.bytes_observed + count}}
  end

  def handle_cast(:new_pattern, void) do
    {:noreply, %{void | patterns_seen: void.patterns_seen + 1}}
  end

  def handle_cast(:new_connection, void) do
    {:noreply, %{void | connections_seen: void.connections_seen + 1}}
  end

  defp generate_node_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
    |> then(&"muyata-#{&1}")
  rescue
    _ -> "muyata-#{System.system_time(:millisecond)}"
  end
end
