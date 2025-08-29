defmodule LangWeb.Api.V2.TextView do
  use LangWeb, :view
  alias LangWeb.Api.V2.TextView
  alias MarkdownLD.Hash

  def render("parse_result.json", %{
        document: document,
        analysis: analysis,
        metadata: metadata,
        integrity?: integrity?
      }) do
    base = %{
      "@context" => "https://lang.nulity.com/context/text",
      "@type" => "ParseResult",
      "status" => "success",
      "data" => %{
        "document" => render_document(document),
        "analysis" => render_analysis(analysis),
        "metadata" => metadata
      }
    }

    maybe_integrity(base, integrity?)
  end

  def render("parse_result.json", assigns),
    do: render("parse_result.json", Map.put(assigns, :integrity?, false))

  def render("entities.json", %{entities: entities, metadata: metadata, integrity?: integrity?}) do
    base = %{
      "@context" => "https://schema.org",
      "@type" => "EntityExtractionResult",
      "status" => "success",
      "data" => %{
        "entities" => Enum.map(entities, &render_entity/1),
        "metadata" => metadata
      }
    }

    maybe_integrity(base, integrity?)
  end

  def render("entities.json", assigns),
    do: render("entities.json", Map.put(assigns, :integrity?, false))

  def render("semantic.json", %{
        triples: triples,
        relationships: relationships,
        entities: entities,
        context: context,
        job_id: job_id,
        metadata: metadata,
        integrity?: integrity?
      }) do
    base = %{
      "@context" => context["@context"] || "https://schema.org",
      "@type" => "SemanticAnalysisResult",
      "status" => "success",
      "data" => %{
        "triples" => render_triples(triples),
        "relationships" => render_relationships(relationships),
        "entities" => render_semantic_entities(entities),
        "context" => context,
        "job_id" => job_id,
        "metadata" => metadata
      }
    }

    maybe_integrity(base, integrity?)
  end

  def render("semantic.json", assigns),
    do: render("semantic.json", Map.put(assigns, :integrity?, false))

  def render("stylometry.json", %{
        fingerprint: fingerprint,
        features: features,
        complexity: complexity,
        authorship: authorship,
        transformations: transformations,
        metadata: metadata,
        integrity?: integrity?
      }) do
    base = %{
      "@context" => "https://lang.nulity.com/context/stylometry",
      "@type" => "StylometricAnalysisResult",
      "status" => "success",
      "data" => %{
        "fingerprint" => render_fingerprint(fingerprint),
        "features" => render_stylometric_features(features),
        "complexity" => render_complexity(complexity),
        "authorship" => render_authorship(authorship),
        "transformations" => render_transformations(transformations),
        "metadata" => metadata
      }
    }

    maybe_integrity(base, integrity?)
  end

  def render("stylometry.json", assigns),
    do: render("stylometry.json", Map.put(assigns, :integrity?, false))

  def render("markdown_ld.json", %{
        markdown: markdown,
        html: html,
        linked_data: linked_data,
        entities: entities,
        metadata: metadata,
        integrity?: integrity?
      }) do
    base = %{
      "@context" => "https://lang.nulity.com/context/markdown-ld",
      "@type" => "MarkdownLDResult",
      "status" => "success",
      "data" => %{
        "markdown" => %{
          "raw" => markdown.raw || "",
          "structured" => markdown.structured || %{},
          "toc" => markdown.toc || []
        },
        "html" => html || "",
        "linked_data" => render_linked_data(linked_data),
        "entities" => render_semantic_entities(entities),
        "metadata" => metadata
      }
    }

    maybe_integrity(base, integrity?)
  end

  def render("markdown_ld.json", assigns),
    do: render("markdown_ld.json", Map.put(assigns, :integrity?, false))

  def render("comprehensive.json", results) do
    integrity? = Map.get(results, :integrity?, false)

    base = %{
      "@context" => "https://lang.nulity.com/context/comprehensive",
      "@type" => "ComprehensiveAnalysisResult",
      "status" => "success",
      "data" => %{
        "document" => render_document(results[:document]),
        "entities" => render_entities_if_present(results[:entities]),
        "semantic_data" => render_semantic_data_if_present(results[:semantic_data]),
        "stylometry" => render_stylometry_if_present(results[:stylometry]),
        "processing_summary" => %{
          "components" => results[:processing_components] || [],
          "content_length" => results[:content_length],
          "analysis_timestamp" => results[:analysis_timestamp]
        }
      }
    }

    maybe_integrity(base, integrity?)
  end

  def render("error.json", %{error: error, details: details}) do
    %{
      "@context" => "https://lang.nulity.com/context/error",
      "@type" => "Error",
      "status" => "error",
      "error" => %{
        "message" => error,
        "details" => details,
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }
  end

  # Private rendering helpers

  defp render_document(nil), do: nil

  defp render_document(document) do
    %{
      "format" => document.format,
      "content_length" => byte_size(document.content || ""),
      "structure" => render_document_structure(document.structure),
      "metadata" => document.metadata || %{},
      "quality_score" => Map.get(document.analysis || %{}, :quality_score, 0.0)
    }
  end

  defp render_document_structure(nil), do: %{}

  defp render_document_structure(structure) do
    %{
      "headers" => structure[:headers] || [],
      "links" => structure[:links] || [],
      "code_blocks" => structure[:code_blocks] || [],
      "tables" => structure[:tables] || [],
      "images" => structure[:images] || []
    }
  end

  defp render_analysis(nil), do: %{}

  defp render_analysis(analysis) do
    %{
      "document_analysis" => analysis[:document_analysis] || %{},
      "entities" => render_entities_if_present(analysis[:entities]),
      "semantic_data" => render_semantic_data_if_present(analysis[:semantic_data])
    }
  end

  defp render_entity(entity) do
    %{
      "@type" => "Entity",
      "type" => entity[:type] || entity.type,
      "value" => entity[:value] || entity.value,
      "confidence" => entity[:confidence] || entity.confidence || 0.0,
      "position" => entity[:position] || entity.position,
      "context" => entity[:context] || entity.context
    }
  end

  defp render_triples(nil), do: []

  defp render_triples(triples) when is_list(triples) do
    Enum.map(triples, fn triple ->
      %{
        "@type" => "RDFTriple",
        "subject" => triple[:subject] || Map.get(triple, :subject),
        "predicate" => triple[:predicate] || Map.get(triple, :predicate),
        "object" => triple[:object] || Map.get(triple, :object),
        "confidence" => triple[:confidence] || Map.get(triple, :confidence, 0.9)
      }
    end)
  end

  defp render_triples(_), do: []

  defp render_relationships(nil), do: []

  defp render_relationships(relationships) when is_list(relationships) do
    Enum.map(relationships, fn rel ->
      %{
        "@type" => "SemanticRelationship",
        "subject" => rel[:subject] || Map.get(rel, :subject),
        "predicate" => rel[:predicate] || Map.get(rel, :predicate),
        "object" => rel[:object] || Map.get(rel, :object),
        "confidence" => rel[:confidence] || Map.get(rel, :confidence, 0.0),
        "source" => rel[:source] || Map.get(rel, :source, "analysis")
      }
    end)
  end

  defp render_relationships(_), do: []

  defp render_semantic_entities(nil), do: %{}

  defp render_semantic_entities(entities) when is_map(entities) do
    Map.new(entities, fn {key, entity} ->
      {key, render_semantic_entity(entity)}
    end)
  end

  defp render_semantic_entities(_), do: %{}

  defp render_semantic_entity(entity) when is_map(entity) do
    %{
      "@type" => "SemanticEntity",
      "type" => entity[:type] || Map.get(entity, :type),
      "value" => entity[:value] || Map.get(entity, :value),
      "context" => entity[:context] || Map.get(entity, :context),
      "frequency" => entity[:frequency] || Map.get(entity, :frequency, 1)
    }
  end

  defp render_semantic_entity(entity), do: entity

  defp render_fingerprint(nil), do: %{}

  defp render_fingerprint(fingerprint) do
    %{
      "@type" => "StylometricFingerprint",
      "hash" => fingerprint[:hash] || Map.get(fingerprint, :hash),
      "vector" => fingerprint[:vector] || Map.get(fingerprint, :vector, []),
      "features" => fingerprint[:features] || Map.get(fingerprint, :features, %{}),
      "confidence" => fingerprint[:confidence] || Map.get(fingerprint, :confidence, 0.0)
    }
  end

  defp render_stylometric_features(nil), do: %{}

  defp render_stylometric_features(features) when is_map(features) do
    Map.new(features, fn {key, value} ->
      feature_data =
        if is_map(value) do
          %{
            "value" => value[:value] || Map.get(value, :value),
            "score" => value[:score] || Map.get(value, :score, 0.0),
            "percentile" => value[:percentile] || Map.get(value, :percentile)
          }
        else
          %{"value" => value, "score" => 0.0}
        end

      {key, feature_data}
    end)
  end

  defp render_stylometric_features(features), do: features || %{}

  defp render_complexity(nil), do: %{}

  defp render_complexity(complexity) when is_map(complexity) do
    %{
      "@type" => "ComplexityAnalysis",
      "lexical_diversity" =>
        complexity[:lexical_diversity] || Map.get(complexity, :lexical_diversity, 0.0),
      "syntactic_complexity" =>
        complexity[:syntactic_complexity] || Map.get(complexity, :syntactic_complexity, 0.0),
      "readability_score" =>
        complexity[:readability_score] || Map.get(complexity, :readability_score, 0.0),
      "overall_score" => complexity[:overall_score] || Map.get(complexity, :overall_score, 0.0)
    }
  end

  defp render_complexity(complexity) when is_number(complexity) do
    %{
      "@type" => "ComplexityAnalysis",
      "overall_score" => complexity,
      "lexical_diversity" => 0.0,
      "syntactic_complexity" => 0.0,
      "readability_score" => 0.0
    }
  end

  defp render_complexity(_), do: %{}

  defp render_authorship(nil), do: %{}

  defp render_authorship(authorship) do
    %{
      "@type" => "AuthorshipAnalysis",
      "confidence" => authorship[:confidence] || Map.get(authorship, :confidence, 0.0),
      "similarity_scores" =>
        authorship[:similarity_scores] || Map.get(authorship, :similarity_scores, []),
      "likely_matches" => authorship[:likely_matches] || Map.get(authorship, :likely_matches, [])
    }
  end

  defp render_transformations(nil), do: %{}

  defp render_transformations(transformations) when is_map(transformations) do
    %{
      "@type" => "StyleTransformations",
      "suggested_changes" =>
        transformations[:suggested_changes] || Map.get(transformations, :suggested_changes, []),
      "obfuscation_methods" =>
        transformations[:obfuscation_methods] ||
          Map.get(transformations, :obfuscation_methods, []),
      "preservation_score" =>
        transformations[:preservation_score] || Map.get(transformations, :preservation_score, 0.0)
    }
  end

  defp render_transformations(_), do: %{}

  defp render_linked_data(nil), do: %{}

  defp render_linked_data(linked_data) when is_map(linked_data) do
    %{
      "@type" => "LinkedDataExtraction",
      "rdf_triples" =>
        render_triples(linked_data[:rdf_triples] || Map.get(linked_data, :rdf_triples)),
      "json_ld" => linked_data[:json_ld] || Map.get(linked_data, :json_ld, %{}),
      "vocabulary" => linked_data[:vocabulary] || Map.get(linked_data, :vocabulary, []),
      "namespaces" => linked_data[:namespaces] || Map.get(linked_data, :namespaces, %{})
    }
  end

  defp render_linked_data(linked_data), do: linked_data || %{}

  # Integrity helper
  defp maybe_integrity(map, true) do
    data = Map.get(map, "data")

    case Hash.dataset_hash(data) do
      {:ok, integ} -> Map.put(map, "integrity", integ)
      _ -> map
    end
  end

  defp maybe_integrity(map, _), do: map

  # Conditional rendering helpers
  defp render_entities_if_present(nil), do: nil

  defp render_entities_if_present(entities) when is_list(entities) do
    Enum.map(entities, &render_entity/1)
  end

  defp render_entities_if_present(_), do: nil

  defp render_semantic_data_if_present(nil), do: nil

  defp render_semantic_data_if_present(semantic_data) do
    %{
      "triples" => render_triples(semantic_data[:rdf_triples]),
      "relationships" => render_relationships(semantic_data[:relationships]),
      "entities" => render_semantic_entities(semantic_data[:entities]),
      "context" => semantic_data[:context] || %{}
    }
  end

  defp render_stylometry_if_present(nil), do: nil

  defp render_stylometry_if_present(stylometry) do
    %{
      "fingerprint" => render_fingerprint(stylometry[:fingerprint]),
      "features" => render_stylometric_features(stylometry[:features]),
      "complexity" => render_complexity(stylometry[:complexity]),
      "authorship" => render_authorship(stylometry[:authorship])
    }
  end
end
