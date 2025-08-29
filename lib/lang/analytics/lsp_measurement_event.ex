defmodule Lang.Analytics.LSPMeasurementEvent do
  @moduledoc """
  Ash resource for tracking individual LSP measurement events.

  Each event captures a single measurement point showing the effectiveness
  of LSP enhancements in terms of token efficiency, time savings, and quality.
  """

  use Ash.Resource,
    domain: Lang.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("lsp_measurement_events")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:user_id, :uuid, allow_nil?: false)
    attribute(:organization_id, :uuid, allow_nil?: true)

    attribute(:session_id, :string, allow_nil?: true)
    attribute(:request_id, :uuid, allow_nil?: true)

    # LSP operation details
    attribute :lsp_method, :atom do
      constraints(
        one_of: [:hover, :completion, :explain, :refactor, :generate_tests, :diagnostics]
      )

      allow_nil?(false)
    end

    attribute(:operation_context, :string, allow_nil?: true)

    # Token measurements
    attribute :baseline_tokens, :integer do
      constraints(min: 0)
      allow_nil?(true)
    end

    attribute :enhanced_tokens, :integer do
      constraints(min: 0)
      allow_nil?(true)
    end

    attribute :token_reduction_percent, :decimal do
      constraints(min: -100, max: 100)
      allow_nil?(true)
    end

    # Time measurements
    attribute :time_saved_seconds, :integer do
      constraints(min: 0)
      allow_nil?(true)
    end

    attribute :operation_duration_ms, :integer do
      constraints(min: 0)
      allow_nil?(true)
    end

    # Quality measurements
    attribute :quality_score, :decimal do
      constraints(min: 0.0, max: 1.0)
      allow_nil?(true)
    end

    attribute :error_reduction_count, :integer do
      constraints(min: 0)
      allow_nil?(true)
    end

    attribute :iterations_saved, :integer do
      constraints(min: 0)
      allow_nil?(true)
    end

    # User experience
    attribute :user_satisfaction_score, :decimal do
      constraints(min: 0.0, max: 5.0)
      allow_nil?(true)
    end

    attribute(:feature_used, :boolean, default: true)

    attribute :completion_rate, :decimal do
      constraints(min: 0.0, max: 1.0)
      allow_nil?(true)
    end

    # Context and metadata
    attribute(:language, :string, allow_nil?: true)
    attribute(:file_type, :string, allow_nil?: true)
    attribute(:provider, :string, allow_nil?: true)
    attribute(:model, :string, allow_nil?: true)

    attribute(:metadata, :map, default: %{})

    # A/B testing
    attribute :cohort_type, :atom do
      constraints(one_of: [:treatment, :control])
      allow_nil?(true)
    end

    attribute(:experiment_name, :string, allow_nil?: true)

    # Timestamps
    attribute(:occurred_at, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0)

    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :user_id,
        :organization_id,
        :session_id,
        :request_id,
        :lsp_method,
        :operation_context,
        :baseline_tokens,
        :enhanced_tokens,
        :token_reduction_percent,
        :time_saved_seconds,
        :operation_duration_ms,
        :quality_score,
        :error_reduction_count,
        :iterations_saved,
        :user_satisfaction_score,
        :feature_used,
        :completion_rate,
        :language,
        :file_type,
        :provider,
        :model,
        :metadata,
        :cohort_type,
        :experiment_name,
        :occurred_at
      ])

      change(fn changeset, _context ->
        # Calculate token reduction percentage if not provided
        baseline = Ash.Changeset.get_attribute(changeset, :baseline_tokens)
        enhanced = Ash.Changeset.get_attribute(changeset, :enhanced_tokens)

        if baseline && enhanced && baseline > 0 do
          reduction_percent = (baseline - enhanced) / baseline * 100

          Ash.Changeset.force_change_attribute(
            changeset,
            :token_reduction_percent,
            Decimal.new("#{reduction_percent}")
          )
        else
          changeset
        end
      end)
    end

    update :update do
      accept([
        :user_satisfaction_score,
        :completion_rate,
        :metadata
      ])
    end
  end

  calculations do
    calculate(:tokens_saved, :integer, expr(baseline_tokens - enhanced_tokens))

    calculate(
      :efficiency_ratio,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN ?::decimal / ? ELSE 0 END",
          baseline_tokens,
          enhanced_tokens,
          baseline_tokens
        )
      )
    )

    calculate(
      :cost_savings_estimate,
      :decimal,
      expr(fragment("(? - ?) * 0.00002", baseline_tokens, enhanced_tokens))
    )
  end

  # aggregates removed for DSL compatibility; can be reintroduced via read actions or materialized views

  identities do
    identity(:unique_request_measurement, [:request_id, :lsp_method])
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
  end
end
