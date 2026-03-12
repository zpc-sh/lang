defmodule Lang.Tokens.Calculator do
  @moduledoc """
  Comprehensive token calculation for AI model operations.

  This module provides accurate calculations for token efficiency, compression rates,
  and optimization metrics across different models and content types. It implements
  the formula for determining actual token loss/savings when using Lang's optimization
  techniques.

  ## Key Formulas

  - **Token Efficiency Ratio (TER)**: Measures the effectiveness of compressed
    content relative to original content while preserving semantic meaning
  - **Semantic Preservation Score (SPS)**: Calculates how well meaning is preserved
    after compression
  - **Effective Token Reduction (ETR)**: Calculates real-world token savings accounting
    for semantic preservation quality
  - **Optimization ROI**: Measures cost savings relative to compression overhead
  """

  alias Lang.Tokens.Estimate
  # alias Lang.Tokens.Types

  @doc """
  Calculate token efficiency metrics for original and compressed content.

  ## Parameters
  - `original`: Original text content
  - `compressed`: Compressed version of the content
  - `model`: Target model for token calculation (default: "gpt-4o")
  - `provider`: AI provider (default: :openai)
  - `semantic_score`: Optional pre-calculated semantic preservation score (0.0-1.0)

  ## Returns
  A map containing comprehensive token metrics:
  - `original_tokens`: Count of tokens in original content
  - `compressed_tokens`: Count of tokens in compressed content
  - `raw_savings`: Raw token count saved
  - `reduction_percentage`: Simple percentage reduction
  - `semantic_preservation`: Score indicating meaning preservation (0.0-1.0)
  - `effective_token_reduction`: Token savings adjusted for semantic preservation
  - `efficiency_ratio`: Token efficiency ratio (higher is better)
  - `compression_grade`: Letter grade (A+, A, B, etc.) for the compression quality
  - `estimated_cost_savings`: Cost savings in USD based on model pricing
  """
  @spec calculate_efficiency(String.t(), String.t(), String.t(), atom(), float() | nil) :: map()
  def calculate_efficiency(
        original,
        compressed,
        model \\ "gpt-4o",
        provider \\ :openai,
        semantic_score \\ nil
      ) do
    # Calculate token counts
    original_tokens = Estimate.estimate_tokens(original)
    compressed_tokens = Estimate.estimate_tokens(compressed)

    # Basic metrics
    raw_savings = max(0, original_tokens - compressed_tokens)
    reduction_percentage = if original_tokens > 0, do: raw_savings / original_tokens, else: 0.0

    # Calculate or use provided semantic preservation score
    semantic_preservation =
      semantic_score || calculate_semantic_preservation(original, compressed)

    # Calculate Effective Token Reduction (ETR)
    # This is our key formula that balances raw savings with meaning preservation
    effective_token_reduction = raw_savings * semantic_preservation

    # Calculate Token Efficiency Ratio (higher is better)
    efficiency_ratio =
      if compressed_tokens > 0,
        do: effective_token_reduction / compressed_tokens,
        else: 0.0

    # Calculate cost metrics
    cost_savings = calculate_cost_savings(raw_savings, model, provider)

    # Assign compression grade
    compression_grade = grade_compression(reduction_percentage, semantic_preservation)

    %{
      original_tokens: original_tokens,
      compressed_tokens: compressed_tokens,
      raw_savings: raw_savings,
      raw_reduction_percentage: Float.round(reduction_percentage * 100, 2),
      semantic_preservation: Float.round(semantic_preservation, 4),
      effective_token_reduction: round(effective_token_reduction),
      efficiency_ratio: Float.round(efficiency_ratio, 4),
      compression_grade: compression_grade,
      estimated_cost_savings: cost_savings
    }
  end

  @doc """
  Calculate the effectiveness of a context window optimization.

  Measures how well the compression technique preserves the most important
  information while reducing token count.

  ## Parameters
  - `original_context`: Original context window content
  - `optimized_context`: Optimized/compressed context
  - `query`: The query or task that will use this context
  - `model`: Target model (default: "gpt-4o")
  - `provider`: AI provider (default: :openai)

  ## Returns
  Map containing context optimization metrics
  """
  @spec calculate_context_optimization(String.t(), String.t(), String.t(), String.t(), atom()) ::
          map()
  def calculate_context_optimization(
        original_context,
        optimized_context,
        query,
        model \\ "gpt-4o",
        provider \\ :openai
      ) do
    # Base efficiency metrics
    base_metrics = calculate_efficiency(original_context, optimized_context, model, provider)

    # Calculate query relevance preservation
    relevance_preservation = calculate_query_relevance(original_context, optimized_context, query)

    # Calculate Context Relevance Ratio - how well optimization preserves query-relevant information
    context_relevance_ratio = base_metrics.semantic_preservation * relevance_preservation

    # Effective Context Savings - tokens saved while maintaining relevant information
    effective_context_savings = base_metrics.raw_savings * context_relevance_ratio

    # Return enhanced metrics
    Map.merge(base_metrics, %{
      query_relevance_preservation: Float.round(relevance_preservation, 4),
      context_relevance_ratio: Float.round(context_relevance_ratio, 4),
      effective_context_savings: round(effective_context_savings)
    })
  end

  @doc """
  Calculate token savings over time for a streaming session.

  ## Parameters
  - `session_metrics`: List of maps containing token metrics for each update
      Each map should contain at minimum:
      - `original_tokens`: Number of tokens in original content
      - `compressed_tokens`: Number of tokens in compressed content
      - `timestamp`: Timestamp of the update

  ## Returns
  Map with session-level token savings metrics
  """
  @spec calculate_session_savings(list(map())) :: map()
  def calculate_session_savings(session_metrics) do
    total_original = Enum.reduce(session_metrics, 0, &(&1.original_tokens + &2))
    total_compressed = Enum.reduce(session_metrics, 0, &(&1.compressed_tokens + &2))

    total_savings = total_original - total_compressed
    average_reduction = if total_original > 0, do: total_savings / total_original, else: 0.0

    # Calculate savings rate per minute
    first_ts = List.first(session_metrics).timestamp
    last_ts = List.last(session_metrics).timestamp

    minutes = DateTime.diff(last_ts, first_ts) / 60
    savings_rate = if minutes > 0, do: total_savings / minutes, else: 0

    %{
      total_original_tokens: total_original,
      total_compressed_tokens: total_compressed,
      total_token_savings: total_savings,
      average_reduction_percentage: Float.round(average_reduction * 100, 2),
      session_duration_minutes: Float.round(minutes, 2),
      token_savings_per_minute: round(savings_rate),
      update_count: length(session_metrics)
    }
  end

  @doc """
  Evaluate the return on investment (ROI) for token optimization.

  ## Parameters
  - `original_tokens`: Count of tokens in original content
  - `compressed_tokens`: Count of tokens in compressed content
  - `model`: Target model for cost calculation
  - `provider`: AI provider
  - `compression_overhead_ms`: Time in milliseconds to perform compression

  ## Returns
  Map with ROI metrics
  """
  @spec calculate_optimization_roi(integer(), integer(), String.t(), atom(), integer()) :: map()
  def calculate_optimization_roi(
        original_tokens,
        compressed_tokens,
        model,
        provider,
        compression_overhead_ms
      ) do
    # Calculate cost savings
    token_savings = max(0, original_tokens - compressed_tokens)
    cost_savings = calculate_cost_savings(token_savings, model, provider)

    # Convert overhead to cost (rough estimate based on processing costs)
    # Assuming $0.02 per CPU-second for compression
    compression_cost = compression_overhead_ms / 1000 * 0.02

    # Calculate ROI metrics
    net_savings = cost_savings - compression_cost
    roi_percentage = if compression_cost > 0, do: net_savings / compression_cost * 100, else: 0.0

    %{
      token_savings: token_savings,
      cost_savings: Float.round(cost_savings, 6),
      compression_cost: Float.round(compression_cost, 6),
      net_savings: Float.round(net_savings, 6),
      roi_percentage: Float.round(roi_percentage, 2),
      is_profitable: net_savings > 0
    }
  end

  @doc """
  Calculate token efficiency gain across providers for the same content.

  ## Parameters
  - `original`: Original content
  - `compressed`: Compressed content
  - `providers`: List of {provider, model} tuples to compare

  ## Returns
  List of maps with comparative efficiency metrics
  """
  @spec compare_efficiency_across_providers(String.t(), String.t(), list({atom(), String.t()})) ::
          list(map())
  def compare_efficiency_across_providers(original, compressed, providers) do
    original_tokens = Estimate.estimate_tokens(original)
    compressed_tokens = Estimate.estimate_tokens(compressed)
    raw_savings = max(0, original_tokens - compressed_tokens)
    reduction_percentage = if original_tokens > 0, do: raw_savings / original_tokens, else: 0.0

    # Estimate semantic preservation once
    semantic_preservation = calculate_semantic_preservation(original, compressed)

    # Calculate for each provider
    Enum.map(providers, fn {provider, model} ->
      cost_savings = calculate_cost_savings(raw_savings, model, provider)

      %{
        provider: provider,
        model: model,
        original_tokens: original_tokens,
        compressed_tokens: compressed_tokens,
        raw_savings: raw_savings,
        reduction_percentage: Float.round(reduction_percentage * 100, 2),
        semantic_preservation: Float.round(semantic_preservation, 4),
        estimated_cost_savings: cost_savings
      }
    end)
    |> Enum.sort_by(& &1.estimated_cost_savings, :desc)
  end

  # Private helper functions

  # Calculate semantic preservation score between original and compressed content
  # This is our proprietary formula for estimating how well meaning is preserved
  defp calculate_semantic_preservation(original, compressed) do
    # Simple case - if compressed matches original exactly, perfect preservation
    if original == compressed,
      do: 1.0,
      else: do_calculate_semantic_preservation(original, compressed)
  end

  defp do_calculate_semantic_preservation(original, compressed) do
    # Core algorithm for semantic preservation
    # 1. Keyword preservation (do critical terms appear in both?)
    # 2. Structure preservation (are paragraph/section breaks maintained?)
    # 3. Content length ratio (very short summaries lose more information)
    # 4. Special token preservation (code syntax, math symbols, etc.)

    # Keyword preservation (higher weight)
    keyword_score = calculate_keyword_preservation(original, compressed)

    # Structure preservation
    structure_score = calculate_structure_preservation(original, compressed)

    # Content length ratio - penalty for excessive shortening
    length_ratio = String.length(compressed) / max(1, String.length(original))
    # Allow up to 33% reduction without penalty
    length_score = min(1.0, length_ratio * 1.5)

    # Special token preservation for code, math, etc.
    special_score = calculate_special_token_preservation(original, compressed)

    # Weighted combination of factors
    # The weights reflect our empirical findings on what matters most for meaning
    keyword_score * 0.60 +
      structure_score * 0.15 +
      length_score * 0.15 +
      special_score * 0.10
  end

  defp calculate_keyword_preservation(original, compressed) do
    # Extract keywords from original
    original_words = String.split(original, ~r/\s+/) |> Enum.filter(&(String.length(&1) > 3))

    # Count important keywords (unique non-stopwords)
    important_words = filter_important_words(original_words)

    # Check how many appear in compressed version
    compressed_words = String.split(compressed, ~r/\s+/)
    preserved_count = Enum.count(important_words, &Enum.member?(compressed_words, &1))

    # Calculate preservation ratio with diminishing returns for very long texts
    important_count = length(important_words)
    diminishing_factor = :math.sqrt(important_count) / important_count

    case important_count do
      0 -> 1.0
      _ -> preserved_count / important_count * (1 - diminishing_factor) + diminishing_factor
    end
  end

  defp filter_important_words(words) do
    # Remove stopwords and keep unique important words
    stopwords =
      ~w(the and or but for with this that these those from when where how what which who)

    words
    |> Enum.filter(&(String.length(&1) > 3 && !Enum.member?(stopwords, String.downcase(&1))))
    |> Enum.uniq()
  end

  defp calculate_structure_preservation(original, compressed) do
    # Examine paragraph structure
    original_paras = String.split(original, ~r/\n\n+/)
    compressed_paras = String.split(compressed, ~r/\n\n+/)

    # Calculate ratio of paragraph counts with ceiling
    para_ratio = min(1.0, length(compressed_paras) / max(1, length(original_paras)))

    # Check for code block preservation
    original_code_blocks = Regex.scan(~r/```[\s\S]*?```/, original) |> length()
    compressed_code_blocks = Regex.scan(~r/```[\s\S]*?```/, compressed) |> length()

    code_block_ratio =
      if original_code_blocks > 0,
        do: min(1.0, compressed_code_blocks / original_code_blocks),
        else: 1.0

    # Weighted average of structure metrics
    para_ratio * 0.7 + code_block_ratio * 0.3
  end

  defp calculate_special_token_preservation(original, compressed) do
    # Check preservation of special tokens like code syntax, math symbols, etc.
    special_patterns = [
      # Brackets and parentheses
      ~r/[{}()\[\]]/,
      # Operators
      ~r/[<>=%+*\/^-]/,
      # Math expressions
      ~r/\$[\s\S]*?\$/,
      # Inline code
      ~r/`[^`]+`/,
      # Code references like Module.function
      ~r/\b[A-Z][A-Za-z]*\.[A-Za-z]+\b/
    ]

    scores =
      Enum.map(special_patterns, fn pattern ->
        original_matches = Regex.scan(pattern, original) |> length()
        compressed_matches = Regex.scan(pattern, compressed) |> length()

        if original_matches > 0,
          do: min(1.0, compressed_matches / original_matches),
          else: 1.0
      end)

    # Average of pattern preservation scores
    Enum.sum(scores) / length(scores)
  end

  # Calculate cost savings for given token count
  defp calculate_cost_savings(token_savings, model, provider) do
    # Assume 70/30 split between input/output tokens for typical usage
    token_usage = %{
      input_tokens: round(token_savings * 0.7),
      output_tokens: round(token_savings * 0.3)
    }

    # Get cost calculation
    cost_result = Estimate.calculate(provider, model, token_usage)

    # Return total cost saved
    Map.get(cost_result, :total_cost, 0.0)
  end

  # Calculate query relevance preservation
  defp calculate_query_relevance(original, compressed, query) do
    # Simple relevance calculation based on query term preservation
    query_terms = String.split(query, ~r/\s+/) |> Enum.filter(&(String.length(&1) > 2))

    # Count query terms in original and compressed
    original_matches = count_term_matches(original, query_terms)
    compressed_matches = count_term_matches(compressed, query_terms)

    # Calculate preservation ratio
    if original_matches > 0,
      do: min(1.0, compressed_matches / original_matches),
      else: 1.0
  end

  defp count_term_matches(text, terms) do
    downcase_text = String.downcase(text)

    Enum.reduce(terms, 0, fn term, acc ->
      # Count occurrences of term in text
      term_regex = Regex.compile!("\\b#{Regex.escape(String.downcase(term))}\\b", "i")
      matches = Regex.scan(term_regex, downcase_text) |> length()
      acc + matches
    end)
  end

  # Grade compression based on reduction and semantic preservation
  defp grade_compression(reduction_percentage, semantic_preservation) do
    # This is Lang's proprietary grading scale for token optimization
    # It balances token reduction with meaning preservation

    # Calculate composite score (reduction * preservation^2)
    # We square preservation to heavily penalize meaning loss
    composite = reduction_percentage * :math.pow(semantic_preservation, 2)

    cond do
      # Our benchmarks for optimization quality
      # 50%+ reduction with 95%+ preservation
      composite >= 0.50 and semantic_preservation >= 0.95 -> "A++"
      # 40%+ reduction with 90%+ preservation
      composite >= 0.40 and semantic_preservation >= 0.90 -> "A+"
      # 30%+ reduction with 85%+ preservation
      composite >= 0.30 and semantic_preservation >= 0.85 -> "A"
      # 25%+ reduction with 80%+ preservation
      composite >= 0.25 and semantic_preservation >= 0.80 -> "B+"
      # 20%+ reduction with 75%+ preservation
      composite >= 0.20 and semantic_preservation >= 0.75 -> "B"
      # 15%+ reduction with 70%+ preservation
      composite >= 0.15 and semantic_preservation >= 0.70 -> "C+"
      # 10%+ reduction with 65%+ preservation
      composite >= 0.10 and semantic_preservation >= 0.65 -> "C"
      # 5%+ reduction with 60%+ preservation
      composite >= 0.05 and semantic_preservation >= 0.60 -> "D"
      # Poor compression or unacceptable meaning loss
      true -> "F"
    end
  end
end
