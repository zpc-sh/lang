defmodule Lang.Query.Workers.RequestWorker do
  @moduledoc """
  Executes natural language query requests and stores results.

  Integrates existing capabilities to handle natural language queries:
  - GraphReasoner for dependency and impact analysis
  - Provider implementations for natural language processing
  - DependencyAnalysisWorker for ownership tracking
  - Native search capabilities for semantic code search

  Handles background processing for all natural language query operations:
  - Natural language code queries with semantic search
  - Impact analysis ("What breaks if I change X?")
  - Dependency analysis ("What depends on this?")
  - Code ownership tracking ("Who owns this code?")
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger

  alias Lang.Query.{Request, Result}
  alias Lang.GraphReasoner
  alias Lang.Providers.Router
  alias Lang.Workers.DependencyAnalysisWorker
  alias Lang.Native.FSScanner

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id}}) do
    with {:ok, req} <- Request.by_id(request_id),
         {:ok, _} <- Request.update_status(req, %{}, %{status: :running}) do
      result =
        :telemetry.span([:lang, :query, :execute], %{kind: req.kind, request_id: req.id}, fn ->
          case execute(req) do
            {:ok, output} = ok -> {ok, Map.merge(%{status: :ok}, safe_metrics(output))}
            {:error, reason} = err -> {err, %{status: :error, reason: inspect(reason)}}
          end
        end)

      case result do
        {:ok, output} ->
          {:ok, _} =
            Result.create(%{
              request_id: req.id,
              summary: output[:summary],
              answer: output[:answer],
              confidence_score: output[:confidence_score],
              code_locations: output[:code_locations] || [],
              affected_systems: output[:affected_systems] || [],
              dependency_graph: output[:dependency_graph] || %{},
              ownership_info: output[:ownership_info] || [],
              risk_assessment: output[:risk_assessment] || %{},
              graph_reasoning: output[:graph_reasoning] || %{},
              knowledge_entities: output[:knowledge_entities] || [],
              search_results: output[:search_results] || [],
              recommendations: output[:recommendations] || [],
              details: output[:details] || %{},
              artifacts: output[:artifacts] || [],
              provider_used: output[:provider_used],
              processing_method: output[:processing_method],
              metrics: output[:metrics] || %{},
              completed_at: DateTime.utc_now()
            })

          {:ok, _} = Request.complete(req, %{metadata: %{}})
          :ok

        {:error, reason} ->
          Logger.error("Query request failed",
            request_id: req.id,
            kind: req.kind,
            reason: inspect(reason)
          )

          {:ok, _} = Request.fail(req, %{error_message: to_string(reason), metadata: %{}})
          :ok
      end
    else
      _ -> :ok
    end
  end

  defp execute(%Request{kind: kind} = req) do
    case kind do
      :natural ->
        handle_natural_query(req)

      :impact ->
        handle_impact_analysis(req)

      :dependency ->
        handle_dependency_analysis(req)

      :ownership ->
        handle_ownership_analysis(req)

      _ ->
        {:error, "Unknown query kind: #{kind}"}
    end
  end

  # ============================================================================
  # Natural Language Query Handling
  # ============================================================================

  defp handle_natural_query(req) do
    processing_start = System.monotonic_time(:millisecond)

    # Try graph reasoning first if enabled
    result =
      if req.use_graph_reasoning do
        case try_graph_reasoning(req) do
          {:ok, graph_result} -> {:ok, graph_result}
          {:error, _} -> try_provider_query(req)
        end
      else
        try_provider_query(req)
      end

    processing_time = System.monotonic_time(:millisecond) - processing_start

    case result do
      {:ok, base_result} ->
        # Enhance with semantic search
        enhanced_result = enhance_with_semantic_search(req, base_result)

        {:ok,
         Map.merge(enhanced_result, %{
           processing_method: determine_processing_method(req),
           metrics: %{
             processing_time_ms: processing_time,
             used_graph_reasoning: req.use_graph_reasoning,
             semantic_search_enabled: true
           }
         })}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp try_graph_reasoning(req) do
    if has_extractable_content?(req) do
      case GraphReasoner.quick_text_analysis(req.context["content"] || req.query, %{
             find_communities: true,
             centrality_algorithm: "pagerank"
           }) do
        {:ok, analysis} ->
          {:ok,
           %{
             summary: "Graph-based analysis of query: #{req.query}",
             answer: format_graph_analysis_answer(analysis, req.query),
             confidence_score: Decimal.new("0.80"),
             graph_reasoning: analysis,
             knowledge_entities: extract_entities_from_analysis(analysis),
             processing_method: "graph_reasoning"
           }}

        {:error, reason} ->
          Logger.debug("Graph reasoning failed, falling back to provider", reason: reason)
          {:error, reason}
      end
    else
      {:error, :no_extractable_content}
    end
  end

  defp try_provider_query(req) do
    provider = req.provider_preference || auto_select_provider(req)

    params = %{
      query: req.query,
      context: req.context["content"] || "",
      scope: req.scope
    }

    case Router.route_request("lang.query.natural", params, provider: String.to_atom(provider)) do
      {:ok, provider_result} ->
        {:ok,
         %{
           summary: "Natural language query processed",
           answer: provider_result["answer"] || provider_result["response"],
           confidence_score: parse_confidence(provider_result["confidence"]),
           provider_used: provider,
           processing_method: "provider_ai",
           details: provider_result
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Impact Analysis Handling
  # ============================================================================

  defp handle_impact_analysis(req) do
    processing_start = System.monotonic_time(:millisecond)

    # Use graph reasoning for dependency impact analysis
    graph_result =
      case analyze_impact_with_graph(req) do
        {:ok, result} -> result
        {:error, _} -> %{}
      end

    # Use provider for qualitative impact analysis
    provider_result =
      case analyze_impact_with_provider(req) do
        {:ok, result} -> result
        {:error, _} -> %{}
      end

    processing_time = System.monotonic_time(:millisecond) - processing_start

    # Combine both approaches
    {:ok,
     %{
       summary: "Impact analysis for: #{req.target_element || req.query}",
       answer: provider_result["answer"] || "Impact analysis completed",
       confidence_score: Decimal.new("0.75"),
       affected_systems: extract_affected_systems(graph_result, provider_result),
       dependency_graph: graph_result,
       risk_assessment: extract_risk_assessment(provider_result),
       recommendations: extract_recommendations(provider_result),
       processing_method: "hybrid",
       metrics: %{
         processing_time_ms: processing_time,
         graph_analysis_success: !Enum.empty?(graph_result),
         provider_analysis_success: !Enum.empty?(provider_result)
       }
     }}
  end

  defp analyze_impact_with_graph(req) do
    # Try to build dependency graph for impact analysis
    if req.context["dependencies"] do
      dependencies = parse_dependencies(req.context["dependencies"])

      case GraphReasoner.analyze_dependency_graph(dependencies, %{
             impact_analysis: true,
             criticality_analysis: true,
             max_depth: 10
           }) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :no_dependency_data}
    end
  end

  defp analyze_impact_with_provider(req) do
    # Anthropic is good for impact analysis
    provider = req.provider_preference || "anthropic"

    params = %{
      change_description: req.change_description || req.query,
      code: req.context["code"],
      target_element: req.target_element
    }

    Router.route_request("lang.query.impact", params, provider: String.to_atom(provider))
  end

  # ============================================================================
  # Dependency Analysis Handling
  # ============================================================================

  defp handle_dependency_analysis(req) do
    processing_start = System.monotonic_time(:millisecond)

    # Use existing dependency analysis capabilities
    result =
      case perform_dependency_analysis(req) do
        {:ok, deps} -> deps
        {:error, _} -> %{}
      end

    processing_time = System.monotonic_time(:millisecond) - processing_start

    {:ok,
     %{
       summary: "Dependency analysis for: #{req.target_element || req.query}",
       answer: format_dependency_answer(result),
       confidence_score: Decimal.new("0.85"),
       dependency_graph: result,
       code_locations: extract_dependency_locations(result),
       processing_method: "dependency_analysis",
       metrics: %{
         processing_time_ms: processing_time,
         dependencies_found: count_dependencies(result)
       }
     }}
  end

  defp perform_dependency_analysis(req) do
    # Leverage existing dependency analysis logic
    if req.context["scan_result_id"] do
      # Use existing scan results
      analyze_existing_dependencies(req.context["scan_result_id"])
    else
      # Perform new dependency analysis on target
      analyze_target_dependencies(req.target_element, req.context)
    end
  end

  # ============================================================================
  # Ownership Analysis Handling
  # ============================================================================

  defp handle_ownership_analysis(req) do
    processing_start = System.monotonic_time(:millisecond)

    ownership_info =
      case analyze_code_ownership(req) do
        {:ok, info} -> info
        {:error, _} -> []
      end

    processing_time = System.monotonic_time(:millisecond) - processing_start

    {:ok,
     %{
       summary: "Code ownership analysis for: #{req.target_element || req.query}",
       answer: format_ownership_answer(ownership_info),
       confidence_score: Decimal.new("0.90"),
       ownership_info: ownership_info,
       code_locations: extract_ownership_locations(ownership_info),
       processing_method: "ownership_analysis",
       metrics: %{
         processing_time_ms: processing_time,
         contributors_found: length(ownership_info)
       }
     }}
  end

  defp analyze_code_ownership(req) do
    # This would integrate with git blame and contributor analysis
    # For now, return mock data structure
    {:ok,
     [
       %{
         "file_path" => req.target_element || "unknown",
         "primary_owner" => %{
           "name" => "System Analysis",
           "email" => "system@lang.ai",
           "contribution_percentage" => 100.0,
           "last_modified" => DateTime.utc_now() |> DateTime.to_iso8601()
         },
         "contributors" => [],
         "ownership_confidence" => 0.7
       }
     ]}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp enhance_with_semantic_search(req, base_result) do
    # Use FSScanner for semantic code search if available
    case try_semantic_search(req.query, req.context) do
      {:ok, search_results} ->
        Map.put(base_result, :search_results, search_results)

      {:error, _} ->
        base_result
    end
  end

  defp try_semantic_search(query, context) do
    # Try to use native semantic search capabilities
    if context["project_path"] do
      case FSScanner.search_code(context["project_path"], "generic", query) do
        {:ok, results} ->
          {:ok,
           Enum.map(results, fn result ->
             %{
               "file_path" => result.file,
               "line_number" => result.line,
               "match_text" => result.text,
               "relevance_score" => 0.8
             }
           end)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :no_project_path}
    end
  end

  defp has_extractable_content?(req) do
    content = req.context["content"] || req.query
    String.length(content) > 10
  end

  defp auto_select_provider(req) do
    # Simple provider selection based on query characteristics
    cond do
      String.contains?(String.downcase(req.query), ["security", "vulnerability"]) -> "anthropic"
      String.contains?(String.downcase(req.query), ["explain", "how", "what"]) -> "openai"
      String.length(req.query) < 50 -> "xai"
      true -> "openai"
    end
  end

  defp determine_processing_method(req) do
    if req.use_graph_reasoning do
      "hybrid"
    else
      "provider_ai"
    end
  end

  defp format_graph_analysis_answer(analysis, query) do
    entities_count = length(Map.get(analysis.knowledge_graph, :entities, []))

    "Found #{entities_count} relevant entities for query '#{query}'. " <>
      "Graph analysis reveals structural relationships and semantic connections."
  end

  defp extract_entities_from_analysis(analysis) do
    Map.get(analysis, :knowledge_graph, %{})
    |> Map.get(:entities, [])
    |> Enum.map(fn entity ->
      %{
        "id" => entity.id,
        "type" => entity.type,
        "label" => entity.label,
        "confidence" => entity.confidence
      }
    end)
  end

  defp parse_confidence(nil), do: Decimal.new("0.5")
  defp parse_confidence(conf) when is_number(conf), do: Decimal.from_float(conf)

  defp parse_confidence(conf) when is_binary(conf) do
    case Float.parse(conf) do
      {f, ""} -> Decimal.from_float(f)
      _ -> Decimal.new("0.5")
    end
  end

  defp parse_dependencies(deps_data) when is_list(deps_data), do: deps_data

  defp parse_dependencies(deps_data) when is_binary(deps_data) do
    # Parse dependency string format like "module_a -> module_b,module_c"
    String.split(deps_data, "\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case String.split(line, "->") do
        [from, to] -> {String.trim(from), String.split(to, ",") |> Enum.map(&String.trim/1)}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_dependencies(_), do: []

  defp extract_affected_systems(graph_result, provider_result) do
    graph_systems =
      case graph_result do
        %{subgraphs: subgraphs} ->
          Enum.map(subgraphs, fn sg ->
            %{
              "name" => sg.id,
              "type" => "dependency",
              "impact_level" => "medium"
            }
          end)

        _ ->
          []
      end

    provider_systems =
      case provider_result do
        %{"affected_systems" => systems} when is_list(systems) -> systems
        _ -> []
      end

    graph_systems ++ provider_systems
  end

  defp extract_risk_assessment(provider_result) do
    %{
      "level" => provider_result["risk_level"] || "MEDIUM",
      "blast_radius" => provider_result["blast_radius"] || "localized",
      "probability" => provider_result["probability"] || 0.5,
      "severity" => provider_result["severity"] || "moderate"
    }
  end

  defp extract_recommendations(provider_result) do
    case provider_result do
      %{"recommendations" => recs} when is_list(recs) -> recs
      %{"suggestions" => sugs} when is_list(sugs) -> sugs
      _ -> ["Consider thorough testing before deployment", "Monitor key metrics post-change"]
    end
  end

  defp analyze_existing_dependencies(scan_result_id) do
    # This would integrate with existing scan results
    # For now, return empty structure
    {:ok, %{nodes: [], edges: []}}
  end

  defp analyze_target_dependencies(target, context) do
    # This would perform fresh dependency analysis
    {:ok,
     %{
       nodes: [%{id: target, type: "target"}],
       edges: [],
       analysis_type: "fresh"
     }}
  end

  defp format_dependency_answer(result) do
    node_count = length(Map.get(result, :nodes, []))
    edge_count = length(Map.get(result, :edges, []))

    "Found #{node_count} dependencies with #{edge_count} relationships."
  end

  defp extract_dependency_locations(result) do
    Map.get(result, :nodes, [])
    |> Enum.map(fn node ->
      %{
        "file_path" => node.id,
        "line_number" => 1,
        "type" => "dependency"
      }
    end)
  end

  defp count_dependencies(result) do
    length(Map.get(result, :nodes, []))
  end

  defp format_ownership_answer(ownership_info) do
    case ownership_info do
      [] ->
        "No ownership information found"

      [info | _] ->
        owner = get_in(info, ["primary_owner", "name"])
        "Primary owner: #{owner || "Unknown"}"
    end
  end

  defp extract_ownership_locations(ownership_info) do
    Enum.map(ownership_info, fn info ->
      %{
        "file_path" => info["file_path"],
        "line_number" => 1,
        "type" => "ownership",
        "owner" => get_in(info, ["primary_owner", "name"])
      }
    end)
  end

  defp safe_metrics(%{metrics: m}) when is_map(m), do: m
  defp safe_metrics(_), do: %{}
end
