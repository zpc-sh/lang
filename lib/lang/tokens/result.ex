defmodule Lang.Tokens.Result do
  @moduledoc """
  Output of a token optimization request (token counts, compression ratios, cache recommendations).

  Stores the results of token optimization operations including:
  - Token count estimates for different models
  - Compressed content and compression ratios
  - Filtered content with relevance scores
  - Delta streaming information
  - Cache strategy recommendations
  """

  use Ash.Resource,
    domain: Lang.Tokens,
    data_layer: AshPostgres.DataLayer

  alias Lang.Tokens.Request

  postgres do
    table("token_results")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :summary, :string do
      allow_nil?(true)
      description("Human-readable summary of the optimization result")
    end

    attribute :token_count, :integer do
      allow_nil?(true)
      description("Original token count before optimization")
    end

    attribute :optimized_token_count, :integer do
      allow_nil?(true)
      description("Token count after optimization")
    end

    attribute :compression_ratio, :decimal do
      allow_nil?(true)
      description("Achieved compression ratio (0.0-1.0)")
    end

    attribute :model_estimates, :map do
      allow_nil?(false)
      default(%{})
      description("Token count estimates per model type (gpt-4, claude-3, etc.)")
    end

    attribute :optimized_content, :string do
      allow_nil?(true)
      description("Compressed or filtered content")
    end

    attribute :relevance_scores, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Relevance scores for filtered content chunks")
    end

    attribute :streaming_deltas, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Delta information for streaming optimization")
    end

    attribute :cache_recommendations, :map do
      allow_nil?(false)
      default(%{})
      description("Caching strategy recommendations")
    end

    attribute :details, :map do
      allow_nil?(false)
      default(%{})
      description("Additional detailed results and metadata")
    end

    attribute :artifacts, {:array, :map} do
      allow_nil?(false)
      default([])
      description("Generated artifacts (compressed files, filter rules, etc.)")
    end

    attribute :confidence_score, :decimal do
      allow_nil?(true)
      description("Confidence score for the optimization quality")
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
        :token_count,
        :optimized_token_count,
        :compression_ratio,
        :model_estimates,
        :optimized_content,
        :relevance_scores,
        :streaming_deltas,
        :cache_recommendations,
        :details,
        :artifacts,
        :confidence_score,
        :metrics,
        :completed_at
      ])
    end

    update :update do
      accept([
        :summary,
        :token_count,
        :optimized_token_count,
        :compression_ratio,
        :model_estimates,
        :optimized_content,
        :relevance_scores,
        :streaming_deltas,
        :cache_recommendations,
        :details,
        :artifacts,
        :confidence_score,
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
      :token_savings,
      :integer,
      expr(token_count - optimized_token_count)
    )

    calculate(
      :savings_percentage,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN (? - ?)::decimal / ?::decimal * 100 ELSE 0 END",
          token_count,
          token_count,
          optimized_token_count,
          token_count
        )
      )
    )
  end
end
