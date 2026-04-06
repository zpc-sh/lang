defmodule Lang.Analysis do
  @moduledoc "Facade over the unified Analyses domain. Prefer resource actions."

  require Ash.Query
  alias Lang.Analyses.{Project, Run, File, Violation}

  # Projects
  def list_projects(user_id, opts \\ []) do
    order_by = Keyword.get(opts, :order_by, :inserted_at)
    order_dir = Keyword.get(opts, :order_dir, :desc)

    Project
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort([{order_dir, order_by}])
    |> Ash.Query.load([:analysis_sessions])
    |> Ash.read!()
  end

  def get_project!(id), do: Project.by_id!(id, load: [:analysis_sessions])

  def get_user_project(user_id, project_id) do
    Project
    |> Ash.Query.filter(id == ^project_id and user_id == ^user_id)
    |> Ash.Query.load([:analysis_sessions])
    |> Ash.read_one()
    |> case do
      {:ok, v} -> v
      _ -> nil
    end
  end

  def create_project(attrs \\ %{}), do: Project.create(attrs)
  def update_project(project, attrs), do: Project.update(project, attrs)
  def archive_project(project), do: Project.archive(project)
  def activate_project(project), do: Project.activate(project)
  def delete_project(project), do: Project.destroy(project)
  def change_project(project, attrs \\ %{}), do: Ash.Changeset.for_update(project, :update, attrs)

  # Runs/Sessions
  def list_analysis_sessions(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Run
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.offset(offset)
    |> Ash.Query.load([:analyzed_files])
    |> Ash.read!()
  end

  def get_latest_analysis_session(project_id) do
    Run
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.Query.load([:analyzed_files])
    |> Ash.read_one()
    |> elem(1)
  end

  def get_analysis_session!(id), do: Run.by_id!(id, load: [:analyzed_files, :project])

  def get_user_analysis_session(user_id, session_id) do
    Run
    |> Ash.Query.filter(id == ^session_id)
    |> Ash.Query.load([:project])
    |> Ash.read_one()
    |> case do
      {:ok, %{project: %{user_id: ^user_id}} = run} -> run
      _ -> nil
    end
  end

  def create_analysis_session(attrs \\ %{}), do: Run.create(attrs)

  def update_analysis_session_status(run, status, attrs \\ %{}),
    do:
      Run.update_status(run, %{
        status: status,
        metadata: attrs[:metadata],
        error_message: attrs[:error_message]
      })

  def update_analysis_session_stats(run, stats), do: Run.update_stats(run, stats)
  def complete_analysis_session(run, stats \\ %{}), do: Run.complete(run, stats)

  def fail_analysis_session(run, msg, metadata \\ %{}),
    do: Run.fail(run, %{error_message: msg, metadata: metadata})

  def cancel_analysis_session(run), do: Run.cancel(run)

  # Files
  def list_analyzed_files(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    File
    |> Ash.Query.filter(analysis_session_id == ^session_id)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.offset(offset)
    |> Ash.Query.load([:violations])
    |> Ash.read!()
  end

  def get_analyzed_file!(id), do: File.by_id!(id, load: [:violations])

  def get_user_analyzed_file(user_id, file_id) do
    File
    |> Ash.Query.filter(id == ^file_id)
    |> Ash.Query.load(analysis_session: [:project])
    |> Ash.read_one()
    |> case do
      {:ok, %{analysis_session: %{project: %{user_id: ^user_id}}} = file} -> file
      _ -> nil
    end
  end

  def create_analyzed_file(attrs \\ %{}), do: File.create(attrs)

  def update_analyzed_file_status(file, status, _attrs \\ %{}),
    do: File.update_status(file, %{status: status})

  def complete_analyzed_file(file, result, ms),
    do: File.complete(file, %{analysis_result: result}, %{processing_time_ms: ms})

  def fail_analyzed_file(file, msg), do: File.fail(file, %{}, %{error_message: msg})
  def skip_analyzed_file(file, reason), do: File.skip(file, %{}, %{reason: reason})

  def update_analyzed_file(file_id, attrs) when is_binary(file_id),
    do: with({:ok, file} <- File.by_id(file_id), do: update_analyzed_file(file, attrs))

  def update_analyzed_file(file, attrs), do: Ash.update(file, attrs)

  def create_scan_result(attrs \\ %{}) do
    session_id = Map.get(attrs, :session_id) || Map.get(attrs, "session_id")
    files = Map.get(attrs, :files) || Map.get(attrs, "files", [])

    created_files =
      Enum.flat_map(files, fn file_attrs ->
        case create_analyzed_file(Map.put(file_attrs, :analysis_session_id, session_id)) do
          {:ok, file} -> [file]
          _ -> []
        end
      end)

    {:ok, %{files: created_files}}
  end

  # Violations
  def list_violations(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    ids =
      File
      |> Ash.Query.filter(analysis_session_id == ^session_id)
      |> Ash.Query.select([:id])
      |> Ash.read!()
      |> Enum.map(& &1.id)

    Violation
    |> Ash.Query.filter(analyzed_file_id in ^ids)
    |> Ash.Query.sort([{:desc, :severity_level}, {:asc, :inserted_at}])
    |> Ash.Query.limit(limit)
    |> Ash.Query.offset(offset)
    |> Ash.read!()
  end

  def get_violation_stats(session_id) do
    vs = list_violations(session_id, limit: 10_000)

    %{
      total: length(vs),
      by_severity:
        vs
        |> Enum.frequencies_by(& &1.severity)
        |> Map.merge(%{info: 0, low: 0, medium: 0, high: 0, critical: 0}),
      open: Enum.count(vs, &(&1.status in [:open, :acknowledged]))
    }
  end

  def get_violation!(id), do: Violation.by_id!(id)

  def get_user_violation(user_id, violation_id) do
    Violation
    |> Ash.Query.filter(id == ^violation_id)
    |> Ash.Query.load(analyzed_file: [analysis_session: [:project]])
    |> Ash.read_one()
    |> case do
      {:ok, %{analyzed_file: %{analysis_session: %{project: %{user_id: ^user_id}}}} = violation} ->
        violation

      _ ->
        nil
    end
  end
  def create_violation(attrs \\ %{}), do: Violation.create(attrs)

  def update_violation_status(v, status, attrs \\ %{}),
    do: Violation.update_status(v, %{}, %{status: status, metadata: attrs[:metadata]})

  def resolve_violation(v, who, note \\ nil),
    do: Violation.resolve(v, %{}, %{resolved_by: who, resolution_note: note})

  def acknowledge_violation(v, who, note \\ nil),
    do: Violation.acknowledge(v, %{}, %{acknowledged_by: who, note: note})

  def suppress_violation(v, who, reason),
    do: Violation.suppress(v, %{}, %{suppressed_by: who, reason: reason})

  def mark_false_positive(v, who, reason),
    do: Violation.mark_false_positive(v, %{}, %{marked_by: who, reason: reason})

  def get_user_analysis_stats(user_id) do
    projects = list_projects(user_id)
    project_ids = Enum.map(projects, & &1.id)

    sessions =
      Run
      |> Ash.Query.filter(project_id in ^project_ids)
      |> Ash.read!()

    total_files = Enum.sum_by(sessions, &(&1.file_count || 0))
    total_violations = Enum.sum_by(sessions, &(&1.violations_count || 0))
    critical_violations = Enum.sum_by(sessions, &(&1.critical_issues_count || 0))

    recent_sessions_count =
      sessions
      |> Enum.filter(fn s ->
        s.inserted_at &&
          DateTime.diff(DateTime.utc_now(), s.inserted_at, :day) <= 30
      end)
      |> length()

    %{
      total_projects: length(projects),
      total_files: total_files,
      total_violations: total_violations,
      critical_violations: critical_violations,
      recent_sessions: recent_sessions_count
    }
  end

  def process_analysis_session(session, files) do
    # Placeholder for actual processing logic
    # In a real app, this would trigger background workers
    {:ok, session}
  end

  # Ephemeral/placeholder helpers (not implemented yet)
  def analyze_ephemeral(_files), do: {:error, :not_implemented}
  def ingest_file_content(_session_id, _attrs), do: {:error, :not_implemented}
end
