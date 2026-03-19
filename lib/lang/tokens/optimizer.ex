defmodule Lang.Tokens.Optimizer do
  @moduledoc """
  High-level interface for token optimization operations.

  This module provides a simple, task-oriented API for token optimization
  that leverages the underlying compression, calculation, and estimation
  functionality. It's designed for direct use in application code.

  ## Examples

      # Optimize a context window for a specific query
      {:ok, optimized} = Lang.Tokens.Optimizer.optimize_context(
        large_context,
        "How does authentication work?",
        target_reduction: 0.5
      )

      # Optimize code while preserving structure
      {:ok, optimized_code} = Lang.Tokens.Optimizer.optimize_code(
        source_code,
        language: "elixir",
        preserve_structure: true
      )

      # Create a streaming delta for efficient updates
      {:ok, delta} = Lang.Tokens.Optimizer.create_delta(old_content, new_content)
  """

  alias Lang.Tokens.Calculator
  alias Lang.Tokens.Compressor
  alias Lang.Tokens.Estimate
  alias Lang.Tokens.Filter

  @doc """
  Optimize a context window for a specific query or task.

  This is the primary method for reducing token usage in prompt context
  windows. It intelligently analyzes the content and query to preserve
  the most relevant information while reducing token count.

  ## Options

  - `:target_reduction` - Target reduction percentage (0.0-1.0, default: 0.4)
  - `:min_preservation` - Minimum semantic preservation threshold (0.0-1.0, default: 0.8)
  - `:strategy` - Optimization strategy (`:balanced`, `:aggressive`, `:conservative`, default: `:balanced`)
  - `:model` - Target model for optimization (default: "gpt-4o")
  - `:return_metrics` - Whether to return detailed metrics (default: false)

  ## Returns

  - `{:ok, optimized_content}` or
  - `{:ok, %{content: optimized_content, metrics: metrics}}` if return_metrics is true
  - `{:error, reason}` on failure
  """
  @spec optimize_context(String.t(), String.t(), keyword()) ::
          {:ok, String.t() | map()} | {:error, String.t()}
  def optimize_context(context, query, opts \\ []) do
    # Extract options
    target_reduction = Keyword.get(opts, :target_reduction, 0.4)
    min_preservation = Keyword.get(opts, :min_preservation, 0.8)
    strategy = Keyword.get(opts, :strategy, :balanced)
    model = Keyword.get(opts, :model, "gpt-4o")
    return_metrics = Keyword.get(opts, :return_metrics, false)

    # Validate inputs
    with :ok <- validate_target_reduction(target_reduction),
         :ok <- validate_min_preservation(min_preservation) do
      try do
        # Apply query-aware filtering first
        {:ok, filtered} = Filter.filter_by_relevance(context, query, min_relevance: 0.3)

        # Apply compression with the appropriate level
        compression_level = strategy_to_compression_level(strategy)
        {:ok, compressed} = Compressor.compress_content(filtered, level: compression_level)

        # Calculate metrics
        metrics = Calculator.calculate_context_optimization(context, compressed, query, model)

        # Check if we met our targets
        cond do
          # If preservation is too low, try a more conservative approach
          metrics.semantic_preservation < min_preservation && strategy != :conservative ->
            optimize_context(context, query, Keyword.put(opts, :strategy, :conservative))

          # If reduction is too low but preservation is good, try more aggressive approach
          metrics.raw_reduction_percentage < target_reduction * 100 &&
            metrics.semantic_preservation > min_preservation + 0.1 &&
              strategy != :aggressive ->
            optimize_context(context, query, Keyword.put(opts, :strategy, :aggressive))

          # Return the result
          return_metrics ->
            {:ok, %{content: compressed, metrics: metrics}}

          true ->
            {:ok, compressed}
        end
      rescue
        e -> {:error, "Optimization failed: #{Exception.message(e)}"}
      end
    end
  end

  @doc """
  Optimize code content while preserving structure and functionality.

  This method is specialized for code optimization, focusing on preserving
  syntax and structural elements that are critical for code understanding.

  ## Options

  - `:language` - Programming language (default: auto-detect)
  - `:preserve_structure` - Whether to preserve structural elements (default: true)
  - `:preserve_comments` - Whether to preserve comments (default: true)
  - `:return_metrics` - Whether to return detailed metrics (default: false)
  - `:target_reduction` - Target reduction percentage (0.0-1.0, default: 0.3)

  ## Returns

  - `{:ok, optimized_code}` or
  - `{:ok, %{content: optimized_code, metrics: metrics}}` if return_metrics is true
  - `{:error, reason}` on failure
  """
  @spec optimize_code(String.t(), keyword()) :: {:ok, String.t() | map()} | {:error, String.t()}
  def optimize_code(code, opts \\ []) do
    # Extract options
    language = Keyword.get(opts, :language)
    preserve_structure = Keyword.get(opts, :preserve_structure, true)
    preserve_comments = Keyword.get(opts, :preserve_comments, true)
    return_metrics = Keyword.get(opts, :return_metrics, false)
    target_reduction = Keyword.get(opts, :target_reduction, 0.3)

    try do
      # Detect language if not provided
      detected_language = language || detect_language(code)

      # Apply code-specific optimization
      compression_opts = [
        preserve_structure: preserve_structure,
        preserve_comments: preserve_comments,
        language: detected_language,
        target_reduction: target_reduction
      ]

      {:ok, optimized} = Compressor.compress_code(code, compression_opts)

      # Calculate metrics
      metrics = Calculator.calculate_efficiency(code, optimized)

      if return_metrics do
        {:ok, %{content: optimized, metrics: metrics}}
      else
        {:ok, optimized}
      end
    rescue
      e -> {:error, "Code optimization failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Create an optimized delta between old and new content for efficient streaming.

  This is useful for situations where content is being updated incrementally,
  such as in collaborative editing or streaming API responses.

  ## Options

  - `:format` - Delta format (`:simple`, `:jsonpatch`, `:semantic`, default: `:semantic`)
  - `:compression_level` - Compression level for the delta (default: :medium)

  ## Returns

  - `{:ok, delta}` - The compressed delta representation
  - `{:error, reason}` on failure
  """
  @spec create_delta(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def create_delta(old_content, new_content, opts \\ []) do
    # Extract options
    format = Keyword.get(opts, :format, :semantic)
    compression_level = Keyword.get(opts, :compression_level, :medium)

    try do
      # Create token-level delta
      case Compressor.compress_differential(old_content, new_content,
             format: format,
             level: compression_level
           ) do
        {:ok, delta} ->
          # Calculate metrics
          old_tokens = Estimate.estimate_tokens(new_content)
          delta_tokens = Estimate.estimate_tokens(inspect(delta))
          savings = old_tokens - delta_tokens
          savings_percentage = if old_tokens > 0, do: savings / old_tokens * 100, else: 0

          # Enhance delta with metrics
          enhanced_delta =
            Map.merge(delta, %{
              token_savings: savings,
              savings_percentage: Float.round(savings_percentage, 2)
            })

          {:ok, enhanced_delta}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, "Delta creation failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Provide recommendations for optimal token usage for a specific task.

  Analyzes content and usage patterns to suggest optimization strategies
  that would be most effective.

  ## Options

  - `:task_type` - The type of task (`:chat`, `:completion`, `:embedding`, etc.)
  - `:content_type` - Content type (`:code`, `:text`, `:documentation`, etc.)
  - `:model` - Target model (default: "gpt-4o")

  ## Returns

  - `{:ok, recommendations}` - Map of recommendations with expected savings
  - `{:error, reason}` on failure
  """
  @spec recommend_optimizations(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def recommend_optimizations(content, opts \\ []) do
    # Extract options
    task_type = Keyword.get(opts, :task_type, :completion)
    content_type = Keyword.get(opts, :content_type, :text)
    model = Keyword.get(opts, :model, "gpt-4o")

    try do
      # Analyze content characteristics
      token_count = Estimate.estimate_tokens(content)
      content_length = String.length(content)
      avg_token_length = content_length / max(1, token_count)

      # Generate optimization recommendations based on content analysis
      recommendations = %{
        strategies: recommend_strategies(content, task_type, content_type),
        estimated_savings: estimate_potential_savings(content, task_type, content_type, model),
        token_metrics: %{
          current_tokens: token_count,
          token_density: Float.round(avg_token_length, 2),
          estimated_cost: format_cost(estimate_cost(token_count, model))
        }
      }

      {:ok, recommendations}
    rescue
      e -> {:error, "Recommendation generation failed: #{Exception.message(e)}"}
    end
  end

  @doc """
  Generate an optimized version of content for embedding or processing.

  Creates an optimized, semantic-preserving version of content
  that maintains key information while reducing token usage.

  ## Options

  - `:target_reduction` - Target reduction percentage (0.0-1.0, default: 0.4)
  - `:optimization_mode` - Mode (`:lossless`, `:hybrid`, `:lossy`, default: `:hybrid`)
  - `:return_metrics` - Whether to return detailed metrics (default: false)

  ## Returns

  - `{:ok, optimized_content}` or
  - `{:ok, %{content: optimized_content, metrics: metrics}}` if return_metrics is true
  - `{:error, reason}` on failure
  """
  @spec optimize_for_embedding(String.t(), keyword()) ::
          {:ok, String.t() | map()} | {:error, String.t()}
  def optimize_for_embedding(content, opts \\ []) do
    # Extract options
    target_reduction = Keyword.get(opts, :target_reduction, 0.4)
    optimization_mode = Keyword.get(opts, :optimization_mode, :hybrid)
    return_metrics = Keyword.get(opts, :return_metrics, false)

    # Validate inputs
    with :ok <- validate_target_reduction(target_reduction) do
      try do
        # Apply compression with the appropriate mode
        {:ok, optimized} =
          Compressor.compress_content(content,
            mode: optimization_mode,
            target_reduction: target_reduction
          )

        # Calculate metrics
        metrics = Calculator.calculate_efficiency(content, optimized)

        if return_metrics do
          {:ok, %{content: optimized, metrics: metrics}}
        else
          {:ok, optimized}
        end
      rescue
        e -> {:error, "Embedding optimization failed: #{Exception.message(e)}"}
      end
    end
  end

  # Private helper functions

  defp validate_target_reduction(target)
       when is_float(target) and target >= 0.0 and target <= 0.9,
       do: :ok

  defp validate_target_reduction(_),
    do: {:error, "Target reduction must be a float between 0.0 and 0.9"}

  defp validate_min_preservation(min) when is_float(min) and min >= 0.5 and min <= 1.0, do: :ok

  defp validate_min_preservation(_),
    do: {:error, "Minimum preservation must be between 0.5 and 1.0"}

  defp strategy_to_compression_level(:conservative), do: :light
  defp strategy_to_compression_level(:balanced), do: :medium
  defp strategy_to_compression_level(:aggressive), do: :high
  defp strategy_to_compression_level(_), do: :medium

  defp detect_language(code) do
    # Simple language detection based on file extensions and syntax patterns
    cond do
      String.contains?(code, "defmodule") && String.contains?(code, "do:") -> "elixir"
      String.contains?(code, "function") && String.contains?(code, "=>") -> "javascript"
      String.contains?(code, "def ") && String.contains?(code, "self") -> "python"
      String.contains?(code, "fn") && String.contains?(code, "->") -> "rust"
      String.contains?(code, "import ") && String.contains?(code, "from") -> "python"
      String.contains?(code, "#include") -> "c++"
      true -> "text"
    end
  end

  defp recommend_strategies(_content, task_type, content_type) do
    # Base recommendations on content analysis
    base_strategies = [
      %{
        name: "Semantic Compression",
        description: "AI-powered semantic-preserving compression",
        expected_reduction: "30-50%",
        ideal_for: ["Large documents", "Context windows"]
      },
      %{
        name: "Query-Focused Filtering",
        description: "Keep only content relevant to the query",
        expected_reduction: "40-70%",
        ideal_for: ["RAG systems", "Search results"]
      }
    ]

    # Add task-specific strategies
    task_strategies =
      case task_type do
        :chat ->
          [
            %{
              name: "Chat History Pruning",
              description: "Remove redundant turns in chat history",
              expected_reduction: "30-60%",
              ideal_for: ["Long conversations", "Multi-turn chats"]
            }
          ]

        :embedding ->
          [
            %{
              name: "Embedding Optimization",
              description: "Focus on semantic signal for embeddings",
              expected_reduction: "20-40%",
              ideal_for: ["Vector databases", "Similarity search"]
            }
          ]

        _ ->
          []
      end

    # Add content-specific strategies
    content_strategies =
      case content_type do
        :code ->
          [
            %{
              name: "Code Structure Preservation",
              description: "Maintain code structure while reducing tokens",
              expected_reduction: "20-40%",
              ideal_for: ["Code explanation", "Code review"]
            }
          ]

        :documentation ->
          [
            %{
              name: "Documentation Summarization",
              description: "Preserve key information in documentation",
              expected_reduction: "40-60%",
              ideal_for: ["API docs", "Technical documentation"]
            }
          ]

        _ ->
          []
      end

    base_strategies ++ task_strategies ++ content_strategies
  end

  defp estimate_potential_savings(content, task_type, content_type, model) do
    # Base savings estimates on content type and task
    base_reduction =
      case {task_type, content_type} do
        {:chat, _} -> 0.45
        {_, :code} -> 0.35
        {_, :documentation} -> 0.55
        {_, :text} -> 0.40
        _ -> 0.30
      end

    # Calculate token count and potential savings
    token_count = Estimate.estimate_tokens(content)
    potential_savings = round(token_count * base_reduction)
    cost_savings = estimate_cost(potential_savings, model)

    %{
      tokens: potential_savings,
      percentage: Float.round(base_reduction * 100, 1),
      estimated_cost_savings: format_cost(cost_savings)
    }
  end

  defp estimate_cost(token_count, model) do
    # Simple cost estimation - assumes mixed input/output
    token_usage = %{
      input_tokens: round(token_count * 0.7),
      output_tokens: round(token_count * 0.3)
    }

    cost_result = Estimate.calculate(:openai, model, token_usage)
    Map.get(cost_result, :total_cost, 0.0)
  end

  defp format_cost(cost) when cost < 0.01, do: "$#{:erlang.float_to_binary(cost, decimals: 6)}"
  defp format_cost(cost), do: "$#{:erlang.float_to_binary(cost, decimals: 4)}"
end
