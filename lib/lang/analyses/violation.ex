defmodule Lang.Analyses.Violation do
  @moduledoc """
  Violation Resource for Analysis Domain

  Represents issues, problems, or violations found during text analysis.
  Violations are linked to specific analyzed files and contain detailed
  information about the issue, severity, and potential fixes.
  """

  use Ash.Resource,
    domain: Lang.Analyses,
    data_layer: AshPostgres.DataLayer

  alias Lang.Analyses.File

  postgres do
    table("violations")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :rule_id, :string do
      allow_nil?(false)
      constraints(min_length: 1, max_length: 100)
    end

    attribute :rule_name, :string do
      allow_nil?(false)
      constraints(min_length: 1, max_length: 200)
    end

    attribute :rule_category, :atom do
      allow_nil?(true)

      constraints(
        one_of: [
          :security,
          :performance,
          :maintainability,
          :reliability,
          :bugs,
          :code_smells,
          :duplications,
          :coverage,
          :complexity
        ]
      )
    end

    attribute :severity, :atom do
      allow_nil?(false)
      constraints(one_of: [:info, :low, :medium, :high, :critical])
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:open)
      constraints(one_of: [:open, :acknowledged, :resolved, :suppressed, :false_positive])
    end

    attribute :message, :string do
      allow_nil?(false)
      constraints(min_length: 1, max_length: 1000)
    end

    attribute :description, :string do
      allow_nil?(true)
      constraints(max_length: 5000)
    end

    attribute :fix_suggestion, :string do
      allow_nil?(true)
      constraints(max_length: 2000)
    end

    attribute :line_number, :integer do
      allow_nil?(true)
      constraints(min: 1)
    end

    attribute :column_number, :integer do
      allow_nil?(true)
      constraints(min: 0)
    end

    attribute :line_content, :string do
      allow_nil?(true)
    end

    attribute :impact_assessment, :string do
      allow_nil?(true)
      constraints(max_length: 1000)
    end

    attribute :compliance_tags, {:array, :string} do
      allow_nil?(false)
      default([])
    end

    attribute :confidence_score, :decimal do
      allow_nil?(true)
      constraints(min: 0, max: 100)
    end

    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
    end

    attribute :resolved_at, :utc_datetime do
      allow_nil?(true)
    end

    attribute :resolved_by, :string do
      allow_nil?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :analyzed_file, File do
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :rule_id,
        :rule_name,
        :rule_category,
        :severity,
        :message,
        :description,
        :fix_suggestion,
        :line_number,
        :column_number,
        :line_content,
        :impact_assessment,
        :compliance_tags,
        :confidence_score,
        :metadata,
        :analyzed_file_id
      ])

      validate(present([:rule_id, :rule_name, :severity, :message, :analyzed_file_id]))

      change(fn changeset, _context ->
        # Validate compliance tags
        case Ash.Changeset.get_attribute(changeset, :compliance_tags) do
          nil ->
            changeset

          tags when is_list(tags) ->
            validated_tags = validate_compliance_tags(tags)
            Ash.Changeset.change_attribute(changeset, :compliance_tags, validated_tags)

          _ ->
            Ash.Changeset.add_error(changeset, :compliance_tags, "must be a list of strings")
        end
      end)

      change(fn changeset, _context ->
        # Validate and clean metadata
        metadata = Ash.Changeset.get_attribute(changeset, :metadata) || %{}
        validated_metadata = validate_metadata_structure(metadata)
        Ash.Changeset.change_attribute(changeset, :metadata, validated_metadata)
      end)
    end

    update :update_status do
      accept([:resolved_by, :metadata])
      argument(:status, :atom, allow_nil?: false)

      validate(present(:status))
      validate(one_of(:status, [:open, :acknowledged, :resolved, :suppressed, :false_positive]))

      change(fn changeset, _context ->
        status = Ash.Changeset.get_argument(changeset, :status)
        current_status = changeset.data.status

        case validate_status_transition(current_status, status) do
          :ok ->
            changeset = Ash.Changeset.change_attribute(changeset, :status, status)

            # Set resolved_at for resolved status
            if status == :resolved and is_nil(changeset.data.resolved_at) do
              Ash.Changeset.change_attribute(changeset, :resolved_at, DateTime.utc_now())
            else
              changeset
            end

          {:error, message} ->
            Ash.Changeset.add_error(changeset, :status, message)
        end
      end)
    end

    update :resolve do
      accept([:metadata])
      argument(:resolved_by, :string, allow_nil?: false)
      argument(:resolution_note, :string, allow_nil?: true)

      change(fn changeset, context ->
        resolved_by = context.arguments[:resolved_by]
        resolution_note = context.arguments[:resolution_note]

        metadata =
          (changeset.data.metadata || %{})
          |> Map.put("resolution_note", resolution_note)
          |> Map.put("resolved_at", DateTime.utc_now())

        changeset
        |> Ash.Changeset.change_attribute(:status, :resolved)
        |> Ash.Changeset.change_attribute(:resolved_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:resolved_by, resolved_by)
        |> Ash.Changeset.change_attribute(:metadata, metadata)
      end)
    end

    update :acknowledge do
      accept([:metadata])
      argument(:acknowledged_by, :string, allow_nil?: false)
      argument(:note, :string, allow_nil?: true)

      change(fn changeset, context ->
        acknowledged_by = context.arguments[:acknowledged_by]
        note = context.arguments[:note]

        metadata =
          (changeset.data.metadata || %{})
          |> Map.put("acknowledged_by", acknowledged_by)
          |> Map.put("acknowledgment_note", note)
          |> Map.put("acknowledged_at", DateTime.utc_now())

        changeset
        |> Ash.Changeset.change_attribute(:status, :acknowledged)
        |> Ash.Changeset.change_attribute(:metadata, metadata)
      end)
    end

    update :suppress do
      accept([:metadata])
      argument(:suppressed_by, :string, allow_nil?: false)
      argument(:reason, :string, allow_nil?: false)

      change(fn changeset, context ->
        suppressed_by = context.arguments[:suppressed_by]
        reason = context.arguments[:reason]

        metadata =
          (changeset.data.metadata || %{})
          |> Map.put("suppressed_by", suppressed_by)
          |> Map.put("suppression_reason", reason)
          |> Map.put("suppressed_at", DateTime.utc_now())

        changeset
        |> Ash.Changeset.change_attribute(:status, :suppressed)
        |> Ash.Changeset.change_attribute(:metadata, metadata)
      end)
    end

    update :mark_false_positive do
      accept([:metadata])
      argument(:marked_by, :string, allow_nil?: false)
      argument(:reason, :string, allow_nil?: false)

      change(fn changeset, context ->
        marked_by = context.arguments[:marked_by]
        reason = context.arguments[:reason]

        metadata =
          (changeset.data.metadata || %{})
          |> Map.put("false_positive_by", marked_by)
          |> Map.put("false_positive_reason", reason)
          |> Map.put("false_positive_at", DateTime.utc_now())

        changeset
        |> Ash.Changeset.change_attribute(:status, :false_positive)
        |> Ash.Changeset.change_attribute(:metadata, metadata)
      end)
    end

    destroy(:destroy)
  end

  code_interface do
    define(:read_all, action: :read)
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:update_status, action: :update_status)
    define(:resolve, action: :resolve)
    define(:acknowledge, action: :acknowledge)
    define(:suppress, action: :suppress)
    define(:mark_false_positive, action: :mark_false_positive)
    define(:destroy, action: :destroy)
  end

  calculations do
    calculate(:is_open, :boolean, expr(status == :open))
    calculate(:is_resolved, :boolean, expr(status == :resolved))
    calculate(:is_suppressed, :boolean, expr(status == :suppressed))
    calculate(:is_acknowledged, :boolean, expr(status == :acknowledged))
    calculate(:is_false_positive, :boolean, expr(status == :false_positive))
    calculate(:is_actionable, :boolean, expr(status in [:open, :acknowledged]))

    calculate(
      :severity_level,
      :integer,
      expr(
        cond do
          severity == :info -> 1
          severity == :low -> 2
          severity == :medium -> 3
          severity == :high -> 4
          severity == :critical -> 5
          true -> 0
        end
      )
    )

    calculate(
      :display_location,
      :string,
      expr(
        cond do
          is_nil(line_number) ->
            "Unknown location"

          is_nil(column_number) ->
            fragment("'Line ' || ?", line_number)

          true ->
            fragment("'Line ' || ? || ', Column ' || ?", line_number, column_number)
        end
      )
    )
  end

  # Helper functions
  defp validate_compliance_tags(tags) do
    valid_tags = [
      "OWASP",
      "PCI-DSS",
      "GDPR",
      "HIPAA",
      "SOX",
      "ISO-27001",
      "NIST",
      "CWE",
      "CVE",
      "SANS",
      "FIPS",
      "SOC2"
    ]

    Enum.filter(tags, &(&1 in valid_tags))
  end

  defp validate_metadata_structure(metadata) when is_map(metadata) do
    valid_keys = [
      "cwe_id",
      "cve_references",
      "external_references",
      "code_snippet",
      "suggested_tools",
      "estimated_fix_time",
      "risk_score",
      "technical_debt",
      "performance_impact",
      "security_risk_level",
      "automation_available",
      "related_violations"
    ]

    # Filter to only include valid keys
    Enum.reduce(metadata, %{}, fn {key, value}, acc ->
      if key in valid_keys do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  defp validate_metadata_structure(_), do: %{}

  defp validate_status_transition(current_status, new_status) do
    case {current_status, new_status} do
      # Valid transitions from open
      {:open, :acknowledged} -> :ok
      {:open, :resolved} -> :ok
      {:open, :suppressed} -> :ok
      {:open, :false_positive} -> :ok
      # Valid transitions from acknowledged
      {:acknowledged, :resolved} -> :ok
      {:acknowledged, :suppressed} -> :ok
      {:acknowledged, :false_positive} -> :ok
      {:acknowledged, :open} -> :ok
      # Valid transitions from suppressed (can be reopened)
      {:suppressed, :open} -> :ok
      {:suppressed, :resolved} -> :ok
      # False positives can be reopened if mistakenly marked
      {:false_positive, :open} -> :ok
      # No change
      {status, status} -> :ok
      # Invalid transitions
      {from, to} -> {:error, "cannot transition from '#{from}' to '#{to}'"}
    end
  end

  # Instance helper functions
  def open?(%{status: :open}), do: true
  def open?(_), do: false

  def resolved?(%{status: :resolved}), do: true
  def resolved?(_), do: false

  def suppressed?(%{status: :suppressed}), do: true
  def suppressed?(_), do: false

  def acknowledged?(%{status: :acknowledged}), do: true
  def acknowledged?(_), do: false

  def false_positive?(%{status: :false_positive}), do: true
  def false_positive?(_), do: false

  def actionable?(%{status: status}) when status in [:open, :acknowledged], do: true
  def actionable?(_), do: false

  def severity_level(%{severity: :info}), do: 1
  def severity_level(%{severity: :low}), do: 2
  def severity_level(%{severity: :medium}), do: 3
  def severity_level(%{severity: :high}), do: 4
  def severity_level(%{severity: :critical}), do: 5
  def severity_level(_), do: 0

  def severity_color(%{severity: :info}), do: "blue"
  def severity_color(%{severity: :low}), do: "green"
  def severity_color(%{severity: :medium}), do: "yellow"
  def severity_color(%{severity: :high}), do: "orange"
  def severity_color(%{severity: :critical}), do: "red"
  def severity_color(_), do: "gray"

  def status_color(%{status: :open}), do: "red"
  def status_color(%{status: :acknowledged}), do: "yellow"
  def status_color(%{status: :resolved}), do: "green"
  def status_color(%{status: :suppressed}), do: "gray"
  def status_color(%{status: :false_positive}), do: "gray"
  def status_color(_), do: "gray"

  def display_location(%{line_number: nil}), do: "Unknown location"

  def display_location(%{line_number: line, column_number: nil}) do
    "Line #{line}"
  end

  def display_location(%{line_number: line, column_number: col}) do
    "Line #{line}, Column #{col}"
  end

  def estimated_fix_time(%{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "estimated_fix_time", "Unknown")
  end

  def estimated_fix_time(_), do: "Unknown"

  def risk_score(%{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "risk_score", 0)
  end

  def risk_score(_), do: 0

  def summary(%{} = violation) do
    %{
      id: violation.id,
      rule_id: violation.rule_id,
      rule_name: violation.rule_name,
      severity: violation.severity,
      status: violation.status,
      message: violation.message,
      line_number: violation.line_number,
      confidence_score: violation.confidence_score,
      compliance_tags: violation.compliance_tags
    }
  end

  def severities, do: [:info, :low, :medium, :high, :critical]
  def statuses, do: [:open, :acknowledged, :resolved, :suppressed, :false_positive]

  def categories do
    [
      :security,
      :performance,
      :maintainability,
      :reliability,
      :bugs,
      :code_smells,
      :duplications,
      :coverage,
      :complexity
    ]
  end
end
