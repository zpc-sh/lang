defmodule Lang.Analysis.AnalysisSession do
  use Ecto.Schema
  import Ecto.Changeset

  alias Lang.Analysis.{Project, AnalyzedFile, AnalysisInsight}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending processing completed failed cancelled)

  schema "analysis_sessions" do
    field :status, :string, default: "pending"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :file_count, :integer, default: 0
    field :total_size_bytes, :integer, default: 0
    field :violations_count, :integer, default: 0
    field :critical_issues_count, :integer, default: 0
    field :warnings_count, :integer, default: 0
    field :processing_time_ms, :integer
    field :metadata, :map, default: %{}
    field :error_message, :string

    belongs_to :project, Project
    has_many :analyzed_files, AnalyzedFile, on_delete: :delete_all
    has_many :analysis_insights, AnalysisInsight, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for starting a new analysis session.
  """
  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [:project_id, :metadata])
    |> validate_required([:project_id])
    |> put_change(:started_at, DateTime.utc_now())
    |> validate_metadata()
  end

  @doc """
  Creates a changeset for updating session status.
  """
  def update_status_changeset(session, status, attrs \\ %{}) do
    session
    |> cast(attrs, [:error_message, :metadata])
    |> put_change(:status, status)
    |> validate_inclusion(:status, @statuses)
    |> maybe_set_completed_at(status)
    |> validate_status_transition(session.status)
  end

  @doc """
  Creates a changeset for updating file counts and statistics.
  """
  def update_stats_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :file_count,
      :total_size_bytes,
      :violations_count,
      :critical_issues_count,
      :warnings_count,
      :processing_time_ms
    ])
    |> validate_number(:file_count, greater_than_or_equal_to: 0)
    |> validate_number(:total_size_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:violations_count, greater_than_or_equal_to: 0)
    |> validate_number(:critical_issues_count, greater_than_or_equal_to: 0)
    |> validate_number(:warnings_count, greater_than_or_equal_to: 0)
    |> validate_number(:processing_time_ms, greater_than_or_equal_to: 0)
  end

  @doc """
  Creates a changeset for completing an analysis session.
  """
  def complete_changeset(session, stats \\ %{}) do
    now = DateTime.utc_now()

    processing_time =
      if session.started_at do
        DateTime.diff(now, session.started_at, :millisecond)
      else
        Map.get(stats, :processing_time_ms, 0)
      end

    session
    |> cast(stats, [
      :file_count,
      :total_size_bytes,
      :violations_count,
      :critical_issues_count,
      :warnings_count,
      :metadata
    ])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, now)
    |> put_change(:processing_time_ms, processing_time)
  end

  @doc """
  Creates a changeset for failing an analysis session.
  """
  def fail_changeset(session, error_message, metadata \\ %{}) do
    now = DateTime.utc_now()

    processing_time =
      if session.started_at do
        DateTime.diff(now, session.started_at, :millisecond)
      else
        0
      end

    session
    |> cast(%{error_message: error_message, metadata: metadata}, [:error_message, :metadata])
    |> put_change(:status, "failed")
    |> put_change(:completed_at, now)
    |> put_change(:processing_time_ms, processing_time)
    |> validate_required([:error_message])
  end

  @doc """
  Creates a changeset for cancelling an analysis session.
  """
  def cancel_changeset(session) do
    now = DateTime.utc_now()

    processing_time =
      if session.started_at do
        DateTime.diff(now, session.started_at, :millisecond)
      else
        0
      end

    session
    |> put_change(:status, "cancelled")
    |> put_change(:completed_at, now)
    |> put_change(:processing_time_ms, processing_time)
  end

  # Private functions

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
      "upload_id",
      "source_type",
      "repository_info",
      "analysis_options",
      "user_agent",
      "client_version",
      "file_patterns",
      "exclude_patterns"
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

  defp maybe_set_completed_at(changeset, status)
       when status in ["completed", "failed", "cancelled"] do
    case get_field(changeset, :completed_at) do
      nil -> put_change(changeset, :completed_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  defp maybe_set_completed_at(changeset, _status), do: changeset

  defp validate_status_transition(changeset, current_status) do
    new_status = get_change(changeset, :status)

    case {current_status, new_status} do
      # Valid transitions
      {"pending", "processing"} ->
        changeset

      {"pending", "cancelled"} ->
        changeset

      {"pending", "failed"} ->
        changeset

      {"processing", "completed"} ->
        changeset

      {"processing", "failed"} ->
        changeset

      {"processing", "cancelled"} ->
        changeset

      # No change
      {status, status} ->
        changeset

      # Invalid transitions
      {from, to} ->
        add_error(changeset, :status, "cannot transition from '#{from}' to '#{to}'")
    end
  end

  @doc """
  Returns all valid statuses.
  """
  def statuses, do: @statuses

  @doc """
  Checks if the session is in progress.
  """
  def in_progress?(%__MODULE__{status: status}) when status in ["pending", "processing"], do: true
  def in_progress?(_), do: false

  @doc """
  Checks if the session is completed.
  """
  def completed?(%__MODULE__{status: "completed"}), do: true
  def completed?(_), do: false

  @doc """
  Checks if the session has failed.
  """
  def failed?(%__MODULE__{status: "failed"}), do: true
  def failed?(_), do: false

  @doc """
  Checks if the session was cancelled.
  """
  def cancelled?(%__MODULE__{status: "cancelled"}), do: true
  def cancelled?(_), do: false

  @doc """
  Returns the duration of the analysis in milliseconds.
  """
  def duration(%__MODULE__{started_at: nil}), do: nil

  def duration(%__MODULE__{started_at: started, completed_at: nil}) do
    DateTime.diff(DateTime.utc_now(), started, :millisecond)
  end

  def duration(%__MODULE__{started_at: started, completed_at: completed}) do
    DateTime.diff(completed, started, :millisecond)
  end

  @doc """
  Returns a human-readable status description.
  """
  def status_description(%__MODULE__{status: "pending"}), do: "Waiting to start"
  def status_description(%__MODULE__{status: "processing"}), do: "Analyzing files"
  def status_description(%__MODULE__{status: "completed"}), do: "Analysis complete"

  def status_description(%__MODULE__{status: "failed", error_message: msg}) when is_binary(msg) do
    "Failed: #{msg}"
  end

  def status_description(%__MODULE__{status: "failed"}), do: "Analysis failed"
  def status_description(%__MODULE__{status: "cancelled"}), do: "Analysis cancelled"

  @doc """
  Returns analysis summary statistics.
  """
  def summary(%__MODULE__{} = session) do
    %{
      status: session.status,
      file_count: session.file_count,
      total_size_mb: round(session.total_size_bytes / 1_048_576 * 100) / 100,
      violations_count: session.violations_count,
      critical_issues_count: session.critical_issues_count,
      warnings_count: session.warnings_count,
      processing_time_seconds: round(session.processing_time_ms / 1000 * 100) / 100,
      started_at: session.started_at,
      completed_at: session.completed_at
    }
  end
end
