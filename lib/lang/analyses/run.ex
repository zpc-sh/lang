defmodule Lang.Analyses.Run do
  @moduledoc """
  AnalysisSession Resource for Analysis Domain

  Represents a single analysis run within a project. Tracks lifecycle,
  counts, timing, and any error/metadata associated with the run.
  """

  use Ash.Resource,
    domain: Lang.Analyses,
    data_layer: AshPostgres.DataLayer

  alias Lang.Analyses.Project
  alias Lang.Analyses.File

  postgres do
    table("analysis_sessions")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :status, :atom do
      allow_nil?(false)
      default(:pending)
      constraints(one_of: [:pending, :running, :completed, :failed])
    end

    attribute :started_at, :utc_datetime do
      allow_nil?(true)
    end

    attribute :completed_at, :utc_datetime do
      allow_nil?(true)
    end

    attribute :file_count, :integer do
      allow_nil?(false)
      default(0)
    end

    attribute :total_size_bytes, :integer do
      allow_nil?(false)
      default(0)
    end

    attribute :violations_count, :integer do
      allow_nil?(false)
      default(0)
    end

    attribute :critical_issues_count, :integer do
      allow_nil?(false)
      default(0)
    end

    attribute :warnings_count, :integer do
      allow_nil?(false)
      default(0)
    end

    attribute :processing_time_ms, :integer do
      allow_nil?(true)
    end

    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
    end

    attribute :error_message, :string do
      allow_nil?(true)
    end

    attribute :workspace_id, :uuid do
      allow_nil?(true)
      description("Ephemeral workspace identifier (maps to Redis store)")
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :project, Project do
      attribute_writable?(true)
    end

    # Workspace is Redis-backed; avoid cross data-layer relationship here.

    has_many :analyzed_files, File do
      destination_attribute(:analysis_session_id)
    end
  end

  actions do
    defaults([:read])

    create :create do
      accept([:project_id, :metadata])
      validate(present([:project_id]))

      change(fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :pending)
        |> Ash.Changeset.change_attribute(:started_at, DateTime.utc_now())
      end)
    end

    update :update_status do
      accept([:status, :error_message, :metadata])
      validate(present(:status))
      validate(one_of(:status, [:pending, :running, :completed, :failed]))

      change(fn changeset, _ ->
        status = Ash.Changeset.get_attribute(changeset, :status)
        changeset = Ash.Changeset.change_attribute(changeset, :status, status)

        case status do
          :running ->
            Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())

          :completed ->
            Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())

          :failed ->
            Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())

          _ ->
            changeset
        end
      end)
    end

    update :update_stats do
      accept([
        :file_count,
        :total_size_bytes,
        :violations_count,
        :critical_issues_count,
        :warnings_count,
        :processing_time_ms,
        :metadata
      ])
    end

    update :complete do
      accept([
        :file_count,
        :total_size_bytes,
        :violations_count,
        :critical_issues_count,
        :warnings_count,
        :processing_time_ms,
        :metadata
      ])

      change(fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :completed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end)
    end

    update :fail do
      accept([:error_message, :metadata])

      validate(present(:error_message))

      change(fn changeset, _ ->
        msg = Ash.Changeset.get_attribute(changeset, :error_message)

        changeset
        |> Ash.Changeset.change_attribute(:status, :failed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:error_message, msg)
      end)
    end

    update :cancel do
      accept([])

      change(fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :failed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:error_message, "cancelled")
      end)
    end

    destroy(:destroy)
  end

  code_interface do
    define(:read_all, action: :read)
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:update_status, action: :update_status)
    define(:update_stats, action: :update_stats)
    define(:complete, action: :complete)
    define(:fail, action: :fail)
    define(:cancel, action: :cancel)
    define(:destroy, action: :destroy)
  end

  preparations do
    prepare(build(load: [:project, :analyzed_files]))
  end

  # Helper predicates (legacy compatibility)
  def in_progress?(%{status: status}) when status in [:pending, :running], do: true
  def in_progress?(_), do: false

  def duration(%{started_at: nil}), do: 0

  def duration(%{started_at: start_time, completed_at: nil}) do
    DateTime.diff(DateTime.utc_now(), start_time, :millisecond)
  end

  def duration(%{started_at: start_time, completed_at: end_time}) do
    DateTime.diff(end_time, start_time, :millisecond)
  end

  def status_description(%{status: :pending}), do: "Pending"
  def status_description(%{status: :running}), do: "Running"
  def status_description(%{status: :completed}), do: "Completed"
  def status_description(%{status: :failed}), do: "Failed"
  def status_description(_), do: "Unknown"

  def summary(%{} = run) do
    %{
      id: run.id,
      status: run.status,
      file_count: run.file_count,
      violations_count: run.violations_count,
      warnings_count: run.warnings_count,
      critical_issues_count: run.critical_issues_count,
      duration_ms: duration(run)
    }
  end
end
