defmodule Lang.GraphReasoner do
  @moduledoc """
  Advanced graph reasoning capabilities for analyzing both text and graph-structured data.

  This module provides sophisticated graph algorithms, knowledge graph extraction,
  dependency analysis, and multi-modal reasoning that bridges text analysis with
  graph structures.

  ## Features

  - **Graph Creation & Analysis**: Create and analyze directed/undirected graphs
  - **Centrality Algorithms**: PageRank, betweenness, closeness, eigenvector, degree, Katz
  - **Community Detection**: Louvain, Leiden, modularity optimization, spectral clustering
  - **Path Analysis**: Shortest paths, critical paths, k-shortest paths, widest paths
  - **Knowledge Graph Extraction**: Extract structured knowledge from text
  - **Graph Reasoning**: Complex inference, pattern matching, semantic reasoning
  - **Dependency Analysis**: Cycle detection, impact analysis, criticality scoring
  - **Graph Mining**: Motif detection, clique finding, dense subgraph discovery
  - **Text-Graph Bridge**: Align text with graphs, augment graphs with text data

  ## Examples

      # Create a graph
      nodes = [
        %{id: "person1", node_type: "PERSON", label: "Alice", properties: %{}, weight: 1.0},
        %{id: "person2", node_type: "PERSON", label: "Bob", properties: %{}, weight: 1.0}
      ]

      edges = [
        %{id: "edge1", source: "person1", target: "person2", edge_type: "KNOWS",
          label: "knows", weight: 0.8, confidence: 0.9}
      ]

      {:ok, graph_id} = GraphReasoner.create_graph(nodes, edges)

      # Analyze centrality
      {:ok, result} = GraphReasoner.analyze_centrality(graph_id, "pagerank", %{})

      # Detect communities
      {:ok, communities} = GraphReasoner.detect_communities(graph_id, "louvain", %{})

      # Extract knowledge graph from text
      {:ok, kg} = GraphReasoner.extract_knowledge_graph("Alice knows Bob and works with Charlie", %{})
  """

  use RustlerPrecompiled,
    otp_app: :lang,
    crate: "graph_reasoner",
    base_url: "https://github.com/nocsi/lang/releases/download/v",
    force_build: System.get_env("RUSTLER_PRECOMPILATION_EXAMPLE_BUILD") in ["1", "true"],
    version: "0.1.0"

  @type graph_node :: %{
          id: String.t(),
          node_type: String.t(),
          label: String.t(),
          properties: map(),
          weight: float(),
          centrality_scores: map(),
          community_id: String.t() | nil,
          semantic_embedding: [float()] | nil,
          metadata: map()
        }

  @type graph_edge :: %{
          id: String.t(),
          source: String.t(),
          target: String.t(),
          edge_type: String.t(),
          label: String.t(),
          weight: float(),
          confidence: float(),
          properties: map(),
          bidirectional: boolean(),
          semantic_strength: float(),
          metadata: map()
        }

  @type reasoning_result :: %{
          query_type: String.t(),
          nodes: [node()],
          edges: [edge()],
          paths: [[String.t()]],
          subgraphs: [subgraph_result()],
          reasoning_steps: [String.t()],
          confidence_score: float(),
          processing_time_us: non_neg_integer(),
          metadata: map()
        }

  @type subgraph_result :: %{
          id: String.t(),
          nodes: [String.t()],
          edges: [String.t()],
          pattern_type: String.t(),
          significance_score: float(),
          properties: map()
        }

  @type centrality_result :: %{
          node_scores: map(),
          algorithm_used: String.t(),
          top_nodes: [{String.t(), float()}],
          distribution_stats: centrality_stats(),
          processing_time_us: non_neg_integer()
        }

  @type centrality_stats :: %{
          mean: float(),
          median: float(),
          std_dev: float(),
          min: float(),
          max: float(),
          percentile_95: float()
        }

  @type community_result :: %{
          communities: [community()],
          modularity_score: float(),
          algorithm_used: String.t(),
          processing_time_us: non_neg_integer()
        }

  @type community :: %{
          id: String.t(),
          nodes: [String.t()],
          internal_edges: non_neg_integer(),
          external_edges: non_neg_integer(),
          density: float(),
          centrality_score: float()
        }

  @type path_analysis_result :: %{
          shortest_paths: [path_result()],
          critical_paths: [path_result()],
          bottlenecks: [String.t()],
          connectivity_score: float(),
          processing_time_us: non_neg_integer()
        }

  @type path_result :: %{
          path: [String.t()],
          total_weight: float(),
          hop_count: non_neg_integer(),
          confidence: float(),
          path_type: String.t()
        }

  @type knowledge_graph_result :: %{
          entities: [entity()],
          relations: [relation()],
          triples: [triple()],
          schema: graph_schema(),
          confidence_threshold: float(),
          processing_time_us: non_neg_integer()
        }

  @type entity :: %{
          id: String.t(),
          entity_type: String.t(),
          labels: [String.t()],
          properties: map(),
          confidence: float(),
          source_spans: [text_span()]
        }

  @type relation :: %{
          id: String.t(),
          relation_type: String.t(),
          domain: String.t(),
          range: String.t(),
          properties: map(),
          confidence: float()
        }

  @type triple :: %{
          subject: String.t(),
          predicate: String.t(),
          object: String.t(),
          confidence: float(),
          source_evidence: [String.t()],
          inferred: boolean()
        }

  @type text_span :: %{
          start: non_neg_integer(),
          end: non_neg_integer(),
          text: String.t(),
          context: String.t()
        }

  @type graph_schema :: %{
          entity_types: [String.t()],
          relation_types: [String.t()],
          type_hierarchy: map(),
          constraints: [String.t()]
        }

  # Core graph operations

  @doc """
  Create a new graph from nodes and edges.

  ## Parameters

  - `nodes`: List of node structs with id, type, label, properties, etc.
  - `edges`: List of edge structs connecting the nodes

  ## Returns

  - `{:ok, graph_id}` - String identifier for the created graph
  - `{:error, reason}` - Error creating the graph

  ## Example

      nodes = [
        %{id: "n1", node_type: "CONCEPT", label: "Machine Learning",
          properties: %{}, weight: 1.0, centrality_scores: %{},
          community_id: nil, semantic_embedding: nil, metadata: %{}}
      ]

      edges = [
        %{id: "e1", source: "n1", target: "n2", edge_type: "RELATES_TO",
          label: "relates to", weight: 0.8, confidence: 0.9, properties: %{},
          bidirectional: false, semantic_strength: 0.8, metadata: %{}}
      ]

      {:ok, graph_id} = GraphReasoner.create_graph(nodes, edges)
  """
  @spec create_graph(list(graph_node()), list(graph_edge())) ::
          {:ok, String.t()} | {:error, atom()}
  def create_graph(_nodes, _edges), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Analyze centrality metrics for nodes in the graph.

  ## Algorithms

  - `"pagerank"` - Google's PageRank algorithm
  - `"betweenness"` - Betweenness centrality
  - `"closeness"` - Closeness centrality
  - `"eigenvector"` - Eigenvector centrality
  - `"degree"` - Degree centrality (in, out, total)
  - `"katz"` - Katz centrality

  ## Options

  - `damping_factor` - For PageRank (default: 0.85)
  - `max_iterations` - Maximum iterations (default: 100)
  - `tolerance` - Convergence tolerance (default: 1e-6)
  - `normalized` - Normalize results (default: true)
  - `mode` - For degree centrality: "in", "out", "total"

  ## Example

      {:ok, result} = GraphReasoner.analyze_centrality(graph_id, "pagerank", %{
        damping_factor: 0.85,
        max_iterations: 100,
        tolerance: 1e-6
      })

      # Access results
      top_nodes = result.top_nodes
      all_scores = result.node_scores
      stats = result.distribution_stats
  """
  @spec analyze_centrality(String.t(), String.t(), map()) ::
          {:ok, centrality_result()} | {:error, atom()}
  def analyze_centrality(_graph_id, _algorithm, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Detect communities in the graph using various algorithms.

  ## Algorithms

  - `"louvain"` - Louvain method for community detection
  - `"leiden"` - Leiden algorithm (improved Louvain)
  - `"modularity"` - Greedy modularity optimization
  - `"spectral"` - Spectral clustering

  ## Options

  - `resolution` - Resolution parameter (default: 1.0)
  - `max_iterations` - Maximum iterations (default: 100)
  - `tolerance` - Convergence tolerance (default: 1e-7)
  - `random_seed` - Random seed for reproducibility (default: 42)
  - `num_communities` - Target number of communities (spectral only)

  ## Example

      {:ok, result} = GraphReasoner.detect_communities(graph_id, "louvain", %{
        resolution: 1.0,
        max_iterations: 100
      })

      # Access results
      communities = result.communities
      modularity = result.modularity_score
  """
  @spec detect_communities(String.t(), String.t(), map()) ::
          {:ok, community_result()} | {:error, atom()}
  def detect_communities(_graph_id, _algorithm, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Find paths between nodes using various algorithms.

  ## Algorithms

  - `"shortest"` - Single shortest path
  - `"all_simple"` - All simple paths
  - `"k_shortest"` - K shortest paths
  - `"widest"` - Path with maximum minimum edge weight

  ## Options

  - `k` - Number of paths to find (for k_shortest)
  - `max_length` - Maximum path length
  - `use_weights` - Use edge weights (default: false)

  ## Example

      {:ok, result} = GraphReasoner.find_paths(graph_id, "source_node", "target_node", "shortest", %{
        use_weights: true,
        max_length: 10
      })

      # Access results
      paths = result.shortest_paths
      critical = result.critical_paths
      bottlenecks = result.bottlenecks
  """
  @spec find_paths(String.t(), String.t(), String.t(), String.t(), map()) ::
          {:ok, path_analysis_result()} | {:error, atom()}
  def find_paths(_graph_id, _source, _target, _algorithm, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  # Knowledge graph extraction

  @doc """
  Extract a knowledge graph from text using NLP and pattern matching.

  ## Configuration

  - `confidence_threshold` - Minimum confidence for extractions (default: 0.7)
  - `max_entity_distance` - Maximum distance between related entities (default: 50)
  - `use_coreference` - Enable coreference resolution (default: true)
  - `linguistic_features` - Use linguistic features (default: true)
  - `custom_entity_patterns` - Additional entity extraction patterns
  - `custom_relation_patterns` - Additional relation extraction patterns

  ## Returns

  Knowledge graph with extracted entities, relations, and triples.

  ## Example

      text = "Alice works at Google. She is a software engineer who develops machine learning systems."

      {:ok, kg} = GraphReasoner.extract_knowledge_graph(text, %{
        confidence_threshold: 0.8,
        use_coreference: true,
        linguistic_features: true
      })

      # Access results
      entities = kg.entities
      relations = kg.relations
      triples = kg.triples
      schema = kg.schema
  """
  @spec extract_knowledge_graph(String.t(), map()) ::
          {:ok, knowledge_graph_result()} | {:error, atom()}
  def extract_knowledge_graph(_text, _config), do: :erlang.nif_error(:nif_not_loaded)

  # Advanced reasoning

  @doc """
  Perform complex reasoning over the graph.

  ## Reasoning Types

  - `"traversal"` - Graph traversal with various strategies
  - `"pattern"` - Pattern matching and recognition
  - `"inference"` - Logical inference and rule application
  - `"similarity"` - Similarity-based reasoning
  - `"temporal"` - Temporal reasoning over time-aware graphs

  ## Traversal Options

  - `start_node` - Starting node for traversal
  - `max_depth` - Maximum traversal depth
  - `traversal_type` - "bfs", "dfs", or "semantic"
  - `semantic_threshold` - Minimum semantic strength for traversal

  ## Pattern Options

  - `pattern_type` - "structural", "semantic", "temporal", "causal"
  - `min_confidence` - Minimum pattern confidence

  ## Inference Options

  - `strategy` - "forward_chaining", "backward_chaining", "abductive"
  - `max_inferences` - Maximum number of inferences
  - `target_goal` - Goal for backward chaining

  ## Similarity Options

  - `reference_node` - Node to find similarities to
  - `similarity_threshold` - Minimum similarity score
  - `max_results` - Maximum number of similar nodes

  ## Example

      # Traversal reasoning
      {:ok, result} = GraphReasoner.reason_over_graph(graph_id, "find connected concepts", "traversal", %{
        start_node: "concept1",
        max_depth: 3,
        traversal_type: "semantic"
      })

      # Pattern reasoning
      {:ok, result} = GraphReasoner.reason_over_graph(graph_id, "find triangles", "pattern", %{
        pattern_type: "structural",
        min_confidence: 0.8
      })

      # Inference reasoning
      {:ok, result} = GraphReasoner.reason_over_graph(graph_id, "infer relationships", "inference", %{
        strategy: "forward_chaining",
        max_inferences: 50
      })
  """
  @spec reason_over_graph(String.t(), String.t(), String.t(), map()) ::
          {:ok, reasoning_result()} | {:error, atom()}
  def reason_over_graph(_graph_id, _query, _reasoning_type, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Analyze dependency graphs with cycle detection and impact analysis.

  ## Features

  - Cycle detection and analysis
  - Critical path identification
  - Impact analysis and propagation
  - Stability and coupling metrics
  - Risk assessment

  ## Options

  - `cycle_detection` - Enable cycle detection (default: true)
  - `impact_analysis` - Enable impact analysis (default: true)
  - `criticality_analysis` - Enable criticality analysis (default: true)
  - `max_depth` - Maximum analysis depth (default: 50)
  - `weight_threshold` - Minimum edge weight threshold (default: 0.1)

  ## Example

      dependencies = [
        {"module_a", ["module_b", "module_c"]},
        {"module_b", ["module_d"]},
        {"module_c", ["module_d"]},
        {"module_d", ["module_a"]}  # Creates a cycle
      ]

      {:ok, result} = GraphReasoner.analyze_dependency_graph(dependencies, %{
        cycle_detection: true,
        impact_analysis: true,
        max_depth: 20
      })

      # Access results
      cycles = result.subgraphs |> Enum.filter(&(&1.pattern_type == "dependency_cycle"))
      critical_paths = result.paths
      reliability = result.confidence_score
  """
  @spec analyze_dependency_graph([{String.t(), [String.t()]}], map()) ::
          {:ok, reasoning_result()} | {:error, atom()}
  def analyze_dependency_graph(_dependencies, _options), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Mine graph patterns including motifs, cliques, and dense subgraphs.

  ## Pattern Types

  - `"motifs"` - Network motifs (triangles, squares, stars, chains)
  - `"cliques"` - Maximal cliques and dense clusters
  - `"bridges"` - Bridge edges critical for connectivity
  - `"articulation"` - Articulation points (cut vertices)
  - `"dense_subgraphs"` - Dense subgraph discovery

  ## Motif Options

  - `motif_size` - Size of motifs to find (default: 3)
  - `motif_types` - Types: ["triangle", "square", "star", "chain"]

  ## Clique Options

  - `min_clique_size` - Minimum clique size (default: 3)
  - `max_clique_size` - Maximum clique size (default: 8)

  ## Dense Subgraph Options

  - `min_density` - Minimum density threshold (default: 0.6)
  - `min_size` - Minimum subgraph size (default: 3)

  ## Example

      # Find motifs
      {:ok, motifs} = GraphReasoner.mine_graph_patterns(graph_id, "motifs", %{
        motif_size: 3,
        motif_types: ["triangle", "star"]
      })

      # Find cliques
      {:ok, cliques} = GraphReasoner.mine_graph_patterns(graph_id, "cliques", %{
        min_clique_size: 3,
        max_clique_size: 6
      })

      # Find dense subgraphs
      {:ok, dense} = GraphReasoner.mine_graph_patterns(graph_id, "dense_subgraphs", %{
        min_density: 0.7,
        min_size: 4
      })
  """
  @spec mine_graph_patterns(String.t(), String.t(), map()) ::
          {:ok, [subgraph_result()]} | {:error, atom()}
  def mine_graph_patterns(_graph_id, _pattern_type, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Bridge text analysis with graph structures for multi-modal reasoning.

  ## Bridge Types

  - `"align"` - Align text spans with graph nodes
  - `"augment"` - Augment graph with information from text
  - `"query"` - Query graph using natural language
  - `"synthesize"` - Synthesize insights from text and graph

  ## Text Data Format

  Each text item should have:
  - `"text"` - The text content
  - `"query"` - Query text (for query bridge type)
  - Additional metadata fields as needed

  ## Options

  - `similarity_threshold` - Text-graph similarity threshold (default: 0.7)
  - `max_alignment_distance` - Maximum alignment distance (default: 100)
  - `use_embedding_similarity` - Use semantic embeddings (default: true)
  - `text_preprocessing_enabled` - Enable text preprocessing (default: true)

  ## Examples

      # Align text with graph
      text_data = [%{"text" => "Alice works on machine learning projects"}]
      {:ok, result} = GraphReasoner.bridge_text_and_graph(text_data, graph_id, "align", %{})

      # Augment graph with text
      {:ok, result} = GraphReasoner.bridge_text_and_graph(text_data, graph_id, "augment", %{})

      # Query graph with natural language
      query_data = [%{"query" => "Find people who work on AI"}]
      {:ok, result} = GraphReasoner.bridge_text_and_graph(query_data, graph_id, "query", %{})

      # Synthesize text and graph insights
      {:ok, result} = GraphReasoner.bridge_text_and_graph(text_data, graph_id, "synthesize", %{})
  """
  @spec bridge_text_and_graph([map()], String.t(), String.t(), map()) ::
          {:ok, reasoning_result()} | {:error, atom()}
  def bridge_text_and_graph(_text_data, _graph_id, _bridge_type, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  # Utility functions

  @doc """
  Get statistics about a graph.

  Returns information about node count, edge count, density, etc.

  ## Example

      {:ok, stats} = GraphReasoner.get_graph_stats(graph_id)

      # Access stats
      node_count = stats["node_count"]
      edge_count = stats["edge_count"]
      density = stats["density"]
      access_count = stats["access_count"]
  """
  @spec get_graph_stats(String.t()) :: {:ok, map()} | {:error, atom()}
  def get_graph_stats(_graph_id), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Clear all internal caches.

  Clears graph cache, query cache, and other internal state.
  Useful for memory management in long-running processes.

  ## Example

      :ok = GraphReasoner.clear_caches()
  """
  @spec clear_caches() :: :ok
  def clear_caches(), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get performance statistics for the graph reasoner.

  Returns information about cached graphs, memory usage, etc.

  ## Example

      {:ok, stats} = GraphReasoner.get_performance_stats()

      graphs_cached = stats["graphs_cached"]
      queries_cached = stats["queries_cached"]
      estimated_memory = stats["estimated_memory_bytes"]
  """
  @spec get_performance_stats() :: {:ok, map()} | {:error, atom()}
  def get_performance_stats(), do: :erlang.nif_error(:nif_not_loaded)

  # High-level helper functions

  @doc """
  Create a simple graph from a list of relationships.

  ## Example

      relationships = [
        {"Alice", "knows", "Bob"},
        {"Bob", "works_with", "Charlie"},
        {"Alice", "manages", "Charlie"}
      ]

      {:ok, graph_id} = GraphReasoner.create_simple_graph(relationships)
  """
  @spec create_simple_graph([{String.t(), String.t(), String.t()}]) ::
          {:ok, String.t()} | {:error, atom()}
  def create_simple_graph(relationships) do
    {nodes, edges} = relationships_to_graph_elements(relationships)
    create_graph(nodes, edges)
  end

  @doc """
  Perform a complete analysis of a graph including centrality, communities, and patterns.

  Returns a comprehensive analysis result.

  ## Example

      {:ok, analysis} = GraphReasoner.analyze_graph_comprehensive(graph_id, %{
        centrality_algorithms: ["pagerank", "betweenness"],
        community_algorithm: "louvain",
        find_patterns: ["motifs", "cliques"]
      })
  """
  @spec analyze_graph_comprehensive(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def analyze_graph_comprehensive(graph_id, options \\ %{}) do
    centrality_algos = Map.get(options, :centrality_algorithms, ["pagerank"])
    community_algo = Map.get(options, :community_algorithm, "louvain")
    pattern_types = Map.get(options, :find_patterns, ["motifs"])

    results = %{}

    # Analyze centrality
    centrality_results =
      Enum.reduce(centrality_algos, %{}, fn algo, acc ->
        case analyze_centrality(graph_id, algo, %{}) do
          {:ok, result} -> Map.put(acc, algo, result)
          {:error, _} -> acc
        end
      end)

    results = Map.put(results, :centrality, centrality_results)

    # Detect communities
    case detect_communities(graph_id, community_algo, %{}) do
      {:ok, community_result} ->
        Map.put(results, :communities, community_result)

      {:error, _} ->
        results
    end

    # Mine patterns
    pattern_results =
      Enum.reduce(pattern_types, %{}, fn pattern_type, acc ->
        case mine_graph_patterns(graph_id, pattern_type, %{}) do
          {:ok, patterns} -> Map.put(acc, pattern_type, patterns)
          {:error, _} -> acc
        end
      end)

    results = Map.put(results, :patterns, pattern_results)

    # Get basic stats
    case get_graph_stats(graph_id) do
      {:ok, stats} ->
        Map.put(results, :stats, stats)

      {:error, _} ->
        results
    end

    {:ok, results}
  end

  @doc """
  Extract and analyze a knowledge graph from text in one operation.

  ## Example

      text = "Machine learning is a subset of artificial intelligence.
              It uses algorithms to analyze data and make predictions."

      {:ok, result} = GraphReasoner.extract_and_analyze_knowledge_graph(text, %{
        confidence_threshold: 0.8,
        analyze_centrality: true,
        find_communities: true
      })
  """
  @spec extract_and_analyze_knowledge_graph(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def extract_and_analyze_knowledge_graph(text, options \\ %{}) do
    # Extract knowledge graph
    case extract_knowledge_graph(text, options) do
      {:ok, kg_result} ->
        # Convert to graph format
        nodes = Enum.map(kg_result.entities, &entity_to_node/1)

        edges =
          Enum.map(kg_result.relations, fn rel ->
            relation_to_edge(rel, kg_result.triples)
          end)

        # Create graph
        case create_graph(nodes, edges) do
          {:ok, graph_id} ->
            # Analyze if requested
            analysis_result =
              if Map.get(options, :analyze_centrality, false) or
                   Map.get(options, :find_communities, false) do
                analyze_graph_comprehensive(graph_id, options)
              else
                {:ok, %{}}
              end

            case analysis_result do
              {:ok, analysis} ->
                {:ok,
                 %{
                   knowledge_graph: kg_result,
                   graph_id: graph_id,
                   analysis: analysis
                 }}

              {:error, reason} ->
                {:ok,
                 %{
                   knowledge_graph: kg_result,
                   graph_id: graph_id,
                   analysis: %{error: reason}
                 }}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions

  defp relationships_to_graph_elements(relationships) do
    nodes_map =
      relationships
      |> Enum.flat_map(fn {source, _relation, target} -> [source, target] end)
      |> Enum.uniq()
      |> Enum.with_index()
      |> Enum.map(fn {name, idx} ->
        %{
          id: "node_#{idx}",
          node_type: "ENTITY",
          label: name,
          properties: %{},
          weight: 1.0,
          centrality_scores: %{},
          community_id: nil,
          semantic_embedding: nil,
          metadata: %{}
        }
      end)

    node_name_to_id =
      nodes_map
      |> Enum.map(fn node -> {node.label, node.id} end)
      |> Map.new()

    edges =
      relationships
      |> Enum.with_index()
      |> Enum.map(fn {{source, relation, target}, idx} ->
        %{
          id: "edge_#{idx}",
          source: Map.get(node_name_to_id, source),
          target: Map.get(node_name_to_id, target),
          edge_type: String.upcase(relation),
          label: relation,
          weight: 1.0,
          confidence: 1.0,
          properties: %{},
          bidirectional: false,
          semantic_strength: 1.0,
          metadata: %{}
        }
      end)

    {nodes_map, edges}
  end

  defp entity_to_node(entity) do
    %{
      id: entity.id,
      node_type: entity.entity_type,
      label: Enum.at(entity.labels, 0, entity.id),
      properties: entity.properties,
      weight: entity.confidence,
      centrality_scores: %{},
      community_id: nil,
      semantic_embedding: nil,
      metadata: %{
        source_spans: entity.source_spans,
        confidence: entity.confidence
      }
    }
  end

  defp relation_to_edge(relation, triples) do
    # Find a triple that uses this relation
    triple = Enum.find(triples, fn t -> t.predicate == relation.id end)

    %{
      id: relation.id,
      source: if(triple, do: triple.subject, else: "unknown"),
      target: if(triple, do: triple.object, else: "unknown"),
      edge_type: relation.relation_type,
      label: relation.relation_type,
      weight: relation.confidence,
      confidence: relation.confidence,
      properties: relation.properties,
      bidirectional: false,
      semantic_strength: relation.confidence,
      metadata: %{
        domain: relation.domain,
        range: relation.range
      }
    }
  end

  @doc """
  Create a knowledge graph and convert it to a simple graph for analysis.

  ## Example

      text = "Alice works at Google and knows Bob."
      {:ok, {kg, graph_id}} = GraphReasoner.text_to_analyzable_graph(text)
  """
  @spec text_to_analyzable_graph(String.t(), map()) ::
          {:ok, {knowledge_graph_result(), String.t()}} | {:error, atom()}
  def text_to_analyzable_graph(text, options \\ %{}) do
    case extract_knowledge_graph(text, options) do
      {:ok, kg_result} ->
        nodes = Enum.map(kg_result.entities, &entity_to_node/1)

        edges =
          Enum.map(kg_result.relations, fn rel ->
            relation_to_edge(rel, kg_result.triples)
          end)

        case create_graph(nodes, edges) do
          {:ok, graph_id} -> {:ok, {kg_result, graph_id}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Run a quick analysis on a text-derived knowledge graph.

  ## Example

      text = "Machine learning models process data to make predictions."
      {:ok, result} = GraphReasoner.quick_text_analysis(text, %{
        find_communities: true,
        centrality_algorithm: "pagerank"
      })
  """
  @spec quick_text_analysis(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def quick_text_analysis(text, options \\ %{}) do
    case text_to_analyzable_graph(text, options) do
      {:ok, {kg_result, graph_id}} ->
        centrality_algo = Map.get(options, :centrality_algorithm, "pagerank")

        result = %{knowledge_graph: kg_result, graph_id: graph_id}

        # Add centrality analysis if requested
        result =
          case analyze_centrality(graph_id, centrality_algo, %{}) do
            {:ok, centrality} -> Map.put(result, :centrality, centrality)
            {:error, _} -> result
          end

        # Add community detection if requested
        result =
          if Map.get(options, :find_communities, false) do
            case detect_communities(graph_id, "louvain", %{}) do
              {:ok, communities} -> Map.put(result, :communities, communities)
              {:error, _} -> result
            end
          else
            result
          end

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
