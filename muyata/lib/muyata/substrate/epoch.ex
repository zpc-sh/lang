defmodule Muyata.Substrate.Epoch do
  @moduledoc """
  Epoch management — tracking the growth from void to knowledge.

  Each epoch is a snapshot of what muyata knew at a point in time.
  Sealing an epoch captures the current tree state, increments the
  counter, and computes what was learned since the last seal.

  The void grows but never shrinks within an epoch.
  """
  use GenServer

  defmodule Snapshot do
    @moduledoc false
    defstruct [
      :epoch,
      :tree_hash,
      :node_count,
      :pattern_count,
      :bloom_stats,
      :coverage,
      :sealed_at
    ]
  end

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Seal the current epoch."
  def seal do
    GenServer.call(__MODULE__, :seal)
  end

  @doc "Get diff between two epochs."
  def diff(epoch_a, epoch_b) do
    GenServer.call(__MODULE__, {:diff, epoch_a, epoch_b})
  end

  @doc "Get all sealed epochs."
  def epochs do
    GenServer.call(__MODULE__, :epochs)
  end

  @doc "Get growth rate (patterns per epoch)."
  def growth_rate do
    GenServer.call(__MODULE__, :growth_rate)
  end

  @impl true
  def init(_opts) do
    {:ok, %{snapshots: [], current_epoch: 0}}
  end

  @impl true
  def handle_call(:seal, _from, state) do
    # Gather current state from all subsystems
    void = Muyata.Void.state()
    tree_stats = Muyata.Substrate.Tree.stats()
    bloom_stats = Muyata.Substrate.Bloom.stats()
    coverage = Muyata.Observer.Heatmap.coverage()

    snapshot = %Snapshot{
      epoch: state.current_epoch,
      tree_hash: tree_stats.root_hash,
      node_count: tree_stats.node_count,
      pattern_count: void.patterns_seen,
      bloom_stats: bloom_stats,
      coverage: coverage,
      sealed_at: System.system_time(:second)
    }

    # Advance epoch in void
    Muyata.Void.advance_epoch()
    # Seal the tree
    Muyata.Substrate.Tree.seal()

    new_state = %{
      state
      | snapshots: state.snapshots ++ [snapshot],
        current_epoch: state.current_epoch + 1
    }

    {:reply, {:ok, snapshot}, new_state}
  end

  def handle_call({:diff, epoch_a, epoch_b}, _from, state) do
    a = Enum.find(state.snapshots, &(&1.epoch == epoch_a))
    b = Enum.find(state.snapshots, &(&1.epoch == epoch_b))

    result =
      case {a, b} do
        {nil, _} -> {:error, :epoch_not_found}
        {_, nil} -> {:error, :epoch_not_found}
        {a, b} -> {:ok, compute_diff(a, b)}
      end

    {:reply, result, state}
  end

  def handle_call(:epochs, _from, state) do
    summaries =
      Enum.map(state.snapshots, fn s ->
        %{
          epoch: s.epoch,
          nodes: s.node_count,
          patterns: s.pattern_count,
          coverage: s.coverage,
          sealed_at: s.sealed_at
        }
      end)

    {:reply, summaries, state}
  end

  def handle_call(:growth_rate, _from, state) do
    rate =
      case state.snapshots do
        [] -> 0.0
        [_] -> 0.0
        snapshots ->
          first = List.first(snapshots)
          last = List.last(snapshots)
          epochs = last.epoch - first.epoch

          if epochs > 0 do
            Float.round((last.pattern_count - first.pattern_count) / epochs, 2)
          else
            0.0
          end
      end

    {:reply, rate, state}
  end

  defp compute_diff(a, b) do
    %{
      from_epoch: a.epoch,
      to_epoch: b.epoch,
      nodes_added: b.node_count - a.node_count,
      patterns_added: b.pattern_count - a.pattern_count,
      coverage_delta: Float.round(b.coverage - a.coverage, 6),
      bloom_fill_delta:
        Float.round(b.bloom_stats.fill_ratio - a.bloom_stats.fill_ratio, 6)
    }
  end
end
