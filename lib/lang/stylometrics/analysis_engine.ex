defmodule Lang.Stylometrics.AnalysisEngine do
  @moduledoc """
  Engine for stylometric analysis including writing fingerprinting and style obfuscation
  """

  require Logger

  @doc """
  Analyze writing style for fingerprinting or detection
  """
  def analyze_writing_style(content, options \\ %{}) do
    Logger.info("Analyzing writing style", content_length: String.length(content))

    with {:ok, linguistic_features} <- extract_linguistic_features(content),
         {:ok, syntactic_features} <- extract_syntactic_features(content),
         {:ok, lexical_features} <- extract_lexical_features(content),
         {:ok, stylistic_features} <- extract_stylistic_features(content) do
      analysis = %{
        content_length: String.length(content),
        linguistic_features: linguistic_features,
        syntactic_features: syntactic_features,
        lexical_features: lexical_features,
        stylistic_features: stylistic_features,
        fingerprint:
          generate_style_fingerprint(
            linguistic_features,
            syntactic_features,
            lexical_features,
            stylistic_features
          ),
        confidence_score: calculate_confidence_score(content),
        analyzed_at: DateTime.utc_now()
      }

      {:ok, analysis}
    else
      error -> error
    end
  end

  @doc """
  Compare two writing samples for authorship attribution
  """
  def compare_writing_styles(sample1, sample2, options \\ %{}) do
    with {:ok, analysis1} <- analyze_writing_style(sample1, options),
         {:ok, analysis2} <- analyze_writing_style(sample2, options) do
      similarity_score = calculate_similarity_score(analysis1, analysis2)

      comparison = %{
        sample1_fingerprint: analysis1.fingerprint,
        sample2_fingerprint: analysis2.fingerprint,
        similarity_score: similarity_score,
        likely_same_author: similarity_score > 0.75,
        confidence_level:
          determine_confidence_level(
            similarity_score,
            analysis1.confidence_score,
            analysis2.confidence_score
          ),
        feature_similarities: compare_feature_groups(analysis1, analysis2),
        distinctive_differences: find_distinctive_differences(analysis1, analysis2)
      }

      {:ok, comparison}
    end
  end

  @doc """
  Generate style obfuscation suggestions to alter writing fingerprint
  """
  def generate_obfuscation_suggestions(content, target_style \\ :neutral) do
    with {:ok, current_analysis} <- analyze_writing_style(content) do
      suggestions = %{
        lexical_suggestions: generate_lexical_obfuscation(current_analysis),
        syntactic_suggestions: generate_syntactic_obfuscation(current_analysis),
        stylistic_suggestions: generate_stylistic_obfuscation(current_analysis, target_style),
        vocabulary_suggestions: generate_vocabulary_obfuscation(current_analysis),
        structural_suggestions: generate_structural_obfuscation(current_analysis)
      }

      {:ok,
       %{
         original_fingerprint: current_analysis.fingerprint,
         obfuscation_suggestions: suggestions,
         estimated_effectiveness: estimate_obfuscation_effectiveness(suggestions),
         target_style: target_style
       }}
    end
  end

  @doc """
  Apply obfuscation transformations to text
  """
  def apply_obfuscation(content, transformations, options \\ %{}) do
    # 0.0 to 1.0
    intensity = Map.get(options, :intensity, 0.5)
    preserve_meaning = Map.get(options, :preserve_meaning, true)

    transformed_content =
      content
      |> apply_lexical_transformations(transformations[:lexical] || [], intensity)
      |> apply_syntactic_transformations(transformations[:syntactic] || [], intensity)
      |> apply_stylistic_transformations(transformations[:stylistic] || [], intensity)

    if preserve_meaning do
      # Verify meaning preservation
      case verify_meaning_preservation(content, transformed_content) do
        {:ok, preserved} when preserved ->
          {:ok,
           %{
             original_content: content,
             transformed_content: transformed_content,
             transformations_applied: transformations,
             meaning_preserved: true,
             transformation_intensity: intensity
           }}

        {:ok, false} ->
          {:error, :meaning_not_preserved}

        error ->
          error
      end
    else
      {:ok,
       %{
         original_content: content,
         transformed_content: transformed_content,
         transformations_applied: transformations,
         meaning_preserved: :not_checked,
         transformation_intensity: intensity
       }}
    end
  end

  # Private helper functions

  defp extract_linguistic_features(content) do
    sentences = split_into_sentences(content)
    words = extract_words(content)

    features = %{
      sentence_count: length(sentences),
      word_count: length(words),
      avg_sentence_length: calculate_avg_sentence_length(sentences),
      avg_word_length: calculate_avg_word_length(words),
      type_token_ratio: calculate_type_token_ratio(words),
      hapax_legomena: count_hapax_legomena(words),
      function_word_frequency: calculate_function_word_frequency(words),
      punctuation_density: calculate_punctuation_density(content)
    }

    {:ok, features}
  end

  defp extract_syntactic_features(content) do
    sentences = split_into_sentences(content)

    features = %{
      simple_sentences: count_simple_sentences(sentences),
      compound_sentences: count_compound_sentences(sentences),
      complex_sentences: count_complex_sentences(sentences),
      passive_voice_frequency: count_passive_voice(sentences),
      question_frequency: count_questions(sentences),
      exclamation_frequency: count_exclamations(sentences),
      subordinate_clause_frequency: count_subordinate_clauses(sentences),
      coordination_frequency: count_coordinations(sentences)
    }

    {:ok, features}
  end

  defp extract_lexical_features(content) do
    words = extract_words(content)

    features = %{
      vocabulary_richness: calculate_vocabulary_richness(words),
      rare_word_frequency: calculate_rare_word_frequency(words),
      technical_term_frequency: calculate_technical_term_frequency(words),
      foreign_word_frequency: calculate_foreign_word_frequency(words),
      neologism_frequency: calculate_neologism_frequency(words),
      archaic_word_frequency: calculate_archaic_word_frequency(words),
      colloquialism_frequency: calculate_colloquialism_frequency(words),
      abbreviation_frequency: calculate_abbreviation_frequency(words)
    }

    {:ok, features}
  end

  defp extract_stylistic_features(content) do
    features = %{
      formality_level: assess_formality_level(content),
      emotion_intensity: assess_emotion_intensity(content),
      subjectivity_score: calculate_subjectivity_score(content),
      rhetorical_device_usage: identify_rhetorical_devices(content),
      paragraph_structure: analyze_paragraph_structure(content),
      transition_usage: analyze_transition_usage(content),
      emphasis_patterns: identify_emphasis_patterns(content),
      humor_indicators: detect_humor_indicators(content)
    }

    {:ok, features}
  end

  defp generate_style_fingerprint(linguistic, syntactic, lexical, stylistic) do
    # Create a weighted fingerprint vector
    fingerprint_vector = [
      linguistic.avg_sentence_length * 0.1,
      linguistic.avg_word_length * 0.1,
      linguistic.type_token_ratio * 0.15,
      linguistic.function_word_frequency * 0.2,
      syntactic.passive_voice_frequency * 0.1,
      syntactic.complex_sentences * 0.1,
      lexical.vocabulary_richness * 0.15,
      stylistic.formality_level * 0.1
    ]

    # Generate hash-like fingerprint
    fingerprint_hash =
      fingerprint_vector
      |> Enum.map(&Float.round(&1, 3))
      |> Enum.join("-")
      |> (&:crypto.hash(:sha256, &1)).()
      |> Base.encode16()
      |> String.slice(0..15)

    %{
      vector: fingerprint_vector,
      hash: fingerprint_hash,
      components: %{
        linguistic_weight: 0.45,
        syntactic_weight: 0.2,
        lexical_weight: 0.15,
        stylistic_weight: 0.2
      }
    }
  end

  defp calculate_confidence_score(content) do
    word_count = content |> String.split() |> length()

    cond do
      word_count < 50 -> 0.3
      word_count < 200 -> 0.6
      word_count < 500 -> 0.8
      true -> 0.95
    end
  end

  defp calculate_similarity_score(analysis1, analysis2) do
    # Compare fingerprint vectors using cosine similarity
    vector1 = analysis1.fingerprint.vector
    vector2 = analysis2.fingerprint.vector

    dot_product =
      Enum.zip(vector1, vector2)
      |> Enum.reduce(0, fn {a, b}, acc -> acc + (a * b) end)

    magnitude1 = :math.sqrt(Enum.reduce(vector1, 0, fn x, acc -> acc + (x * x) end))
    magnitude2 = :math.sqrt(Enum.reduce(vector2, 0, fn x, acc -> acc + (x * x) end))

    if magnitude1 == 0 or magnitude2 == 0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  defp determine_confidence_level(similarity_score, conf1, conf2) do
    base_confidence = min(conf1, conf2)

    cond do
      similarity_score > 0.9 and base_confidence > 0.8 -> :very_high
      similarity_score > 0.8 and base_confidence > 0.6 -> :high
      similarity_score > 0.6 and base_confidence > 0.4 -> :medium
      true -> :low
    end
  end

  defp compare_feature_groups(analysis1, analysis2) do
    %{
      linguistic_similarity:
        compare_feature_group(analysis1.linguistic_features, analysis2.linguistic_features),
      syntactic_similarity:
        compare_feature_group(analysis1.syntactic_features, analysis2.syntactic_features),
      lexical_similarity:
        compare_feature_group(analysis1.lexical_features, analysis2.lexical_features),
      stylistic_similarity:
        compare_feature_group(analysis1.stylistic_features, analysis2.stylistic_features)
    }
  end

  defp compare_feature_group(features1, features2) do
    common_keys = Map.keys(features1) |> Enum.filter(&Map.has_key?(features2, &1))

    similarities =
      Enum.map(common_keys, fn key ->
        val1 = Map.get(features1, key, 0)
        val2 = Map.get(features2, key, 0)
        calculate_feature_similarity(val1, val2)
      end)

    if length(similarities) > 0 do
      Enum.sum(similarities) / length(similarities)
    else
      0.0
    end
  end

  defp calculate_feature_similarity(val1, val2) when is_number(val1) and is_number(val2) do
    if val1 == 0 and val2 == 0 do
      1.0
    else
      max_val = max(abs(val1), abs(val2))

      if max_val == 0 do
        1.0
      else
        1.0 - abs(val1 - val2) / max_val
      end
    end
  end

  defp calculate_feature_similarity(_, _), do: 0.0

  defp find_distinctive_differences(analysis1, analysis2) do
    all_features1 = flatten_features(analysis1)
    all_features2 = flatten_features(analysis2)

    Enum.reduce(all_features1, [], fn {key, val1}, acc ->
      case Map.get(all_features2, key) do
        nil ->
          acc

        val2 ->
          similarity = calculate_feature_similarity(val1, val2)

          if similarity < 0.5 do
            [{key, val1, val2, similarity} | acc]
          else
            acc
          end
      end
    end)
    |> Enum.sort_by(fn {_, _, _, similarity} -> similarity end)
    |> Enum.take(5)
  end

  defp flatten_features(analysis) do
    Map.merge(analysis.linguistic_features, analysis.syntactic_features)
    |> Map.merge(analysis.lexical_features)
    |> Map.merge(analysis.stylistic_features)
  end

  # Obfuscation functions

  defp generate_lexical_obfuscation(analysis) do
    base_suggestions = [
      %{
        type: :synonym_replacement,
        description: "Replace common words with synonyms",
        impact: :medium
      },
      %{
        type: :vocabulary_elevation,
        description: "Use more sophisticated vocabulary",
        impact: :high
      },
      %{
        type: :technical_terms,
        description: "Incorporate domain-specific terminology",
        impact: :medium
      }
    ]

    # Add specific suggestions based on analysis
    if analysis.lexical_features.vocabulary_richness < 0.5 do
      base_suggestions ++
        [%{type: :expand_vocabulary, description: "Increase vocabulary diversity", impact: :high}]
    else
      base_suggestions
    end
  end

  defp generate_syntactic_obfuscation(analysis) do
    suggestions = []

    suggestions =
      if analysis.syntactic_features.complex_sentences < 0.3 do
        [
          %{
            type: :increase_complexity,
            description: "Use more complex sentence structures",
            impact: :high
          }
          | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if analysis.syntactic_features.passive_voice_frequency < 0.1 do
        [
          %{
            type: :add_passive_voice,
            description: "Incorporate passive voice constructions",
            impact: :medium
          }
          | suggestions
        ]
      else
        suggestions
      end

    suggestions ++
      [
        %{
          type: :vary_sentence_length,
          description: "Vary sentence length distribution",
          impact: :medium
        },
        %{type: :restructure_clauses, description: "Reorganize subordinate clauses", impact: :low}
      ]
  end

  defp generate_stylistic_obfuscation(analysis, target_style) do
    base_suggestions = [
      %{
        type: :adjust_formality,
        description: "Modify formality level",
        target: target_style,
        impact: :high
      },
      %{type: :change_tone, description: "Alter emotional tone", impact: :medium},
      %{type: :modify_transitions, description: "Change transition patterns", impact: :low}
    ]

    case target_style do
      :academic ->
        base_suggestions ++
          [
            %{type: :add_hedging, description: "Include hedging language", impact: :medium},
            %{type: :cite_sources, description: "Add reference patterns", impact: :low}
          ]

      :informal ->
        base_suggestions ++
          [
            %{type: :add_contractions, description: "Use contractions", impact: :medium},
            %{type: :casual_expressions, description: "Include casual expressions", impact: :high}
          ]

      _ ->
        base_suggestions
    end
  end

  defp generate_vocabulary_obfuscation(analysis) do
    [
      %{type: :word_substitution, description: "Strategic word replacement", impact: :high},
      %{type: :phrase_restructuring, description: "Reorganize common phrases", impact: :medium},
      %{type: :idiom_variation, description: "Vary idiomatic expressions", impact: :medium}
    ]
  end

  defp generate_structural_obfuscation(analysis) do
    [
      %{
        type: :paragraph_restructuring,
        description: "Modify paragraph organization",
        impact: :low
      },
      %{
        type: :topic_sentence_variation,
        description: "Vary topic sentence patterns",
        impact: :low
      },
      %{type: :conclusion_patterns, description: "Change conclusion structures", impact: :low}
    ]
  end

  defp estimate_obfuscation_effectiveness(suggestions) do
    total_impact =
      suggestions
      |> Map.values()
      |> List.flatten()
      |> Enum.reduce(0, fn suggestion, acc -> acc + (case suggestion.impact do
          :high -> 3
          :medium -> 2
          :low -> 1
        end) end)

    max_possible = length(Map.values(suggestions) |> List.flatten()) * 3

    if max_possible > 0 do
      total_impact / max_possible
    else
      0.0
    end
  end

  # Transformation application functions

  defp apply_lexical_transformations(content, transformations, intensity) do
    # Apply lexical transformations based on intensity
    Enum.reduce(transformations, content, fn transformation, acc ->
      case transformation.type do
        :synonym_replacement -> apply_synonym_replacement(acc, intensity)
        :vocabulary_elevation -> apply_vocabulary_elevation(acc, intensity)
        _ -> acc
      end
    end)
  end

  defp apply_syntactic_transformations(content, transformations, intensity) do
    # Apply syntactic transformations
    Enum.reduce(transformations, content, fn transformation, acc ->
      case transformation.type do
        :increase_complexity -> apply_complexity_increase(acc, intensity)
        :add_passive_voice -> apply_passive_voice_addition(acc, intensity)
        _ -> acc
      end
    end)
  end

  defp apply_stylistic_transformations(content, transformations, intensity) do
    # Apply stylistic transformations
    Enum.reduce(transformations, content, fn transformation, acc ->
      case transformation.type do
        :adjust_formality -> apply_formality_adjustment(acc, intensity)
        :change_tone -> apply_tone_change(acc, intensity)
        _ -> acc
      end
    end)
  end

  # Real stylometric transformation implementations
  defp apply_synonym_replacement(content, intensity) do
    # Apply synonym replacement based on intensity level
    replacements = get_synonym_replacements(intensity)

    Enum.reduce(replacements, content, fn {pattern, replacement}, acc ->
      if :rand.uniform() < intensity do
        String.replace(acc, pattern, replacement)
      else
        acc
      end
    end)
  end

  defp apply_vocabulary_elevation(content, intensity) do
    # Replace simple words with more sophisticated alternatives
    elevations = [
      {~r/\buse\b/i, "utilize"},
      {~r/\bhelp\b/i, "assist"},
      {~r/\bshow\b/i, "demonstrate"},
      {~r/\bbig\b/i, "substantial"},
      {~r/\bsmall\b/i, "minute"},
      {~r/\bstart\b/i, "commence"},
      {~r/\bend\b/i, "conclude"},
      {~r/\bmake\b/i, "generate"},
      {~r/\bget\b/i, "acquire"},
      {~r/\btell\b/i, "inform"}
    ]

    Enum.reduce(elevations, content, fn {pattern, replacement}, acc ->
      if :rand.uniform() < intensity do
        String.replace(acc, pattern, replacement)
      else
        acc
      end
    end)
  end

  defp apply_complexity_increase(content, intensity) do
    # Add complexity by introducing subordinate clauses and conjunctions
    sentences = String.split(content, ~r/\.\s+/, trim: true)

    complex_sentences =
      Enum.map(sentences, fn sentence ->
        if :rand.uniform() < intensity and String.length(sentence) > 20 do
          add_complexity_to_sentence(sentence)
        else
          sentence
        end
      end)

    Enum.join(complex_sentences, ". ") <> if String.ends_with?(content, "."), do: ".", else: ""
  end

  defp apply_passive_voice_addition(content, intensity) do
    # Transform active voice to passive voice patterns
    active_patterns = [
      {~r/(\w+)\s+creates?\s+(\w+)/i, "\\2 is created by \\1"},
      {~r/(\w+)\s+makes?\s+(\w+)/i, "\\2 is made by \\1"},
      {~r/(\w+)\s+develops?\s+(\w+)/i, "\\2 is developed by \\1"},
      {~r/(\w+)\s+builds?\s+(\w+)/i, "\\2 is built by \\1"},
      {~r/(\w+)\s+writes?\s+(\w+)/i, "\\2 is written by \\1"}
    ]

    Enum.reduce(active_patterns, content, fn {pattern, replacement}, acc ->
      if :rand.uniform() < intensity do
        String.replace(acc, pattern, replacement)
      else
        acc
      end
    end)
  end

  defp apply_formality_adjustment(content, intensity) do
    # Increase formality by replacing informal expressions
    formal_replacements = [
      {~r/\bcan't\b/i, "cannot"},
      {~r/\bwon't\b/i, "will not"},
      {~r/\bisn't\b/i, "is not"},
      {~r/\baren't\b/i, "are not"},
      {~r/\bI think\b/i, "It is my opinion that"},
      {~r/\bI believe\b/i, "It is believed that"},
      {~r/\ba lot of\b/i, "numerous"},
      {~r/\bkind of\b/i, "somewhat"},
      {~r/\bpretty\s+(\w+)/i, "rather \\1"},
      {~r/\breally\s+(\w+)/i, "particularly \\1"}
    ]

    Enum.reduce(formal_replacements, content, fn {pattern, replacement}, acc ->
      if :rand.uniform() < intensity do
        String.replace(acc, pattern, replacement)
      else
        acc
      end
    end)
  end

  defp apply_tone_change(content, intensity) do
    # Adjust tone based on intensity (0.0 = casual, 1.0 = professional)
    if intensity > 0.7 do
      # Professional tone
      content
      |> String.replace(~r/\bawesome\b/i, "excellent")
      |> String.replace(~r/\bgreat\b/i, "outstanding")
      |> String.replace(~r/\bcool\b/i, "impressive")
      |> String.replace(~r/\bstuff\b/i, "materials")
      |> String.replace(~r/\bthings\b/i, "items")
    else
      # Keep casual tone or make more casual
      content
      |> String.replace(~r/\butilize\b/i, "use")
      |> String.replace(~r/\bassist\b/i, "help")
      |> String.replace(~r/\bcommence\b/i, "start")
    end
  end

  defp verify_meaning_preservation(original, transformed) do
    # Basic semantic similarity check using word overlap and sentence structure
    original_words = extract_content_words(original)
    transformed_words = extract_content_words(transformed)

    # Calculate Jaccard similarity
    intersection = MapSet.intersection(original_words, transformed_words)
    union = MapSet.union(original_words, transformed_words)

    similarity =
      if MapSet.size(union) > 0 do
        MapSet.size(intersection) / MapSet.size(union)
      else
        1.0
      end

    # Check sentence count preservation
    original_sentences = count_sentences(original)
    transformed_sentences = count_sentences(transformed)

    sentence_ratio =
      min(original_sentences, transformed_sentences) /
        max(original_sentences, transformed_sentences)

    # Combined score (word similarity + structure similarity)
    combined_score = similarity * 0.7 + sentence_ratio * 0.3

    if combined_score > 0.6 do
      {:ok, true}
    else
      {:error, :meaning_too_altered}
    end
  end

  # Helper functions for stylometric analysis
  defp get_synonym_replacements(intensity) do
    base_replacements = [
      {~r/\bgood\b/i, "excellent"},
      {~r/\bbad\b/i, "poor"},
      {~r/\bfast\b/i, "rapid"},
      {~r/\bslow\b/i, "gradual"},
      {~r/\beasy\b/i, "straightforward"},
      {~r/\bhard\b/i, "challenging"}
    ]

    if intensity > 0.5 do
      base_replacements ++
        [
          {~r/\bvery\s+(\w+)/i, "extremely \\1"},
          {~r/\bquite\s+(\w+)/i, "considerably \\1"},
          {~r/\bsomewhat\s+(\w+)/i, "moderately \\1"}
        ]
    else
      base_replacements
    end
  end

  defp add_complexity_to_sentence(sentence) do
    # Add subordinate clauses or conjunctive phrases
    complexity_additions = [
      ", which demonstrates that",
      ", thereby indicating that",
      ", consequently resulting in",
      ", furthermore establishing",
      ", subsequently leading to"
    ]

    addition = Enum.random(complexity_additions)

    # Split sentence roughly in half and add complexity
    words = String.split(sentence)

    if length(words) > 5 do
      {first_half, second_half} = Enum.split(words, div(length(words), 2))
      Enum.join(first_half, " ") <> addition <> " " <> Enum.join(second_half, " ")
    else
      sentence
    end
  end

  defp extract_content_words(text) do
    # Extract meaningful words (excluding stop words)
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
        "should"
      ])

    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.reject(&MapSet.member?(stop_words, &1))
    |> MapSet.new()
  end

  defp count_sentences(text) do
    text
    |> String.split(~r/[.!?]+/)
    |> Enum.count(&(String.trim(&1) != ""))
  end

  # Feature extraction helper functions (simplified implementations)

  defp split_into_sentences(content) do
    String.split(content, ~r/[.!?]+/) |> Enum.reject(&(&1 == ""))
  end

  defp extract_words(content) do
    String.split(content, ~r/\W+/) |> Enum.reject(&(&1 == ""))
  end

  defp calculate_avg_sentence_length(sentences) do
    if length(sentences) > 0 do
      total_words = sentences |> Enum.reduce(0, fn x, acc -> acc + length(String.split(x)) end)
      total_words / length(sentences)
    else
      0
    end
  end

  defp calculate_avg_word_length(words) do
    if length(words) > 0 do
      total_chars = words |> Enum.reduce(0, fn x, acc -> acc + String.length(x) end)
      total_chars / length(words)
    else
      0
    end
  end

  defp calculate_type_token_ratio(words) do
    if length(words) > 0 do
      unique_words = words |> Enum.uniq() |> length()
      unique_words / length(words)
    else
      0
    end
  end

  defp count_hapax_legomena(words) do
    words |> Enum.frequencies() |> Enum.count(fn {_, count} -> count == 1 end)
  end

  defp calculate_function_word_frequency(words) do
    function_words =
      ~w[the a an and or but in on at to for of with by from up about into over after]

    function_word_count =
      Enum.count(words, fn word -> String.downcase(word) in function_words end)

    if length(words) > 0 do
      function_word_count / length(words)
    else
      0
    end
  end

  defp calculate_punctuation_density(content) do
    punctuation_count = Regex.scan(~r/[.,;:!?]/, content) |> length()

    if String.length(content) > 0 do
      punctuation_count / String.length(content)
    else
      0
    end
  end

  # Simplified syntactic feature functions
  # Placeholder
  defp count_simple_sentences(sentences), do: length(sentences) * 0.6
  # Placeholder
  defp count_compound_sentences(sentences), do: length(sentences) * 0.25
  # Placeholder
  defp count_complex_sentences(sentences), do: length(sentences) * 0.15

  defp count_passive_voice(sentences) do
    passive_count = Enum.count(sentences, &String.contains?(&1, ["was ", "were ", "been "]))
    passive_count / max(length(sentences), 1)
  end

  defp count_questions(sentences) do
    question_count = Enum.count(sentences, &String.contains?(&1, "?"))
    question_count / max(length(sentences), 1)
  end

  defp count_exclamations(sentences) do
    exclamation_count = Enum.count(sentences, &String.contains?(&1, "!"))
    exclamation_count / max(length(sentences), 1)
  end

  # Placeholder
  defp count_subordinate_clauses(sentences), do: 0.1
  # Placeholder
  defp count_coordinations(sentences), do: 0.15

  # Simplified lexical feature functions
  defp calculate_vocabulary_richness(words), do: calculate_type_token_ratio(words)
  # Placeholder
  defp calculate_rare_word_frequency(_words), do: 0.05
  # Placeholder
  defp calculate_technical_term_frequency(_words), do: 0.02
  # Placeholder
  defp calculate_foreign_word_frequency(_words), do: 0.01
  # Placeholder
  defp calculate_neologism_frequency(_words), do: 0.005
  # Placeholder
  defp calculate_archaic_word_frequency(_words), do: 0.002
  # Placeholder
  defp calculate_colloquialism_frequency(_words), do: 0.03
  # Placeholder
  defp calculate_abbreviation_frequency(_words), do: 0.02

  # Simplified stylistic feature functions
  defp assess_formality_level(content) do
    # Simple formality assessment based on word patterns
    formal_indicators = Regex.scan(~r/\b(therefore|furthermore|consequently|however)\b/i, content)
    informal_indicators = Regex.scan(~r/\b(gonna|wanna|kinda|pretty much|sort of)\b/i, content)

    formal_score = length(formal_indicators)
    informal_score = length(informal_indicators)

    cond do
      formal_score > informal_score -> 0.8
      informal_score > formal_score -> 0.2
      true -> 0.5
    end
  end

  defp assess_emotion_intensity(content) do
    emotion_words =
      ~w[love hate amazing terrible wonderful awful excited disappointed thrilled frustrated]

    emotion_count =
      Enum.count(String.split(content), fn word ->
        String.downcase(word) in emotion_words
      end)

    min(emotion_count / 10.0, 1.0)
  end

  defp calculate_subjectivity_score(content) do
    subjective_indicators = ~w[I think I feel I believe in my opinion personally I suppose]

    subjective_count =
      Enum.reduce(subjective_indicators, 0, fn indicator, acc ->
        acc + length(Regex.scan(~r/#{indicator}/i, content))
      end)

    min(subjective_count / 5.0, 1.0)
  end

  defp identify_rhetorical_devices(_content) do
    # Placeholder - would identify metaphors, alliteration, etc.
    %{metaphors: 0, alliteration: 0, repetition: 0}
  end

  defp analyze_paragraph_structure(content) do
    paragraphs = String.split(content, ~r/\n\s*\n/) |> Enum.reject(&(&1 == ""))

    %{
      paragraph_count: length(paragraphs),
      avg_paragraph_length:
        if(length(paragraphs) > 0, do: String.length(content) / length(paragraphs), else: 0)
    }
  end

  defp analyze_transition_usage(content) do
    transitions = ~w[however therefore furthermore moreover consequently nevertheless thus hence]

    transition_count =
      Enum.reduce(transitions, 0, fn transition, acc ->
        acc + length(Regex.scan(~r/\b#{transition}\b/i, content))
      end)

    %{
      transition_count: transition_count,
      transition_density: transition_count / max(String.length(content), 1)
    }
  end

  defp identify_emphasis_patterns(content) do
    caps_count = Regex.scan(~r/[A-Z]{2,}/, content) |> length()
    exclamation_count = Regex.scan(~r/!/, content) |> length()

    %{all_caps: caps_count, exclamations: exclamation_count}
  end

  defp detect_humor_indicators(content) do
    humor_markers = ~w[lol haha funny joke kidding sarcasm ironic]

    humor_count =
      Enum.count(String.split(content), fn word ->
        String.downcase(word) in humor_markers
      end)

    %{humor_markers: humor_count, likely_humorous: humor_count > 0}
  end
end
