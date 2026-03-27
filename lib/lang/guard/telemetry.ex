defmodule Lang.Guard.Telemetry do
  @moduledoc """
  Structured threat event emission for the Guard system.

  Emits events in a format compatible with the Guard Mesh
  telemetry pipeline for cross-node threat intelligence aggregation.
  """

  use GenServer
  require Logger

  @flush_interval :timer.seconds(30)
  @max_buffer_size 100

  defstruct [:buffer, :stats]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Emit a guard event."
  @spec emit(String.t(), map()) :: :ok
  def emit(event_type, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:emit, event_type, metadata})
  end

  @doc "Emit a threat detection event."
  @spec threat_detected(map()) :: :ok
  def threat_detected(scan_result) do
    emit("guard.threat_detected", %{
      risk_score: scan_result[:risk_score],
      flags: scan_result[:flags],
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc "Emit a shield application event."
  @spec shield_applied(String.t(), String.t()) :: :ok
  def shield_applied(agent_type, version) do
    emit("guard.shield_applied", %{
      agent_type: agent_type,
      version: version,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc "Emit a wash event."
  @spec content_washed(non_neg_integer(), [String.t()]) :: :ok
  def content_washed(annotations_count, flags) do
    emit("guard.content_washed", %{
      annotations: annotations_count,
      flags: flags,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc "Get buffered events (for testing/debugging)."
  def get_buffer, do: GenServer.call(__MODULE__, :get_buffer)

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Logger.info("Guard Telemetry started")
    Process.send_after(self(), :flush, @flush_interval)

    {:ok, %__MODULE__{
      buffer: [],
      stats: %{events_emitted: 0, flushes: 0}
    }}
  end

  @impl true
  def handle_cast({:emit, event_type, metadata}, state) do
    event = %{
      event_id: "grd-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}",
      event_type: event_type,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      metadata: metadata
    }

    buffer = [event | state.buffer]

    # Auto-flush if buffer is full
    if length(buffer) >= @max_buffer_size do
      flush_buffer(buffer)
      stats = %{state.stats | events_emitted: state.stats.events_emitted + length(buffer), flushes: state.stats.flushes + 1}
      {:noreply, %{state | buffer: [], stats: stats}}
    else
      {:noreply, %{state | buffer: buffer}}
    end
  end

  @impl true
  def handle_call(:get_buffer, _from, state) do
    {:reply, Enum.reverse(state.buffer), state}
  end

  @impl true
  def handle_info(:flush, state) do
    if length(state.buffer) > 0 do
      flush_buffer(state.buffer)
    end

    Process.send_after(self(), :flush, @flush_interval)

    stats = %{state.stats |
      events_emitted: state.stats.events_emitted + length(state.buffer),
      flushes: state.stats.flushes + 1
    }

    {:noreply, %{state | buffer: [], stats: stats}}
  end

  defp flush_buffer(events) do
    count = length(events)

    # TODO: send to Guard Mesh telemetry endpoint
    # For now, log locally
    Logger.debug("Guard Telemetry: flushed #{count} events")

    # Also forward to Lang.Events if available
    try do
      Enum.each(events, fn event ->
        Lang.Events.track_event(event)
      end)
    rescue
      _ -> :ok
    end
  end
end
