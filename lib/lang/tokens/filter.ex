defmodule Lang.Tokens.Filter do
  @moduledoc """
  Advanced token filtering system with relevance scoring and context awareness.
  
  This module provides intelligent token filtering capabilities that:
  - Score tokens based on semantic relevance to the current context
  - Remove redundant or low-value tokens
  - Preserve important structural and semantic information
  - Support multiple filtering strategies (aggressive, balanced, conservative)
  """

  require Logger
  alias Lang.TextIntelligence.{AnalysisEngine, FormatDetector}
  alias Lang.Native.TreeParser

  @type filter_strategy :: :aggressive | :balanced | :conservative
  @type token_weight :: float()
  @type filter_result :: {:ok, %{tokens: list(), metrics: map()}} | {:error, term()}

  @doc """
  Filter tokens based on relevance and importance scoring.
  
  ## Parameters
  - `tokens` - List of tokens to filter
  - `context` - Current context information (file type, surrounding code, etc.)
  - `strategy` - Filtering strategy (:aggressive, :balanced, :conservative)
  - `target_reduction` - Target reduction percentage (0.0-1.0)
  
  ## Returns
  {:ok, %{tokens: filtered_tokens, metrics: filter_metrics}} | {:error, reason}
  """
  @spec filter_tokens(list(), map(), filter_strategy(), float()) :: filter_result()
  def filter_tokens(tokens, context, strategy \\ :balanced, target_reduction \\ 0.3) 
      when is_list(tokens) and is_map(context) and target_reduction >= 0.0 and target_reduction <= 1.0 do
    
    with {:ok, weighted_tokens} <- score_tokens(tokens, context),
         {:ok, filtered} <- apply_filtering_strategy(weighted_tokens, strategy, target_reduction),
         metrics <- calculate_metrics(tokens, filtered, strategy) do
      
      Logger.debug("Token filtering: #{length(tokens)} -> #{length(filtered)} tokens (#{Float.round(metrics.reduction_ratio * 100, 1)}% reduction)")
      
      {:ok, %{
        tokens: Enum.map(filtered, & &1.token),
        metrics: metrics
      }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Score individual tokens based on their relevance and importance.
  """
  @spec score_tokens(list(), map()) :: {:ok, list()} | {:error, term()}
  def score_tokens(tokens, context) when is_list(tokens) and is_map(context) do
    try do
      file_type = Map.get(context, :file_type, "unknown")
      language = Map.get(context, :language, detect_language(context))
      surrounding_context = Map.get(context, :surrounding_context, "")
      
      weighted_tokens = 
        tokens
        |> Enum.with_index()
        |> Enum.map(fn {token, index} ->
          weight = calculate_token_weight(token, index, length(tokens), %{
            file_type: file_type,
            language: language,
            surrounding_context: surrounding_context,
            semantic_context: extract_semantic_context(tokens, index)
          })
          
          %{token: token, weight: weight, index: index}
        end)
      
      {:ok, weighted_tokens}
    rescue
      error -> {:error, {:scoring_failed, error}}
    end
  end

  # Calculate importance weight for a single token
  defp calculate_token_weight(token, index, total_tokens, context) do
    base_weight = 0.5
    
    # Position-based scoring (beginning and end are more important)
    position_weight = calculate_position_weight(index, total_tokens)
    
    # Content-based scoring
    content_weight = calculate_content_weight(token, context)
    
    # Semantic scoring based on context
    semantic_weight = calculate_semantic_weight(token, context)
    
    # Structural importance (keywords, operators, etc.)
    structural_weight = calculate_structural_weight(token, context.language)
    
    # Combine weights with different priorities
    final_weight = 
      base_weight * 0.1 +
      position_weight * 0.2 +
      content_weight * 0.3 +
      semantic_weight * 0.25 +
      structural_weight * 0.15
    
    # Clamp to [0.0, 1.0]
    max(0.0, min(1.0, final_weight))
  end

  # Position-based weight calculation
  defp calculate_position_weight(index, total_tokens) do
    relative_pos = index / max(total_tokens - 1, 1)
    
    cond do
      # Beginning tokens are important
      relative_pos <= 0.1 -> 0.9
      # End tokens are important
      relative_pos >= 0.9 -> 0.8
      # Middle tokens get variable weight
      true -> 0.3 + 0.4 * :math.sin(relative_pos * :math.pi())
    end
  end

  # Content-based weight calculation
  defp calculate_content_weight(token, context) do
    token_str = to_string(token)
    
    cond do
      # Empty or whitespace-only tokens
      String.trim(token_str) == "" -> 0.1
      
      # Very short tokens (single chars, except important ones)
      String.length(token_str) == 1 and not important_single_char?(token_str) -> 0.2
      
      # Common stop words/patterns
      is_stop_word?(token_str) -> 0.15
      
      # Important keywords for the language
      is_language_keyword?(token_str, context.language) -> 0.9
      
      # Identifiers and names
      is_identifier?(token_str) -> 0.7
      
      # Literals (strings, numbers)
      is_literal?(token_str) -> 0.6
      
      # Default weight for other content
      true -> 0.5
    end
  end

  # Semantic weight based on surrounding context
  defp calculate_semantic_weight(token, context) do
    token_str = to_string(token)
    semantic_ctx = Map.get(context, :semantic_context, %{})
    
    # Check if token appears in important semantic contexts
    weight = 0.5
    
    # Boost weight if token is part of function/class definitions
    weight = if appears_in_definition?(token_str, semantic_ctx), do: weight + 0.3, else: weight
    
    # Boost weight if token is part of type annotations
    weight = if appears_in_types?(token_str, semantic_ctx), do: weight + 0.2, else: weight
    
    # Boost weight if token relates to control flow
    weight = if is_control_flow?(token_str), do: weight + 0.25, else: weight
    
    # Reduce weight for repeated tokens (diminishing returns)
    repetition_penalty = calculate_repetition_penalty(token_str, semantic_ctx)
    weight * (1.0 - repetition_penalty)
  end

  # Structural importance weight
  defp calculate_structural_weight(token, language) do
    token_str = to_string(token)
    
    case language do
      lang when lang in ["elixir", "erlang"] ->
        cond do
          token_str in ["def", "defp", "defmodule", "defstruct", "defprotocol"] -> 1.0
          token_str in ["do", "end", "when", "case", "if", "unless"] -> 0.9
          token_str in ["->", "|>", "<-", "=", "==", "!="] -> 0.8
          String.starts_with?(token_str, "@") -> 0.7  # Attributes
          String.starts_with?(token_str, ":") -> 0.6  # Atoms
          true -> 0.4
        end
      
      lang when lang in ["javascript", "typescript"] ->
        cond do
          token_str in ["function", "class", "const", "let", "var"] -> 1.0
          token_str in ["if", "else", "for", "while", "switch", "case"] -> 0.9
          token_str in ["=>", "===", "!==", "&&", "||"] -> 0.8
          token_str in ["async", "await", "promise"] -> 0.7
          true -> 0.4
        end
      
      lang when lang in ["python"] ->
        cond do
          token_str in ["def", "class", "import", "from"] -> 1.0
          token_str in ["if", "elif", "else", "for", "while", "try", "except"] -> 0.9
          token_str in ["==", "!=", "and", "or", "not"] -> 0.8
          token_str in ["self", "cls", "__init__"] -> 0.7
          true -> 0.4
        end
      
      _ -> 0.5  # Default for unknown languages
    end
  end

  # Apply filtering strategy to weighted tokens
  defp apply_filtering_strategy(weighted_tokens, strategy, target_reduction) do
    total_tokens = length(weighted_tokens)
    target_count = round(total_tokens * (1.0 - target_reduction))
    
    # Sort by weight (descending) and take top tokens
    sorted_tokens = Enum.sort_by(weighted_tokens, & &1.weight, :desc)
    
    # Apply strategy-specific adjustments
    kept_tokens = case strategy do
      :aggressive ->
        # Very selective, only keep highest weighted tokens
        Enum.take(sorted_tokens, max(target_count, round(total_tokens * 0.2)))
      
      :balanced ->
        # Standard approach, respect target reduction
        Enum.take(sorted_tokens, target_count)
      
      :conservative ->
        # Keep more tokens, lower reduction
        conservative_target = max(target_count, round(total_tokens * 0.7))
        Enum.take(sorted_tokens, conservative_target)
    end
    
    # Sort back to original order
    result = 
      kept_tokens
      |> Enum.sort_by(& &1.index)
    
    {:ok, result}
  end

  # Calculate filtering metrics
  defp calculate_metrics(original_tokens, filtered_tokens, strategy) do
    original_count = length(original_tokens)
    filtered_count = length(filtered_tokens)
    reduction_ratio = if original_count > 0, do: (original_count - filtered_count) / original_count, else: 0.0
    
    # Calculate token diversity metrics
    original_unique = original_tokens |> Enum.uniq() |> length()
    filtered_unique = Enum.map(filtered_tokens, & &1.token) |> Enum.uniq() |> length()
    
    diversity_retention = if original_unique > 0, do: filtered_unique / original_unique, else: 0.0
    
    %{
      original_count: original_count,
      filtered_count: filtered_count,
      reduction_ratio: reduction_ratio,
      strategy: strategy,
      diversity_retention: diversity_retention,
      compression_efficiency: calculate_compression_efficiency(original_tokens, filtered_tokens)
    }
  end

  # Helper functions for token analysis
  defp detect_language(%{file_path: path}) when is_binary(path) do
    FormatDetector.detect_from_uri(path) || "unknown"
  end
  defp detect_language(_), do: "unknown"

  defp extract_semantic_context(tokens, index) do
    # Get surrounding tokens for context
    start_idx = max(0, index - 5)
    end_idx = min(length(tokens) - 1, index + 5)
    
    context_tokens = Enum.slice(tokens, start_idx, end_idx - start_idx + 1)
    context_string = Enum.join(context_tokens, " ")
    
    %{
      surrounding_tokens: context_tokens,
      context_string: context_string,
      token_frequencies: calculate_token_frequencies(tokens)
    }
  end

  defp important_single_char?(char) do
    char in ["(", ")", "{", "}", "[", "]", ";", ":", ",", ".", "=", "+", "-", "*", "/"]
  end

  defp is_stop_word?(token) do
    stop_words = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"]
    String.downcase(token) in stop_words
  end

  defp is_language_keyword?(token, language) do
    keywords = case language do
      "elixir" -> ["def", "defp", "defmodule", "do", "end", "if", "unless", "case", "cond", "when"]
      "javascript" -> ["function", "const", "let", "var", "if", "else", "for", "while", "return"]
      "python" -> ["def", "class", "if", "elif", "else", "for", "while", "try", "except", "import"]
      _ -> []
    end
    
    token in keywords
  end

  defp is_identifier?(token) do
    String.match?(token, ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/)
  end

  defp is_literal?(token) do
    # Check for string literals, numbers, etc.
    String.match?(token, ~r/^(".*"|'.*'|\d+\.?\d*|true|false|nil|null)$/)
  end

  defp appears_in_definition?(token, semantic_ctx) do
    context_str = Map.get(semantic_ctx, :context_string, "")
    String.match?(context_str, ~r/\b(def|defp|defmodule|class|function)\s+.*#{Regex.escape(token)}/i)
  end

  defp appears_in_types?(token, semantic_ctx) do
    context_str = Map.get(semantic_ctx, :context_string, "")
    String.match?(context_str, ~r/\b(::|\s*:\s*|@type|@spec).*#{Regex.escape(token)}/i)
  end

  defp is_control_flow?(token) do
    token in ["if", "else", "elif", "unless", "case", "when", "cond", "for", "while", "loop", "break", "continue", "return", "yield"]
  end

  defp calculate_repetition_penalty(token, semantic_ctx) do
    frequencies = Map.get(semantic_ctx, :token_frequencies, %{})
    frequency = Map.get(frequencies, token, 1)
    
    # Diminishing returns for repeated tokens
    case frequency do
      1 -> 0.0
      2 -> 0.1
      3 -> 0.2
      4 -> 0.3
      _ -> 0.4  # Cap penalty at 40%
    end
  end

  defp calculate_token_frequencies(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc ->
      token_str = to_string(token)
      Map.update(acc, token_str, 1, &(&1 + 1))
    end)
  end

  defp calculate_compression_efficiency(original_tokens, filtered_tokens) do
    # Simple heuristic: measure information density
    if length(original_tokens) > 0 do
      original_chars = original_tokens |> Enum.join("") |> String.length()
      filtered_chars = Enum.map(filtered_tokens, & &1.token) |> Enum.join("") |> String.length()
      
      if original_chars > 0, do: filtered_chars / original_chars, else: 0.0
    else
      0.0
    end
  end
end
