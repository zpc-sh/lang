defmodule Lang.Agent.BehavioralSample do
  @moduledoc """
  Behavioral sample resource for tracking agent behavior patterns over time.

  This resource stores behavioral metrics and patterns that are used for
  establishing baselines, detecting anomalies, and identifying rogue agents.
  """

  use Ash.Resource,
    domain: Lang.Agent,
    data_layer: AshPostgres.DataLayer

  # Needed to use Ash.Query macros (filter/2 with ^ pins)
  require Ash.Query

  postgres do
    table("agent_behavioral_samples")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :agent_id, :uuid do
      allow_nil?(false)
      description("ID of the agent this sample belongs to")
    end

    attribute :sample_type, :atom do
      allow_nil?(false)
      description("Type of behavioral sample")
      constraints(one_of: [:baseline, :runtime, :post_action, :periodic])
    end

    attribute :task_type, :atom do
      description("Type of task being performed during this sample")
      constraints(one_of: [:analysis, :generation, :coordination, :scanning, :idle])
    end

    attribute :cognitive_metrics, :map do
      allow_nil?(false)
      default(%{})
      description("Cognitive load and processing metrics")
    end

    attribute :resource_metrics, :map do
      allow_nil?(false)
      default(%{})
      description("Resource usage patterns (tokens, memory, CPU)")
    end

    attribute :behavioral_patterns, :map do
      allow_nil?(false)
      default(%{})
      description("Behavioral pattern indicators")
    end

    attribute :execution_metrics, :map do
      allow_nil?(false)
      default(%{})
      description("Execution timing and performance metrics")
    end

    attribute :interaction_metrics, :map do
      allow_nil?(false)
      default(%{})
      description("Inter-agent and user interaction patterns")
    end

    attribute :anomaly_indicators, :map do
      allow_nil?(false)
      default(%{})
      description("Potential anomaly indicators detected")
    end

    attribute :context_data, :map do
      allow_nil?(false)
      default(%{})
      description("Context information when sample was taken")
    end

    attribute :confidence_score, :decimal do
      allow_nil?(false)
      default(Decimal.new("1.0"))
      description("Confidence in the accuracy of this sample")
      constraints(min: 0.0, max: 1.0)
    end

    attribute :session_id, :string do
      description("Session ID when sample was collected")
    end

    attribute :duration_seconds, :integer do
      description("Duration of the sampling period in seconds")
    end

    attribute :tags, {:array, :string} do
      allow_nil?(false)
      default([])
      description("Tags for categorizing behavioral samples")
    end

    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
      description("Additional sample metadata")
    end

    timestamps()
  end

  relationships do
    belongs_to :agent, Lang.Agent.Agent do
      source_attribute(:agent_id)
      destination_attribute(:id)
    end
  end

  actions do
    defaults([:read])

    create :record_sample do
      description("Record a new behavioral sample for an agent")

      argument(:agent_id, :uuid, allow_nil?: false)
      argument(:sample_type, :atom, allow_nil?: false)
      argument(:task_type, :atom)
      argument(:cognitive_metrics, :map, default: %{})
      argument(:resource_metrics, :map, default: %{})
      argument(:behavioral_patterns, :map, default: %{})
      argument(:execution_metrics, :map, default: %{})
      argument(:interaction_metrics, :map, default: %{})
      argument(:anomaly_indicators, :map, default: %{})
      argument(:context_data, :map, default: %{})
      argument(:confidence_score, :decimal, default: Decimal.new("1.0"))
      argument(:session_id, :string)
      argument(:duration_seconds, :integer)
      argument(:tags, {:array, :string}, default: [])
      argument(:metadata, :map, default: %{})

      change(fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(
          :agent_id,
          Ash.Changeset.get_argument(changeset, :agent_id)
        )
        |> Ash.Changeset.change_attribute(
          :sample_type,
          Ash.Changeset.get_argument(changeset, :sample_type)
        )
        |> Ash.Changeset.change_attribute(
          :task_type,
          Ash.Changeset.get_argument(changeset, :task_type)
        )
        |> Ash.Changeset.change_attribute(
          :cognitive_metrics,
          Ash.Changeset.get_argument(changeset, :cognitive_metrics)
        )
        |> Ash.Changeset.change_attribute(
          :resource_metrics,
          Ash.Changeset.get_argument(changeset, :resource_metrics)
        )
        |> Ash.Changeset.change_attribute(
          :behavioral_patterns,
          Ash.Changeset.get_argument(changeset, :behavioral_patterns)
        )
        |> Ash.Changeset.change_attribute(
          :execution_metrics,
          Ash.Changeset.get_argument(changeset, :execution_metrics)
        )
        |> Ash.Changeset.change_attribute(
          :interaction_metrics,
          Ash.Changeset.get_argument(changeset, :interaction_metrics)
        )
        |> Ash.Changeset.change_attribute(
          :anomaly_indicators,
          Ash.Changeset.get_argument(changeset, :anomaly_indicators)
        )
        |> Ash.Changeset.change_attribute(
          :context_data,
          Ash.Changeset.get_argument(changeset, :context_data)
        )
        |> Ash.Changeset.change_attribute(
          :confidence_score,
          Ash.Changeset.get_argument(changeset, :confidence_score)
        )
        |> Ash.Changeset.change_attribute(
          :session_id,
          Ash.Changeset.get_argument(changeset, :session_id)
        )
        |> Ash.Changeset.change_attribute(
          :duration_seconds,
          Ash.Changeset.get_argument(changeset, :duration_seconds)
        )
        |> Ash.Changeset.change_attribute(:tags, Ash.Changeset.get_argument(changeset, :tags))
        |> Ash.Changeset.change_attribute(
          :metadata,
          Ash.Changeset.get_argument(changeset, :metadata)
        )
      end)
    end

    create :record_baseline do
      description("Record a baseline behavioral sample")

      argument(:agent_id, :uuid, allow_nil?: false)
      argument(:baseline_data, :map, allow_nil?: false)
      argument(:context, :map, default: %{})

      change(fn changeset, _context ->
        baseline_data = Ash.Changeset.get_argument(changeset, :baseline_data)
        context = Ash.Changeset.get_argument(changeset, :context)

        # Extract metrics from baseline data
        cognitive_metrics = Map.get(baseline_data, :cognitive, %{})
        resource_metrics = Map.get(baseline_data, :resources, %{})
        behavioral_patterns = Map.get(baseline_data, :patterns, %{})

        changeset
        |> Ash.Changeset.change_attribute(
          :agent_id,
          Ash.Changeset.get_argument(changeset, :agent_id)
        )
        |> Ash.Changeset.change_attribute(:sample_type, :baseline)
        |> Ash.Changeset.change_attribute(:cognitive_metrics, cognitive_metrics)
        |> Ash.Changeset.change_attribute(:resource_metrics, resource_metrics)
        |> Ash.Changeset.change_attribute(:behavioral_patterns, behavioral_patterns)
        |> Ash.Changeset.change_attribute(:context_data, context)
        |> Ash.Changeset.change_attribute(:tags, ["baseline", "establishment"])
        |> Ash.Changeset.change_attribute(:metadata, %{
          baseline_established_at: DateTime.utc_now(),
          baseline_version: "1.0"
        })
      end)
    end

    create :record_anomaly do
      description("Record a behavioral sample with anomaly indicators")

      argument(:agent_id, :uuid, allow_nil?: false)
      argument(:anomaly_data, :map, allow_nil?: false)
      argument(:severity, :atom, default: :medium)

      change(fn changeset, _context ->
        anomaly_data = Ash.Changeset.get_argument(changeset, :anomaly_data)
        severity = Ash.Changeset.get_argument(changeset, :severity)

        # Calculate confidence based on anomaly strength
        anomaly_strength = Map.get(anomaly_data, :strength, 0.5)
        confidence = Decimal.from_float(min(anomaly_strength * 2, 1.0))

        changeset
        |> Ash.Changeset.change_attribute(
          :agent_id,
          Ash.Changeset.get_argument(changeset, :agent_id)
        )
        |> Ash.Changeset.change_attribute(:sample_type, :runtime)
        |> Ash.Changeset.change_attribute(:anomaly_indicators, anomaly_data)
        |> Ash.Changeset.change_attribute(:confidence_score, confidence)
        |> Ash.Changeset.change_attribute(:tags, ["anomaly", Atom.to_string(severity)])
        |> Ash.Changeset.change_attribute(:metadata, %{
          anomaly_detected_at: DateTime.utc_now(),
          anomaly_severity: severity
        })
      end)
    end
  end

  # aggregates disabled temporarily (Ash v3 DSL migration pending)

  calculations do
    calculate :is_baseline, :boolean do
      calculation(expr(sample_type == :baseline))
    end

    calculate :is_anomalous, :boolean do
      calculation(expr("anomaly" in tags))
    end

    calculate :has_high_confidence, :boolean do
      calculation(expr(confidence_score >= 0.8))
    end

    calculate :cognitive_load_level, :atom do
      calculation(fn records, _context ->
        Enum.map(records, fn record ->
          load = get_in(record.cognitive_metrics, ["load"]) || 0.0

          cond do
            load < 0.3 -> :low
            load < 0.6 -> :medium
            load < 0.8 -> :high
            true -> :critical
          end
        end)
      end)
    end
  end

  preparations do
    prepare(build(sort: [inserted_at: :desc]))
  end

  # --- Ash v3 wrapper functions (replacing code_interface usage) ---
  def read_by_agent(agent_id) do
    __MODULE__
    |> Ash.Query.filter(agent_id == ^agent_id)
    |> Ash.read()
  end

  def read_baselines(agent_id) do
    __MODULE__
    |> Ash.Query.filter(agent_id == ^agent_id and sample_type == :baseline)
    |> Ash.read()
  end

  def record_sample(agent_id, sample_type, attrs \\ %{}) do
    args = Map.merge(attrs, %{agent_id: agent_id, sample_type: sample_type})
    __MODULE__
    |> Ash.Changeset.for_create(:record_sample, args)
    |> Ash.create()
  end
end
