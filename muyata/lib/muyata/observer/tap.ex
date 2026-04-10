defmodule Muyata.Observer.Tap do
  @moduledoc """
  The eye — passive byte stream tap.

  Receives raw byte copies from the Relay (async, never blocks traffic).
  Forwards to Framing for boundary detection and Census for classification.
  Updates Void state counters.

  The Tap is the entry point of the observation pipeline:
  Relay → Tap → Framing → Census → Substrate
  """
  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Observe bytes from the relay. Direction is :client or :server."
  def observe(direction, data) when direction in [:client, :server] do
    GenServer.cast(__MODULE__, {:observe, direction, data})
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:observe, direction, data}, state) do
    byte_count = byte_size(data)

    # Update void counters (fire and forget)
    Muyata.Void.observe_bytes(byte_count)

    # Feed to framing for boundary detection
    Muyata.Observer.Framing.ingest(direction, data)

    # Feed to heatmap for coverage tracking
    Muyata.Observer.Heatmap.observe(data)

    {:noreply, state}
  end
end
