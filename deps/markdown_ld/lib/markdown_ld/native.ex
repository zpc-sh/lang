defmodule MarkdownLd.Native do
  @moduledoc """
  Native Rust functions for high-performance markdown processing.
  
  This module provides the interface to the underlying Rust implementation
  with SIMD optimizations, memory pooling, and advanced parsing capabilities.
  """

  use Rustler, otp_app: :markdown_ld, crate: "markdown_ld_nif"

  # Markdown parsing functions
  def parse_markdown(_content, _options), do: :erlang.nif_error(:nif_not_loaded)
  def parse_markdown_binary(_binary, _options), do: :erlang.nif_error(:nif_not_loaded)
  def parse_batch_parallel(_documents, _options), do: :erlang.nif_error(:nif_not_loaded)

  # SIMD-optimized extraction functions
  def word_count_simd(_content), do: :erlang.nif_error(:nif_not_loaded)
  def extract_links_simd(_content), do: :erlang.nif_error(:nif_not_loaded)
  def extract_headings_simd(_content), do: :erlang.nif_error(:nif_not_loaded)
  def extract_code_blocks_simd(_content), do: :erlang.nif_error(:nif_not_loaded)
  def extract_tasks_simd(_content), do: :erlang.nif_error(:nif_not_loaded)

  # Performance and caching functions
  def get_performance_stats(), do: :erlang.nif_error(:nif_not_loaded)
  def reset_performance_stats(), do: :erlang.nif_error(:nif_not_loaded)
  def clear_pattern_cache(), do: :erlang.nif_error(:nif_not_loaded)
end