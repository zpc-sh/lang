defmodule Lang.Analytics.TokenEfficiencyReport do
  @moduledoc """
  Ash resource for tracking token efficiency trends over time.

  This resource stores aggregated token efficiency data for historical analysis,
  trend identification, and business reporting on LSP enhancement impact.
  """

  use Ash.Resource,
    domain: Lang.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("token_efficiency_reports")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:organization_id, :uuid, allow_nil?: true)

    # Report time period
    attribute(:report_date, :date, allow_nil?: false)

    attribute :report_period, :atom do
      constraints(one_of: [:daily, :weekly, :monthly, :quarterly])
      allow_nil?(false)
      default(:daily)
    end

    attribute(:period_start, :utc_datetime_usec, allow_nil?: false)
    attribute(:period_end, :utc_datetime_usec, allow_nil?: false)

    # Token efficiency metrics
    attribute :total_baseline_tokens, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :total_enhanced_tokens, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :total_tokens_saved, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :avg_token_reduction_percent, :decimal do
      constraints(min: 0, max: 100)
      allow_nil?(true)
    end

    attribute :median_token_reduction_percent, :decimal do
      constraints(min: 0, max: 100)
      allow_nil?(true)
    end

    # Operation counts
    attribute :total_lsp_operations, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :successful_operations, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :failed_operations, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    # Success rate
    attribute :success_rate_percent, :decimal do
      constraints(min: 0, max: 100)
      allow_nil?(true)
    end

    # Method breakdown (JSON storage for flexibility)
    attribute(:method_efficiency, :map, default: %{})
    attribute(:provider_efficiency, :map, default: %{})
    attribute(:language_efficiency, :map, default: %{})

    # User metrics
    attribute :active_users, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :new_users, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :returning_users, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    # Quality metrics
    attribute :avg_quality_score, :decimal do
      constraints(min: 0.0, max: 1.0)
      allow_nil?(true)
    end

    attribute :total_errors_prevented, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :total_iterations_saved, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    # Business impact
    attribute :estimated_cost_savings_usd, :decimal do
      constraints(min: 0)
      allow_nil?(true)
    end

    attribute :productivity_value_usd, :decimal do
      constraints(min: 0)
      allow_nil?(true)
    end

    attribute :total_business_value_usd, :decimal do
      constraints(min: 0)
      allow_nil?(true)
    end

    # Trend analysis
    attribute(:previous_period_comparison, :map, default: %{})
    # "improving", "declining", "stable"
    attribute(:trend_direction, :string, allow_nil?: true)
    # 0.0 to 1.0
    attribute(:trend_confidence, :decimal, allow_nil?: true)

    # A/B testing results
    attribute(:ab_test_results, :map, default: %{})
    attribute(:statistical_significance, :decimal, allow_nil?: true)

    # Additional metadata
    attribute(:metadata, :map, default: %{})

    # Report generation info
    attribute(:generated_at, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0)
    attribute(:generated_by, :string, allow_nil?: true)

    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :organization_id,
        :report_date,
        :report_period,
        :period_start,
        :period_end,
        :total_baseline_tokens,
        :total_enhanced_tokens,
        :total_tokens_saved,
        :avg_token_reduction_percent,
        :median_token_reduction_percent,
        :total_lsp_operations,
        :successful_operations,
        :failed_operations,
        :success_rate_percent,
        :method_efficiency,
        :provider_efficiency,
        :language_efficiency,
        :active_users,
        :new_users,
        :returning_users,
        :avg_quality_score,
        :total_errors_prevented,
        :total_iterations_saved,
        :estimated_cost_savings_usd,
        :productivity_value_usd,
        :previous_period_comparison,
        :trend_direction,
        :trend_confidence,
        :ab_test_results,
        :statistical_significance,
        :metadata,
        :generated_at,
        :generated_by
      ])

      change(fn changeset, _context ->
        # Calculate derived metrics
        baseline = Ash.Changeset.get_attribute(changeset, :total_baseline_tokens) || 0
        enhanced = Ash.Changeset.get_attribute(changeset, :total_enhanced_tokens) || 0
        total_ops = Ash.Changeset.get_attribute(changeset, :total_lsp_operations) || 0
        successful = Ash.Changeset.get_attribute(changeset, :successful_operations) || 0
        cost_savings = Ash.Changeset.get_attribute(changeset, :estimated_cost_savings_usd) || 0
        productivity_value = Ash.Changeset.get_attribute(changeset, :productivity_value_usd) || 0

        # Calculate tokens saved
        tokens_saved = max(0, baseline - enhanced)

        changeset =
          Ash.Changeset.force_change_attribute(changeset, :total_tokens_saved, tokens_saved)

        # Calculate token reduction percentage
        changeset =
          if baseline > 0 do
            reduction_percent = tokens_saved / baseline * 100

            Ash.Changeset.force_change_attribute(
              changeset,
              :avg_token_reduction_percent,
              reduction_percent
            )
          else
            changeset
          end

        # Calculate success rate
        changeset =
          if total_ops > 0 do
            success_rate = successful / total_ops * 100
            Ash.Changeset.force_change_attribute(changeset, :success_rate_percent, success_rate)
          else
            changeset
          end

        # Calculate total business value
        total_value = cost_savings + productivity_value
        Ash.Changeset.force_change_attribute(changeset, :total_business_value_usd, total_value)
      end)
    end

    update :update do
      accept([
        :total_baseline_tokens,
        :total_enhanced_tokens,
        :total_lsp_operations,
        :successful_operations,
        :failed_operations,
        :method_efficiency,
        :provider_efficiency,
        :language_efficiency,
        :active_users,
        :new_users,
        :returning_users,
        :avg_quality_score,
        :total_errors_prevented,
        :total_iterations_saved,
        :previous_period_comparison,
        :trend_direction,
        :trend_confidence,
        :ab_test_results,
        :statistical_significance,
        :metadata
      ])

      require_atomic?(false)

      change(fn changeset, _context ->
        # Recalculate derived metrics on update
        baseline = Ash.Changeset.get_attribute(changeset, :total_baseline_tokens)
        enhanced = Ash.Changeset.get_attribute(changeset, :total_enhanced_tokens)
        total_ops = Ash.Changeset.get_attribute(changeset, :total_lsp_operations)
        successful = Ash.Changeset.get_attribute(changeset, :successful_operations)

        changeset =
          if baseline && enhanced do
            tokens_saved = max(0, baseline - enhanced)

            changeset =
              Ash.Changeset.force_change_attribute(changeset, :total_tokens_saved, tokens_saved)

            if baseline > 0 do
              reduction_percent = tokens_saved / baseline * 100

              Ash.Changeset.force_change_attribute(
                changeset,
                :avg_token_reduction_percent,
                reduction_percent
              )
            else
              changeset
            end
          else
            changeset
          end

        changeset =
          if total_ops && total_ops > 0 && successful do
            success_rate = successful / total_ops * 100
            Ash.Changeset.force_change_attribute(changeset, :success_rate_percent, success_rate)
          else
            changeset
          end

        # Recalculate business value metrics if cost data is present
        cost_savings = Ash.Changeset.get_attribute(changeset, :estimated_cost_savings_usd) || 0
        productivity_value = Ash.Changeset.get_attribute(changeset, :productivity_value_usd) || 0
        total_value = cost_savings + productivity_value

        Ash.Changeset.force_change_attribute(changeset, :total_business_value_usd, total_value)
      end)
    end

    read :by_date_range do
      argument(:start_date, :date, allow_nil?: false)
      argument(:end_date, :date, allow_nil?: false)
      argument(:organization_id, :uuid, allow_nil?: true)

      filter(
        expr(
          report_date >= ^arg(:start_date) and
            report_date <= ^arg(:end_date)
        )
      )

      filter(
        expr(
          if is_nil(^arg(:organization_id)) do
            true
          else
            organization_id == ^arg(:organization_id)
          end
        )
      )
    end

    read :by_period do
      argument(:report_period, :atom, allow_nil?: false)
      argument(:organization_id, :uuid, allow_nil?: true)
      argument(:limit, :integer, default: 50)

      filter(expr(report_period == ^arg(:report_period)))

      filter(
        expr(
          if is_nil(^arg(:organization_id)) do
            true
          else
            organization_id == ^arg(:organization_id)
          end
        )
      )

      prepare(build(sort: [report_date: :desc]))
    end

    read :latest_trends do
      argument(:organization_id, :uuid, allow_nil?: true)
      argument(:days, :integer, default: 30)

      filter(expr(report_date >= fragment("CURRENT_DATE - INTERVAL '? days'", ^arg(:days))))

      filter(
        expr(
          if is_nil(^arg(:organization_id)) do
            true
          else
            organization_id == ^arg(:organization_id)
          end
        )
      )

      prepare(build(sort: [report_date: :desc]))
    end
  end

  calculations do
    calculate(
      :efficiency_ratio,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN ?::decimal / ? ELSE 0 END",
          total_baseline_tokens,
          total_enhanced_tokens,
          total_baseline_tokens
        )
      )
    )

    calculate(
      :tokens_per_operation,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN ?::decimal / ? ELSE 0 END",
          total_lsp_operations,
          total_tokens_saved,
          total_lsp_operations
        )
      )
    )

    calculate(
      :cost_per_token_saved,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN ?::decimal / ? ELSE 0 END",
          total_tokens_saved,
          estimated_cost_savings_usd,
          total_tokens_saved
        )
      )
    )

    calculate(
      :roi_percent,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN ? / ? * 100 ELSE 0 END",
          total_baseline_tokens,
          total_tokens_saved,
          total_baseline_tokens
        )
      )
    )

    calculate(
      :user_growth_rate,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN ?::decimal / ? * 100 ELSE 0 END",
          returning_users,
          new_users,
          returning_users
        )
      )
    )
  end

  # aggregates removed for DSL compatibility; use reports queries or materialized data instead

  identities do
    identity(:unique_org_date_period, [:organization_id, :report_date, :report_period])
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:by_date_range, args: [:start_date, :end_date, :organization_id])
    define(:by_period, args: [:report_period, :organization_id, :limit])
    define(:latest_trends, args: [:organization_id, :days])
  end
end
