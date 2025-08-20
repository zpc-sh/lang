#!/usr/bin/env elixir

# GraphReasoner Demonstration Script
# This script showcases the advanced graph reasoning capabilities

Mix.install([])

defmodule GraphReasonerDemo do
  @moduledoc """
  Demonstration of the GraphReasoner NIF capabilities for analyzing both
  text and graph-structured data with sophisticated algorithms.
  """

  alias Lang.GraphReasoner

  def run_demo do
    IO.puts("🚀 GraphReasoner Demonstration")
    IO.puts("=" <> String.duplicate("=", 50))
    IO.puts("")

    # Demo 1: Basic Graph Creation and Analysis
    demo_basic_graph_analysis()

    # Demo 2: Knowledge Graph Extraction from Text
    demo_knowledge_graph_extraction()

    # Demo 3: Dependency Analysis
    demo_dependency_analysis()

    # Demo 4: Text-Graph Bridge
    demo_text_graph_bridge()

    # Demo 5: Advanced Graph Mining
    demo_graph_mining()

    IO.puts("\n✅ All demonstrations completed successfully!")
  end

  defp demo_basic_graph_analysis do
    IO.puts("📊 Demo 1: Basic Graph Creation and Analysis")
    IO.puts("-" <> String.duplicate("-", 45))

    # Create a sample social network graph
    nodes = [
      %{
        id: "alice",
        node_type: "PERSON",
        label: "Alice Johnson",
        properties: %{"role" => "Engineer", "department" => "AI"},
        weight: 1.0,
        centrality_scores: %{},
        community_id: nil,
        semantic_embedding: nil,
        metadata: %{}
      },
      %{
        id: "bob",
        node_type: "PERSON",
        label: "Bob Smith",
        properties: %{"role" => "Manager", "department" => "AI"},
        weight: 1.0,
        centrality_scores: %{},
        community_id: nil,
        semantic_embedding: nil,
        metadata: %{}
      },
      %{
        id: "charlie",
        node_type: "PERSON",
        label: "Charlie Brown",
        properties: %{"role" => "Researcher", "department" => "ML"},
        weight: 1.0,
        centrality_scores: %{},
        community_id: nil,
        semantic_embedding: nil,
        metadata: %{}
      },
      %{
        id: "diana",
        node_type: "PERSON",
        label: "Diana Wilson",
        properties: %{"role" => "Engineer", "department" => "ML"},
        weight: 1.0,
        centrality_scores: %{},
        community_id: nil,
        semantic_embedding: nil,
        metadata: %{}
      }
    ]

    edges = [
      %{
        id: "e1",
        source: "alice",
        target: "bob",
        edge_type: "REPORTS_TO",
        label: "reports to",
        weight: 1.0,
        confidence: 0.9,
        properties: %{},
        bidirectional: false,
        semantic_strength: 1.0,
        metadata: %{}
      },
      %{
        id: "e2",
        source: "alice",
        target: "charlie",
        edge_type: "COLLABORATES_WITH",
        label: "collaborates with",
        weight: 0.8,
        confidence: 0.85,
        properties: %{},
        bidirectional: true,
        semantic_strength: 0.8,
        metadata: %{}
      },
      %{
        id: "e3",
        source: "bob",
        target: "diana",
        edge_type: "MANAGES",
        label: "manages",
        weight: 1.0,
        confidence: 0.95,
        properties: %{},
        bidirectional: false,
        semantic_strength: 1.0,
        metadata: %{}
      },
      %{
        id: "e4",
        source: "charlie",
        target: "diana",
        edge_type: "MENTORS",
        label: "mentors",
        weight: 0.7,
        confidence: 0.8,
        properties: %{},
        bidirectional: false,
        semantic_strength: 0.7,
        metadata: %{}
      }
    ]

    case GraphReasoner.create_graph(nodes, edges) do
      {:ok, graph_id} ->
        IO.puts("✅ Created graph with ID: #{graph_id}")

        # Analyze PageRank centrality
        case GraphReasoner.analyze_centrality(graph_id, "pagerank", %{
               damping_factor: 0.85,
               max_iterations: 100
             }) do
          {:ok, centrality_result} ->
            IO.puts("🔍 PageRank Analysis:")
            IO.puts("   Top nodes: #{inspect(centrality_result.top_nodes)}")
            IO.puts("   Processing time: #{centrality_result.processing_time_us}μs")

          {:error, reason} ->
            IO.puts("❌ Centrality analysis failed: #{reason}")
        end

        # Detect communities
        case GraphReasoner.detect_communities(graph_id, "louvain", %{
               resolution: 1.0,
               max_iterations: 100
             }) do
          {:ok, community_result} ->
            IO.puts("🏘️  Community Detection:")
            IO.puts("   Found #{length(community_result.communities)} communities")
            IO.puts("   Modularity score: #{community_result.modularity_score}")

          {:error, reason} ->
            IO.puts("❌ Community detection failed: #{reason}")
        end

        # Find paths
        case GraphReasoner.find_paths(graph_id, "alice", "diana", "shortest", %{}) do
          {:ok, path_result} ->
            IO.puts("🛤️  Path Analysis:")
            IO.puts("   Shortest paths found: #{length(path_result.shortest_paths)}")

          {:error, reason} ->
            IO.puts("❌ Path analysis failed: #{reason}")
        end

      {:error, reason} ->
        IO.puts("❌ Graph creation failed: #{reason}")
    end

    IO.puts("")
  end

  defp demo_knowledge_graph_extraction do
    IO.puts("🧠 Demo 2: Knowledge Graph Extraction from Text")
    IO.puts("-" <> String.duplicate("-", 45))

    text = """
    Alice Johnson is a machine learning engineer at Google. She works closely with
    Bob Smith, who is the AI research manager. Alice specializes in natural language
    processing and has published several papers on transformer architectures.
    Bob oversees the development of large language models and collaborates with
    Stanford University on neural network research.
    """

    case GraphReasoner.extract_knowledge_graph(text, %{
           confidence_threshold: 0.7,
           use_coreference: true,
           linguistic_features: true
         }) do
      {:ok, kg_result} ->
        IO.puts("✅ Knowledge Graph Extracted:")
        IO.puts("   Entities found: #{length(kg_result.entities)}")
        IO.puts("   Relations found: #{length(kg_result.relations)}")
        IO.puts("   Triples generated: #{length(kg_result.triples)}")
        IO.puts("   Processing time: #{kg_result.processing_time_us}μs")

        # Show some extracted entities
        IO.puts("📍 Sample entities:")

        Enum.take(kg_result.entities, 3)
        |> Enum.each(fn entity ->
          IO.puts(
            "   - #{entity.entity_type}: #{Enum.join(entity.labels, ", ")} (confidence: #{entity.confidence})"
          )
        end)

      {:error, reason} ->
        IO.puts("❌ Knowledge graph extraction failed: #{reason}")
    end

    IO.puts("")
  end

  defp demo_dependency_analysis do
    IO.puts("🔗 Demo 3: Dependency Analysis")
    IO.puts("-" <> String.duplicate("-", 30))

    # Sample software dependency graph with a cycle
    dependencies = [
      {"module_auth", ["module_user", "module_crypto"]},
      {"module_user", ["module_database", "module_validation"]},
      {"module_database", ["module_connection", "module_query"]},
      {"module_crypto", ["module_hash", "module_encryption"]},
      # Creates a cycle!
      {"module_validation", ["module_regex", "module_auth"]},
      {"module_connection", ["module_pool"]},
      {"module_query", ["module_parser"]},
      {"module_hash", []},
      {"module_encryption", ["module_hash"]},
      {"module_regex", []},
      {"module_parser", []},
      {"module_pool", []}
    ]

    case GraphReasoner.analyze_dependency_graph(dependencies, %{
           cycle_detection: true,
           impact_analysis: true,
           criticality_analysis: true,
           max_depth: 20
         }) do
      {:ok, analysis_result} ->
        IO.puts("✅ Dependency Analysis Complete:")
        IO.puts("   Nodes analyzed: #{length(analysis_result.nodes)}")
        IO.puts("   Edges analyzed: #{length(analysis_result.edges)}")
        IO.puts("   Critical paths: #{length(analysis_result.paths)}")
        IO.puts("   Reliability score: #{analysis_result.confidence_score}")

        # Show detected cycles
        cycles =
          Enum.filter(
            analysis_result.subgraphs,
            fn sg -> sg.pattern_type == "dependency_cycle" end
          )

        IO.puts("🔄 Cycles detected: #{length(cycles)}")

        Enum.each(cycles, fn cycle ->
          IO.puts(
            "   - Cycle: #{Enum.join(cycle.nodes, " → ")} (severity: #{cycle.significance_score})"
          )
        end)

      {:error, reason} ->
        IO.puts("❌ Dependency analysis failed: #{reason}")
    end

    IO.puts("")
  end

  defp demo_text_graph_bridge do
    IO.puts("🌉 Demo 4: Text-Graph Bridge")
    IO.puts("-" <> String.duplicate("-", 30))

    # Create a simple knowledge graph first
    case GraphReasoner.create_simple_graph([
           {"Machine Learning", "is_part_of", "Artificial Intelligence"},
           {"Deep Learning", "is_subset_of", "Machine Learning"},
           {"Neural Networks", "implements", "Deep Learning"},
           {"Transformers", "is_type_of", "Neural Networks"},
           {"GPT", "uses", "Transformers"}
         ]) do
      {:ok, graph_id} ->
        IO.puts("✅ Created knowledge graph: #{graph_id}")

        # Test text alignment
        text_data = [
          %{"text" => "Transformers are a type of neural network architecture"},
          %{"text" => "GPT models use transformer-based architectures for language understanding"}
        ]

        case GraphReasoner.bridge_text_and_graph(text_data, graph_id, "align", %{
               similarity_threshold: 0.6,
               use_embedding_similarity: true
             }) do
          {:ok, alignment_result} ->
            IO.puts("🎯 Text-Graph Alignment:")
            IO.puts("   Aligned nodes: #{length(alignment_result.nodes)}")
            IO.puts("   Subgraphs found: #{length(alignment_result.subgraphs)}")
            IO.puts("   Confidence: #{alignment_result.confidence_score}")

          {:error, reason} ->
            IO.puts("❌ Text-graph alignment failed: #{reason}")
        end

        # Test natural language querying
        query_data = [%{"query" => "Find all types of neural networks"}]

        case GraphReasoner.bridge_text_and_graph(query_data, graph_id, "query", %{}) do
          {:ok, query_result} ->
            IO.puts("❓ Natural Language Query:")
            IO.puts("   Results found: #{length(query_result.nodes)} nodes")
            IO.puts("   Query confidence: #{query_result.confidence_score}")

          {:error, reason} ->
            IO.puts("❌ Natural language query failed: #{reason}")
        end

      {:error, reason} ->
        IO.puts("❌ Simple graph creation failed: #{reason}")
    end

    IO.puts("")
  end

  defp demo_graph_mining do
    IO.puts("⛏️  Demo 5: Advanced Graph Mining")
    IO.puts("-" <> String.duplicate("-", 32))

    # Create a more complex graph for mining
    relationships = [
      {"A", "connects", "B"},
      {"A", "connects", "C"},
      {"A", "connects", "D"},
      {"B", "connects", "C"},
      {"B", "connects", "E"},
      {"C", "connects", "D"},
      {"C", "connects", "F"},
      {"D", "connects", "F"},
      {"E", "connects", "F"},
      {"F", "connects", "G"},
      {"G", "connects", "H"},
      {"H", "connects", "I"},
      {"G", "connects", "I"},
      {"I", "connects", "J"},
      {"J", "connects", "A"}
    ]

    case GraphReasoner.create_simple_graph(relationships) do
      {:ok, graph_id} ->
        IO.puts("✅ Created complex graph for mining: #{graph_id}")

        # Mine network motifs
        case GraphReasoner.mine_graph_patterns(graph_id, "motifs", %{
               motif_size: 3,
               motif_types: ["triangle", "star"]
             }) do
          {:ok, motifs} ->
            IO.puts("🔺 Network Motifs:")
            IO.puts("   Motifs found: #{length(motifs)}")

            Enum.take(motifs, 3)
            |> Enum.each(fn motif ->
              IO.puts(
                "   - #{motif.pattern_type}: #{length(motif.nodes)} nodes (significance: #{motif.significance_score})"
              )
            end)

          {:error, reason} ->
            IO.puts("❌ Motif mining failed: #{reason}")
        end

        # Find cliques
        case GraphReasoner.mine_graph_patterns(graph_id, "cliques", %{
               min_clique_size: 3,
               max_clique_size: 5
             }) do
          {:ok, cliques} ->
            IO.puts("🔸 Clique Detection:")
            IO.puts("   Cliques found: #{length(cliques)}")

            Enum.take(cliques, 2)
            |> Enum.each(fn clique ->
              IO.puts(
                "   - Clique: #{Enum.join(clique.nodes, ", ")} (density: #{clique.properties["density"] || "N/A"})"
              )
            end)

          {:error, reason} ->
            IO.puts("❌ Clique detection failed: #{reason}")
        end

        # Find bridges and articulation points
        case GraphReasoner.mine_graph_patterns(graph_id, "bridges", %{
               importance_threshold: 0.3
             }) do
          {:ok, bridges} ->
            IO.puts("🌉 Bridge Analysis:")
            IO.puts("   Bridges found: #{length(bridges)}")

          {:error, reason} ->
            IO.puts("❌ Bridge analysis failed: #{reason}")
        end

      {:error, reason} ->
        IO.puts("❌ Complex graph creation failed: #{reason}")
    end

    IO.puts("")
  end

  defp demo_comprehensive_analysis do
    IO.puts("🎯 Demo 6: Comprehensive Graph Analysis")
    IO.puts("-" <> String.duplicate("-", 40))

    text = """
    The research team consists of Dr. Sarah Chen, who leads the machine learning
    division, and Prof. Michael Rodriguez, who specializes in natural language
    processing. Sarah's team develops deep learning models for computer vision,
    while Michael's group focuses on transformer architectures for language
    understanding. They collaborate on multimodal AI systems that combine
    vision and language processing capabilities.
    """

    case GraphReasoner.extract_and_analyze_knowledge_graph(text, %{
           confidence_threshold: 0.75,
           analyze_centrality: true,
           find_communities: true,
           centrality_algorithms: ["pagerank", "betweenness"]
         }) do
      {:ok, result} ->
        kg = result.knowledge_graph
        analysis = result.analysis

        IO.puts("✅ Comprehensive Analysis Complete:")
        IO.puts("   Graph ID: #{result.graph_id}")
        IO.puts("   Entities: #{length(kg.entities)}")
        IO.puts("   Relations: #{length(kg.relations)}")
        IO.puts("   Processing time: #{kg.processing_time_us}μs")

        if Map.has_key?(analysis, :centrality) do
          centrality_algos = Map.keys(analysis.centrality)
          IO.puts("   Centrality algorithms: #{Enum.join(centrality_algos, ", ")}")
        end

        if Map.has_key?(analysis, :communities) do
          communities = analysis.communities.communities
          IO.puts("   Communities found: #{length(communities)}")
          IO.puts("   Modularity: #{analysis.communities.modularity_score}")
        end

      {:error, reason} ->
        IO.puts("❌ Comprehensive analysis failed: #{reason}")
    end

    IO.puts("")
  end

  def demo_performance_insights do
    IO.puts("📈 Performance and Cache Statistics")
    IO.puts("-" <> String.duplicate("-", 35))

    case GraphReasoner.get_performance_stats() do
      {:ok, stats} ->
        IO.puts("🔧 System Performance:")
        IO.puts("   Graphs cached: #{stats["graphs_cached"]}")
        IO.puts("   Queries cached: #{stats["queries_cached"]}")
        IO.puts("   Estimated memory: #{stats["estimated_memory_bytes"]} bytes")

      {:error, reason} ->
        IO.puts("❌ Could not retrieve performance stats: #{reason}")
    end

    IO.puts("")
  end

  def cleanup_demo do
    IO.puts("🧹 Cleaning up caches...")

    case GraphReasoner.clear_caches() do
      :ok -> IO.puts("✅ Caches cleared successfully")
      _ -> IO.puts("❌ Failed to clear caches")
    end
  end

  # Helper function for quick testing
  def quick_test(text \\ nil) do
    sample_text =
      text ||
        """
        Machine learning is transforming artificial intelligence. Deep learning
        models use neural networks to process complex data patterns. Companies
        like Google and OpenAI are developing large language models that can
        understand and generate human-like text.
        """

    IO.puts("🚀 Quick GraphReasoner Test")
    IO.puts("Text: #{String.slice(sample_text, 0, 100)}...")

    case GraphReasoner.quick_text_analysis(sample_text, %{
           find_communities: true,
           centrality_algorithm: "pagerank"
         }) do
      {:ok, result} ->
        kg = result.knowledge_graph
        IO.puts("✅ Success!")
        IO.puts("   Entities: #{length(kg.entities)}")
        IO.puts("   Relations: #{length(kg.relations)}")
        IO.puts("   Graph ID: #{result.graph_id}")

        if Map.has_key?(result, :centrality) do
          top_nodes = result.centrality.top_nodes
          IO.puts("   Top central nodes: #{inspect(Enum.take(top_nodes, 3))}")
        end

      {:error, reason} ->
        IO.puts("❌ Failed: #{reason}")
    end
  end
end

# Run the demonstration if this file is executed directly
if System.argv() |> Enum.any?(&(&1 == "--run")) do
  GraphReasonerDemo.run_demo()
  GraphReasonerDemo.demo_performance_insights()
  GraphReasonerDemo.cleanup_demo()
else
  IO.puts("""
  GraphReasoner Demo Script

  Usage:
    elixir demo_graph_reasoner.exs --run    # Run full demonstration

  Or in IEx:
    iex> c("demo_graph_reasoner.exs")
    iex> GraphReasonerDemo.run_demo()        # Full demo
    iex> GraphReasonerDemo.quick_test()      # Quick test
    iex> GraphReasonerDemo.quick_test("Your custom text here")

  Available functions:
    - run_demo()           # Complete demonstration
    - quick_test(text)     # Quick analysis test
    - cleanup_demo()       # Clear caches
  """)
end
