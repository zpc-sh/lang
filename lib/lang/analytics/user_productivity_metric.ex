defmodule Lang.Analytics.UserProductivityMetric do
  @moduledoc """
  Ash resource for tracking aggregated user productivity metrics.

  This resource stores time-based aggregations of user performance data,
  allowing us to track productivity improvements over time periods.
  """

  use Ash.Resource,
    domain: Lang.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("user_productivity_metrics")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:user_id, :uuid, allow_nil?: false)
    attribute(:organization_id, :uuid, allow_nil?: true)

    # Time period for aggregation
    attribute(:period_start, :utc_datetime_usec, allow_nil?: false)
    attribute(:period_end, :utc_datetime_usec, allow_nil?: false)

    attribute :period_type, :atom do
      constraints(one_of: [:hourly, :daily, :weekly, :monthly])
      allow_nil?(false)
      default(:daily)
    end

    # Productivity metrics
    attribute :total_operations, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :lsp_assisted_operations, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :non_lsp_operations, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    # Token efficiency
    attribute :total_tokens_saved, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :avg_token_reduction_percent, :decimal do
      constraints(min: 0, max: 100)
      allow_nil?(true)
    end

    attribute :baseline_token_usage, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :enhanced_token_usage, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    # Time efficiency
    attribute :total_time_saved_seconds, :integer do
      constraints(min: 0)
      allow_nil?(false)
      default(0)
    end

    attribute :avg_time_saved_per_operation, :decimal do
      constraints(min: 0)
      allow_nil?(true)
    end

    attribute :total_operation_time_ms, :integer do
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

    # User experience
    attribute :avg_satisfaction_score, :decimal do
      constraints(min: 0.0, max: 5.0)
      allow_nil?(true)
    end

    attribute :feature_adoption_rate, :decimal do
      constraints(min: 0.0, max: 1.0)
      allow_nil?(true)
    end

    attribute :completion_rate, :decimal do
      constraints(min: 0.0, max: 1.0)
      allow_nil?(true)
    end

    # Method breakdown (stored as JSON map)
    attribute(:method_usage_breakdown, :map, default: %{})
    attribute(:provider_performance, :map, default: %{})
    attribute(:language_breakdown, :map, default: %{})

    # A/B testing context
    attribute :cohort_type, :atom do
      constraints(one_of: [:treatment, :control])
      allow_nil?(true)
    end

    # Cost impact
    attribute :estimated_cost_savings_usd, :decimal do
      constraints(min: 0)
      allow_nil?(true)
    end

    attribute :productivity_value_usd, :decimal do
      constraints(min: 0)
      allow_nil?(true)
    end

    # Metadata for additional context
    attribute(:metadata, :map, default: %{})

    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :user_id,
        :organization_id,
        :period_start,
        :period_end,
        :period_type,
        :total_operations,
        :lsp_assisted_operations,
        :non_lsp_operations,
        :total_tokens_saved,
        :avg_token_reduction_percent,
        :baseline_token_usage,
        :enhanced_token_usage,
        :total_time_saved_seconds,
        :avg_time_saved_per_operation,
        :total_operation_time_ms,
        :avg_quality_score,
        :total_errors_prevented,
        :total_iterations_saved,
        :avg_satisfaction_score,
        :feature_adoption_rate,
        :completion_rate,
        :method_usage_breakdown,
        :provider_performance,
        :language_breakdown,
        :cohort_type,
        :estimated_cost_savings_usd,
        :productivity_value_usd,
        :metadata
      ])

      change(fn changeset, _context ->
        # Calculate derived metrics
        total_ops = Ash.Changeset.get_attribute(changeset, :total_operations) || 0
        lsp_ops = Ash.Changeset.get_attribute(changeset, :lsp_assisted_operations) || 0
        tokens_saved = Ash.Changeset.get_attribute(changeset, :total_tokens_saved) || 0
        time_saved = Ash.Changeset.get_attribute(changeset, :total_time_saved_seconds) || 0

        changeset =
          if total_ops > 0 do
            adoption_rate = lsp_ops / total_ops

            changeset
            |> Ash.Changeset.force_change_attribute(:feature_adoption_rate, adoption_rate)
          else
            changeset
          end

        changeset =
          if lsp_ops > 0 && time_saved > 0 do
            avg_time_per_op = time_saved / lsp_ops

            changeset
            |> Ash.Changeset.force_change_attribute(
              :avg_time_saved_per_operation,
              avg_time_per_op
            )
          else
            changeset
          end

        # Calculate cost savings (approximate)
        # Average cost across providers
        cost_per_token = 0.00002
        developer_hourly_rate = 100

        cost_savings = tokens_saved * cost_per_token
        productivity_value = time_saved / 3600 * developer_hourly_rate

        changeset
        |> Ash.Changeset.force_change_attribute(:estimated_cost_savings_usd, cost_savings)
        |> Ash.Changeset.force_change_attribute(:productivity_value_usd, productivity_value)
      end)
    end

    update :update do
      accept([
        :total_operations,
        :lsp_assisted_operations,
        :non_lsp_operations,
        :total_tokens_saved,
        :avg_token_reduction_percent,
        :baseline_token_usage,
        :enhanced_token_usage,
        :total_time_saved_seconds,
        :total_operation_time_ms,
        :avg_quality_score,
        :total_errors_prevented,
        :total_iterations_saved,
        :avg_satisfaction_score,
        :completion_rate,
        :method_usage_breakdown,
        :provider_performance,
        :language_breakdown,
        :metadata
      ])

      require_atomic?(false)

      change(fn changeset, _context ->
        # Recalculate derived metrics on update
        total_ops = Ash.Changeset.get_attribute(changeset, :total_operations)
        lsp_ops = Ash.Changeset.get_attribute(changeset, :lsp_assisted_operations)
        tokens_saved = Ash.Changeset.get_attribute(changeset, :total_tokens_saved)
        time_saved = Ash.Changeset.get_attribute(changeset, :total_time_saved_seconds)

        changeset =
          if total_ops && total_ops > 0 && lsp_ops do
            adoption_rate = lsp_ops / total_ops
            Ash.Changeset.force_change_attribute(changeset, :feature_adoption_rate, adoption_rate)
          else
            changeset
          end

        changeset =
          if lsp_ops && lsp_ops > 0 && time_saved do
            avg_time_per_op = time_saved / lsp_ops

            Ash.Changeset.force_change_attribute(
              changeset,
              :avg_time_saved_per_operation,
              avg_time_per_op
            )
          else
            changeset
          end

        # Recalculate cost metrics
        if tokens_saved && time_saved do
          cost_per_token = 0.00002
          developer_hourly_rate = 100

          cost_savings = tokens_saved * cost_per_token
          productivity_value = time_saved / 3600 * developer_hourly_rate

          changeset
          |> Ash.Changeset.force_change_attribute(:estimated_cost_savings_usd, cost_savings)
          |> Ash.Changeset.force_change_attribute(:productivity_value_usd, productivity_value)
        else
          changeset
        end
      end)
    end

    read :by_user_and_period do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:period_start, :utc_datetime_usec, allow_nil?: false)
      argument(:period_end, :utc_datetime_usec, allow_nil?: false)

      filter(
        expr(
          user_id == ^arg(:user_id) and
            period_start >= ^arg(:period_start) and
            period_end <= ^arg(:period_end)
        )
      )
    end

    read :by_organization do
      argument(:organization_id, :uuid, allow_nil?: false)
      argument(:period_type, :atom, allow_nil?: true)

      filter(expr(organization_id == ^arg(:organization_id)))

      filter(
        expr(
          if is_nil(^arg(:period_type)) do
            true
          else
            period_type == ^arg(:period_type)
          end
        )
      )
    end
  end

  calculations do
    calculate(
      :total_value_usd,
      :decimal,
      expr(estimated_cost_savings_usd + productivity_value_usd)
    )

    calculate(
      :efficiency_multiplier,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN ?::decimal / ? ELSE 0 END",
          baseline_token_usage,
          baseline_token_usage,
          enhanced_token_usage
        )
      )
    )

    calculate(
      :roi_percent,
      :decimal,
      expr(
        fragment(
          "CASE WHEN ? > 0 THEN (? / ?) * 100 ELSE 0 END",
          baseline_token_usage,
          total_tokens_saved,
          baseline_token_usage
        )
      )
    )
  end

  identities do
    identity(:unique_user_period, [:user_id, :period_start, :period_end, :period_type])
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:by_user_and_period, args: [:user_id, :period_start, :period_end])
    define(:by_organization, args: [:organization_id])
  end
end
