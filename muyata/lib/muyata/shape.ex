defmodule Muyata.Shape do
  @moduledoc """
  Sealed protocol shape — composable, transferable, mergeable.

  Once muyata has sufficient coverage of a protocol, knowledge is
  sealed into a Shape: framing hypothesis + message catalog + heatmap
  snapshot + tree hash, packaged as a single transferable unit.

  Shapes are the composable endpoints:
  - merge(a, b) — combine learnings from two instances
  - diff(a, b) — what does one know that the other doesn't?
  - wrap(shape) — graduate from void-observer to typed proxy

  The lifecycle: void → observation → heatmap → shape → composable proxy
  """

  defstruct [
    :name,
    :framing,
    :tree_hash,
    :epoch,
    :sealed_at,
    message_types: %{},
    heatmap_digest: nil,
    coverage: 0.0,
    node_id: nil
  ]

  @doc "Seal current muyata state into a Shape."
  def seal(name \\ nil) do
    void = Muyata.Void.state()
    framing_status = Muyata.Observer.Framing.status()
    patterns = Muyata.Observer.Census.patterns()
    tree_stats = Muyata.Substrate.Tree.stats()
    coverage = Muyata.Observer.Heatmap.coverage()

    message_types =
      Map.new(patterns, fn p ->
        {p.tag, %{count: p.count, avg_len: p.avg_len, directions: p.directions}}
      end)

    %__MODULE__{
      name: name || "shape-#{void.epoch}",
      framing: framing_status.dominant,
      message_types: message_types,
      tree_hash: tree_stats.root_hash,
      epoch: void.epoch,
      coverage: coverage,
      sealed_at: System.system_time(:second),
      node_id: void.node_id
    }
  end

  @doc "Merge two shapes — combine learnings."
  def merge(%__MODULE__{} = a, %__MODULE__{} = b) do
    merged_types =
      Map.merge(a.message_types, b.message_types, fn _key, va, vb ->
        %{
          count: va.count + vb.count,
          avg_len: div(va.avg_len + vb.avg_len, 2),
          directions: merge_directions(va.directions, vb.directions)
        }
      end)

    %__MODULE__{
      name: "merged-#{a.name}-#{b.name}",
      framing: a.framing || b.framing,
      message_types: merged_types,
      tree_hash: nil,
      epoch: max(a.epoch, b.epoch),
      coverage: max(a.coverage, b.coverage),
      sealed_at: System.system_time(:second)
    }
  end

  @doc "Diff two shapes — what does b know that a doesn't?"
  def diff(%__MODULE__{} = a, %__MODULE__{} = b) do
    a_tags = Map.keys(a.message_types) |> MapSet.new()
    b_tags = Map.keys(b.message_types) |> MapSet.new()

    %{
      only_in_a: MapSet.difference(a_tags, b_tags) |> MapSet.to_list(),
      only_in_b: MapSet.difference(b_tags, a_tags) |> MapSet.to_list(),
      shared: MapSet.intersection(a_tags, b_tags) |> MapSet.size(),
      coverage_delta: Float.round(b.coverage - a.coverage, 6)
    }
  end

  @doc "Serialize to ETF for DC transfer."
  def to_etf(%__MODULE__{} = shape) do
    :erlang.term_to_binary(Map.from_struct(shape))
  end

  @doc "Deserialize from ETF."
  def from_etf(binary) when is_binary(binary) do
    data = :erlang.binary_to_term(binary)
    struct(__MODULE__, data)
  end

  defp merge_directions(a, b) do
    Map.merge(a, b, fn _k, va, vb -> va + vb end)
  end
end
