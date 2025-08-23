defmodule Lang.Analysis.Violation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Lang.Analysis.AnalyzedFile

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @severities ~w(info low medium high critical)
  @statuses ~w(open acknowledged resolved suppressed false_positive)
  @categories ~w(security performance maintainability reliability bugs code_smells duplications coverage complexity)

  schema "violations" do
    field :rule_id, :string
    field :rule_name, :string
    field :rule_category, :string
    field :severity, :string
    field :status, :string, default: "open"
    field :message, :string
    field :description, :string
    field :fix_suggestion, :string
    field :line_number, :integer
    field :column_number, :integer
    field :line_content, :string
    field :impact_assessment, :string
    field :compliance_tags, {:array, :string}, default: []
    field :confidence_score, :decimal
    field :metadata, :map, default: %{}
    field :resolved_at, :utc_datetime
    field :resolved_by, :string

    belongs_to :analyzed_file, AnalyzedFile

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for creating a violation.
  """
  def create_changeset(violation, attrs) do
    violation
    |> cast(attrs, [
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
    |> validate_required([:rule_id, :rule_name, :severity, :message, :analyzed_file_id])
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:rule_category, @categories)
    |> validate_length(:rule_id, min: 1, max: 100)
    |> validate_length(:rule_name, min: 1, max: 200)
    |> validate_length(:message, min: 1, max: 1000)
    |> validate_length(:description, max: 5000)
    |> validate_length(:fix_suggestion, max: 2000)
    |> validate_length(:impact_assessment, max: 1000)
    |> validate_number(:line_number, greater_than: 0)
    |> validate_number(:column_number, greater_than_or_equal_to: 0)
    |> validate_number(:confidence_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_compliance_tags()
    |> validate_metadata()
  end

  @doc """
  Creates a changeset for updating violation status.
  """
  def update_status_changeset(violation, status, attrs \\ %{}) do
    violation
    |> cast(attrs, [:resolved_by, :metadata])
    |> put_change(:status, status)
    |> validate_inclusion(:status, @statuses)
    |> maybe_set_resolved_at(status)
    |> validate_status_transition(violation.status)
  end

  @doc """
  Creates a changeset for resolving a violation.
  """
  def resolve_changeset(violation, resolved_by, resolution_note \\ nil) do
    metadata =
      violation.metadata
      |> Map.put("resolution_note", resolution_note)
      |> Map.put("resolved_at", DateTime.utc_now())

    violation
    |> cast(%{resolved_by: resolved_by, metadata: metadata}, [:resolved_by, :metadata])
    |> put_change(:status, "resolved")
    |> put_change(:resolved_at, DateTime.utc_now())
    |> validate_required([:resolved_by])
  end

  @doc """
  Creates a changeset for acknowledging a violation.
  """
  def acknowledge_changeset(violation, acknowledged_by, note \\ nil) do
    metadata =
      violation.metadata
      |> Map.put("acknowledged_by", acknowledged_by)
      |> Map.put("acknowledgment_note", note)
      |> Map.put("acknowledged_at", DateTime.utc_now())

    violation
    |> cast(%{metadata: metadata}, [:metadata])
    |> put_change(:status, "acknowledged")
  end

  @doc """
  Creates a changeset for suppressing a violation.
  """
  def suppress_changeset(violation, suppressed_by, reason) do
    metadata =
      violation.metadata
      |> Map.put("suppressed_by", suppressed_by)
      |> Map.put("suppression_reason", reason)
      |> Map.put("suppressed_at", DateTime.utc_now())

    violation
    |> cast(%{metadata: metadata}, [:metadata])
    |> put_change(:status, "suppressed")
    |> validate_required([:metadata])
  end

  @doc """
  Creates a changeset for marking as false positive.
  """
  def false_positive_changeset(violation, marked_by, reason) do
    metadata =
      violation.metadata
      |> Map.put("false_positive_by", marked_by)
      |> Map.put("false_positive_reason", reason)
      |> Map.put("false_positive_at", DateTime.utc_now())

    violation
    |> cast(%{metadata: metadata}, [:metadata])
    |> put_change(:status, "false_positive")
    |> validate_required([:metadata])
  end

  # Private functions

  defp validate_compliance_tags(changeset) do
    case get_field(changeset, :compliance_tags) do
      nil ->
        put_change(changeset, :compliance_tags, [])

      tags when is_list(tags) ->
        validate_compliance_tags_values(changeset, tags)

      _ ->
        add_error(changeset, :compliance_tags, "must be a list of strings")
    end
  end

  defp validate_compliance_tags_values(changeset, tags) do
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

    invalid_tags = Enum.reject(tags, &(&1 in valid_tags))

    case invalid_tags do
      [] ->
        changeset

      invalid ->
        add_error(
          changeset,
          :compliance_tags,
          "contains invalid tags: #{Enum.join(invalid, ", ")}"
        )
    end
  end

  defp validate_metadata(changeset) do
    case get_field(changeset, :metadata) do
      nil ->
        put_change(changeset, :metadata, %{})

      metadata when is_map(metadata) ->
        validate_metadata_structure(changeset, metadata)

      _ ->
        add_error(changeset, :metadata, "must be a valid JSON object")
    end
  end

  defp validate_metadata_structure(changeset, metadata) do
    # Define valid metadata keys
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

    invalid_keys =
      metadata
      |> Map.keys()
      |> Enum.reject(&(&1 in valid_keys))

    case invalid_keys do
      [] ->
        changeset

      keys ->
        add_error(changeset, :metadata, "contains invalid keys: #{Enum.join(keys, ", ")}")
    end
  end

  defp maybe_set_resolved_at(changeset, "resolved") do
    case get_field(changeset, :resolved_at) do
      nil -> put_change(changeset, :resolved_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  defp maybe_set_resolved_at(changeset, _status), do: changeset

  defp validate_status_transition(changeset, current_status) do
    new_status = get_change(changeset, :status)

    case {current_status, new_status} do
      # Valid transitions from open
      {"open", "acknowledged"} ->
        changeset

      {"open", "resolved"} ->
        changeset

      {"open", "suppressed"} ->
        changeset

      {"open", "false_positive"} ->
        changeset

      # Valid transitions from acknowledged
      {"acknowledged", "resolved"} ->
        changeset

      {"acknowledged", "suppressed"} ->
        changeset

      {"acknowledged", "false_positive"} ->
        changeset

      {"acknowledged", "open"} ->
        changeset

      # Valid transitions from suppressed (can be reopened)
      {"suppressed", "open"} ->
        changeset

      {"suppressed", "resolved"} ->
        changeset

      # False positives can be reopened if mistakenly marked
      {"false_positive", "open"} ->
        changeset

      # No change
      {status, status} ->
        changeset

      # Invalid transitions
      {from, to} ->
        add_error(changeset, :status, "cannot transition from '
#{from}' to '#{to}'")
    end
  end

  @doc """
  Returns all valid severities.
  """
  def severities, do: @severities

  @doc """
  Returns all valid statuses.
  """
  def statuses, do: @statuses

  @doc """
  Returns all valid categories.
  """
  def categories, do: @categories

  @doc """
  Checks if the violation is open.
  """
  def open?(%__MODULE__{status: "open"}), do: true
  def open?(_), do: false

  @doc """
  Checks if the violation is resolved.
  """
  def resolved?(%__MODULE__{status: "resolved"}), do: true
  def resolved?(_), do: false

  @doc """
  Checks if the violation is suppressed.
  """
  def suppressed?(%__MODULE__{status: "suppressed"}), do: true
  def suppressed?(_), do: false

  @doc """
  Checks if the violation is acknowledged.
  """
  def acknowledged?(%__MODULE__{status: "acknowledged"}), do: true
  def acknowledged?(_), do: false

  @doc """
  Checks if the violation is marked as false positive.
  """
  def false_positive?(%__MODULE__{status: "false_positive"}), do: true
  def false_positive?(_), do: false

  @doc """
  Returns the severity level as an integer for sorting.
  """
  def severity_level(%__MODULE__{severity: "info"}), do: 1
  def severity_level(%__MODULE__{severity: "low"}), do: 2
  def severity_level(%__MODULE__{severity: "medium"}), do: 3
  def severity_level(%__MODULE__{severity: "high"}), do: 4
  def severity_level(%__MODULE__{severity: "critical"}), do: 5
  def severity_level(_), do: 0

  @doc """
  Returns the severity color for UI display.
  """
  def severity_color(%__MODULE__{severity: "info"}), do: "blue"
  def severity_color(%__MODULE__{severity: "low"}), do: "green"
  def severity_color(%__MODULE__{severity: "medium"}), do: "yellow"
  def severity_color(%__MODULE__{severity: "high"}), do: "orange"
  def severity_color(%__MODULE__{severity: "critical"}), do: "red"
  def severity_color(_), do: "gray"

  @doc """
  Returns the status color for UI display.
  """
  def status_color(%__MODULE__{status: "open"}), do: "red"
  def status_color(%__MODULE__{status: "acknowledged"}), do: "yellow"
  def status_color(%__MODULE__{status: "resolved"}), do: "green"
  def status_color(%__MODULE__{status: "suppressed"}), do: "gray"
  def status_color(%__MODULE__{status: "false_positive"}), do: "gray"
  def status_color(_), do: "gray"

  @doc """
  Returns a human-readable description of the violation.
  """
  def display_location(%__MODULE__{line_number: nil}), do: "Unknown location"

  def display_location(%__MODULE__{line_number: line, column_number: nil}) do
    "Line #{line}"
  end

  def display_location(%__MODULE__{line_number: line, column_number: col}) do
    "Line #{line}, Column #{col}"
  end

  @doc """
  Returns the estimated fix time from metadata.
  """
  def estimated_fix_time(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "estimated_fix_time", "Unknown")
  end

  def estimated_fix_time(_), do: "Unknown"

  @doc """
  Returns the risk score from metadata.
  """
  def risk_score(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "risk_score", 0)
  end

  def risk_score(_), do: 0

  @doc """
  Checks if the violation is actionable (not suppressed or false positive).
  """
  def actionable?(%__MODULE__{status: status}) when status in ["open", "acknowledged"], do: true
  def actionable?(_), do: false

  @doc """
  Returns a summary of the violation for API responses.
  """
  def summary(%__MODULE__{} = violation) do
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
end
