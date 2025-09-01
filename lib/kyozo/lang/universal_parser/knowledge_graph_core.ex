defmodule Kyozo.Lang.UniversalParser.KnowledgeGraph do
  @moduledoc """
  Minimal knowledge graph builder used by LinkedDataExtractor and LSP graph ops.

  Builds a simple in-memory graph with nodes and edges from extracted linked data
  (entities and relationships). Also provides a lightweight analyzer.
  """

  require Logger

  @type entity :: %{optional(String.t()) => any()} | %{optional(atom()) => any()}
  @type relationship :: %{optional(String.t()) => any()} | %{optional(atom()) => any()}
  @type kg_node :: %{id: String.t(), label: String.t(), type: String.t() | nil, properties: map()}
  @type kg_edge :: %{from: String.t(), to: String.t(), predicate: String.t() | nil, confidence: float() | nil}
  @type t :: %{nodes: [kg_node()], edges: [kg_edge()], updated_at: DateTime.t(), stats: map()}

  @spec build_from_linked_data([%{entities: [entity()], relationships: [relationship()]}], keyword()) ::
          {:ok, t()} | {:error, term()}
  def build_from_linked_data(linked_data_list, _opts \\ []) when is_list(linked_data_list) do
    entities = Enum.flat_map(linked_data_list, &normalize_entities/1)
    rels = Enum.flat_map(linked_data_list, &normalize_relationships/1)
    build_graph(entities, rels)
  end

  @spec build_graph([entity()], [relationship()]) :: {:ok, t()} | {:error, term()}
  def build_graph(entities, relationships) when is_list(entities) and is_list(relationships) do
    {nodes_map, id_map} =
      Enum.reduce(entities, {%{}, %{}}, fn e, {acc_nodes, id_map} ->
        {id, node, id_map} = entity_to_node(e, id_map)
        {Map.put(acc_nodes, id, node), id_map}
      end)

    {nodes_map, edges} =
      Enum.reduce(relationships, {nodes_map, []}, fn r, {nmap, edges} ->
        {from_id, to_id, pred, conf, nmap} = relationship_to_edge(r, nmap)
        {nmap, [%{from: from_id, to: to_id, predicate: pred, confidence: conf} | edges]}
      end)

    nodes = nmap_to_sorted(nodes_map)
    graph = %{nodes: nodes, edges: Enum.reverse(edges), updated_at: DateTime.utc_now()}
    {:ok, Map.put(graph, :stats, analyze_graph(graph))}
  end

  @spec analyze_graph(%{nodes: [kg_node()], edges: [kg_edge()]}) :: map()
  def analyze_graph(%{nodes: nodes, edges: edges}) do
    degs =
      edges
      |> Enum.reduce(%{}, fn %{from: f, to: t}, acc ->
        acc
        |> Map.update(f, %{out: 1, in: 0}, fn m -> %{m | out: m.out + 1} end)
        |> Map.update(t, %{out: 0, in: 1}, fn m -> %{m | in: m.in + 1} end)
      end)

    %{
      node_count: length(nodes),
      edge_count: length(edges),
      avg_out_degree: avg_degree(degs, :out),
      avg_in_degree: avg_degree(degs, :in)
    }
  end

  # Internals
  defp normalize_entities(%{entities: list}) when is_list(list), do: list
  defp normalize_entities(%{"entities" => list}) when is_list(list), do: list
  defp normalize_entities(_), do: []

  defp normalize_relationships(%{relationships: list}) when is_list(list), do: list
  defp normalize_relationships(%{"relationships" => list}) when is_list(list), do: list
  defp normalize_relationships(_), do: []

  defp entity_to_node(entity, id_map) do
    id = map_get(entity, ["id", :id]) || gensym("ent")
    type = map_get(entity, ["type", :type])
    props = map_get(entity, ["properties", :properties]) || %{}
    label = map_get(props, ["name", :name]) || to_string(type || id)
    node = %{id: id, label: label, type: type, properties: props}
    {id, node, Map.put_new(id_map, id, true)}
  end

  defp relationship_to_edge(rel, nodes_map) do
    subj = map_get(rel, ["subject", :subject]) || map_get(rel, ["from", :from]) || gensym("ent")
    obj = map_get(rel, ["object", :object]) || map_get(rel, ["to", :to]) || gensym("ent")
    pred = map_get(rel, ["predicate", :predicate])
    conf = map_get(rel, ["confidence", :confidence])

    # ensure placeholder nodes exist if referenced but missing
    nodes_map =
      nodes_map
      |> ensure_node(subj)
      |> ensure_node(obj)

    {subj, obj, pred, conf, nodes_map}
  end

  defp ensure_node(nodes_map, id) do
    if Map.has_key?(nodes_map, id) do
      nodes_map
    else
      Map.put(nodes_map, id, %{id: id, label: id, type: nil, properties: %{}})
    end
  end

  defp map_get(map, keys) when is_list(keys) do
    Enum.find_value(keys, fn k ->
      case map do
        %{^k => v} -> v
        _ -> nil
      end
    end)
  end

  defp gensym(prefix) do
    prefix <> "_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp nmap_to_sorted(nmap) do
    nmap
    |> Map.values()
    |> Enum.sort_by(& &1.id)
  end

  defp avg_degree(degs, key) do
    if map_size(degs) == 0 do
      0.0
    else
      total = Enum.reduce(degs, 0, fn {_id, m}, acc -> acc + Map.get(m, key, 0) end)
      total / map_size(degs)
    end
  end
end
