defmodule Kyozo.Lang.UniversalParser.KnowledgeGraphCoreTest do
  use ExUnit.Case, async: true

  alias Kyozo.Lang.UniversalParser.KnowledgeGraph, as: KG

  test "build_graph from entities and relationships" do
    entities = [
      %{id: "p1", type: "schema:Person", properties: %{name: "Ada"}},
      %{id: "o1", type: "schema:Organization", properties: %{name: "ACME"}}
    ]

    rels = [
      %{subject: "o1", predicate: "schema:employs", object: "p1", confidence: 0.9}
    ]

    assert {:ok, %{nodes: nodes, edges: edges, stats: stats}} = KG.build_graph(entities, rels)
    assert length(nodes) == 2
    assert length(edges) == 1
    assert Map.has_key?(stats, :node_count)
    assert Map.has_key?(stats, :edge_count)
  end

  test "build_from_linked_data folds inputs" do
    ld = [%{entities: [%{id: "p1", type: "schema:Person", properties: %{name: "Ada"}}], relationships: []}]
    assert {:ok, %{nodes: [_], edges: []}} = KG.build_from_linked_data(ld)
  end
end

