defmodule Lang.Workers.ContentSearchWorker do
  @moduledoc """
  Content Search Worker for analyzing and indexing document content.

  This worker performs deep content analysis including full-text search indexing,
  semantic analysis, and content classification for documents processed by the
  file system scanner.

  ## Features

  - **Full-Text Indexing** - Build searchable indexes of document content
  - **Semantic Analysis** - Extract semantic meaning and topics from text
  - **Content Classification** - Categorize documents by type and domain
  - **Keyword Extraction** - Identify important terms and phrases
  - **Language Detection** - Determine the language of text content
  - **Similarity Analysis** - Find related documents based on content similarity

  ## Usage

      # Queue content search job
      job = ContentSearchWorker.new(%{
        file_id: file.id,
        content: file_content,
        metadata: %{format: "markdown", language: "en"}
      })
      |> Oban.insert()

  """

  use Oban.Worker, queue: :analysis, max_attempts: 3

  alias Lang.Analysis
  alias Lang.Native
  alias Kyozo.Lang.UniversalParser
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    file_id = args["file_id"]
    content = args["content"]
    metadata = args["metadata"] || %{}

    Logger.info("Starting content search analysis", file_id: file_id, size: byte_size(content))

    try do
      # Parse and analyze content using UniversalParser
      {:ok, document} =
        UniversalParser.parse(content,
          include_analysis: true,
          include_insights: true
        )

      # Perform content search analysis
      search_results = %{
        full_text_index: build_full_text_index(content, document),
        semantic_analysis: extract_semantic_features(document),
        content_classification: classify_content(document),
        keywords: extract_keywords(document),
        language_detection: detect_language(content),
        similarity_vectors: build_similarity_vectors(document)
      }

      # Store results in database
      case Analysis.update_analyzed_file(file_id, %{
             search_index: search_results.full_text_index,
             semantic_features: search_results.semantic_analysis,
             content_classification: search_results.content_classification,
             extracted_keywords: search_results.keywords,
             detected_language: search_results.language_detection,
             similarity_vectors: search_results.similarity_vectors,
             search_indexed_at: DateTime.utc_now()
           }) do
        {:ok, _updated_file} ->
          Logger.info("Content search analysis completed successfully", file_id: file_id)
          :ok

        {:error, reason} ->
          Logger.error("Failed to store content search results", file_id: file_id, reason: reason)
          {:error, {:storage_failed, reason}}
      end
    rescue
      error ->
        Logger.error("Content search analysis failed",
          file_id: file_id,
          error: Exception.message(error)
        )

        {:error, {:analysis_failed, error}}
    end
  end

  # === Private Functions ===

  defp build_full_text_index(content, document) do
    # Extract searchable text tokens
    words = extract_words(content)

    # Build term frequency map
    term_frequencies = calculate_term_frequencies(words)

    # Extract important phrases (2-3 word combinations)
    phrases = extract_phrases(words)

    # Build searchable index
    %{
      word_count: length(words),
      unique_terms: map_size(term_frequencies),
      term_frequencies: term_frequencies,
      important_phrases: phrases,
      searchable_text: String.downcase(content),
      format: document.format,
      structure_keywords: extract_structure_keywords(document)
    }
  end

  defp extract_words(content) do
    content
    |> String.downcase()
    # Remove punctuation but keep apostrophes in contractions
    |> String.replace(~r/[^\w\s']/, " ")
    |> String.split()
    |> Enum.reject(&(String.length(&1) < 2))
    |> remove_stop_words()
  end

  defp remove_stop_words(words) do
    stop_words =
      MapSet.new([
        "the",
        "a",
        "an",
        "and",
        "or",
        "but",
        "in",
        "on",
        "at",
        "to",
        "for",
        "of",
        "with",
        "by",
        "is",
        "are",
        "was",
        "were",
        "be",
        "been",
        "have",
        "has",
        "had",
        "do",
        "does",
        "did",
        "will",
        "would",
        "could",
        "should",
        "this",
        "that",
        "these",
        "those",
        "i",
        "you",
        "he",
        "she",
        "it",
        "we",
        "they"
      ])

    Enum.reject(words, &MapSet.member?(stop_words, &1))
  end

  defp calculate_term_frequencies(words) do
    total_words = length(words)

    words
    |> Enum.frequencies()
    |> Map.new(fn {term, count} -> {term, count / total_words} end)
  end

  defp extract_phrases(words) do
    # Extract 2-grams and 3-grams
    bigrams = extract_ngrams(words, 2)
    trigrams = extract_ngrams(words, 3)

    (bigrams ++ trigrams)
    |> Enum.frequencies()
    |> Enum.filter(fn {_phrase, freq} -> freq > 1 end)
    |> Enum.sort_by(fn {_phrase, freq} -> freq end, :desc)
    |> Enum.take(20)
    |> Map.new()
  end

  defp extract_ngrams(words, n) do
    words
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.map(&Enum.join(&1, " "))
  end

  defp extract_structure_keywords(document) do
    keywords = []

    # Extract from headers if available
    keywords =
      case document.structure do
        %{headers: headers} when is_list(headers) ->
          header_words =
            headers
            |> Enum.map(&String.downcase/1)
            |> Enum.flat_map(&String.split/1)

          keywords ++ header_words

        _ ->
          keywords
      end

    # Extract from code blocks if available
    keywords =
      case document.structure do
        %{code_blocks: blocks} when is_list(blocks) ->
          code_keywords =
            blocks
            |> Enum.map(fn block -> Map.get(block, :language, "") end)
            |> Enum.reject(&(&1 == ""))

          keywords ++ code_keywords

        _ ->
          keywords
      end

    Enum.uniq(keywords)
  end

  defp extract_semantic_features(document) do
    %{
      topics: extract_topics(document),
      entities: extract_named_entities(document),
      sentiment: analyze_sentiment(document),
      complexity: calculate_semantic_complexity(document),
      domain: classify_domain(document)
    }
  end

  defp extract_topics(document) do
    # Simple topic extraction based on high-frequency meaningful terms
    case document.structure do
      %{term_frequencies: freqs} ->
        freqs
        |> Enum.filter(fn {term, freq} -> freq > 0.01 and String.length(term) > 3 end)
        |> Enum.sort_by(fn {_term, freq} -> freq end, :desc)
        |> Enum.take(10)
        |> Enum.map(fn {term, _freq} -> term end)

      _ ->
        []
    end
  end

  defp extract_named_entities(document) do
    # Basic named entity recognition using patterns
    content = document.content

    # Find capitalized words (potential proper nouns)
    proper_nouns =
      Regex.scan(~r/\b[A-Z][a-z]+\b/, content)
      |> Enum.map(&List.first/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_entity, count} -> count > 1 end)
      |> Map.new()

    # Find email addresses
    emails =
      Regex.scan(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, content)
      |> Enum.map(&List.first/1)

    # Find URLs
    urls =
      Regex.scan(~r/https?:\/\/[^\s]+/, content)
      |> Enum.map(&List.first/1)

    %{
      proper_nouns: proper_nouns,
      emails: emails,
      urls: urls
    }
  end

  defp analyze_sentiment(document) do
    # Simple sentiment analysis based on positive/negative word counts
    content = String.downcase(document.content)

    positive_words = [
      "good",
      "great",
      "excellent",
      "amazing",
      "wonderful",
      "fantastic",
      "love",
      "like",
      "enjoy",
      "happy",
      "pleased",
      "satisfied"
    ]

    negative_words = [
      "bad",
      "terrible",
      "awful",
      "hate",
      "dislike",
      "angry",
      "sad",
      "disappointed",
      "frustrated",
      "annoying",
      "boring",
      "difficult"
    ]

    positive_count = Enum.count(positive_words, &String.contains?(content, &1))
    negative_count = Enum.count(negative_words, &String.contains?(content, &1))

    total_sentiment_words = positive_count + negative_count

    cond do
      total_sentiment_words == 0 -> :neutral
      positive_count > negative_count -> :positive
      negative_count > positive_count -> :negative
      true -> :neutral
    end
  end

  defp calculate_semantic_complexity(document) do
    case document.analysis do
      %{complexity_score: score} -> score
      # Default moderate complexity
      _ -> 5.0
    end
  end

  defp classify_domain(document) do
    content = String.downcase(document.content)

    # Technical domains
    cond do
      String.contains?(content, ["code", "function", "api", "database", "server"]) ->
        "technical"

      String.contains?(content, ["business", "market", "sales", "revenue", "customer"]) ->
        "business"

      String.contains?(content, ["research", "study", "analysis", "hypothesis", "data"]) ->
        "research"

      String.contains?(content, ["tutorial", "guide", "how-to", "instructions", "steps"]) ->
        "educational"

      true ->
        "general"
    end
  end

  defp classify_content(document) do
    format = document.format

    # Base classification on format
    base_type =
      case format do
        "markdown" -> "documentation"
        "json" -> "data"
        "yaml" -> "configuration"
        format when format in ["javascript", "python", "elixir"] -> "code"
        _ -> "text"
      end

    # Refine based on content
    content = String.downcase(document.content)

    refined_type =
      cond do
        String.contains?(content, ["readme", "documentation", "guide"]) -> "documentation"
        String.contains?(content, ["test", "spec", "describe", "it("]) -> "test"
        String.contains?(content, ["config", "settings", "environment"]) -> "configuration"
        String.contains?(content, ["api", "endpoint", "route", "controller"]) -> "api"
        true -> base_type
      end

    %{
      format: format,
      base_type: base_type,
      refined_type: refined_type,
      confidence: calculate_classification_confidence(document, refined_type)
    }
  end

  defp calculate_classification_confidence(document, classification) do
    # Simple confidence based on how well the content matches the classification
    content = String.downcase(document.content)

    confidence_indicators =
      case classification do
        "documentation" -> ["readme", "doc", "guide", "tutorial", "how", "what", "why"]
        "test" -> ["test", "spec", "describe", "it", "expect", "assert"]
        "configuration" -> ["config", "setting", "env", "port", "host", "key"]
        "api" -> ["api", "endpoint", "route", "get", "post", "put", "delete"]
        "code" -> ["function", "class", "method", "variable", "return", "import"]
        _ -> []
      end

    matches = Enum.count(confidence_indicators, &String.contains?(content, &1))
    min(0.9, 0.5 + matches * 0.1)
  end

  defp extract_keywords(document) do
    case document.structure do
      %{term_frequencies: freqs} ->
        # Get top keywords by frequency, filtering out very common words
        freqs
        |> Enum.filter(fn {term, freq} ->
          freq > 0.005 and String.length(term) > 2 and not too_common?(term)
        end)
        |> Enum.sort_by(fn {_term, freq} -> freq end, :desc)
        |> Enum.take(15)
        |> Map.new()

      _ ->
        # Fallback: extract from content directly
        extract_fallback_keywords(document.content)
    end
  end

  defp too_common?(term) do
    common_words = [
      "will",
      "can",
      "may",
      "also",
      "each",
      "some",
      "more",
      "use",
      "used",
      "make",
      "way",
      "work",
      "part",
      "time",
      "get",
      "new",
      "see",
      "know"
    ]

    term in common_words
  end

  defp extract_fallback_keywords(content) do
    content
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(&(String.length(&1) < 4))
    |> remove_stop_words()
    |> Enum.frequencies()
    |> Enum.filter(fn {_term, count} -> count > 1 end)
    |> Enum.sort_by(fn {_term, count} -> count end, :desc)
    |> Enum.take(10)
    |> Map.new()
  end

  defp detect_language(content) do
    # Simple language detection based on common words
    content_lower = String.downcase(content)

    # English indicators
    english_indicators = ["the", "and", "or", "is", "are", "was", "were", "have", "has"]
    english_count = Enum.count(english_indicators, &String.contains?(content_lower, " #{&1} "))

    # Spanish indicators
    spanish_indicators = ["el", "la", "los", "las", "y", "o", "es", "son", "fue", "fueron"]
    spanish_count = Enum.count(spanish_indicators, &String.contains?(content_lower, " #{&1} "))

    # French indicators
    french_indicators = ["le", "la", "les", "et", "ou", "est", "sont", "était", "étaient"]
    french_count = Enum.count(french_indicators, &String.contains?(content_lower, " #{&1} "))

    cond do
      english_count >= spanish_count and english_count >= french_count -> "en"
      spanish_count >= french_count -> "es"
      french_count > 0 -> "fr"
      true -> "unknown"
    end
  end

  defp build_similarity_vectors(document) do
    # Create a simple TF-IDF-like vector for document similarity
    case document.structure do
      %{term_frequencies: freqs} ->
        # Take top 50 most frequent terms to create a feature vector
        top_terms =
          freqs
          |> Enum.sort_by(fn {_term, freq} -> freq end, :desc)
          |> Enum.take(50)
          |> Map.new()

        %{
          feature_vector: top_terms,
          vector_size: map_size(top_terms),
          norm: calculate_vector_norm(top_terms)
        }

      _ ->
        %{feature_vector: %{}, vector_size: 0, norm: 0.0}
    end
  end

  defp calculate_vector_norm(vector) do
    vector
    |> Map.values()
    |> Enum.map(&(&1 * &1))
    |> Enum.sum()
    |> :math.sqrt()
  end
end
