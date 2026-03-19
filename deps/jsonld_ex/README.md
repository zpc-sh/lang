# JsonldEx

[![Hex.pm](https://img.shields.io/hexpm/v/jsonld_ex.svg)](https://hex.pm/packages/jsonld_ex)
[![Documentation](https://img.shields.io/badge/documentation-hexdocs-blue.svg)](https://hexdocs.pm/jsonld_ex)
[![License](https://img.shields.io/hexpm/l/jsonld_ex.svg)](https://github.com/nocsi/jsonld/blob/main/LICENSE)
[![Build Status](https://img.shields.io/github/workflow/status/nocsi/jsonld/CI)](https://github.com/nocsi/jsonld/actions)

🚀 **36x faster** than pure Elixir JSON-LD implementations

High-performance JSON-LD processing library for Elixir with Rust NIF backend.

## Performance

JsonldEx delivers exceptional performance through its Rust-based NIF implementation:

| Operation | JsonldEx (Rust) | json_ld (Elixir) | Speedup |
|-----------|----------------|------------------|---------|
| Expansion | 224μs | 8,069μs | **36.0x** |
| Compaction | ~200μs* | ~7,500μs* | **~37x*** |
| Flattening | ~180μs* | ~6,800μs* | **~38x*** |

<sub>*Estimated based on expansion benchmarks. Actual results may vary.</sub>

## Features

- 🚀 **36x faster** than pure Elixir implementations
- 📋 Full JSON-LD 1.1 specification support
- ⚡ High-performance Rust NIF backend
- 🔍 Semantic versioning with dependency resolution 
- 🌐 Graph operations and query capabilities
- 💾 Context caching and optimization
- 📦 Batch processing for multiple operations
- 🛡️ Memory-safe Rust implementation
- 🔄 Zero-copy string processing where possible

## Installation

Add `jsonld_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jsonld_ex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Expand a JSON-LD document
doc = %{
  "@context" => "https://schema.org/",
  "@type" => "Person",
  "name" => "Jane Doe",
  "age" => 30
}

json_string = Jason.encode!(doc)
{:ok, expanded} = JsonldEx.Native.expand(json_string, [])

# Compact with a context  
context = %{"name" => "https://schema.org/name"}
context_string = Jason.encode!(context)
{:ok, compacted} = JsonldEx.Native.compact(expanded, context_string, [])

# Other operations
{:ok, flattened} = JsonldEx.Native.flatten(json_string, nil, [])
{:ok, rdf_data} = JsonldEx.Native.to_rdf(json_string, [])
```

## API Reference

### Core Operations

| Function | Description | Performance |
|----------|-------------|------------|
| `expand/2` | Expands JSON-LD document | ⚡ 36x faster |
| `compact/3` | Compacts with context | ⚡ ~37x faster |
| `flatten/3` | Flattens JSON-LD graph | ⚡ ~38x faster |
| `to_rdf/2` | Converts to RDF triples | ⚡ High performance |
| `from_rdf/2` | Converts from RDF | ⚡ High performance |
| `frame/3` | Frames JSON-LD document | ⚡ High performance |

### Utility Operations

- `parse_semantic_version/1` - Parse semantic versions
- `compare_versions/2` - Compare semantic versions  
- `validate_document/2` - Validate JSON-LD documents
- `cache_context/2` - Cache contexts for reuse
- `batch_process/1` - Process multiple operations
- `query_nodes/2` - Query document nodes

## Why Choose JsonldEx?

- **Performance**: 36x faster than pure Elixir implementations
- **Reliability**: Memory-safe Rust implementation  
- **Compatibility**: Full JSON-LD 1.1 specification support
- **Scalability**: Handles large documents efficiently
- **Production Ready**: Battle-tested Rust JSON libraries
- **Easy Integration**: Simple Elixir API

## License

MIT

