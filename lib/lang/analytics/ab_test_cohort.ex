defmodule Lang.Analytics.ABTestCohort do
  @moduledoc """
  Ash resource for managing A/B test cohort assignments.

  This resource tracks which users are assigned to treatment vs control groups
  for LSP enhancement experiments, enabling statistical measurement of improvements.
  """

  use Ash.Resource,
    domain: Lang.Analytics,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("ab_test_cohorts")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:user_id, :uuid, allow_nil?: false)
    attribute(:organization_id, :uuid, allow_nil?: true)

    attribute(:experiment_name, :string, allow_nil?: false)

    attribute :cohort_type, :atom do
      constraints(one_of: [:treatment, :control])
      allow_nil?(false)
    end

    attribute(:assigned_at, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0)

    # Experiment configuration
    attribute(:experiment_version, :string, allow_nil?: true)
    attribute(:treatment_probability, :decimal, default: 0.5)

    attribute :experiment_status, :atom do
      constraints(one_of: [:active, :paused, :completed, :archived])
      allow_nil?(false)
      default(:active)
    end

    # Randomization seed for reproducible assignments
    attribute(:randomization_seed, :string, allow_nil?: true)

    # Experiment metadata
    attribute(:metadata, :map, default: %{})

    # Tracking experiment participation
    attribute(:first_interaction_at, :utc_datetime_usec, allow_nil?: true)
    attribute(:last_interaction_at, :utc_datetime_usec, allow_nil?: true)
    attribute(:total_interactions, :integer, default: 0)

    # Experiment completion tracking
    attribute(:completed_experiment, :boolean, default: false)
    attribute(:completed_at, :utc_datetime_usec, allow_nil?: true)

    # Statistical significance tracking
    attribute(:included_in_analysis, :boolean, default: true)
    attribute(:exclusion_reason, :string, allow_nil?: true)

    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :user_id,
        :organization_id,
        :experiment_name,
        :cohort_type,
        :assigned_at,
        :experiment_version,
        :treatment_probability,
        :experiment_status,
        :randomization_seed,
        :metadata,
        :included_in_analysis
      ])

      change(fn changeset, _context ->
        # Generate randomization seed if not provided
        seed = Ash.Changeset.get_attribute(changeset, :randomization_seed)

        if is_nil(seed) do
          user_id = Ash.Changeset.get_attribute(changeset, :user_id)
          experiment = Ash.Changeset.get_attribute(changeset, :experiment_name)
          generated_seed = :crypto.hash(:sha256, "#{user_id}:#{experiment}") |> Base.encode64()

          Ash.Changeset.force_change_attribute(changeset, :randomization_seed, generated_seed)
        else
          changeset
        end
      end)
    end

    update :update do
      accept([
        :experiment_status,
        :first_interaction_at,
        :last_interaction_at,
        :total_interactions,
        :completed_experiment,
        :completed_at,
        :included_in_analysis,
        :exclusion_reason,
        :metadata
      ])
    end

    update :record_interaction do
      accept([])
      require_atomic?(false)

      change(fn changeset, _context ->
        now = DateTime.utc_now()
        current_interactions = Ash.Changeset.get_attribute(changeset, :total_interactions) || 0
        first_interaction = Ash.Changeset.get_attribute(changeset, :first_interaction_at)

        changeset =
          if is_nil(first_interaction) do
            Ash.Changeset.force_change_attribute(changeset, :first_interaction_at, now)
          else
            changeset
          end

        changeset
        |> Ash.Changeset.force_change_attribute(:last_interaction_at, now)
        |> Ash.Changeset.force_change_attribute(:total_interactions, current_interactions + 1)
      end)
    end

    update :complete_experiment do
      accept([:completed_at])
      require_atomic?(false)

      change(fn changeset, _context ->
        now = DateTime.utc_now()

        changeset
        |> Ash.Changeset.force_change_attribute(:completed_experiment, true)
        |> Ash.Changeset.force_change_attribute(:completed_at, now)
      end)
    end

    update :exclude_from_analysis do
      argument(:reason, :string, allow_nil?: false)
      require_atomic?(false)

      change(fn changeset, context ->
        reason = Map.get(context.arguments, :reason)

        changeset
        |> Ash.Changeset.force_change_attribute(:included_in_analysis, false)
        |> Ash.Changeset.force_change_attribute(:exclusion_reason, reason)
      end)
    end

    read :by_user_and_experiment do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:experiment_name, :string, allow_nil?: false)

      filter(
        expr(
          user_id == ^arg(:user_id) and
            experiment_name == ^arg(:experiment_name)
        )
      )
    end

    read :active_experiments do
      filter(expr(experiment_status == :active))
    end

    read :by_experiment do
      argument(:experiment_name, :string, allow_nil?: false)
      argument(:cohort_type, :atom, allow_nil?: true)
      argument(:include_inactive, :boolean, default: false)

      filter(expr(experiment_name == ^arg(:experiment_name)))

      filter(
        expr(
          if is_nil(^arg(:cohort_type)) do
            true
          else
            cohort_type == ^arg(:cohort_type)
          end
        )
      )

      filter(
        expr(
          if ^arg(:include_inactive) do
            true
          else
            experiment_status == :active
          end
        )
      )
    end

    read :for_analysis do
      argument(:experiment_name, :string, allow_nil?: false)
      argument(:min_interactions, :integer, default: 1)

      filter(
        expr(
          experiment_name == ^arg(:experiment_name) and
            included_in_analysis == true and
            total_interactions >= ^arg(:min_interactions)
        )
      )
    end
  end

  calculations do
    calculate(
      :experiment_duration_days,
      :decimal,
      expr(
        fragment(
          "EXTRACT(EPOCH FROM (COALESCE(?, NOW()) - ?)) / 86400",
          completed_at,
          assigned_at
        )
      )
    )

    calculate(
      :interaction_frequency,
      :decimal,
      expr(
        fragment(
          "CASE WHEN EXTRACT(EPOCH FROM (? - ?)) > 86400 THEN ?::decimal / (EXTRACT(EPOCH FROM (? - ?)) / 86400) ELSE ? END",
          last_interaction_at,
          first_interaction_at,
          total_interactions,
          last_interaction_at,
          first_interaction_at,
          total_interactions
        )
      )
    )

    calculate(
      :days_since_assignment,
      :integer,
      expr(fragment("EXTRACT(DAYS FROM (NOW() - ?))", assigned_at))
    )
  end

  identities do
    identity(:unique_user_experiment, [:user_id, :experiment_name])
  end

  code_interface do
    define(:create)
    define(:read)
    define(:update)
    define(:record_interaction)
    define(:complete_experiment, args: [:completed_at])
    define(:exclude_from_analysis, args: [:reason])
    define(:by_user_and_experiment, args: [:user_id, :experiment_name])
    define(:active_experiments)
    define(:by_experiment, args: [:experiment_name])
    define(:for_analysis, args: [:experiment_name])
  end
end
