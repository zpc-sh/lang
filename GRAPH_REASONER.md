# GraphReasoner: Advanced Graph Analysis & Text-Graph Integration

A sophisticated Rust-powered NIF (Native Implemented Function) for Elixir that provides state-of-the-art graph reasoning capabilities, combining traditional graph analysis with knowledge graph extraction and multi-modal text-graph reasoning.

## 🌟 Key Features

### Core Graph Operations
- **Graph Creation & Management**: Create, store, and manage complex directed/undirected graphs
- **Multiple Graph Formats**: Support for various node and edge types with rich metadata
- **Efficient Caching**: In-memory graph and query caching for optimal performance

### Advanced Graph Algorithms

#### Centrality Analysis
- **PageRank**: Google's PageRank algorithm with customizable damping factors
- **Betweenness Centrality**: Identify nodes that act as bridges in the network
- **Closeness Centrality**: Measure how close nodes are to all other nodes
- **Eigenvector Centrality**: Find nodes connected to other important nodes
- **Degree Centrality**: Analyze node connectivity (in/out/total degree)
- **Katz Centrality**: Weighted centrality with decay factor

#### Community Detection
- **Louvain Method**: Fast community detection with modularity optimization
- **Leiden Algorithm**: Improved version of Louvain with better quality guarantees
- **Modularity Optimization**: Greedy modularity-based community finding
- **Spectral Clustering**: Eigenvalue-based community detection

#### Path Analysis
- **Shortest Paths**: Single and multiple shortest path algorithms
- **K-Shortest Paths**: Find multiple alternative paths between nodes
- **Critical Path Analysis**: Identify bottlenecks and critical connections
- **Widest Path**: Find paths with maximum minimum edge weight

### Knowledge Graph Extraction
- **Entity Recognition**: Extract entities from text using advanced NLP patterns
- **Relation Extraction**: Identify relationships between entities
- **Triple Generation**: Create RDF-style subject-predicate-object triples
- **Coreference Resolution**: Link pronouns and references to entities
- **Schema Generation**: Automatically generate graph schemas from extracted data

### Graph Mining & Pattern Detection
- **Network Motifs**: Find triangles, squares, stars, chains, and custom patterns
- **Clique Detection**: Identify maximal cliques and dense subgraphs
- **Bridge Analysis**: Find critical edges that connect different parts of the graph
- **Articulation Points**: Identify nodes whose removal would disconnect the graph
- **Dense Subgraph Discovery**: Mine densely connected regions

### Dependency Analysis
- **Cycle Detection**: Find dependency cycles with severity analysis
- **Impact Analysis**: Assess how changes propagate through dependencies
- **Criticality Scoring**: Rank nodes by their importance to system stability
- **Risk Assessment**: Evaluate reliability and stability metrics

### Text-Graph Bridge
- **Text Alignment**: Map text spans to graph nodes with confidence scores
- **Graph Augmentation**: Enrich graphs with information extracted from text
- **Natural Language Queries**: Query graphs using natural language
- **Multi-modal Synthesis**: Combine text and graph insights for comprehensive analysis

### Advanced Reasoning
- **Forward/Backward Chaining**: Logical inference over graph structures
- **Pattern Matching**: Complex structural and semantic pattern recognition
- **Similarity Reasoning**: Find similar nodes and subgraphs
- **Temporal Reasoning**: Analyze time-aware graph relationships
- **Abductive Reasoning**: Infer explanations for observed patterns

## 🚀 Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    # ... other deps
  ]
end
```

The GraphReasoner NIF is automatically compiled when you run:

```bash
mix compile
```

## 📖 Quick Start

### Basic Graph Analysis

```elixir
alias Lang.GraphReasoner

# Create a simple graph
nodes = [
  %{id: "alice", node_type: "PERSON", label: "Alice", properties: %{}, 
    weight: 1.0, centrality_scores: %{}, community_id: nil, 
    semantic_embedding: nil, metadata: %{}},
  %{id: "bob", node_type: "PERSON", label: "Bob", properties: %{}, 
    weight: 1.0, centrality_scores: %{}, community_id: nil, 
    semantic_embedding: nil, metadata: %{}}
]

edges = [
  %{id: "e1", source: "alice", target: "bob", edge_type: "KNOWS", 
    label: "knows", weight: 0.8, confidence: 0.9, properties: %{}, 
    bidirectional: false, semantic_strength: 0.8, metadata: %{}}
]

{:ok, graph_id} = GraphReasoner.create_graph(nodes, edges)

# Analyze centrality
{:ok, result} = GraphReasoner.analyze_centrality(graph_id, "pagerank", %{
  damping_factor: 0.85,
  max_iterations: 100
})

IO.inspect(result.top_nodes)
```

### Knowledge Graph from Text

```elixir
text = """
Alice works at Google as a machine learning engineer. She collaborates 
with Bob on neural network research. Bob is the team lead for the AI 
division and has published papers on transformer architectures.
"""

{:ok, kg} = GraphReasoner.extract_knowledge_graph(text, %{
  confidence_threshold: 0.8,
  use_coreference: true
})

IO.puts "Found #{length(kg.entities)} entities and #{length(kg.relations)} relations"
```

### Simple Dependency Analysis

```elixir
dependencies = [
  {"module_a", ["module_b", "module_c"]},
  {"module_b", ["module_d"]},
  {"module_c", ["module_d"]},
  {"module_d", ["module_a"]}  # Creates a cycle!
]

{:ok, analysis} = GraphReasoner.analyze_dependency_graph(dependencies, %{
  cycle_detection: true,
  impact_analysis: true
})

# Find cycles
cycles = Enum.filter(analysis.subgraphs, fn sg -> 
  sg.pattern_type == "dependency_cycle" 
end)

IO.puts "Found #{length(cycles)} dependency cycles"
```

### Comprehensive Analysis

```elixir
# One-shot analysis combining multiple techniques
text = "Machine learning models use neural networks to process data..."

{:ok, result} = GraphReasoner.extract_and_analyze_knowledge_graph(text, %{
  confidence_threshold: 0.75,
  analyze_centrality: true,
  find_communities: true
})

IO.inspect(result.knowledge_graph.entities)
IO.inspect(result.analysis.centrality)
```

## 🔧 Configuration Options

### Centrality Analysis Options

```elixir
# PageRank
%{
  damping_factor: 0.85,        # Random walk restart probability
  max_iterations: 100,         # Maximum iterations for convergence
  tolerance: 1e-6              # Convergence tolerance
}

# Betweenness Centrality
%{
  normalized: true,            # Normalize by graph size
  endpoints: false             # Include path endpoints in calculation
}

# Degree Centrality
%{
  mode: "total",              # "in", "out", or "total"
  normalized: true            # Normalize by maximum possible degree
}
```

### Community Detection Options

```elixir
# Louvain Method
%{
  resolution: 1.0,            # Resolution parameter for community size
  max_iterations: 100,        # Maximum optimization iterations
  tolerance: 1e-7,            # Convergence tolerance
  random_seed: 42             # Seed for reproducibility
}

# Spectral Clustering
%{
  num_communities: 5,         # Target number of communities
  max_iterations: 100         # Maximum iterations
}
```

### Knowledge Extraction Options

```elixir
%{
  confidence_threshold: 0.7,        # Minimum confidence for extractions
  max_entity_distance: 50,          # Max chars between related entities
  use_coreference: true,            # Enable coreference resolution
  linguistic_features: true,        # Use linguistic feature analysis
  custom_entity_patterns: [...],    # Custom regex patterns for entities
  custom_relation_patterns: [...]   # Custom patterns for relations
}
```

## 🎯 Advanced Usage Examples

### Mining Graph Patterns

```elixir
# Find network motifs
{:ok, motifs} = GraphReasoner.mine_graph_patterns(graph_id, "motifs", %{
  motif_size: 3,
  motif_types: ["triangle", "star", "chain"]
})

# Detect cliques
{:ok, cliques} = GraphReasoner.mine_graph_patterns(graph_id, "cliques", %{
  min_clique_size: 3,
  max_clique_size: 6
})

# Find structural bridges
{:ok, bridges} = GraphReasoner.mine_graph_patterns(graph_id, "bridges", %{
  importance_threshold: 0.5
})
```

### Text-Graph Integration

```elixir
# Align text with existing graph
text_data = [%{"text" => "Alice is a software engineer"}]
{:ok, alignment} = GraphReasoner.bridge_text_and_graph(
  text_data, graph_id, "align", %{}
)

# Query graph with natural language
queries = [%{"query" => "Find all engineers who work on AI"}]
{:ok, results} = GraphReasoner.bridge_text_and_graph(
  queries, graph_id, "query", %{}
)

# Synthesize insights from text and graph
{:ok, insights} = GraphReasoner.bridge_text_and_graph(
  text_data, graph_id, "synthesize", %{}
)
```

### Complex Reasoning

```elixir
# Traversal-based reasoning
{:ok, result} = GraphReasoner.reason_over_graph(graph_id, 
  "find connected concepts", "traversal", %{
    start_node: "alice",
    max_depth: 3,
    traversal_type: "semantic"
  })

# Pattern-based reasoning
{:ok, patterns} = GraphReasoner.reason_over_graph(graph_id,
  "find collaboration patterns", "pattern", %{
    pattern_type: "structural",
    min_confidence: 0.8
  })

# Inference reasoning
{:ok, inferences} = GraphReasoner.reason_over_graph(graph_id,
  "infer relationships", "inference", %{
    strategy: "forward_chaining",
    max_inferences: 50
  })
```

## 📊 Performance Features

### Caching System
- **Graph Cache**: Stores frequently accessed graphs in memory
- **Query Cache**: Caches complex query results with LRU eviction
- **Pattern Cache**: Caches compiled regex and search patterns

### Parallel Processing
- **Multi-threaded Algorithms**: Centrality and community detection use Rayon
- **Concurrent Graph Operations**: Multiple graphs processed simultaneously  
- **SIMD Optimizations**: Vectorized operations where possible

### Memory Management
- **Custom Allocator**: Uses mimalloc for improved performance
- **Streaming Processing**: Handle large graphs without loading entirely in memory
- **Compression**: LZ4 compression for cached data structures

### Performance Monitoring

```elixir
# Get performance statistics
{:ok, stats} = GraphReasoner.get_performance_stats()
IO.inspect(stats)
# %{"graphs_cached" => 5, "queries_cached" => 123, "estimated_memory_bytes" => 2048576}

# Clear caches when needed
:ok = GraphReasoner.clear_caches()
```

## 🔬 Algorithm Details

### PageRank Implementation
- Uses power iteration method with teleportation
- Handles dangling nodes correctly
- Supports weighted and directed graphs
- Configurable damping factor and convergence criteria

### Community Detection
- **Louvain**: Modularity optimization with local search
- **Leiden**: Improved Louvain with refinement step
- Supports resolution parameter for community size control
- Parallel implementation for large graphs

### Knowledge Extraction
- **Entity Recognition**: Multi-pattern NLP with context analysis
- **Relation Extraction**: Dependency parsing and pattern matching
- **Coreference**: Simple pronoun and named entity linking
- **Schema Inference**: Automatic type hierarchy generation

## 🛠️ Development & Extensions

### Custom Pattern Development

```elixir
# Define custom entity patterns
custom_entities = [
  %{
    "pattern" => "\\b[A-Z][a-z]+ (University|College|Institute)\\b",
    "entity_type" => "EDUCATIONAL_INSTITUTION", 
    "confidence" => 0.9
  }
]

# Define custom relation patterns  
custom_relations = [
  %{
    "pattern" => "(.+) graduated from (.+)",
    "relation_type" => "GRADUATED_FROM",
    "subject_types" => ["PERSON"],
    "object_types" => ["EDUCATIONAL_INSTITUTION"],
    "confidence" => 0.85
  }
]
```

### Integration with Existing Systems

The GraphReasoner integrates seamlessly with:
- **Phoenix LiveView**: Real-time graph visualization
- **Ecto**: Database-backed graph persistence  
- **Broadway**: Stream processing for large-scale analysis
- **Nx**: Numerical computing integration

## 🔍 Debugging & Troubleshooting

### Common Issues

1. **Graph Creation Fails**
   ```elixir
   # Ensure all node IDs are unique
   # Verify edge source/target nodes exist
   # Check data structure format
   ```

2. **Memory Usage**
   ```elixir
   # Monitor cache usage
   {:ok, stats} = GraphReasoner.get_performance_stats()
   
   # Clear caches periodically
   :ok = GraphReasoner.clear_caches()
   ```

3. **Performance Optimization**
   ```elixir
   # Use appropriate algorithms for graph size
   # Enable parallel processing for large graphs
   # Consider sampling for exploration
   ```

### Logging and Monitoring

```elixir
# Enable detailed logging in config
config :lang, GraphReasoner,
  log_level: :debug,
  enable_performance_tracking: true
```

## 🚧 Roadmap

### Upcoming Features
- [ ] **GPU Acceleration**: CUDA support for large-scale analysis
- [ ] **Distributed Processing**: Multi-node graph analysis
- [ ] **Graph Databases**: Native Neo4j and ArangoDB integration  
- [ ] **ML Integration**: Nx-powered graph neural networks
- [ ] **Visualization**: Built-in D3.js graph visualization
- [ ] **Streaming**: Real-time graph updates and analysis

### Algorithm Enhancements
- [ ] **Advanced NLP**: BERT/GPT integration for entity extraction
- [ ] **Temporal Analysis**: Time-series graph analysis
- [ ] **Probabilistic Reasoning**: Bayesian network integration
- [ ] **Multi-layer Networks**: Support for multi-dimensional graphs

## 📚 References & Citations

This implementation draws from established research in:
- Graph theory and network analysis
- Community detection algorithms (Blondel et al., 2008)
- Knowledge graph extraction techniques
- Natural language processing and information extraction

## 🤝 Contributing

1. **Issues**: Report bugs and request features via GitHub issues
2. **Pull Requests**: Follow the established coding standards
3. **Documentation**: Help improve examples and documentation
4. **Testing**: Add test cases for new functionality

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## ✨ Acknowledgments

- Built with [Rustler](https://github.com/rusterlium/rustler) for Elixir-Rust integration
- Uses [petgraph](https://github.com/petgraph/petgraph) for core graph algorithms
- Powered by [rayon](https://github.com/rayon-rs/rayon) for parallel processing
- Optimized with [mimalloc](https://github.com/microsoft/mimalloc) memory allocator