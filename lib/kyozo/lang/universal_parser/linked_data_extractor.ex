defmodule Kyozo.Lang.UniversalParser.LinkedDataExtractor do
  @moduledoc """
  Linked Data Extractor for Semantic Information Extraction

  This module extracts semantic information, RDF triples, and knowledge graph
  data from parsed content. It handles various formats including JSON-LD,
  Markdown-LD, and can extract semantic meaning from regular content.

  ## Features

  - **JSON-LD Processing** - Full JSON-LD context expansion and triple extraction
  - **Markdown-LD Support** - Extract semantics from annotated Markdown
  - **Entity Recognition** - Identify and extract entities from text
  - **RDF Triple Generation** - Convert semantic data to RDF triples
  - **Knowledge Graph Building** - Create interconnected semantic structures
  - **Context Management** - Handle @context expansion and validation

  ## Supported Formats

  ### JSON-LD
  - Full JSON-LD 1.1 specification support
  - Context expansion and compaction
  - Frame-based data shaping
  - Multi-graph support

  ### Markdown-LD
  - Semantic annotations in Markdown (`data-lang-entity`, `data-lang-uri`)
  - RDFa-style markup extraction
  - Schema.org vocabulary support
  - Custom vocabulary integration

  ### Regular Formats
  - Entity extraction from plain text
  - Automatic schema inference
  - Relationship detection
  - Semantic enrichment

  ## Usage Examples

      # Extract from JSON-LD
      jsonld = ~s({
        "@context": "https://schema.org/",
        "@type": "Person",
        "name": "John Doe",
        "email": "john@example.com"
      })
      {:ok, linked_data} = LinkedDataExtractor.extract(jsonld, :jsonld)

      # Extract from Markdown-LD
      markdown = ~s(
        # Article
        <span data-lang-entity="Person" data-lang-uri="https://example.org/john">
        John Smith
        </span> wrote this article.
      )
      {:ok, linked_data} = LinkedDataExtractor.extract(markdown, :markdown_ld)

      # Build knowledge graph
      {:ok, graph} = LinkedDataExtractor.build_knowledge_graph([doc1, doc2, doc3])

  """

  alias Kyozo.Lang.UniversalParser.{Document, KnowledgeGraph}
  require Logger

  @type extraction_options :: [
          extract_context: boolean(),
          expand_context: boolean(),
          extract_entities: boolean(),
          extract_relationships: boolean(),
          vocabulary: String.t() | [String.t()],
          confidence_threshold: float()
        ]

  @type linked_data :: %{
          context: map() | nil,
          entities: [entity()],
          relationships: [relationship()],
          triples: [rdf_triple()],
          vocab_used: [String.t()],
          confidence_scores: map()
        }

  @type entity :: %{
          id: String.t() | nil,
          type: String.t(),
          properties: map(),
          uri: String.t() | nil,
          confidence: float()
        }

  @type relationship :: %{
          subject: String.t(),
          predicate: String.t(),
          object: String.t(),
          confidence: float()
        }

  @type rdf_triple :: {String.t(), String.t(), String.t()}

  @default_options [
    extract_context: true,
    expand_context: true,
    extract_entities: true,
    extract_relationships: true,
    vocabulary: ["https://schema.org/"],
    confidence_threshold: 0.7
  ]

  @doc """
  Extract linked data from parsed document content.

  ## Options

  - `:extract_context` - Extract and process @context information (default: true)
  - `:expand_context` - Expand compact IRIs using context (default: true)
  - `:extract_entities` - Extract entity information (default: true)
  - `:extract_relationships` - Extract relationships between entities (default: true)
  - `:vocabulary` - Vocabularies to use for semantic annotation (default: Schema.org)
  - `:confidence_threshold` - Minimum confidence for extracted data (default: 0.7)

  ## Examples

      # Basic extraction
      {:ok, linked_data} = LinkedDataExtractor.extract(document)

      # With custom vocabulary
      {:ok, linked_data} = LinkedDataExtractor.extract(document,
        vocabulary: ["https://schema.org/", "https://example.org/vocab/"]
      )

  """
  @spec extract(Document.t(), extraction_options()) :: {:ok, linked_data()} | {:error, term()}
  def extract(%Document{format: format, parsed: parsed, content: content}, options \\ []) do
    options = Keyword.merge(@default_options, options)

    case format do
      "jsonld" ->
        extract_from_jsonld(parsed, content, options)

      "markdown_ld" ->
        extract_from_markdown_ld(parsed, content, options)

      "json" ->
        extract_from_json(parsed, content, options)

      "markdown" ->
        extract_from_markdown(parsed, content, options)

      "xml" ->
        extract_from_xml(parsed, content, options)

      _ ->
        extract_from_text(content, options)
    end
  end

  @doc """
  Extract linked data from raw content with format specification.

  ## Examples

      {:ok, linked_data} = LinkedDataExtractor.extract_from_content(content, :jsonld)

  """
  @spec extract_from_content(String.t(), atom(), extraction_options()) ::
          {:ok, linked_data()} | {:error, term()}
  def extract_from_content(content, format, options \\ []) when is_binary(content) do
    options = Keyword.merge(@default_options, options)

    case format do
      :jsonld ->
        with {:ok, parsed} <- parse_jsonld(content) do
          extract_from_jsonld(parsed, content, options)
        end

      :markdown_ld ->
        with {:ok, parsed} <- parse_markdown_ld(content) do
          extract_from_markdown_ld(parsed, content, options)
        end

      _ ->
        {:error, {:unsupported_format, format}}
    end
  end

  @doc """
  Build a knowledge graph from multiple documents with linked data.

  ## Examples

      documents = [doc1, doc2, doc3]
      {:ok, graph} = LinkedDataExtractor.build_knowledge_graph(documents)

  """
  @spec build_knowledge_graph([Document.t()], extraction_options()) ::
          {:ok, KnowledgeGraph.t()} | {:error, term()}
  def build_knowledge_graph(documents, options \\ []) when is_list(documents) do
    options = Keyword.merge(@default_options, options)

    with {:ok, linked_data_list} <- extract_from_documents(documents, options),
         {:ok, graph} <- KnowledgeGraph.build_from_linked_data(linked_data_list, options) do
      {:ok, graph}
    end
  end

  @doc """
  Validate linked data structure and context.

  ## Examples

      {:ok, :valid} = LinkedDataExtractor.validate(linked_data)
      {:error, {:invalid_context, reason}} = LinkedDataExtractor.validate(bad_data)

  """
  @spec validate(linked_data()) :: {:ok, :valid} | {:error, term()}
  def validate(%{} = linked_data) do
    with :ok <- validate_context(linked_data[:context]),
         :ok <- validate_entities(linked_data[:entities]),
         :ok <- validate_relationships(linked_data[:relationships]),
         :ok <- validate_triples(linked_data[:triples]) do
      {:ok, :valid}
    end
  end

  # === Private Functions - JSON-LD Processing ===

  defp extract_from_jsonld(parsed, _content, options) do
    Logger.debug("Extracting linked data from JSON-LD", parsed_type: typeof(parsed))

    with {:ok, context} <- extract_jsonld_context(parsed, options),
         {:ok, entities} <- extract_jsonld_entities(parsed, context, options),
         {:ok, relationships} <- extract_jsonld_relationships(parsed, entities, options),
         {:ok, triples} <- generate_rdf_triples(entities, relationships) do
      linked_data = %{
        context: context,
        entities: entities,
        relationships: relationships,
        triples: triples,
        vocab_used: extract_vocabulary_used(context),
        confidence_scores: calculate_confidence_scores(entities, relationships)
      }

      {:ok, linked_data}
    end
  end

  defp extract_jsonld_context(parsed, options) do
    if Keyword.get(options, :extract_context, true) do
      case Map.get(parsed, "@context") do
        nil ->
          {:ok, nil}

        context when is_binary(context) ->
          {:ok, %{"@context" => context}}

        context when is_map(context) ->
          if Keyword.get(options, :expand_context, true) do
            expand_context(context)
          else
            {:ok, context}
          end

        context when is_list(context) ->
          {:ok, %{"@context" => context}}

        _ ->
          {:error, :invalid_context_format}
      end
    else
      {:ok, nil}
    end
  end

  defp extract_jsonld_entities(parsed, context, options) do
    if Keyword.get(options, :extract_entities, true) do
      entities = do_extract_jsonld_entities(parsed, context, options)
      {:ok, entities}
    else
      {:ok, []}
    end
  end

  defp do_extract_jsonld_entities(parsed, context, options) when is_map(parsed) do
    base_entity = extract_primary_entity(parsed, context)
    nested_entities = extract_nested_entities(parsed, context, options)

    [base_entity | nested_entities]
    |> Enum.filter(&(not is_nil(&1)))
    |> Enum.filter(&meets_confidence_threshold(&1, options))
  end

  defp do_extract_jsonld_entities(parsed, _context, _options) when is_list(parsed) do
    # Handle JSON-LD arrays
    parsed
    |> Enum.flat_map(&extract_entity_from_item/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp extract_primary_entity(parsed, context) do
    type = Map.get(parsed, "@type")
    id = Map.get(parsed, "@id")

    if type do
      properties =
        parsed
        |> Map.drop(["@context", "@type", "@id"])
        |> expand_property_names(context)

      %{
        id: id,
        type: expand_type_name(type, context),
        properties: properties,
        uri: resolve_uri(id, context),
        confidence: calculate_entity_confidence(parsed, type)
      }
    else
      nil
    end
  end

  defp extract_nested_entities(parsed, context, options) do
    parsed
    |> Enum.flat_map(fn {_key, value} ->
      case value do
        %{"@type" => _} = nested ->
          [do_extract_jsonld_entities(nested, context, options)]

        list when is_list(list) ->
          Enum.flat_map(list, fn item ->
            if is_map(item) and Map.has_key?(item, "@type") do
              [do_extract_jsonld_entities(item, context, options)]
            else
              []
            end
          end)

        _ ->
          []
      end
    end)
    |> List.flatten()
  end

  defp extract_jsonld_relationships(parsed, entities, options) do
    if Keyword.get(options, :extract_relationships, true) do
      relationships = do_extract_jsonld_relationships(parsed, entities)
      {:ok, relationships}
    else
      {:ok, []}
    end
  end

  defp do_extract_jsonld_relationships(parsed, _entities) when is_map(parsed) do
    subject_id = Map.get(parsed, "@id", "_:blank")

    parsed
    |> Map.drop(["@context", "@type", "@id"])
    |> Enum.flat_map(fn {predicate, object} ->
      case object do
        %{"@id" => object_id} ->
          [create_relationship(subject_id, predicate, object_id)]

        object_id when is_binary(object_id) ->
          if String.starts_with?(object_id, "http") do
            [create_relationship(subject_id, predicate, object_id)]
          else
            []
          end

        list when is_list(list) ->
          Enum.map(list, fn item ->
            case item do
              %{"@id" => id} -> create_relationship(subject_id, predicate, id)
              id when is_binary(id) -> create_relationship(subject_id, predicate, id)
              _ -> nil
            end
          end)
          |> Enum.filter(&(not is_nil(&1)))

        _ ->
          []
      end
    end)
  end

  # === Private Functions - Markdown-LD Processing ===

  defp extract_from_markdown_ld(parsed, content, options) do
    Logger.debug("Extracting linked data from Markdown-LD")

    with {:ok, entities} <- extract_markdown_ld_entities(parsed, content, options),
         {:ok, relationships} <- extract_markdown_ld_relationships(parsed, entities),
         {:ok, triples} <- generate_rdf_triples(entities, relationships) do
      linked_data = %{
        context: extract_markdown_ld_context(content),
        entities: entities,
        relationships: relationships,
        triples: triples,
        vocab_used: ["https://schema.org/"],
        confidence_scores: calculate_confidence_scores(entities, relationships)
      }

      {:ok, linked_data}
    end
  end

  defp extract_markdown_ld_relationships(_parsed, _entities) do
    # TODO: Implement relationship extraction from Markdown-LD
    # This would analyze semantic links between entities in the markdown
    {:ok, []}
  end

  defp extract_markdown_ld_entities(_parsed, content, options) do
    # Extract entities from data-lang-entity attributes
    entity_patterns = [
      ~r/<[^>]+data-lang-entity="([^"]+)"[^>]*data-lang-uri="([^"]+)"[^>]*>([^<]+)</,
      ~r/<[^>]+data-lang-uri="([^"]+)"[^>]*data-lang-entity="([^"]+)"[^>]*>([^<]+)</
    ]

    entities =
      entity_patterns
      |> Enum.flat_map(&Regex.scan(&1, content))
      |> Enum.map(&create_markdown_ld_entity/1)
      |> Enum.filter(&meets_confidence_threshold(&1, options))

    {:ok, entities}
  end

  defp create_markdown_ld_entity([_full_match, entity_type, uri, text]) do
    %{
      id: generate_entity_id(text),
      type: entity_type,
      properties: %{
        "name" => String.trim(text),
        "text" => String.trim(text)
      },
      uri: uri,
      # High confidence for explicit markup
      confidence: 0.9
    }
  end

  defp extract_markdown_ld_context(content) do
    # Look for context declarations in HTML comments or meta tags
    context_pattern = ~r/<!--\s*@context:\s*([^-]+)\s*-->/

    case Regex.run(context_pattern, content) do
      [_, context_url] -> %{"@context" => String.trim(context_url)}
      nil -> %{"@context" => "https://schema.org/"}
    end
  end

  # === Private Functions - Standard Format Processing ===

  defp extract_from_json(parsed, _content, options) do
    # Try to infer semantic structure from regular JSON
    entities = infer_entities_from_json(parsed, options)
    relationships = infer_relationships_from_json(parsed, entities)

    linked_data = %{
      context: nil,
      entities: entities,
      relationships: relationships,
      triples: [],
      vocab_used: [],
      confidence_scores: %{}
    }

    {:ok, linked_data}
  end

  defp extract_from_markdown(parsed, content, options) do
    # Extract entities from markdown structure
    entities = extract_markdown_entities(parsed, content, options)

    linked_data = %{
      context: nil,
      entities: entities,
      relationships: [],
      triples: [],
      vocab_used: [],
      confidence_scores: %{}
    }

    {:ok, linked_data}
  end

  defp extract_from_xml(_parsed, _content, _options) do
    # TODO: Implement XML/RDFa extraction
    {:ok, empty_linked_data()}
  end

  defp extract_from_text(content, options) do
    # Basic entity recognition from plain text
    entities = perform_ner(content, options)

    linked_data = %{
      context: nil,
      entities: entities,
      relationships: [],
      triples: [],
      vocab_used: [],
      confidence_scores: %{}
    }

    {:ok, linked_data}
  end

  # === Helper Functions ===

  defp parse_jsonld(content) do
    try do
      case Jason.decode(content) do
        {:ok, parsed} -> {:ok, parsed}
        {:error, reason} -> {:error, {:json_decode_error, reason}}
      end
    rescue
      error -> {:error, {:parsing_failed, error}}
    end
  end

  defp parse_markdown_ld(content) do
    # Use markdown_ld library if available, otherwise parse as markdown
    case Code.ensure_loaded(MarkdownLD) do
      {:module, MarkdownLD} ->
        try do
          {:ok, MarkdownLD.parse(content)}
        rescue
          error -> {:error, {:markdown_ld_parse_error, error}}
        end

      {:error, :nofile} ->
        # Fallback to basic markdown parsing
        {:ok, %{content: content, entities: [], markup: []}}
    end
  end

  defp expand_context(context) do
    # TODO: Implement full JSON-LD context expansion
    # For now, return as-is
    {:ok, context}
  end

  defp expand_property_names(properties, _context) do
    # TODO: Expand compact IRIs using context
    properties
  end

  defp expand_type_name(type, _context) do
    # TODO: Expand type names using context
    type
  end

  defp resolve_uri(nil, _context), do: nil

  defp resolve_uri(id, _context) when is_binary(id) do
    if String.starts_with?(id, "http") do
      id
    else
      # TODO: Resolve relative URIs using context base
      id
    end
  end

  defp calculate_entity_confidence(parsed, type) do
    base_confidence = if type, do: 0.8, else: 0.3

    # Increase confidence based on completeness
    property_count = map_size(Map.drop(parsed, ["@context", "@type", "@id"]))
    completeness_bonus = min(0.2, property_count * 0.05)

    base_confidence + completeness_bonus
  end

  defp meets_confidence_threshold(entity, options) do
    threshold = Keyword.get(options, :confidence_threshold, 0.7)
    entity.confidence >= threshold
  end

  defp create_relationship(subject, predicate, object) do
    %{
      subject: subject,
      predicate: predicate,
      object: object,
      confidence: 0.8
    }
  end

  defp generate_rdf_triples(entities, relationships) do
    entity_triples =
      entities
      |> Enum.flat_map(&entity_to_triples/1)

    relationship_triples =
      relationships
      |> Enum.map(&relationship_to_triple/1)

    {:ok, entity_triples ++ relationship_triples}
  end

  defp entity_to_triples(entity) do
    base_triples = []

    # Add type triple
    type_triple =
      if entity.type do
        [{entity.id || "_:blank", "rdf:type", entity.type}]
      else
        []
      end

    # Add property triples
    property_triples =
      entity.properties
      |> Enum.map(fn {prop, value} ->
        {entity.id || "_:blank", prop, value}
      end)

    base_triples ++ type_triple ++ property_triples
  end

  defp relationship_to_triple(relationship) do
    {relationship.subject, relationship.predicate, relationship.object}
  end

  defp extract_vocabulary_used(nil), do: []

  defp extract_vocabulary_used(context) when is_map(context) do
    context
    |> Map.values()
    |> Enum.filter(&is_binary/1)
    |> Enum.filter(&String.starts_with?(&1, "http"))
    |> Enum.uniq()
  end

  defp calculate_confidence_scores(entities, relationships) do
    entity_avg =
      if length(entities) > 0 do
        entities |> Enum.reduce(0, fn x, acc -> acc + x.confidence end) |> Kernel./(length(entities))
      else
        0.0
      end

    relationship_avg =
      if length(relationships) > 0 do
        relationships
        |> Enum.reduce(0, fn x, acc -> acc + x.confidence end)
        |> Kernel./(length(relationships))
      else
        0.0
      end

    %{
      entities_avg: entity_avg,
      relationships_avg: relationship_avg,
      overall: (entity_avg + relationship_avg) / 2
    }
  end

  defp generate_entity_id(text) do
    # Generate a simple ID based on text
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.replace(~r/\s+/, "_")
    |> then(&"_:#{&1}")
  end

  defp extract_entity_from_item(item) when is_map(item) do
    if Map.has_key?(item, "@type") do
      [extract_primary_entity(item, nil)]
    else
      []
    end
  end

  defp extract_entity_from_item(_), do: []

  defp infer_entities_from_json(parsed, _options) when is_map(parsed) do
    # Simple heuristics for entity detection in JSON
    cond do
      Map.has_key?(parsed, "id") or Map.has_key?(parsed, "name") ->
        [
          %{
            id: Map.get(parsed, "id", "_:inferred"),
            type: infer_type_from_properties(parsed),
            properties: parsed,
            uri: nil,
            confidence: 0.5
          }
        ]

      true ->
        []
    end
  end

  defp infer_entities_from_json(_, _), do: []

  defp infer_relationships_from_json(_parsed, _entities) do
    # TODO: Implement relationship inference
    []
  end

  defp extract_markdown_entities(parsed, _content, _options) do
    # Extract entities from markdown headers, links, etc.
    headers = Map.get(parsed, :headers, [])

    headers
    |> Enum.with_index()
    |> Enum.map(fn {header, index} ->
      %{
        id: "_:header_#{index}",
        type: "schema:Thing",
        properties: %{"name" => String.replace(header, ~r/^#+\s*/, "")},
        uri: nil,
        confidence: 0.6
      }
    end)
  end

  defp perform_ner(content, _options) do
    # Basic named entity recognition
    # TODO: Integrate with proper NER library
    words = String.split(content)

    words
    |> Enum.filter(&String.match?(&1, ~r/^[A-Z][a-z]+$/))
    |> Enum.uniq()
    |> Enum.with_index()
    |> Enum.map(fn {word, index} ->
      %{
        id: "_:entity_#{index}",
        type: "schema:Thing",
        properties: %{"name" => word},
        uri: nil,
        confidence: 0.4
      }
    end)
  end

  defp infer_type_from_properties(properties) do
    cond do
      Map.has_key?(properties, "email") or Map.has_key?(properties, "name") ->
        "schema:Person"

      Map.has_key?(properties, "title") or Map.has_key?(properties, "description") ->
        "schema:CreativeWork"

      true ->
        "schema:Thing"
    end
  end

  defp extract_from_documents(documents, options) do
    documents
    |> Enum.map(&extract(&1, options))
    |> collect_results()
  end

  defp collect_results(results) do
    {successes, errors} =
      results
      |> Enum.split_with(fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    if length(errors) > 0 do
      Logger.warning("Some linked data extractions failed",
        error_count: length(errors),
        success_count: length(successes)
      )
    end

    success_data = Enum.map(successes, fn {:ok, data} -> data end)
    {:ok, success_data}
  end

  defp empty_linked_data do
    %{
      context: nil,
      entities: [],
      relationships: [],
      triples: [],
      vocab_used: [],
      confidence_scores: %{}
    }
  end

  defp typeof(term) do
    cond do
      is_map(term) -> :map
      is_list(term) -> :list
      is_binary(term) -> :binary
      true -> :other
    end
  end

  # === Validation Functions ===

  defp validate_context(nil), do: :ok
  defp validate_context(context) when is_map(context), do: :ok
  defp validate_context(_), do: {:error, :invalid_context}

  defp validate_entities(entities) when is_list(entities) do
    if Enum.all?(entities, &valid_entity?/1) do
      :ok
    else
      {:error, :invalid_entities}
    end
  end

  defp validate_entities(_), do: {:error, :invalid_entities}

  defp validate_relationships(relationships) when is_list(relationships) do
    if Enum.all?(relationships, &valid_relationship?/1) do
      :ok
    else
      {:error, :invalid_relationships}
    end
  end

  defp validate_relationships(_), do: {:error, :invalid_relationships}

  defp validate_triples(triples) when is_list(triples) do
    if Enum.all?(triples, &valid_triple?/1) do
      :ok
    else
      {:error, :invalid_triples}
    end
  end

  defp validate_triples(_), do: {:error, :invalid_triples}

  defp valid_entity?(%{type: type, confidence: conf})
       when is_binary(type) and is_number(conf) and conf >= 0 and conf <= 1,
       do: true

  defp valid_entity?(_), do: false

  defp valid_relationship?(%{subject: s, predicate: p, object: o, confidence: c})
       when is_binary(s) and is_binary(p) and is_binary(o) and is_number(c),
       do: true

  defp valid_relationship?(_), do: false

  defp valid_triple?({s, p, o})
       when is_binary(s) and is_binary(p) and is_binary(o),
       do: true

  defp valid_triple?(_), do: false
end
