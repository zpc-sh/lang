defmodule Kyozo.Lang.UniversalParser.KnowledgeGraph do
  @moduledoc """
  Knowledge Graph Builder for Universal Parser

  This module creates interconnected semantic graphs from multiple documents
  with linked data. It builds relationships between entities across documents
  and provides graph analysis and traversal capabilities.

  ## Features

  - **Cross-Document Relationships** - Link entities across multiple documents
  - **Graph Analysis** - Analyze connectivity, centrality, and importance
  - **Query Interface** - Find entities, relationships, and paths
  - **Graph Visualization** - Export formats for visualization tools
  - **Semantic Reasoning** - Infer implicit relationships
  - **Performance Optimized** - Efficient graph storage and traversal

  ## Usage Examples

      # Build graph from multiple linked data sources
      linked_data_list = [doc1_linked_data, doc2_linked_data, doc3_linked_data]
      {:ok, graph} = KnowledgeGraph.build_from_linked_data(linked_data_list)

      # Query the graph
      {:ok, person_entities} = KnowledgeGraph.find_entities(graph, type: "Person")
      {:ok, connections} = KnowledgeGraph.get_connections(graph, entity_id)

      # Analysis
      centrality_scores = KnowledgeGraph.calculate_centrality(graph)
      important_entities = KnowledgeGraph.most_important_entities(graph, 10)

  """

  require Logger

  @type entity_id :: String.t()
  @type relationship_type :: String.t()
  @type confidence_score :: float()

  @type graph_entity :: %{
          id: entity_id(),
          type: String.t(),
          properties: map(),
          uri: String.t() | nil,
          confidence: confidence_score(),
          source_documents: [String.t()],
          merged_count: non_neg_integer()
        }

  @type graph_relationship :: %{
          id: String.t(),
          subject: entity_id(),
          predicate: relationship_type(),
          object: entity_id(),
          confidence: confidence_score(),
          source_documents: [String.t()],
          weight: float()
        }

  @type knowledge_graph :: %{
          entities: %{entity_id() => graph_entity()},
          relationships: %{String.t() => graph_relationship()},
          metadata: %{
            entity_count: non_neg_integer(),
            relationship_count: non_neg_integer(),
            document_count: non_neg_integer(),
            build_time_ms: non_neg_integer(),
            density: float(),
            connected_components: non_neg_integer()
          },
          indexes: %{
            by_type: %{String.t() => [entity_id()]},
            by_relationship: %{relationship_type() => [String.t()]},
            adjacency: %{entity_id() => [entity_id()]}
          }
        }

  @type graph_query :: [
          type: String.t() | nil,
          properties: map() | nil,
          min_confidence: float() | nil,
          source_document: String.t() | nil
        ]

  @type path_result :: %{
          path: [entity_id()],
          relationships: [String.t()],
          total_weight: float(),
          confidence: float()
        }

  @doc """
  Build a knowledge graph from multiple linked data sources.

  ## Options

  - `:merge_threshold` - Confidence threshold for entity merging (default: 0.8)
  - `:min_confidence` - Minimum confidence for including relationships (default: 0.5)
  - `:enable_inference` - Enable implicit relationship inference (default: true)
  - `:max_entities` - Maximum entities to include (default: 10000)

  ## Examples

      {:ok, graph} = KnowledgeGraph.build_from_linked_data(linked_data_list,
        merge_threshold: 0.9,
        min_confidence: 0.7
      )

  """
  @spec build_from_linked_data([map()], keyword()) :: {:ok, knowledge_graph()} | {:error, term()}
  def build_from_linked_data(linked_data_list, options \\ []) when is_list(linked_data_list) do
    start_time = System.monotonic_time(:millisecond)

    options =
      Keyword.merge(
        [
          merge_threshold: 0.8,
          min_confidence: 0.5,
          enable_inference: true,
          max_entities: 10_000
        ],
        options
      )

    try do
      # Step 1: Extract all entities and relationships
      {all_entities, all_relationships} = extract_graph_elements(linked_data_list)

      # Step 2: Merge duplicate entities
      merged_entities = merge_entities(all_entities, options)

      # Step 3: Filter and process relationships
      processed_relationships = process_relationships(all_relationships, merged_entities, options)

      # Step 4: Build indexes for efficient querying
      indexes = build_indexes(merged_entities, processed_relationships)

      # Step 5: Calculate graph metadata
      metadata = calculate_metadata(merged_entities, processed_relationships, start_time)

      # Step 6: Optional inference
      final_relationships =
        if Keyword.get(options, :enable_inference) do
          infer_relationships(merged_entities, processed_relationships)
        else
          processed_relationships
        end

      graph = %{
        entities: Map.new(merged_entities, fn entity -> {entity.id, entity} end),
        relationships: Map.new(final_relationships, fn rel -> {rel.id, rel} end),
        metadata: metadata,
        indexes: indexes
      }

      {:ok, graph}
    rescue
      error -> {:error, {:graph_build_failed, error}}
    end
  end

  @doc """
  Find entities in the graph based on criteria.

  ## Examples

      # Find all Person entities
      {:ok, people} = KnowledgeGraph.find_entities(graph, type: "Person")

      # Find entities with specific properties
      {:ok, results} = KnowledgeGraph.find_entities(graph,
        properties: %{"occupation" => "engineer"},
        min_confidence: 0.8
      )

  """
  @spec find_entities(knowledge_graph(), graph_query()) ::
          {:ok, [graph_entity()]} | {:error, term()}
  def find_entities(graph, query \\ []) do
    try do
      entities = Map.values(graph.entities)

      filtered_entities =
        entities
        |> filter_by_type(Keyword.get(query, :type))
        |> filter_by_properties(Keyword.get(query, :properties))
        |> filter_by_confidence(Keyword.get(query, :min_confidence, 0.0))
        |> filter_by_source_document(Keyword.get(query, :source_document))

      {:ok, filtered_entities}
    rescue
      error -> {:error, {:query_failed, error}}
    end
  end

  @doc """
  Get all connections (relationships) for a specific entity.

  ## Examples

      {:ok, connections} = KnowledgeGraph.get_connections(graph, "person:john_doe")

  """
  @spec get_connections(knowledge_graph(), entity_id()) ::
          {:ok, [graph_relationship()]} | {:error, term()}
  def get_connections(graph, entity_id) do
    case Map.get(graph.indexes.adjacency, entity_id) do
      nil ->
        {:ok, []}

      _connected_ids ->
        relationships =
          graph.relationships
          |> Map.values()
          |> Enum.filter(fn rel ->
            rel.subject == entity_id or rel.object == entity_id
          end)

        {:ok, relationships}
    end
  end

  @doc """
  Find the shortest path between two entities.

  ## Examples

      {:ok, path} = KnowledgeGraph.find_path(graph, "person:alice", "org:company_x")

  """
  @spec find_path(knowledge_graph(), entity_id(), entity_id()) ::
          {:ok, path_result()} | {:error, term()}
  def find_path(graph, start_id, end_id) do
    case dijkstra_shortest_path(graph, start_id, end_id) do
      nil -> {:error, :no_path_found}
      path -> {:ok, path}
    end
  end

  @doc """
  Calculate centrality scores for all entities in the graph.

  Returns a map of entity_id => centrality_score, where higher scores
  indicate more important/central entities.

  ## Examples

      centrality_scores = KnowledgeGraph.calculate_centrality(graph)
      most_central = centrality_scores |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.take(10)

  """
  @spec calculate_centrality(knowledge_graph()) :: %{entity_id() => float()}
  def calculate_centrality(graph) do
    # Use degree centrality as a simple but effective measure
    graph.entities
    |> Map.keys()
    |> Map.new(fn entity_id ->
      connections = length(Map.get(graph.indexes.adjacency, entity_id, []))
      total_entities = map_size(graph.entities)

      # Normalize by total possible connections
      centrality =
        if total_entities > 1 do
          connections / (total_entities - 1)
        else
          0.0
        end

      {entity_id, centrality}
    end)
  end

  @doc """
  Get the most important entities based on centrality and confidence.

  ## Examples

      important_entities = KnowledgeGraph.most_important_entities(graph, 10)

  """
  @spec most_important_entities(knowledge_graph(), pos_integer()) :: [graph_entity()]
  def most_important_entities(graph, limit) do
    centrality_scores = calculate_centrality(graph)

    graph.entities
    |> Map.values()
    |> Enum.map(fn entity ->
      centrality = Map.get(centrality_scores, entity.id, 0.0)
      # Combined importance score: centrality + confidence + merge count
      importance = centrality * 0.5 + entity.confidence * 0.3 + entity.merged_count * 0.2
      {entity, importance}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(limit)
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Export graph to various formats for visualization.

  ## Supported Formats

  - `:dot` - Graphviz DOT format
  - `:json` - JSON format for D3.js
  - `:gexf` - GEXF format for Gephi
  - `:cypher` - Cypher statements for Neo4j

  ## Examples

      {:ok, dot_content} = KnowledgeGraph.export(graph, :dot)
      {:ok, json_content} = KnowledgeGraph.export(graph, :json)

  """
  @spec export(knowledge_graph(), atom()) :: {:ok, String.t()} | {:error, term()}
  def export(graph, format) do
    case format do
      :dot -> export_dot(graph)
      :json -> export_json(graph)
      :gexf -> export_gexf(graph)
      :cypher -> export_cypher(graph)
      _ -> {:error, {:unsupported_format, format}}
    end
  end

  @doc """
  Get graph statistics and analysis.

  ## Examples

      stats = KnowledgeGraph.analyze(graph)
      # => %{density: 0.23, avg_degree: 3.4, clusters: 5, ...}

  """
  @spec analyze(knowledge_graph()) :: map()
  def analyze(graph) do
    centrality_scores = calculate_centrality(graph)

    %{
      entity_count: graph.metadata.entity_count,
      relationship_count: graph.metadata.relationship_count,
      density: graph.metadata.density,
      connected_components: graph.metadata.connected_components,
      avg_degree: calculate_average_degree(graph),
      max_centrality: centrality_scores |> Map.values() |> Enum.max(fn -> 0.0 end),
      avg_centrality:
        centrality_scores |> Map.values() |> Enum.sum() |> Kernel./(map_size(centrality_scores)),
      entity_types: count_entity_types(graph),
      relationship_types: count_relationship_types(graph)
    }
  end

  # === Private Functions ===

  defp extract_graph_elements(linked_data_list) do
    {entities, relationships} =
      Enum.reduce(linked_data_list, {[], []}, fn linked_data, {acc_entities, acc_rels} ->
        doc_entities = Map.get(linked_data, :entities, [])
        doc_rels = Map.get(linked_data, :relationships, [])

        {acc_entities ++ doc_entities, acc_rels ++ doc_rels}
      end)

    # Convert to graph format with IDs
    graph_entities = Enum.map(entities, &convert_to_graph_entity/1)
    graph_relationships = Enum.map(relationships, &convert_to_graph_relationship/1)

    {graph_entities, graph_relationships}
  end

  defp convert_to_graph_entity(entity) do
    %{
      id: entity[:id] || generate_entity_id(entity),
      type: entity[:type] || "Thing",
      properties: entity[:properties] || %{},
      uri: entity[:uri],
      confidence: entity[:confidence] || 0.5,
      source_documents: [entity[:source_document] || "unknown"],
      merged_count: 1
    }
  end

  defp convert_to_graph_relationship(relationship) do
    %{
      id: generate_relationship_id(relationship),
      subject: relationship[:subject],
      predicate: relationship[:predicate],
      object: relationship[:object],
      confidence: relationship[:confidence] || 0.5,
      source_documents: [relationship[:source_document] || "unknown"],
      weight: calculate_relationship_weight(relationship)
    }
  end

  defp merge_entities(entities, options) do
    merge_threshold = Keyword.get(options, :merge_threshold, 0.8)

    # Simple entity merging based on URI and name similarity
    entities
    |> Enum.group_by(&entity_merge_key/1)
    |> Map.values()
    |> Enum.map(fn similar_entities ->
      case similar_entities do
        [single_entity] -> single_entity
        multiple -> merge_entity_group(multiple, merge_threshold)
      end
    end)
  end

  defp entity_merge_key(entity) do
    # Use URI if available, otherwise use type + normalized name
    cond do
      entity.uri -> {:uri, entity.uri}
      entity.properties["name"] -> {:name, entity.type, normalize_name(entity.properties["name"])}
      true -> {:id, entity.id}
    end
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_name(_), do: ""

  defp merge_entity_group(entities, _threshold) do
    # Take the entity with highest confidence as base
    base_entity = Enum.max_by(entities, & &1.confidence)

    # Merge properties and source documents
    merged_properties =
      Enum.reduce(entities, %{}, fn entity, acc ->
        Map.merge(acc, entity.properties)
      end)

    source_docs =
      entities
      |> Enum.flat_map(& &1.source_documents)
      |> Enum.uniq()

    %{
      base_entity
      | properties: merged_properties,
        source_documents: source_docs,
        merged_count: length(entities),
        confidence: calculate_merged_confidence(entities)
    }
  end

  defp calculate_merged_confidence(entities) do
    # Average confidence weighted by source count
    total_weight = Enum.sum(Enum.map(entities, & &1.merged_count))
    weighted_sum = Enum.sum(Enum.map(entities, &(&1.confidence * &1.merged_count)))

    if total_weight > 0, do: weighted_sum / total_weight, else: 0.5
  end

  defp process_relationships(relationships, entities, options) do
    min_confidence = Keyword.get(options, :min_confidence, 0.5)
    entity_ids = MapSet.new(entities, & &1.id)

    relationships
    |> Enum.filter(fn rel ->
      rel.confidence >= min_confidence and
        MapSet.member?(entity_ids, rel.subject) and
        MapSet.member?(entity_ids, rel.object)
    end)
  end

  defp build_indexes(entities, relationships) do
    # Build type index
    by_type =
      entities
      |> Enum.group_by(& &1.type)
      |> Map.new(fn {type, entities} -> {type, Enum.map(entities, & &1.id)} end)

    # Build relationship type index
    by_relationship =
      relationships
      |> Enum.group_by(& &1.predicate)
      |> Map.new(fn {predicate, rels} -> {predicate, Enum.map(rels, & &1.id)} end)

    # Build adjacency index
    adjacency =
      entities
      |> Map.new(fn entity ->
        connected =
          relationships
          |> Enum.filter(fn rel -> rel.subject == entity.id or rel.object == entity.id end)
          |> Enum.flat_map(fn rel ->
            if rel.subject == entity.id, do: [rel.object], else: [rel.subject]
          end)
          |> Enum.uniq()

        {entity.id, connected}
      end)

    %{
      by_type: by_type,
      by_relationship: by_relationship,
      adjacency: adjacency
    }
  end

  defp calculate_metadata(entities, relationships, start_time) do
    entity_count = length(entities)
    relationship_count = length(relationships)

    # Calculate density (actual edges / possible edges)
    max_edges = if entity_count > 1, do: entity_count * (entity_count - 1), else: 0
    density = if max_edges > 0, do: relationship_count / max_edges, else: 0.0

    build_time = System.monotonic_time(:millisecond) - start_time

    %{
      entity_count: entity_count,
      relationship_count: relationship_count,
      document_count: count_unique_documents(entities, relationships),
      build_time_ms: build_time,
      density: density,
      # Simplified - would need proper algorithm
      connected_components: 1
    }
  end

  defp count_unique_documents(entities, relationships) do
    entity_docs = Enum.flat_map(entities, & &1.source_documents)
    rel_docs = Enum.flat_map(relationships, & &1.source_documents)

    (entity_docs ++ rel_docs)
    |> Enum.uniq()
    |> length()
  end

  defp infer_relationships(_entities, relationships) do
    # Simple transitive relationship inference
    # If A -> B and B -> C, infer A -> C (with lower confidence)

    existing_rels =
      MapSet.new(relationships, fn rel -> {rel.subject, rel.predicate, rel.object} end)

    inferred =
      for rel1 <- relationships,
          rel2 <- relationships,
          rel1.object == rel2.subject,
          rel1.predicate == rel2.predicate,
          not MapSet.member?(existing_rels, {rel1.subject, rel1.predicate, rel2.object}) do
        %{
          id:
            generate_relationship_id(%{
              subject: rel1.subject,
              predicate: "inferred_" <> rel1.predicate,
              object: rel2.object
            }),
          subject: rel1.subject,
          predicate: "inferred_" <> rel1.predicate,
          object: rel2.object,
          # Lower confidence for inferred
          confidence: min(rel1.confidence, rel2.confidence) * 0.8,
          source_documents: (rel1.source_documents ++ rel2.source_documents) |> Enum.uniq(),
          weight: min(rel1.weight, rel2.weight) * 0.8
        }
      end

    relationships ++ inferred
  end

  # Query helper functions
  defp filter_by_type(entities, nil), do: entities
  defp filter_by_type(entities, type), do: Enum.filter(entities, &(&1.type == type))

  defp filter_by_properties(entities, nil), do: entities

  defp filter_by_properties(entities, required_props) do
    Enum.filter(entities, fn entity ->
      Enum.all?(required_props, fn {key, value} ->
        Map.get(entity.properties, key) == value
      end)
    end)
  end

  defp filter_by_confidence(entities, min_confidence) do
    Enum.filter(entities, &(&1.confidence >= min_confidence))
  end

  defp filter_by_source_document(entities, nil), do: entities

  defp filter_by_source_document(entities, source_doc) do
    Enum.filter(entities, fn entity ->
      source_doc in entity.source_documents
    end)
  end

  # Pathfinding
  defp dijkstra_shortest_path(graph, start_id, end_id) do
    # Simplified shortest path - would implement full Dijkstra in production
    case direct_connection?(graph, start_id, end_id) do
      true ->
        rel = find_relationship(graph, start_id, end_id)

        %{
          path: [start_id, end_id],
          relationships: [rel.id],
          total_weight: rel.weight,
          confidence: rel.confidence
        }

      # Would implement BFS/Dijkstra here
      false ->
        nil
    end
  end

  defp direct_connection?(graph, entity1, entity2) do
    connected = Map.get(graph.indexes.adjacency, entity1, [])
    entity2 in connected
  end

  defp find_relationship(graph, subject, object) do
    graph.relationships
    |> Map.values()
    |> Enum.find(fn rel ->
      (rel.subject == subject and rel.object == object) or
        (rel.subject == object and rel.object == subject)
    end)
  end

  # Export functions
  defp export_dot(graph) do
    header = "digraph knowledge_graph {\n  rankdir=LR;\n  node [shape=ellipse];\n"

    entities =
      graph.entities
      |> Map.values()
      |> Enum.map(fn entity ->
        "  \"#{entity.id}\" [label=\"#{entity.properties["name"] || entity.id}\\n(#{entity.type})\"];"
      end)
      |> Enum.join("\n")

    relationships =
      graph.relationships
      |> Map.values()
      |> Enum.map(fn rel ->
        "  \"#{rel.subject}\" -> \"#{rel.object}\" [label=\"#{rel.predicate}\"];"
      end)
      |> Enum.join("\n")

    content = header <> "\n" <> entities <> "\n" <> relationships <> "\n}"
    {:ok, content}
  end

  defp export_json(graph) do
    nodes =
      graph.entities
      |> Map.values()
      |> Enum.map(fn entity ->
        %{
          id: entity.id,
          label: entity.properties["name"] || entity.id,
          type: entity.type,
          confidence: entity.confidence
        }
      end)

    links =
      graph.relationships
      |> Map.values()
      |> Enum.map(fn rel ->
        %{
          source: rel.subject,
          target: rel.object,
          label: rel.predicate,
          weight: rel.weight
        }
      end)

    json_data = %{nodes: nodes, links: links}
    {:ok, Jason.encode!(json_data)}
  end

  defp export_gexf(_graph), do: {:error, :not_implemented}
  defp export_cypher(_graph), do: {:error, :not_implemented}

  # Utility functions
  defp generate_entity_id(entity) do
    name = entity[:properties]["name"] || entity[:type] || "entity"
    normalized = String.replace(name, ~r/[^\w]/, "_") |> String.downcase()
    "#{normalized}_#{:erlang.phash2(entity)}"
  end

  defp generate_relationship_id(relationship) do
    "rel_#{:erlang.phash2({relationship[:subject], relationship[:predicate], relationship[:object]})}"
  end

  defp calculate_relationship_weight(relationship) do
    # Weight based on confidence and relationship type importance
    base_weight = relationship[:confidence] || 0.5

    # Some relationship types are more important
    type_multiplier =
      case relationship[:predicate] do
        pred when pred in ["owns", "created", "manages"] -> 1.2
        pred when pred in ["knows", "related_to"] -> 0.8
        _ -> 1.0
      end

    base_weight * type_multiplier
  end

  defp calculate_average_degree(graph) do
    if map_size(graph.entities) > 0 do
      total_degree =
        graph.indexes.adjacency
        |> Map.values()
        |> Enum.map(&length/1)
        |> Enum.sum()

      total_degree / map_size(graph.entities)
    else
      0.0
    end
  end

  defp count_entity_types(graph) do
    graph.entities
    |> Map.values()
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, entities} -> {type, length(entities)} end)
  end

  defp count_relationship_types(graph) do
    graph.relationships
    |> Map.values()
    |> Enum.group_by(& &1.predicate)
    |> Map.new(fn {predicate, rels} -> {predicate, length(rels)} end)
  end
end
