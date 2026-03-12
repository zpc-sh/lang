# MarkdownLd

[![Hex.pm](https://img.shields.io/hexpm/v/markdown_ld.svg)](https://hex.pm/packages/markdown_ld)
[![Documentation](https://img.shields.io/badge/hex-docs-brightgreen.svg)](https://hexdocs.pm/markdown_ld)
[![Build Status](https://github.com/nocsi/markdown-ld/workflows/CI/badge.svg)](https://github.com/nocsi/markdown-ld/actions)

**High-performance Markdown processing with SIMD optimizations and JSON-LD integration for Elixir.**

MarkdownLd is built for production systems that require **extreme performance** and **reliability**. Leveraging Rust SIMD optimizations, memory pooling, and advanced parsing algorithms, it delivers **10-50x faster** markdown processing compared to traditional pure Elixir solutions.

## ⚡ Performance Highlights

- **🚀 10-50x faster** than pure Elixir markdown parsers
- **🔥 SIMD-optimized** string processing (Apple Silicon NEON, x86 AVX2)
- **⚡ Zero-copy** binary processing for maximum efficiency  
- **🧠 Memory pools** to minimize allocation overhead
- **🔄 Parallel processing** with configurable concurrency
- **📊 Built-in performance** tracking and metrics

## 🚀 Quick Start

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:markdown_ld, "~> 0.4.0"}
  ]
end
```

Basic usage:

```elixir
# Parse markdown content
{:ok, result} = MarkdownLd.parse("""
# Hello World

This is **bold** text with a [link](https://example.com).

```elixir
def hello, do: :world
```

- [ ] Todo item
- [x] Completed item
""")

# Result contains structured data
IO.inspect(result.headings)
# [%{level: 1, text: "Hello World", line: 1}]

IO.inspect(result.links) 
# [%{text: "link", url: "https://example.com", line: 3}]

IO.inspect(result.code_blocks)
# [%{language: "elixir", content: "def hello, do: :world", line: 5}]

IO.inspect(result.tasks)
# [%{completed: false, text: "Todo item", line: 9},
#  %{completed: true, text: "Completed item", line: 10}]
```

## 📖 Features

### Core Parsing
- **Headings** - All levels (H1-H6) with line numbers
- **Links** - Markdown and reference-style links  
- **Code blocks** - Fenced and indented with language detection
- **Task lists** - GitHub-style checkboxes
- **Word counting** - SIMD-optimized text analysis

### Diff & Merge (Foundations)
- **Diff data model** for structure-aware markdown changes
- **JSON-LD semantic ops** types (add/remove/update triples)
- **Three-way merge skeleton** with conflict detection
- **Streaming event schema** for real-time patching
- **Inline diff ops** for text updates within blocks
- **JSON-LD stub extractor** with triple-level diff
  - Supports code fences (```json-ld) and simple frontmatter `jsonld: { ... }`
  - Basic context expansion: `@vocab`, prefixes, and term definitions map to IRIs

### Performance Optimizations
- **Zero-copy processing** - Direct binary manipulation
- **SIMD acceleration** - Vectorized pattern matching
- **Memory pooling** - Reduced allocation overhead
- **Pattern caching** - LRU cache for repeated structures
- **Parallel batch processing** - Both Elixir and Rust concurrency

### Batch Processing

```elixir
# Process multiple documents in parallel
documents = ["# Doc 1", "# Doc 2", "# Doc 3"]

# Elixir-side parallel processing  
{:ok, results} = MarkdownLd.parse_batch(documents, max_workers: 4)

# Rust-side parallel processing (fastest)
{:ok, results} = MarkdownLd.parse_batch_rust(documents)

# Stream processing with backpressure
results = MarkdownLd.parse_stream(document_stream, max_workers: 8)
```

### Performance Tracking

```elixir
# Get performance metrics
{:ok, stats} = MarkdownLd.get_performance_stats()
IO.inspect(stats)
# %{
#   "simd_operations" => 1_250_000,
#   "cache_hit_rate" => 85.2,
#   "memory_pool_usage" => 2_048_576,
#   "pattern_cache_size" => 128
# }

# Reset counters
MarkdownLd.reset_performance_stats()
```

## 🔀 Diffing

```elixir
old = """
# Title

Hello world

JSONLD: post:1, schema:name, Hello
"""

new = """
# Title

Hello brave new world

JSONLD: post:1, schema:name, Hello World
JSONLD: post:1, schema:author, Alice
"""

{:ok, patch} = MarkdownLd.diff(old, new, similarity_threshold: 0.5)
IO.inspect(Enum.map(patch.changes, & &1.kind))
# [:update_block, :jsonld_update, :jsonld_add]
```

### Streaming Diffs

```elixir
old = """
# Title

Para one

JSONLD: post:1, schema:name, Hello
"""

new = """
# Title

Para one updated

JSONLD: post:1, schema:name, Hello World
"""

events = MarkdownLd.Diff.Stream.emit(old, new, max_paragraphs: 2)
# => [%StreamEvent{type: :init_snapshot, ...}, %StreamEvent{type: :chunk_patch, ...}, %StreamEvent{type: :complete, ...}]

{:ok, rebuilt} = MarkdownLd.Diff.Stream.apply_events(old, events, max_paragraphs: 2)

### Heading-Level Chunking

```elixir
# Chunk by H1 sections (default), align by stable heading IDs
events = MarkdownLd.Diff.Stream.emit(old, new,
  chunk_strategy: :headings,
  heading_level: 1,
  rename_match_threshold: 0.7 # fuzzy-match renamed headings
)

# Chunk by H2 subsections
events = MarkdownLd.Diff.Stream.emit(old, new,
  chunk_strategy: :headings,
  heading_level: 2
)
```

## 🧩 Chunking Strategies

- Paragraphs (default): `chunk_strategy: :paragraphs`, `max_paragraphs: 8`.
- Headings: `chunk_strategy: :headings` to start a new chunk at each heading; events include a stable_id derived from the heading text.

## ⚔️ Conflict Formatting

```elixir
merge = MarkdownLd.Diff.three_way_merge(base_patch, our_patch, their_patch)
if merge.merged == nil do
  # Present conflicts in UI
  messages = MarkdownLd.Diff.Format.to_text(merge.conflicts)
  maps = MarkdownLd.Diff.Format.to_maps(merge.conflicts)
end
```

## ✨ Inline Preview

```elixir
# Given an update_block payload with inline_ops from the diff
ops = [{:keep, "Hello"}, {:delete, "brave"}, {:insert, "bold"}, {:keep, "world"}]
MarkdownLd.Diff.Preview.render_ops(ops)
# "Hello {-brave-} {+bold+} world"

# ANSI style
MarkdownLd.Diff.Preview.render_ops(ops, style: :ansi)
```
```

## ⚙️ Configuration

Configure default options in your `config.exs`:

```elixir
config :markdown_ld,
  # Performance options
  parallel: true,
  max_workers: System.schedulers_online(),
  
  # Optimization options  
  cache_patterns: true,
  track_performance: true,
  memory_pool_size: 1024 * 1024,  # 1MB
  pattern_cache_size: 500,
  
  # Processing options
  enable_tables: true,
  enable_strikethrough: true,
  enable_footnotes: true,
  
  # SIMD options (auto-detected)
  simd_enabled: true,
  simd_features: [:neon, :avx2],  # Auto-detected based on CPU
  
  # Batch processing
  batch_size: 100,
  batch_timeout: 5_000,  # 5 seconds
  
  # Development options
  debug_performance: false,
  log_slow_operations: true,
  slow_operation_threshold: 1000  # microseconds
```

### Runtime Configuration

You can also configure options at runtime:

```elixir
# Per-operation configuration
{:ok, result} = MarkdownLd.parse(content, 
  parallel: false,
  cache_patterns: true,
  track_performance: true,
  max_workers: 2
)

# Application-wide configuration  
Application.put_env(:markdown_ld, :max_workers, 8)
```

## 🏗️ Advanced Build System

MarkdownLd includes a comprehensive build system with multiple optimization profiles:

```bash
# Development build (fast compilation)
make dev

# Production build (maximum optimization)  
make prod

# Benchmark build (with profiling symbols)
make bench

# Profile-Guided Optimization
make pgo

# Run comprehensive benchmarks
make bench
```

### Build Profiles
- **`dev`** - Fast compilation with some optimization
- **`prod`** - Full LTO, maximum optimization, stripped binaries
- **`bench`** - Optimized with debug symbols for profiling
- **`pgo`** - Profile-Guided Optimization for additional 10-20% gains

## 📊 Benchmarks

Based on comprehensive benchmarking:

| Document Size | Processing Time | Throughput | vs Pure Elixir |
|---------------|----------------|------------|-----------------|
| Small (1KB)   | 3-7μs         | 150MB/s    | 10-20x faster   |
| Medium (10KB) | 5-10μs        | 1GB/s      | 10-20x faster   |
| Large (100KB) | 15-35μs       | 3GB/s      | 10-25x faster   |

### Extraction Functions
- **Word Count**: 226,027 KB/s
- **Link Extraction**: 875,855 KB/s  
- **Heading Extraction**: 333,659 KB/s
- **Code Block Extraction**: 3,503,418 KB/s

Run benchmarks yourself:
```bash
mix run bench/turbo_benchmark.exs
```

## 🚦 Production Usage

MarkdownLd is designed for high-throughput production systems:

### Scalability
- **Thousands of documents per second**
- **Configurable concurrency** (Elixir processes + Rust threads)
- **Memory-efficient** with pooled allocations
- **Graceful degradation** under load

### Reliability  
- **Comprehensive error handling**
- **Memory safety** (Rust + Elixir supervision)
- **Performance monitoring** with built-in metrics
- **Extensive test coverage**

### Integration
- **Zero dependencies** on external parsers
- **Compatible** with Phoenix, LiveView, GenServer
- **Streamable** for large document processing
- **Configurable** for different performance profiles

## 🔬 Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Elixir API    │───▶│   Rust NIF Core  │───▶│  SIMD Optimized │
│                 │    │                  │    │   Operations    │
│ • Batch Proc.   │    │ • Memory Pools   │    │ • Pattern Match │
│ • Streaming     │    │ • Pattern Cache  │    │ • String Ops    │
│ • Error Handle  │    │ • Parallel Proc. │    │ • Word Count    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🛠️ Development

```bash
# Install dependencies
make install

# Run tests
make test  

# Format code
make format

# Lint code
make lint

# Run benchmarks
make bench

# Generate documentation
make docs
```

## 📚 Documentation

- **[HexDocs](https://hexdocs.pm/markdown_ld)** - Complete API documentation
- **[Performance Report](PERFORMANCE_REPORT.md)** - Detailed benchmark results
- **[Build System](Makefile)** - Advanced build configuration

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Run the full test suite (`make ci`)
5. Submit a pull request

### Development Guidelines
- **Performance first** - All changes should maintain or improve performance
- **Comprehensive tests** - Include benchmarks for performance-critical code
- **Documentation** - Update docs for API changes
- **Backwards compatibility** - Follow semantic versioning

---

**MarkdownLd** - Built for production systems that demand extreme performance. 

Developed with ❤️ for the Elixir community.
## 🔎 Quick Links

- Diff API: `MarkdownLd.diff/3`
- Merge API: `MarkdownLd.Merge.merge_texts/4`
- Streaming: `MarkdownLd.Diff.Stream.emit/3` and `apply_events/3`
- Inline Preview: `MarkdownLd.Diff.Preview.render_ops/2`
- QCPrompt: `QCP.parse/1`, `QCP.Stream.process/1`
- Spec: `SPEC.md` (Markdown‑LD Profile v0.1)
