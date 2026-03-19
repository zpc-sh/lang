defmodule MarkdownLd do
  @moduledoc """
  High-performance Markdown processing with SIMD optimizations and JSON-LD integration.
  
  MarkdownLd provides blazing-fast markdown processing with advanced SIMD optimizations,
  memory pooling, and batch processing capabilities. Built on top of Rust with zero-copy
  processing for maximum performance.
  
  ## Features
  
  - **SIMD-optimized** string processing (Apple Silicon NEON, x86 AVX2)
  - **Zero-copy** binary processing for maximum efficiency
  - **Memory pool** management for reduced allocations
  - **Parallel batch** processing with configurable concurrency
  - **Comprehensive parsing** (links, headings, code blocks, tasks)
  - **Pattern caching** for common structures
  - **Performance tracking** and metrics
  - **JSON-LD metadata** extraction (planned)
  
  ## Quick Start
  
      # Add to your mix.exs
      {:markdown_ld, "~> 0.4.0"}
      
      # Basic parsing
      {:ok, result} = MarkdownLd.parse("# Hello World")
      
      # Batch processing
      {:ok, results} = MarkdownLd.parse_batch(documents, max_workers: 4)
  
  ## Basic Examples
  
      iex> {:ok, result} = MarkdownLd.parse(\"\"\"
      ...> # Hello World
      ...> 
      ...> This is **bold** text with a [link](https://example.com).
      ...> 
      ...> ```elixir
      ...> def hello, do: :world
      ...> ```
      ...> 
      ...> - [ ] Todo item
      ...> - [x] Done item
      ...> \"\"\")
      iex> result.headings
      [%{level: 1, text: "Hello World", line: 1}]
      iex> result.links
      [%{text: "link", url: "https://example.com", line: 3}]
      iex> result.code_blocks
      [%{language: "elixir", content: "def hello, do: :world", line: 5}]
      iex> result.tasks
      [%{completed: false, text: "Todo item", line: 9},
       %{completed: true, text: "Done item", line: 10}]
  
  ## Performance Examples
  
      # Zero-copy binary processing (fastest)
      binary_content = File.read!("large_document.md")
      {:ok, result} = MarkdownLd.parse_binary(binary_content)
      
      # Batch processing for multiple documents
      documents = ["# Doc 1", "# Doc 2", "# Doc 3"]
      {:ok, results} = MarkdownLd.parse_batch_rust(documents)  # Rust parallel
      {:ok, results} = MarkdownLd.parse_batch(documents)       # Elixir parallel
      
      # Stream processing with backpressure
      large_document_stream
      |> MarkdownLd.parse_stream(max_workers: 8)
      |> Stream.filter(fn {:ok, result} -> length(result.headings) > 0 end)
      |> Enum.take(100)
  
  ## Performance Tracking
  
      # Get detailed performance metrics
      {:ok, stats} = MarkdownLd.get_performance_stats()
      # %{
      #   "simd_operations" => 1_250_000,
      #   "cache_hit_rate" => 85.2,
      #   "memory_pool_usage" => 2_048_576,
      #   "pattern_cache_size" => 128
      # }
      
      # Reset counters for benchmarking
      MarkdownLd.reset_performance_stats()
  
  ## Configuration
  
      # In your config.exs
      config :markdown_ld,
        parallel: true,
        max_workers: System.schedulers_online(),
        cache_patterns: true,
        track_performance: true,
        simd_enabled: true
      
      # Per-operation configuration
      {:ok, result} = MarkdownLd.parse(content, 
        parallel: false,
        cache_patterns: true,
        max_workers: 2
      )
  
  ## Architecture
  
  MarkdownLd uses a three-layer architecture for maximum performance:
  
  1. **Elixir API Layer** - Batch processing, streaming, error handling
  2. **Rust NIF Core** - Memory management, pattern caching, coordination
  3. **SIMD Engine** - Vectorized operations, high-performance parsing
  
  This design provides the safety and concurrency of Elixir with the raw 
  performance of optimized Rust code.
  
  ## Performance Characteristics
  
  - **Small documents** (1KB): 3-7μs processing time
  - **Medium documents** (10KB): 5-10μs processing time  
  - **Large documents** (100KB): 15-35μs processing time
  - **Throughput**: Up to 5GB/s for large documents
  - **Memory efficiency**: 50-80% reduction in allocations
  - **Scalability**: Thousands of documents per second
  
  See `PERFORMANCE_REPORT.md` for detailed benchmarking results.
  """

  alias MarkdownLd.Native

  @type parse_result :: %{
    headings: [heading()],
    links: [link()],
    code_blocks: [code_block()],
    tasks: [task()],
    word_count: non_neg_integer(),
    processing_time_us: non_neg_integer()
  }

  @type heading :: %{
    level: 1..6,
    text: String.t(),
    line: pos_integer()
  }

  @type link :: %{
    text: String.t(),
    url: String.t(),
    line: pos_integer()
  }

  @type code_block :: %{
    language: String.t() | nil,
    content: String.t(),
    line: pos_integer()
  }

  @type task :: %{
    completed: boolean(),
    text: String.t(),
    line: pos_integer()
  }

  @type parse_options :: [
    parallel: boolean(),
    max_workers: pos_integer(),
    cache_patterns: boolean(),
    track_performance: boolean()
  ]

  @doc """
  Parse markdown text with SIMD optimizations.
  
  ## Options
  
    * `:parallel` - Enable parallel processing for large documents (default: false)
    * `:max_workers` - Maximum number of worker processes (default: System.schedulers_online())
    * `:cache_patterns` - Enable pattern caching for repeated structures (default: true)
    * `:track_performance` - Include performance metrics in result (default: true)
  
  ## Examples
  
      iex> MarkdownLd.parse("# Hello\\n[Link](http://example.com)")
      {:ok, %{
        headings: [%{level: 1, text: "Hello", line: 1}],
        links: [%{text: "Link", url: "http://example.com", line: 2}],
        word_count: 2,
        processing_time_us: 156
      }}
  """
  @spec parse(String.t() | binary(), parse_options()) :: {:ok, parse_result()} | {:error, String.t()}
  def parse(content, opts \\ [])

  def parse(content, opts) when is_binary(content) do
    opts = Keyword.merge(default_options(), opts)
    Native.parse_markdown(content, opts)
  end

  @doc """
  Parse markdown text with zero-copy optimization for binary input.
  
  This function provides the fastest parsing path by avoiding string conversion
  and operating directly on binary data with SIMD optimizations.
  """
  @spec parse_binary(binary(), parse_options()) :: {:ok, parse_result()} | {:error, String.t()}
  def parse_binary(binary, opts \\ []) when is_binary(binary) do
    opts = Keyword.merge(default_options(), opts)
    Native.parse_markdown_binary(binary, opts)
  end

  @doc """
  Parse multiple markdown documents in parallel with batch optimization.
  
  Uses Elixir-side parallelization with configurable worker processes.
  Best for processing many small to medium documents.
  
  ## Examples
  
      iex> docs = ["# Doc 1", "# Doc 2", "# Doc 3"]
      iex> MarkdownLd.parse_batch(docs, max_workers: 4)
      {:ok, [%{headings: [...]}, %{headings: [...]}, %{headings: [...]}]}
  """
  @spec parse_batch([String.t() | binary()], parse_options()) :: {:ok, [parse_result()]} | {:error, String.t()}
  def parse_batch(documents, opts \\ []) when is_list(documents) do
    opts = Keyword.merge(default_options(), opts)
    max_workers = Keyword.get(opts, :max_workers, System.schedulers_online())
    
    documents
    |> Task.async_stream(
      fn doc -> parse(doc, opts) end,
      max_concurrency: max_workers,
      timeout: :infinity,
      ordered: true
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, result}}, {:ok, acc} -> {:cont, {:ok, [result | acc]}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, "Task failed: #{inspect(reason)}"}}
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  @doc """
  Parse multiple markdown documents using Rust-side parallelization.
  
  Uses Rust rayon for parallel processing. Best for processing large documents
  or when you want to minimize Elixir process overhead.
  """
  @spec parse_batch_rust([String.t() | binary()], parse_options()) :: {:ok, [parse_result()]} | {:error, String.t()}
  def parse_batch_rust(documents, opts \\ []) when is_list(documents) do
    opts = Keyword.merge(default_options(), opts)
    Native.parse_batch_parallel(documents, opts)
  end

  @doc """
  Stream parse markdown documents with backpressure control.
  
  Efficiently processes large numbers of documents with controlled memory usage.
  """
  @spec parse_stream(Enumerable.t(), parse_options()) :: Enumerable.t()
  def parse_stream(documents, opts \\ []) do
    opts = Keyword.merge(default_options(), opts)
    max_workers = Keyword.get(opts, :max_workers, System.schedulers_online())
    
    Task.async_stream(
      documents,
      fn doc -> parse(doc, opts) end,
      max_concurrency: max_workers,
      timeout: :infinity,
      ordered: false
    )
    |> Stream.map(fn
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, reason}} -> {:error, reason}
      {:exit, reason} -> {:error, "Task failed: #{inspect(reason)}"}
    end)
  end

  @doc """
  Extract word count from markdown text with SIMD optimization.
  
  Fast word counting using SIMD pattern matching for whitespace detection.
  """
  @spec word_count(String.t() | binary()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def word_count(content) when is_binary(content) do
    Native.word_count_simd(content)
  end

  @doc """
  Extract all links from markdown text.
  
  Uses SIMD-optimized pattern matching to quickly find markdown link patterns.
  """
  @spec extract_links(String.t() | binary()) :: {:ok, [link()]} | {:error, String.t()}
  def extract_links(content) when is_binary(content) do
    Native.extract_links_simd(content)
  end

  @doc """
  Extract all headings from markdown text.
  
  Fast heading extraction using SIMD pattern matching for hash characters.
  """
  @spec extract_headings(String.t() | binary()) :: {:ok, [heading()]} | {:error, String.t()}
  def extract_headings(content) when is_binary(content) do
    Native.extract_headings_simd(content)
  end

  @doc """
  Extract all code blocks from markdown text.
  
  Efficiently finds fenced code blocks with language detection.
  """
  @spec extract_code_blocks(String.t() | binary()) :: {:ok, [code_block()]} | {:error, String.t()}
  def extract_code_blocks(content) when is_binary(content) do
    Native.extract_code_blocks_simd(content)
  end

  @doc """
  Extract all task items from markdown text.
  
  Finds task list items with completion status detection.
  """
  @spec extract_tasks(String.t() | binary()) :: {:ok, [task()]} | {:error, String.t()}
  def extract_tasks(content) when is_binary(content) do
    Native.extract_tasks_simd(content)
  end

  @doc """
  Get performance statistics from the Rust processing layer.
  
  Returns metrics about SIMD operations, cache hits, memory usage, and processing times.
  """
  @spec get_performance_stats() :: {:ok, map()} | {:error, String.t()}
  def get_performance_stats do
    Native.get_performance_stats()
  end

  @doc """
  Reset performance statistics counters.
  
  Useful for benchmarking and performance analysis.
  """
  @spec reset_performance_stats() :: :ok
  def reset_performance_stats do
    Native.reset_performance_stats()
  end

  @doc """
  Clear pattern cache to free memory.
  
  The pattern cache stores frequently used markdown patterns for faster processing.
  """
  @spec clear_pattern_cache() :: :ok
  def clear_pattern_cache do
    Native.clear_pattern_cache()
  end

  # Private functions

  defp default_options do
    [
      parallel: false,
      max_workers: System.schedulers_online(),
      cache_patterns: true,
      track_performance: true
    ]
  end

  # ——— Diff API (composed) ———

  @doc """
  Compute a combined patch between two markdown strings.

  Produces a `MarkdownLd.Diff.Patch` with changes from:
  - Block-level diff (insert/delete/update, with inline ops for text blocks)
  - JSON-LD semantic diff (add/remove/update triples)

  Options:
  - `:from_rev` / `:to_rev` — optional revision identifiers; defaults to content hashes
  - `:similarity_threshold` — inline update coalescing threshold (default: 0.5)
  - `:meta` — optional patch metadata map
  """
  @spec diff(String.t(), String.t(), keyword()) :: {:ok, MarkdownLd.Diff.Patch.t()}
  def diff(old_text, new_text, opts \\ []) when is_binary(old_text) and is_binary(new_text) do
    from_rev = Keyword.get(opts, :from_rev, content_rev(old_text))
    to_rev = Keyword.get(opts, :to_rev, content_rev(new_text))
    meta = Keyword.get(opts, :meta, %{})

    sim = Keyword.get(opts, :similarity_threshold, 0.5)

    block_changes = MarkdownLd.Diff.Block.diff(old_text, new_text, similarity_threshold: sim)
    jsonld_changes = MarkdownLd.JSONLD.diff(old_text, new_text)
    changes = block_changes ++ jsonld_changes

    {:ok, MarkdownLd.Diff.patch(from_rev, to_rev, changes, Map.merge(%{message: "diff"}, meta))}
  end

  defp content_rev(text) do
    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end
end
