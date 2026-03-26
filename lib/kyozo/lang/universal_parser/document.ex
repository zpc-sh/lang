defmodule Kyozo.Lang.UniversalParser.Document do
  @moduledoc """
  Standardized document structure returned by all Universal Parser operations.

  The Document struct provides a unified interface for representing parsed content
  regardless of the original format. This enables consistent handling of parsing
  results across the entire LANG platform.

  ## Structure Overview

  - `format` - The detected or specified format of the content
  - `content` - The original raw content
  - `parsed` - The format-specific parsed representation
  - `metadata` - Processing information (size, timing, parser used)
  - `structure` - Structural analysis (depth, complexity, organization)
  - `analysis` - Optional quality and complexity analysis
  - `insights` - Optional actionable insights and recommendations

  ## Usage Examples

      # Basic document from JSON parsing
      %Document{
        format: "json",
        content: ~s({"name": "test", "values": [1,2,3]}),
        parsed: %{"name" => "test", "values" => [1, 2, 3]},
        metadata: %{content_size: 32, parse_time_ms: 1.2},
        structure: %{type: :object, keys: ["name", "values"], depth: 2}
      }

      # Document with full analysis
      %Document{
        format: "markdown",
        content: "# Title\n\nContent with [link](url)",
        parsed: %{headers: ["# Title"], links: [{"link", "url"}]},
        analysis: %{complexity_score: 3, readability_score: 8.5},
        insights: ["Well-structured document", "Good use of headers"]
      }

  """

  @type format :: String.t()
  @type content :: String.t()
  @type parsed_data :: term()
  @type metadata :: %{
          atom() => term(),
          content_size: non_neg_integer(),
          parse_time_ms: float(),
          parser_used: module(),
          parsed_at: DateTime.t()
        }
  @type structure :: %{
          atom() => term(),
          type: atom(),
          complexity: atom() | number()
        }
  @type analysis :: %{
          atom() => term(),
          complexity_score: number(),
          readability_score: number(),
          quality_indicators: [String.t()],
          recommendations: [String.t()]
        }
  @type insights :: [String.t()]

  @type t :: %__MODULE__{
          format: format(),
          content: content(),
          parsed: parsed_data(),
          metadata: metadata(),
          structure: structure() | nil,
          analysis: analysis() | nil,
          insights: insights() | nil
        }

  defstruct [
    :format,
    :content,
    :parsed,
    :metadata,
    :structure,
    :analysis,
    :insights
  ]

  @doc """
  Create a new Document with basic information.

  ## Examples

      Document.new("json", original_content, parsed_json, %{
        content_size: byte_size(original_content),
        parse_time_ms: 2.5,
        parser_used: JSONParser
      })

  """
  @spec new(format(), content(), parsed_data(), metadata()) :: t()
  def new(format, content, parsed, metadata) do
    %__MODULE__{
      format: format,
      content: content,
      parsed: parsed,
      metadata: metadata,
      structure: nil,
      analysis: nil,
      insights: nil
    }
  end

  @doc """
  Add structural analysis to a document.

  ## Examples

      structure = %{type: :object, keys: ["name", "age"], depth: 1}
      Document.add_structure(document, structure)

  """
  @spec add_structure(t(), structure()) :: t()
  def add_structure(%__MODULE__{} = document, structure) do
    %{document | structure: structure}
  end

  @doc """
  Add quality and complexity analysis to a document.

  ## Examples

      analysis = %{
        complexity_score: 4.2,
        readability_score: 7.8,
        quality_indicators: ["Well formatted"],
        recommendations: ["Consider adding comments"]
      }
      Document.add_analysis(document, analysis)

  """
  @spec add_analysis(t(), analysis()) :: t()
  def add_analysis(%__MODULE__{} = document, analysis) do
    %{document | analysis: analysis}
  end

  @doc """
  Add actionable insights to a document.

  ## Examples

      insights = [
        "Document follows standard conventions",
        "Consider breaking long sections into subsections"
      ]
      Document.add_insights(document, insights)

  """
  @spec add_insights(t(), insights()) :: t()
  def add_insights(%__MODULE__{} = document, insights) do
    %{document | insights: insights}
  end

  @doc """
  Get a summary of the document for quick overview.

  ## Examples

      Document.summary(document)
      # => %{
      #   format: "json",
      #   size: 256,
      #   complexity: :medium,
      #   parse_time_ms: 1.2,
      #   has_analysis: true,
      #   has_insights: false
      # }

  """
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = document) do
    %{
      format: document.format,
      size: document.metadata.content_size,
      complexity: get_complexity_level(document),
      parse_time_ms: document.metadata.parse_time_ms,
      has_structure: not is_nil(document.structure),
      has_analysis: not is_nil(document.analysis),
      has_insights: not is_nil(document.insights),
      insight_count: if(document.insights, do: length(document.insights), else: 0)
    }
  end

  @doc """
  Extract only the parsed data from a document.

  Useful when you only need the parsed content without metadata.

  ## Examples

      Document.extract_parsed(document)
      # Returns the parsed data directly

  """
  @spec extract_parsed(t()) :: parsed_data()
  def extract_parsed(%__MODULE__{parsed: parsed}), do: parsed

  @doc """
  Check if the document parsing was successful and complete.

  ## Examples

      Document.valid?(document)
      # => true

  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{format: format, content: content, parsed: parsed, metadata: metadata})
      when is_binary(format) and is_binary(content) and not is_nil(parsed) and is_map(metadata) do
    true
  end

  def valid?(_), do: false

  @doc """
  Check if the document has performance issues based on parsing time or size.

  ## Examples

      Document.has_performance_issues?(document)
      # => false

  """
  @spec has_performance_issues?(t()) :: boolean()
  def has_performance_issues?(%__MODULE__{metadata: metadata}) do
    # Consider performance issues if:
    # - Parse time > 5 seconds
    # - Content size > 5MB
    # - Memory usage appears high based on parse time vs size ratio
    parse_time = Map.get(metadata, :parse_time_ms, 0)
    content_size = Map.get(metadata, :content_size, 0)

    parse_time > 5_000 or content_size > 5_000_000 or
      (parse_time > 1000 and content_size < 100_000)
  end

  @doc """
  Get quality score from analysis or calculate a basic one.

  ## Examples

      Document.quality_score(document)
      # => 8.5

  """
  @spec quality_score(t()) :: float()
  def quality_score(%__MODULE__{
        analysis: %{complexity_score: complexity, readability_score: readability}
      }) do
    # Combine complexity and readability into overall quality
    # Lower complexity + higher readability = better quality
    base_quality = 10.0 - complexity + readability
    max(0.0, min(10.0, base_quality / 2))
  end

  def quality_score(%__MODULE__{structure: %{complexity: complexity}})
      when is_number(complexity) do
    # Basic quality based on complexity alone
    max(1.0, min(10.0, 10.0 - complexity))
  end

  def quality_score(_), do: 5.0

  @doc """
  Compare two documents for similarity.

  Returns a similarity score between 0.0 (completely different) and 1.0 (identical).

  ## Examples

      Document.similarity(doc1, doc2)
      # => 0.75

  """
  @spec similarity(t(), t()) :: float()
  def similarity(%__MODULE__{format: format1} = doc1, %__MODULE__{format: format2} = doc2)
      when format1 != format2 do
    # Different formats have lower base similarity
    content_similarity(doc1.content, doc2.content) * 0.5
  end

  def similarity(%__MODULE__{} = doc1, %__MODULE__{} = doc2) do
    content_sim = content_similarity(doc1.content, doc2.content)
    structure_sim = structure_similarity(doc1.structure, doc2.structure)

    # Weight content more heavily than structure
    content_sim * 0.7 + structure_sim * 0.3
  end

  @doc """
  Convert document to a map for JSON serialization.

  ## Examples

      Document.to_map(document)
      # => %{
      #   "format" => "json",
      #   "content" => "{...}",
      #   "parsed" => %{...},
      #   "metadata" => %{...},
      #   ...
      # }

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = document) do
    %{
      "format" => document.format,
      "content" => document.content,
      "parsed" => document.parsed,
      "metadata" => stringify_keys(document.metadata),
      "structure" => document.structure,
      "analysis" => document.analysis,
      "insights" => document.insights,
      "summary" => summary(document)
    }
  end

  @doc """
  Create document from a map (for deserialization).

  ## Examples

      Document.from_map(%{
        "format" => "json",
        "content" => "...",
        "parsed" => %{...},
        "metadata" => %{...}
      })

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{} = map) do
    try do
      document = %__MODULE__{
        format: Map.get(map, "format"),
        content: Map.get(map, "content"),
        parsed: Map.get(map, "parsed"),
        metadata: atomize_keys(Map.get(map, "metadata", %{})),
        structure: Map.get(map, "structure"),
        analysis: Map.get(map, "analysis"),
        insights: Map.get(map, "insights")
      }

      if valid?(document) do
        {:ok, document}
      else
        {:error, :invalid_document_structure}
      end
    rescue
      error -> {:error, {:deserialization_failed, error}}
    end
  end

  # Private helper functions

  defp get_complexity_level(%__MODULE__{analysis: %{complexity_score: score}})
       when is_number(score) do
    cond do
      score < 2 -> :simple
      score < 5 -> :medium
      score < 8 -> :complex
      true -> :very_complex
    end
  end

  defp get_complexity_level(%__MODULE__{structure: %{complexity: complexity}})
       when is_atom(complexity) do
    complexity
  end

  defp get_complexity_level(%__MODULE__{structure: %{complexity: score}}) when is_number(score) do
    cond do
      score < 5 -> :simple
      score < 15 -> :medium
      score < 30 -> :complex
      true -> :very_complex
    end
  end

  defp get_complexity_level(_), do: :unknown

  defp content_similarity(content1, content2) do
    # Simple similarity based on string distance
    # In production, might use more sophisticated algorithms
    len1 = String.length(content1)
    len2 = String.length(content2)

    if len1 == 0 and len2 == 0 do
      1.0
    else
      # Jaccard similarity using word sets
      words1 = content1 |> String.downcase() |> String.split() |> MapSet.new()
      words2 = content2 |> String.downcase() |> String.split() |> MapSet.new()

      intersection_size = MapSet.intersection(words1, words2) |> MapSet.size()
      union_size = MapSet.union(words1, words2) |> MapSet.size()

      if union_size == 0 do
        0.0
      else
        intersection_size / union_size
      end
    end
  end

  defp structure_similarity(nil, nil), do: 1.0
  defp structure_similarity(nil, _), do: 0.0
  defp structure_similarity(_, nil), do: 0.0

  defp structure_similarity(%{type: type1} = s1, %{type: type2} = s2) do
    type_match = if type1 == type2, do: 0.5, else: 0.0

    # Compare other structural attributes
    complexity_match =
      compare_complexity(
        Map.get(s1, :complexity),
        Map.get(s2, :complexity)
      )

    type_match + complexity_match * 0.5
  end

  defp compare_complexity(c1, c2) when c1 == c2, do: 1.0

  defp compare_complexity(c1, c2) when is_number(c1) and is_number(c2) do
    # Similarity based on numeric difference
    max_diff = max(c1, c2)

    if max_diff == 0 do
      1.0
    else
      1.0 - abs(c1 - c2) / max_diff
    end
  end

  defp compare_complexity(_, _), do: 0.5

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp stringify_keys(other), do: other

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) ->
        try do
          {String.to_existing_atom(k), v}
        rescue
          ArgumentError -> {k, v}
        end

      {k, v} ->
        {k, v}
    end)
  end

  defp atomize_keys(other), do: other
end
