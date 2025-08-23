defmodule Lang.Workers.SemanticAnalysisWorker do
  @moduledoc """
  Semantic Analysis Worker for deep semantic processing.

  This worker performs advanced semantic analysis including entity extraction,
  relationship mapping, and cross-document similarity analysis using the
  UniversalParser and LinkedDataExtractor systems.

  ## Features

  - **Entity Relationship Extraction** - Extract semantic entities across documents
  - **Semantic Similarity Analysis** - Compare semantic meaning between files
  - **Knowledge Graph Building** - Build interconnected semantic relationships
  - **Cross-Reference Analysis** - Find references and connections between documents
  - **Linked Data Processing** - Process JSON-LD and Markdown-LD semantic data
  - **Semantic Indexing** - Create searchable semantic indexes

  ## Usage

      # Queue semantic analysis job
      job = SemanticAnalysisWorker.new(%{
        "scan_result_id" => scan_result.id,
        "session_id" => session.id,
        "language" => "elixir",
        "analysis_depth" => "standard"
      })
      |> Oban.insert()

  """

  use Oban.Worker, queue: :analysis, max_attempts: 3

  alias Lang.Analysis
  alias Kyozo.Lang.UniversalParser
  alias Kyozo.Lang.UniversalParser.{LinkedDataExtractor, KnowledgeGraph}
  alias Lang.Native.Parser
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    scan_result_id = args["scan_result_id"]
    session_id = args["session_id"]
    language = args["language"]
    analysis_depth = args["analysis_depth"] || "standard"

    Logger.info("Starting semantic analysis",
      scan_result_id: scan_result_id,
      session_id: session_id,
      language: language,
      depth: analysis_depth
    )

    try do
      # Get analyzed files for this language from the session
      files =
        Analysis.list_analyzed_files(session_id,
          filters: %{language_detected: language},
          limit: 1000
        )

      if Enum.empty?(files) do
        Logger.info("No files found for semantic analysis",
          session_id: session_id,
          language: language
        )

        :ok
      else
        # Process files for semantic analysis
        semantic_results = process_semantic_analysis(files, analysis_depth)

        # Update each file with semantic analysis results
        update_files_with_results(files, semantic_results)

        Logger.info("Semantic analysis completed",
          scan_result_id: scan_result_id,
          files_processed: length(files),
          entities_found: count_total_entities(semantic_results)
        )

        :ok
      end
    rescue
      error ->
        Logger.error("Semantic analysis failed",
          scan_result_id: scan_result_id,
          session_id: session_id,
          error: Exception.message(error)
        )

        {:error, {:analysis_failed, error}}
    end
  end

  # === Private Functions ===

  defp process_semantic_analysis(files, analysis_depth) do
    Logger.info("Processing semantic analysis for #{length(files)} files", depth: analysis_depth)

    # Process each file individually first
    individual_results =
      files
      |> Enum.map(&process_file_semantics(&1, analysis_depth))
      |> Enum.reject(&is_nil/1)

    # Build cross-document relationships
    cross_document_analysis = build_cross_document_relationships(individual_results)

    # Create knowledge graph if deep analysis requested
    knowledge_graph =
      if analysis_depth == "deep" do
        build_knowledge_graph(individual_results, cross_document_analysis)
      else
        %{}
      end

    %{
      individual_results: individual_results,
      cross_document_analysis: cross_document_analysis,
      knowledge_graph: knowledge_graph
    }
  end

  defp process_file_semantics(file, _analysis_depth) do
    try do
      # Parse content using UniversalParser
      {:ok, document} =
        UniversalParser.parse(file.content,
          include_analysis: true,
          include_insights: true,
          include_linked_data: true
        )

      # Extract semantic information
      semantic_data = LinkedDataExtractor.extract(document)

      # Perform entity extraction
      entities = extract_entities(document, semantic_data)

      # Extract relationships within the document
      relationships = extract_relationships(document, entities, semantic_data)

      # Calculate semantic complexity
      complexity = calculate_semantic_complexity(document, entities, relationships)

      # Extract topics and themes
      topics = extract_topics(document, entities)

      # Perform sentiment analysis if applicable
      sentiment = analyze_semantic_sentiment(document)

      %{
        file_id: file.id,
        file_path: file.file_path,
        entities: entities,
        relationships: relationships,
        semantic_data: semantic_data,
        complexity: complexity,
        topics: topics,
        sentiment: sentiment,
        document: document
      }
    rescue
      error ->
        Logger.warning("Failed to process semantic analysis for file",
          file_id: file.id,
          error: Exception.message(error)
        )

        nil
    end
  end

  defp extract_entities(document, semantic_data) do
    entities = %{}

    # Extract from linked data if available
    entities =
      if semantic_data.rdf_triples && length(semantic_data.rdf_triples) > 0 do
        extract_entities_from_rdf(semantic_data.rdf_triples)
      else
        entities
      end

    # Extract from document structure
    entities = Map.merge(entities, extract_entities_from_structure(document))

    # Extract named entities from content
    entities = Map.merge(entities, extract_named_entities(document.content))

    # Extract code entities if it's a code file
    entities =
      if document.format in ["javascript", "typescript", "python", "elixir", "rust"] do
        Map.merge(entities, extract_code_entities(document))
      else
        entities
      end

    entities
  end

  defp extract_entities_from_rdf(rdf_triples) do
    entities = %{}

    Enum.reduce(rdf_triples, entities, fn triple, acc ->
      subject = Map.get(triple, :subject)
      _predicate = Map.get(triple, :predicate)
      object = Map.get(triple, :object)

      # Extract entities from subjects and objects
      acc
      |> add_entity_if_valid(subject, "rdf_subject")
      |> add_entity_if_valid(object, "rdf_object")
    end)
  end

  defp extract_entities_from_structure(document) do
    entities = %{}

    # Extract from headers
    entities =
      case document.structure do
        %{headers: headers} when is_list(headers) ->
          header_entities =
            headers
            |> Enum.with_index()
            |> Enum.map(fn {header, index} ->
              {"header_#{index}", %{type: "header", value: header, context: "document_structure"}}
            end)
            |> Map.new()

          Map.merge(entities, header_entities)

        _ ->
          entities
      end

    # Extract from links
    entities =
      case document.structure do
        %{links: links} when is_list(links) ->
          link_entities =
            links
            |> Enum.with_index()
            |> Enum.map(fn {link, index} ->
              {"link_#{index}", %{type: "link", value: link, context: "document_links"}}
            end)
            |> Map.new()

          Map.merge(entities, link_entities)

        _ ->
          entities
      end

    entities
  end

  defp extract_named_entities(content) do
    entities = %{}

    # Extract proper nouns (capitalized words)
    proper_nouns =
      Regex.scan(~r/\b[A-Z][a-z]{2,}\b/, content)
      |> Enum.map(&List.first/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_word, count} -> count > 1 end)

    entities =
      proper_nouns
      |> Enum.with_index()
      |> Enum.reduce(entities, fn {{word, count}, index}, acc ->
        Map.put(acc, "proper_noun_#{index}", %{
          type: "proper_noun",
          value: word,
          frequency: count,
          context: "content_analysis"
        })
      end)

    # Extract email addresses
    emails =
      Regex.scan(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, content)
      |> Enum.map(&List.first/1)
      |> Enum.uniq()

    entities =
      emails
      |> Enum.with_index()
      |> Enum.reduce(entities, fn {email, index}, acc ->
        Map.put(acc, "email_#{index}", %{
          type: "email",
          value: email,
          context: "contact_information"
        })
      end)

    # Extract URLs
    urls =
      Regex.scan(~r/https?:\/\/[^\s]+/, content)
      |> Enum.map(&List.first/1)
      |> Enum.uniq()

    entities =
      urls
      |> Enum.with_index()
      |> Enum.reduce(entities, fn {url, index}, acc ->
        Map.put(acc, "url_#{index}", %{
          type: "url",
          value: url,
          context: "external_references"
        })
      end)

    entities
  end

  defp extract_code_entities(document) do
    entities = %{}
    content = document.content

    # Extract function definitions
    functions =
      case document.format do
        "elixir" ->
          Regex.scan(~r/def\s+([a-zA-Z_][a-zA-Z0-9_]*)/, content)
          |> Enum.map(fn [_, name] -> name end)

        "javascript" ->
          function_regex =
            ~r/(?:function\s+([a-zA-Z_][a-zA-Z0-9_]*)|([a-zA-Z_][a-zA-Z0-9_]*)\s*[:=]\s*function)/

          Regex.scan(function_regex, content)
          |> Enum.map(fn matches -> Enum.find(matches, &(&1 && &1 != "")) end)
          |> Enum.reject(&is_nil/1)

        "python" ->
          Regex.scan(~r/def\s+([a-zA-Z_][a-zA-Z0-9_]*)/, content)
          |> Enum.map(fn [_, name] -> name end)

        _ ->
          []
      end

    entities =
      functions
      |> Enum.with_index()
      |> Enum.reduce(entities, fn {func_name, index}, acc ->
        Map.put(acc, "function_#{index}", %{
          type: "function",
          value: func_name,
          language: document.format,
          context: "code_definition"
        })
      end)

    # Extract module/class definitions
    modules =
      case document.format do
        "elixir" ->
          Regex.scan(~r/defmodule\s+([A-Za-z0-9_.]+)/, content)
          |> Enum.map(fn [_, name] -> name end)

        "javascript" ->
          Regex.scan(~r/class\s+([A-Za-z0-9_]+)/, content)
          |> Enum.map(fn [_, name] -> name end)

        "python" ->
          Regex.scan(~r/class\s+([A-Za-z0-9_]+)/, content)
          |> Enum.map(fn [_, name] -> name end)

        _ ->
          []
      end

    entities =
      modules
      |> Enum.with_index()
      |> Enum.reduce(entities, fn {module_name, index}, acc ->
        Map.put(acc, "module_#{index}", %{
          type: "module",
          value: module_name,
          language: document.format,
          context: "code_definition"
        })
      end)

    entities
  end

  defp add_entity_if_valid(entities, value, type)
       when is_binary(value) and byte_size(value) > 0 do
    entity_key = "#{type}_#{:erlang.phash2(value)}"

    Map.put(entities, entity_key, %{
      type: type,
      value: value,
      context: "rdf_data"
    })
  end

  defp add_entity_if_valid(entities, _value, _type), do: entities

  defp extract_relationships(document, entities, semantic_data) do
    relationships = []

    # Extract from RDF triples
    relationships =
      if semantic_data.rdf_triples && length(semantic_data.rdf_triples) > 0 do
        rdf_relationships =
          semantic_data.rdf_triples
          |> Enum.map(fn triple ->
            %{
              type: "rdf_relationship",
              subject: Map.get(triple, :subject),
              predicate: Map.get(triple, :predicate),
              object: Map.get(triple, :object),
              context: "linked_data"
            }
          end)

        relationships ++ rdf_relationships
      else
        relationships
      end

    # Extract entity co-occurrence relationships
    entity_relationships = build_entity_cooccurrence_relationships(entities, document.content)

    relationships ++ entity_relationships
  end

  defp build_entity_cooccurrence_relationships(entities, content) do
    entity_values =
      entities
      |> Enum.map(fn {_key, entity} -> {entity.value, entity.type} end)
      |> Enum.filter(fn {value, _type} -> String.length(value) > 2 end)

    # Find entities that appear close to each other in the text
    _relationships = []

    for {value1, type1} <- entity_values,
        {value2, type2} <- entity_values,
        value1 != value2 do
      # Check if entities appear within 100 characters of each other
      if entities_are_colocated?(content, value1, value2, 100) do
        %{
          type: "cooccurrence",
          subject: value1,
          subject_type: type1,
          object: value2,
          object_type: type2,
          context: "text_proximity"
        }
      else
        nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  defp entities_are_colocated?(content, entity1, entity2, max_distance) do
    content_lower = String.downcase(content)
    entity1_lower = String.downcase(entity1)
    entity2_lower = String.downcase(entity2)

    # Find all positions of entity1
    entity1_positions = find_all_positions(content_lower, entity1_lower)
    entity2_positions = find_all_positions(content_lower, entity2_lower)

    # Check if any positions are within max_distance
    Enum.any?(entity1_positions, fn pos1 ->
      Enum.any?(entity2_positions, fn pos2 ->
        abs(pos1 - pos2) <= max_distance
      end)
    end)
  end

  defp find_all_positions(content, search_term) do
    find_positions(content, search_term, 0, [])
  end

  defp find_positions(content, search_term, start_pos, positions) do
    case :binary.match(content, search_term, scope: {start_pos, byte_size(content) - start_pos}) do
      {pos, _len} ->
        find_positions(content, search_term, pos + 1, [pos | positions])

      :nomatch ->
        Enum.reverse(positions)
    end
  end

  defp calculate_semantic_complexity(document, entities, relationships) do
    base_complexity = Map.get(document.analysis || %{}, :complexity_score, 3.0)

    entity_complexity = min(map_size(entities) * 0.1, 2.0)
    relationship_complexity = min(length(relationships) * 0.05, 1.5)

    total_complexity = base_complexity + entity_complexity + relationship_complexity

    # Normalize to 1-10 scale
    min(10.0, max(1.0, total_complexity))
  end

  defp extract_topics(document, entities) do
    # Base topics from document analysis
    base_topics =
      case document.analysis do
        %{topics: topics} when is_list(topics) -> topics
        _ -> []
      end

    # Topics from entities
    entity_topics =
      entities
      |> Enum.map(fn {_key, entity} -> entity.value end)
      |> Enum.filter(fn value -> String.length(value) > 3 end)
      |> Enum.take(10)

    # Topics from document format/type
    format_topics =
      case document.format do
        format when format in ["javascript", "typescript"] -> ["javascript", "web_development"]
        "python" -> ["python", "programming"]
        "elixir" -> ["elixir", "functional_programming"]
        "markdown" -> ["documentation", "text"]
        _ -> []
      end

    (base_topics ++ entity_topics ++ format_topics)
    |> Enum.uniq()
    |> Enum.take(15)
  end

  defp analyze_semantic_sentiment(document) do
    content = String.downcase(document.content)

    # Technical sentiment indicators
    positive_indicators = [
      "improve",
      "optimize",
      "enhance",
      "better",
      "good",
      "great",
      "excellent",
      "clean",
      "simple",
      "elegant",
      "efficient",
      "fast",
      "secure",
      "stable"
    ]

    negative_indicators = [
      "bug",
      "error",
      "fail",
      "broken",
      "slow",
      "complex",
      "difficult",
      "deprecated",
      "legacy",
      "hack",
      "workaround",
      "issue",
      "problem"
    ]

    neutral_indicators = [
      "update",
      "change",
      "modify",
      "implement",
      "add",
      "remove",
      "refactor"
    ]

    positive_count = Enum.count(positive_indicators, &String.contains?(content, &1))
    negative_count = Enum.count(negative_indicators, &String.contains?(content, &1))
    neutral_count = Enum.count(neutral_indicators, &String.contains?(content, &1))

    total_sentiment = positive_count + negative_count + neutral_count

    if total_sentiment == 0 do
      %{sentiment: :neutral, confidence: 0.0}
    else
      sentiment =
        cond do
          positive_count > negative_count and positive_count > neutral_count -> :positive
          negative_count > positive_count and negative_count > neutral_count -> :negative
          true -> :neutral
        end

      confidence = Enum.max([positive_count, negative_count, neutral_count]) / total_sentiment

      %{sentiment: sentiment, confidence: confidence}
    end
  end

  defp build_cross_document_relationships(individual_results) do
    Logger.info("Building cross-document relationships for #{length(individual_results)} files")

    cross_links = []

    # Find files that reference each other by name/path
    cross_links = cross_links ++ find_file_references(individual_results)

    # Find shared entities across files
    cross_links = cross_links ++ find_shared_entities(individual_results)

    # Find similar topics/themes
    cross_links = cross_links ++ find_topic_similarities(individual_results)

    %{
      cross_document_links: cross_links,
      total_connections: length(cross_links)
    }
  end

  defp find_file_references(individual_results) do
    file_paths = Enum.map(individual_results, & &1.file_path)

    references = []

    for result <- individual_results do
      content = result.document.content

      # Find references to other files in the same analysis
      file_refs =
        file_paths
        |> Enum.reject(&(&1 == result.file_path))
        |> Enum.filter(fn other_path ->
          filename = Path.basename(other_path)
          String.contains?(content, filename) or String.contains?(content, other_path)
        end)
        |> Enum.map(fn referenced_path ->
          %{
            type: "file_reference",
            source_file: result.file_path,
            target_file: referenced_path,
            context: "direct_reference"
          }
        end)

      references ++ file_refs
    end
  end

  defp find_shared_entities(individual_results) do
    # Create entity index across all files
    entity_index = %{}

    entity_index =
      Enum.reduce(individual_results, entity_index, fn result, acc ->
        Enum.reduce(result.entities, acc, fn {_key, entity}, inner_acc ->
          entity_value = entity.value
          current_files = Map.get(inner_acc, entity_value, [])
          Map.put(inner_acc, entity_value, [result.file_path | current_files])
        end)
      end)

    # Find entities shared by multiple files
    shared_entities =
      entity_index
      |> Enum.filter(fn {_entity, files} -> length(files) > 1 end)
      |> Enum.map(fn {entity_value, files} ->
        # Create connections between all files that share this entity
        for file1 <- files, file2 <- files, file1 != file2 do
          %{
            type: "shared_entity",
            source_file: file1,
            target_file: file2,
            shared_entity: entity_value,
            context: "entity_sharing"
          }
        end
      end)
      |> List.flatten()

    shared_entities
  end

  defp find_topic_similarities(individual_results) do
    _similarities = []

    for result1 <- individual_results,
        result2 <- individual_results,
        result1.file_path != result2.file_path do
      # Calculate topic overlap
      topics1 = MapSet.new(result1.topics)
      topics2 = MapSet.new(result2.topics)

      intersection = MapSet.intersection(topics1, topics2)
      union = MapSet.union(topics1, topics2)

      similarity_score =
        if MapSet.size(union) > 0 do
          MapSet.size(intersection) / MapSet.size(union)
        else
          0.0
        end

      if similarity_score > 0.3 do
        %{
          type: "topic_similarity",
          source_file: result1.file_path,
          target_file: result2.file_path,
          similarity_score: similarity_score,
          shared_topics: MapSet.to_list(intersection),
          context: "semantic_similarity"
        }
      else
        nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  defp build_knowledge_graph(individual_results, cross_document_analysis) do
    Logger.info("Building knowledge graph from semantic analysis")

    try do
      # Collect all entities and relationships
      all_entities =
        individual_results
        |> Enum.flat_map(fn result ->
          Enum.map(result.entities, fn {_key, entity} ->
            Map.put(entity, :source_file, result.file_path)
          end)
        end)

      all_relationships =
        individual_results
        |> Enum.flat_map(& &1.relationships)
        |> Kernel.++(cross_document_analysis.cross_document_links)

      # Use KnowledgeGraph module to build the graph
      {:ok, graph} = KnowledgeGraph.build_graph(all_entities, all_relationships)

      # Calculate graph metrics
      graph_analysis = KnowledgeGraph.analyze_graph(graph)

      %{
        graph: graph,
        analysis: graph_analysis,
        entity_count: length(all_entities),
        relationship_count: length(all_relationships)
      }
    rescue
      error ->
        Logger.warning("Failed to build knowledge graph", error: Exception.message(error))
        %{error: Exception.message(error)}
    end
  end

  defp update_files_with_results(files, semantic_results) do
    individual_results = semantic_results.individual_results

    # Create a map for quick lookup
    results_by_file_id =
      individual_results
      |> Enum.map(fn result -> {result.file_id, result} end)
      |> Map.new()

    # Update each file
    Enum.each(files, fn file ->
      case Map.get(results_by_file_id, file.id) do
        nil ->
          Logger.warning("No semantic results found for file", file_id: file.id)

        result ->
          update_attrs = %{
            semantic_entities: result.entities,
            entity_relationships: result.relationships,
            semantic_complexity: result.complexity,
            semantic_topics: result.topics,
            semantic_sentiment: result.sentiment,
            cross_document_links:
              get_file_cross_links(file.file_path, semantic_results.cross_document_analysis),
            semantic_analyzed_at: DateTime.utc_now()
          }

          case Analysis.update_analyzed_file(file, update_attrs) do
            {:ok, _updated_file} ->
              Logger.debug("Updated semantic analysis for file", file_id: file.id)

            {:error, reason} ->
              Logger.error("Failed to update semantic analysis",
                file_id: file.id,
                reason: inspect(reason)
              )
          end
      end
    end)
  end

  defp get_file_cross_links(file_path, cross_document_analysis) do
    cross_document_analysis.cross_document_links
    |> Enum.filter(fn link ->
      Map.get(link, :source_file) == file_path or Map.get(link, :target_file) == file_path
    end)
  end

  defp count_total_entities(semantic_results) do
    semantic_results.individual_results
    |> Enum.map(fn result -> map_size(result.entities) end)
    |> Enum.sum()
  end
end
