defmodule LangWeb.Api.V2.TextController do
  @moduledoc """
  Text Intelligence API v2 Controller

  This controller implements the text intelligence endpoints documented in the
  OpenAPI specification. It provides comprehensive text analysis capabilities
  including parsing, entity extraction, semantic analysis, and stylometric analysis.

  All endpoints are authenticated and rate-limited according to user billing plans.
  """

  use LangWeb, :controller

  alias Lang.Analysis
  alias Lang.Workers.{SemanticAnalysisWorker, SecurityScanWorker, DependencyAnalysisWorker}
  alias Kyozo.Lang.UniversalParser
  alias Kyozo.Lang.UniversalParser.LinkedDataExtractor
  alias Lang.Stylometrics.AnalysisEngine, as: StyleEngine
  alias Lang.Native.Parser
  require Logger

  action_fallback LangWeb.Api.FallbackController

  # Content size limits
  # 50MB
  @max_content_size 50 * 1024 * 1024
  @max_batch_size 100

  @doc """
  Parse text content and extract semantic information.

  POST /api/v2/text/parse

  Accepts JSON-LD format with content analysis options.
  Returns structured document with semantic analysis results.
  """
  def parse(conn, params) do
    with {:ok, content} <- validate_content(params),
         {:ok, options} <- validate_parse_options(params),
         {:ok, document} <- parse_content(content, options),
         {:ok, analysis} <- perform_analysis(document, options, conn.assigns.current_user) do
      # Track API usage
      track_api_usage(conn, "text_parse", byte_size(content))

      render(conn, "parse_result.json", %{
        document: document,
        analysis: analysis,
        metadata: build_response_metadata(document, analysis)
      })
    else
      {:error, :content_too_large} ->
        conn
        |> put_status(:payload_too_large)
        |> json(%{error: "Content exceeds maximum size of #{@max_content_size} bytes"})

      {:error, :invalid_format} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid content format or encoding"})

      {:error, reason} ->
        Logger.error("Text parse failed", reason: inspect(reason))

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Analysis failed", details: inspect(reason)})
    end
  end

  @doc """
  Extract named entities from text content.

  POST /api/v2/text/entities

  Performs advanced named entity recognition and classification.
  Returns structured entity data with confidence scores.
  """
  def entities(conn, params) do
    with {:ok, content} <- validate_content(params),
         {:ok, options} <- validate_entity_options(params),
         {:ok, document} <- parse_content(content, %{format: detect_format(content)}),
         {:ok, entities} <- extract_entities(document, options) do
      # Track API usage
      track_api_usage(conn, "entity_extraction", byte_size(content))

      render(conn, "entities.json", %{
        entities: entities,
        metadata: %{
          content_length: byte_size(content),
          entity_count: length(entities),
          processing_time_ms: System.monotonic_time(:millisecond)
        }
      })
    else
      {:error, reason} ->
        handle_api_error(conn, reason, "Entity extraction failed")
    end
  end

  @doc """
  Perform semantic analysis and triple extraction.

  POST /api/v2/text/semantic

  Extracts RDF triples, relationships, and semantic meaning.
  Returns linked data compatible results.
  """
  def semantic(conn, params) do
    with {:ok, content} <- validate_content(params),
         {:ok, options} <- validate_semantic_options(params),
         {:ok, document} <- parse_content(content, options),
         {:ok, semantic_data} <- extract_semantic_data(document, options),
         {:ok, job_result} <-
           queue_semantic_analysis(document, semantic_data, conn.assigns.current_user) do
      # Track API usage
      track_api_usage(conn, "semantic_analysis", byte_size(content))

      render(conn, "semantic.json", %{
        triples: semantic_data.rdf_triples,
        relationships: semantic_data.relationships,
        entities: semantic_data.entities,
        context: semantic_data.context,
        job_id: job_result.job_id,
        metadata: build_response_metadata(document, %{semantic_data: semantic_data})
      })
    else
      {:error, reason} ->
        handle_api_error(conn, reason, "Semantic analysis failed")
    end
  end

  @doc """
  Perform stylometric analysis on text.

  POST /api/v2/text/stylometry

  Analyzes writing style, authorship patterns, and stylistic features.
  Returns comprehensive stylometric fingerprint and analysis.
  """
  def stylometry(conn, params) do
    with {:ok, content} <- validate_content(params),
         {:ok, options} <- validate_stylometry_options(params),
         {:ok, analysis} <- perform_stylometric_analysis(content, options) do
      # Track API usage
      track_api_usage(conn, "stylometry", byte_size(content))

      render(conn, "stylometry.json", %{
        fingerprint: analysis.fingerprint,
        features: analysis.features,
        complexity: analysis.complexity,
        authorship: analysis.authorship,
        transformations: analysis.transformations,
        metadata: %{
          content_length: byte_size(content),
          analysis_time_ms: analysis.processing_time_ms,
          confidence_score: analysis.confidence
        }
      })
    else
      {:error, reason} ->
        handle_api_error(conn, reason, "Stylometric analysis failed")
    end
  end

  @doc """
  Process Markdown-LD content with semantic extraction.

  POST /api/v2/text/markdown-ld

  Specialized endpoint for Markdown with linked data annotations.
  Returns both parsed markdown and extracted semantic data.
  """
  def markdown_ld(conn, params) do
    with {:ok, content} <- validate_content(params),
         :ok <- validate_markdown_format(content),
         {:ok, document} <- parse_markdown_ld(content),
         {:ok, semantic_data} <- extract_linked_data(document) do
      # Track API usage
      track_api_usage(conn, "markdown_ld", byte_size(content))

      render(conn, "markdown_ld.json", %{
        markdown: document.structured_content,
        html: document.rendered_html,
        linked_data: semantic_data.linked_data,
        entities: semantic_data.entities,
        metadata: build_markdown_metadata(document, semantic_data)
      })
    else
      {:error, reason} ->
        handle_api_error(conn, reason, "Markdown-LD processing failed")
    end
  end

  @doc """
  General text analysis endpoint.

  POST /api/v2/text/analyze

  Comprehensive analysis combining multiple analysis types.
  Returns unified analysis results across all supported features.
  """
  def analyze(conn, params) do
    with {:ok, content} <- validate_content(params),
         {:ok, options} <- validate_analyze_options(params),
         {:ok, results} <-
           perform_comprehensive_analysis(content, options, conn.assigns.current_user) do
      # Track API usage
      track_api_usage(conn, "comprehensive_analysis", byte_size(content))

      render(conn, "comprehensive.json", results)
    else
      {:error, reason} ->
        handle_api_error(conn, reason, "Comprehensive analysis failed")
    end
  end

  # === Private Functions ===

  defp validate_content(params) do
    case Map.get(params, "content") do
      content when is_binary(content) and byte_size(content) > 0 ->
        if byte_size(content) <= @max_content_size do
          {:ok, content}
        else
          {:error, :content_too_large}
        end

      _ ->
        {:error, :missing_content}
    end
  end

  defp validate_parse_options(params) do
    options = %{
      format: Map.get(params, "format", "auto"),
      include_analysis: Map.get(params, "include_analysis", true),
      include_insights: Map.get(params, "include_insights", true),
      include_linked_data: Map.get(params, "include_linked_data", false),
      extract_entities: Map.get(params, "extract_entities", false),
      extract_semantics: Map.get(params, "extract_semantics", false)
    }

    {:ok, options}
  end

  defp validate_entity_options(params) do
    options = %{
      types: Map.get(params, "types", ["PERSON", "ORGANIZATION", "LOCATION"]),
      confidence_threshold: Map.get(params, "confidence_threshold", 0.7),
      include_positions: Map.get(params, "include_positions", true),
      include_context: Map.get(params, "include_context", true)
    }

    {:ok, options}
  end

  defp validate_semantic_options(params) do
    options = %{
      context: Map.get(params, "context", "https://schema.org"),
      extract_triples: Map.get(params, "extract_triples", true),
      infer_relationships: Map.get(params, "infer_relationships", true),
      include_provenance: Map.get(params, "include_provenance", false)
    }

    {:ok, options}
  end

  defp validate_stylometry_options(params) do
    options = %{
      features: Map.get(params, "features", ["vocabulary", "syntax", "punctuation", "length"]),
      include_transformations: Map.get(params, "include_transformations", false),
      obfuscation_level: Map.get(params, "obfuscation_level", 0.5),
      comparison_samples: Map.get(params, "comparison_samples", [])
    }

    {:ok, options}
  end

  defp validate_analyze_options(params) do
    options = %{
      include_parsing: Map.get(params, "include_parsing", true),
      include_entities: Map.get(params, "include_entities", true),
      include_semantics: Map.get(params, "include_semantics", true),
      include_stylometry: Map.get(params, "include_stylometry", false),
      include_security: Map.get(params, "include_security", false),
      include_dependencies: Map.get(params, "include_dependencies", false)
    }

    {:ok, options}
  end

  defp parse_content(content, options) do
    format = detect_format_if_auto(content, options)

    UniversalParser.parse(content, Map.put(options, :format, format))
  end

  defp detect_format(content) when is_binary(content) do
    cond do
      String.starts_with?(content, "# ") or String.contains?(content, "## ") -> "markdown"
      String.starts_with?(content, "{") and String.contains?(content, "}") -> "json"
      String.contains?(content, "---") and String.contains?(content, ":") -> "yaml"
      String.contains?(content, "<") and String.contains?(content, ">") -> "html"
      true -> "text"
    end
  end

  defp detect_format_if_auto(content, %{format: "auto"}), do: detect_format(content)
  defp detect_format_if_auto(_content, %{format: format}), do: format

  defp perform_analysis(document, options, _user) do
    results = %{}

    # Basic analysis always included
    results = Map.put(results, :document_analysis, analyze_document_structure(document))

    # Conditional analysis based on options
    results =
      if options[:extract_entities] do
        {:ok, entities} = extract_entities(document, %{})
        Map.put(results, :entities, entities)
      else
        results
      end

    results =
      if options[:extract_semantics] do
        {:ok, semantic_data} = extract_semantic_data(document, %{})
        Map.put(results, :semantic_data, semantic_data)
      else
        results
      end

    {:ok, results}
  end

  defp extract_entities(document, _options) do
    try do
      # Use LinkedDataExtractor for entity extraction
      semantic_data = LinkedDataExtractor.extract(document)

      # Extract entities from multiple sources
      entities = []

      # From RDF triples
      entities = entities ++ extract_entities_from_triples(semantic_data.rdf_triples)

      # From document structure
      entities = entities ++ extract_entities_from_structure(document)

      # From content analysis
      entities = entities ++ extract_named_entities_from_content(document.content)

      {:ok, entities}
    rescue
      error ->
        Logger.error("Entity extraction failed", error: Exception.message(error))
        {:error, :extraction_failed}
    end
  end

  defp extract_semantic_data(document, options) do
    try do
      # Extract linked data
      semantic_data = LinkedDataExtractor.extract(document)

      # Build relationships
      relationships = build_semantic_relationships(semantic_data, document)

      # Extract context information
      context = extract_semantic_context(semantic_data, options)

      result = %{
        rdf_triples: semantic_data.rdf_triples || [],
        relationships: relationships,
        entities: semantic_data.entities || %{},
        context: context,
        provenance: build_provenance_data(document)
      }

      {:ok, result}
    rescue
      error ->
        Logger.error("Semantic extraction failed", error: Exception.message(error))
        {:error, :semantic_extraction_failed}
    end
  end

  defp perform_stylometric_analysis(content, options) do
    try do
      # Use StyleEngine for comprehensive analysis
      {:ok, fingerprint} = StyleEngine.generate_fingerprint(content)
      {:ok, features} = StyleEngine.analyze_features(content, options[:features])

      # Optional transformations
      transformations =
        if options[:include_transformations] do
          {:ok, transforms} =
            StyleEngine.suggest_transformations(content, options[:obfuscation_level])

          transforms
        else
          %{}
        end

      # Authorship analysis if comparison samples provided
      authorship =
        if length(options[:comparison_samples]) > 0 do
          StyleEngine.compare_authorship(content, options[:comparison_samples])
        else
          %{confidence: 0.0, similarity_scores: []}
        end

      analysis = %{
        fingerprint: fingerprint,
        features: features,
        complexity: StyleEngine.calculate_complexity(content),
        authorship: authorship,
        transformations: transformations,
        # Approximate processing time
        processing_time_ms: 150,
        confidence: calculate_analysis_confidence(fingerprint, features)
      }

      {:ok, analysis}
    rescue
      error ->
        Logger.error("Stylometric analysis failed", error: Exception.message(error))
        {:error, :stylometry_failed}
    end
  end

  defp queue_semantic_analysis(document, semantic_data, user) do
    # Queue semantic analysis job for deeper processing
    job_args = %{
      "content" => document.content,
      "format" => document.format,
      "user_id" => user.id,
      "semantic_data" => semantic_data,
      "analysis_depth" => "deep"
    }

    case SemanticAnalysisWorker.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        {:ok, %{job_id: job.id, status: "queued"}}

      {:error, changeset} ->
        Logger.error("Failed to queue semantic analysis job", changeset: changeset)
        {:error, :job_queue_failed}
    end
  end

  defp perform_comprehensive_analysis(content, options, user) do
    results = %{
      content_length: byte_size(content),
      analysis_timestamp: DateTime.utc_now(),
      processing_components: []
    }

    # Parse document
    {:ok, document} = parse_content(content, %{format: detect_format(content)})
    results = Map.put(results, :document, document)

    # Conditional analysis components
    results =
      if options[:include_entities] do
        {:ok, entities} = extract_entities(document, %{})

        results
        |> Map.put(:entities, entities)
        |> update_in([:processing_components], &["entity_extraction" | &1])
      else
        results
      end

    results =
      if options[:include_semantics] do
        {:ok, semantic_data} = extract_semantic_data(document, %{})

        results
        |> Map.put(:semantic_data, semantic_data)
        |> update_in([:processing_components], &["semantic_analysis" | &1])
      else
        results
      end

    results =
      if options[:include_stylometry] do
        {:ok, stylometry} = perform_stylometric_analysis(content, %{features: ["all"]})

        results
        |> Map.put(:stylometry, stylometry)
        |> update_in([:processing_components], &["stylometric_analysis" | &1])
      else
        results
      end

    # Queue background jobs for deeper analysis
    if options[:include_security] do
      queue_security_analysis_job(content, user)
    end

    if options[:include_dependencies] do
      queue_dependency_analysis_job(content, user)
    end

    {:ok, results}
  end

  defp validate_markdown_format(content) do
    if String.contains?(content, "#") or String.contains?(content, "**") do
      :ok
    else
      {:error, :not_markdown}
    end
  end

  defp parse_markdown_ld(content) do
    try do
      {:ok, document} =
        UniversalParser.parse(content, %{
          format: "markdown",
          include_linked_data: true,
          render_html: true
        })

      {:ok, document}
    rescue
      _error ->
        {:error, :markdown_parse_failed}
    end
  end

  defp extract_linked_data(document) do
    try do
      linked_data = LinkedDataExtractor.extract(document)
      {:ok, linked_data}
    rescue
      _error ->
        {:error, :linked_data_extraction_failed}
    end
  end

  # Helper functions for entity extraction
  defp extract_entities_from_triples(triples) when is_list(triples) do
    triples
    |> Enum.flat_map(fn triple ->
      [
        %{type: "rdf_subject", value: Map.get(triple, :subject), confidence: 0.9},
        %{type: "rdf_object", value: Map.get(triple, :object), confidence: 0.9}
      ]
    end)
    |> Enum.reject(&(&1.value == nil))
    |> Enum.uniq_by(& &1.value)
  end

  defp extract_entities_from_triples(_), do: []

  defp extract_entities_from_structure(document) do
    entities = []

    # Extract from headers
    if document.structure && Map.has_key?(document.structure, :headers) do
      header_entities =
        document.structure.headers
        |> Enum.map(&%{type: "header", value: &1, confidence: 0.8})

      entities ++ header_entities
    else
      entities
    end
  end

  defp extract_named_entities_from_content(content) do
    # Simple named entity recognition
    proper_nouns =
      Regex.scan(~r/\b[A-Z][a-z]+\b/, content)
      |> Enum.map(&List.first/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_word, count} -> count > 1 end)
      |> Enum.map(fn {word, count} ->
        %{
          type: "proper_noun",
          value: word,
          confidence: min(0.9, 0.5 + count * 0.1)
        }
      end)

    # Email extraction
    emails =
      Regex.scan(~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, content)
      |> Enum.map(fn [email] ->
        %{type: "email", value: email, confidence: 0.95}
      end)

    proper_nouns ++ emails
  end

  defp build_semantic_relationships(semantic_data, _document) do
    relationships = []

    # Build relationships from RDF triples
    if semantic_data.rdf_triples do
      triple_relationships =
        semantic_data.rdf_triples
        |> Enum.map(fn triple ->
          %{
            subject: Map.get(triple, :subject),
            predicate: Map.get(triple, :predicate),
            object: Map.get(triple, :object),
            confidence: 0.9,
            source: "rdf_extraction"
          }
        end)

      relationships ++ triple_relationships
    else
      relationships
    end
  end

  defp extract_semantic_context(semantic_data, options) do
    base_context = options[:context] || "https://schema.org"

    %{
      "@context" => base_context,
      "@type" => "TextAnalysis",
      "dateCreated" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "analysisMethod" => "LANG_Universal_Parser",
      "confidence" => calculate_semantic_confidence(semantic_data)
    }
  end

  defp build_provenance_data(document) do
    %{
      parser_version: "2.0.0",
      analysis_timestamp: DateTime.utc_now(),
      content_hash: :crypto.hash(:sha256, document.content) |> Base.encode16(case: :lower),
      format_detected: document.format
    }
  end

  defp analyze_document_structure(document) do
    %{
      format: document.format,
      content_length: byte_size(document.content),
      structure_complexity: calculate_structure_complexity(document),
      metadata: document.metadata || %{}
    }
  end

  defp calculate_structure_complexity(document) do
    base_score = 1.0

    # Add complexity based on structure
    if document.structure do
      header_complexity =
        if Map.has_key?(document.structure, :headers) do
          length(document.structure.headers) * 0.1
        else
          0
        end

      link_complexity =
        if Map.has_key?(document.structure, :links) do
          length(document.structure.links) * 0.05
        else
          0
        end

      base_score + header_complexity + link_complexity
    else
      base_score
    end
  end

  defp calculate_analysis_confidence(fingerprint, features) do
    # Simple confidence calculation based on feature richness
    feature_count = if is_map(features), do: map_size(features), else: 0
    fingerprint_quality = if is_map(fingerprint), do: map_size(fingerprint) * 0.1, else: 0.5

    min(0.95, 0.5 + feature_count * 0.05 + fingerprint_quality)
  end

  defp calculate_semantic_confidence(semantic_data) do
    triple_count = if semantic_data.rdf_triples, do: length(semantic_data.rdf_triples), else: 0

    entity_count =
      if is_map(semantic_data.entities), do: map_size(semantic_data.entities), else: 0

    base_confidence = 0.6
    triple_boost = min(0.3, triple_count * 0.02)
    entity_boost = min(0.1, entity_count * 0.01)

    base_confidence + triple_boost + entity_boost
  end

  defp build_response_metadata(document, analysis) do
    %{
      processing_time_ms: System.monotonic_time(:millisecond),
      format_detected: document.format,
      analysis_components: Map.keys(analysis),
      content_stats: %{
        size_bytes: byte_size(document.content),
        estimated_reading_time_minutes: div(byte_size(document.content), 1000)
      }
    }
  end

  defp build_markdown_metadata(document, semantic_data) do
    %{
      markdown_features: extract_markdown_features(document),
      linked_data_count: count_linked_data_elements(semantic_data),
      rendering_time_ms: 45
    }
  end

  defp extract_markdown_features(document) do
    content = document.content

    %{
      headers: Regex.scan(~r/^#+\s+.+$/m, content) |> length(),
      links: Regex.scan(~r/\[.+\]\(.+\)/, content) |> length(),
      code_blocks: Regex.scan(~r/```[\s\S]*?```/, content) |> length(),
      tables: Regex.scan(~r/^\|.+\|$/m, content) |> length()
    }
  end

  defp count_linked_data_elements(semantic_data) do
    triple_count = if semantic_data.rdf_triples, do: length(semantic_data.rdf_triples), else: 0

    entity_count =
      if is_map(semantic_data.entities), do: map_size(semantic_data.entities), else: 0

    triple_count + entity_count
  end

  defp queue_security_analysis_job(content, user) do
    job_args = %{
      "content" => content,
      "user_id" => user.id,
      "analysis_type" => "content_security"
    }

    SecurityScanWorker.new(job_args) |> Oban.insert()
  end

  defp queue_dependency_analysis_job(content, user) do
    job_args = %{
      "content" => content,
      "user_id" => user.id,
      "analyze_versions" => true
    }

    DependencyAnalysisWorker.new(job_args) |> Oban.insert()
  end

  defp track_api_usage(conn, operation, content_size) do
    user = conn.assigns.current_user

    # Track usage for billing purposes
    Lang.Events.track_event(%{
      event_type: "api_call_made",
      user_id: user.id,
      operation: operation,
      content_size: content_size,
      timestamp: DateTime.utc_now()
    })
  end

  defp handle_api_error(conn, reason, message) do
    Logger.error(message, reason: inspect(reason))

    {status, error_response} =
      case reason do
        :missing_content ->
          {:bad_request, %{error: "Content is required"}}

        :content_too_large ->
          {:payload_too_large, %{error: "Content exceeds maximum size"}}

        :invalid_format ->
          {:bad_request, %{error: "Invalid or unsupported content format"}}

        :not_markdown ->
          {:bad_request, %{error: "Content is not valid Markdown"}}

        _ ->
          {:internal_server_error, %{error: message, details: inspect(reason)}}
      end

    conn
    |> put_status(status)
    |> json(error_response)
  end
end
