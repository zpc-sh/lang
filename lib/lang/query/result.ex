defmodule Lang.Query.Result do
  @moduledoc """
  Output of a natural language query request.

  Stores the results of natural language query operations including:
  - Natural language query responses with code locations
  - Impact analysis with risk assessments and affected systems
  - Dependency analysis with relationship graphs
  - Code ownership information with contributor details
  - Graph reasoning results and knowledge extraction
  """

  use Ash.Resource,
    domain: Lang.Query,
    data_layer: AshPostgres.DataLayer

  alias Lang.Query.Request

  postgres do
    table("query_results")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :summary, :string do
      allow_nil?(true)
      description("Human-readable summary of the query result")
    end

    attribute :answer, :string do
      allow_nil?(true)
      description("Direct answer to the natural language query")
    end

    attribute :confidence_score, :decimal do
      allow_nil?(true)
      description("Confidence score for the query result accuracy")
    end

    attribute :code_locations, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Relevant code locations with file paths and line numbers")
    end

    attribute :affected_systems, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Systems affected by impact analysis")
    end

    attribute :dependency_graph, :map do
      allow_nil?(false)
      default(%{})
      description("Dependency relationship graph and analysis")
    end

    attribute :ownership_info, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Code ownership information with contributors")
    end

    attribute :risk_assessment, :map do
      allow_nil?(false)
      default(%{})
      description("Risk level and impact assessment for changes")
    end

    attribute :graph_reasoning, :map do
      allow_nil?(false)
      default(%{})
      description("Graph-based reasoning and analysis results")
    end

    attribute :knowledge_entities, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Extracted knowledge entities and relationships")
    end

    attribute :search_results, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Semantic search results with relevance scores")
    end

    attribute :recommendations, {:array, :string} do
      allow_nil?(false)
      default([])
      description("Actionable recommendations based on the analysis")
    end

    attribute :details, :map do
      allow_nil?(false)
      default(%{})
      description("Additional detailed results and metadata")
    end

    attribute :artifacts, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Generated artifacts (graphs, reports, visualizations)")
    end

    attribute :provider_used, :string do
      allow_nil?(true)
      description("AI provider that generated the result")
    end

    attribute :processing_method, :string do
      allow_nil?(true)
      description("Processing method used (graph_reasoning, provider_ai, hybrid)")
    end

    attribute :metrics, :map do
      allow_nil?(false)
      default(%{})
      description("Performance and processing metrics")
    end

    attribute :completed_at, :utc_datetime do
      allow_nil?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :request, Request do
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :request_id,
        :summary,
        :answer,
        :confidence_score,
        :code_locations,
        :affected_systems,
        :dependency_graph,
        :ownership_info,
        :risk_assessment,
        :graph_reasoning,
        :knowledge_entities,
        :search_results,
        :recommendations,
        :details,
        :artifacts,
        :provider_used,
        :processing_method,
        :metrics,
        :completed_at
      ])
    end

    update :update do
      accept([
        :summary,
        :answer,
        :confidence_score,
        :code_locations,
        :affected_systems,
        :dependency_graph,
        :ownership_info,
        :risk_assessment,
        :graph_reasoning,
        :knowledge_entities,
        :search_results,
        :recommendations,
        :details,
        :artifacts,
        :provider_used,
        :processing_method,
        :metrics,
        :completed_at
      ])
    end
  end

  code_interface do
    define(:read_all, action: :read)
    define(:by_id, action: :read, get_by: [:id])
    define(:by_request_id, action: :read, get_by: [:request_id])
    define(:create, action: :create)
    define(:update, action: :update)
  end

  calculations do
    calculate(
      :has_code_locations,
      :boolean,
      expr(fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", code_locations))
    )

    calculate(
      :has_dependencies,
      :boolean,
      expr(
        fragment("jsonb_array_length(COALESCE(? -> 'nodes', '[]'::jsonb)) > 0", dependency_graph)
      )
    )

    calculate(
      :risk_level,
      :string,
      expr(fragment("COALESCE(? ->> 'level', 'UNKNOWN')", risk_assessment))
    )

    calculate(
      :total_affected_systems,
      :integer,
      expr(fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb))", affected_systems))
    )

    calculate(
      :processing_time_ms,
      :integer,
      expr(fragment("COALESCE(? ->> 'processing_time_ms', '0')::integer", metrics))
    )
  end
end
