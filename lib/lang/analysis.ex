defmodule Lang.Analysis do
  @moduledoc """
  The Analysis context.

  This module provides the main API for managing analysis projects,
  sessions, files, and violations.
  """

  import Ecto.Query, warn: false
  alias Lang.Repo

  alias Lang.Analysis.{
    Project,
    AnalysisSession,
    AnalyzedFile,
    Violation,
    AnalysisRule,
    ProjectRuleConfig,
    AnalysisInsight
  }

  # Projects

  @doc """
  Returns the list of projects for a user.

  ## Examples

      iex> list_projects(user_id)
      [%Project{}, ...]

  """
  def list_projects(user_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)
    order_by = Keyword.get(opts, :order_by, :inserted_at)
    order_dir = Keyword.get(opts, :order_dir, :desc)

    Project
    |> where([p], p.user_id == ^user_id)
    |> maybe_filter_by_status(status_filter)
    |> order_by([p], {^order_dir, field(p, ^order_by)})
    |> preload([:analysis_sessions])
    |> Repo.all()
  end

  @doc """
  Gets a single project.

  Raises `Ecto.NoResultsError` if the Project does not exist.

  ## Examples

      iex> get_project!(123)
      %Project{}

      iex> get_project!(456)
      ** (Ecto.NoResultsError)

  """
  def get_project!(id), do: Repo.get!(Project, id) |> Repo.preload([:analysis_sessions])

  @doc """
  Gets a project by user ID and project ID.

  Returns nil if the project doesn't exist or doesn't belong to the user.
  """
  def get_user_project(user_id, project_id) do
    Project
    |> where([p], p.id == ^project_id and p.user_id == ^user_id)
    |> preload([:analysis_sessions])
    |> Repo.one()
  end

  @doc """
  Creates a project.

  ## Examples

      iex> create_project(%{field: value})
      {:ok, %Project{}}

      iex> create_project(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.

  ## Examples

      iex> update_project(project, %{field: new_value})
      {:ok, %Project{}}

      iex> update_project(project, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Archives a project.
  """
  def archive_project(%Project{} = project) do
    project
    |> Project.archive_changeset()
    |> Repo.update()
  end

  @doc """
  Activates a project.
  """
  def activate_project(%Project{} = project) do
    project
    |> Project.activate_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes a project.

  ## Examples

      iex> delete_project(project)
      {:ok, %Project{}}

      iex> delete_project(project)
      {:error, %Ecto.Changeset{}}

  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.

  ## Examples

      iex> change_project(project)
      %Ecto.Changeset{data: %Project{}}

  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.update_changeset(project, attrs)
  end

  # Analysis Sessions

  @doc """
  Returns the list of analysis sessions for a project.
  """
  def list_analysis_sessions(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    status_filter = Keyword.get(opts, :status)

    AnalysisSession
    |> where([s], s.project_id == ^project_id)
    |> maybe_filter_by_status(status_filter)
    |> order_by([s], desc: s.started_at)
    |> limit(^limit)
    |> offset(^offset)
    |> preload([:analyzed_files, :analysis_insights])
    |> Repo.all()
  end

  @doc """
  Gets the latest analysis session for a project.
  """
  def get_latest_analysis_session(project_id) do
    AnalysisSession
    |> where([s], s.project_id == ^project_id)
    |> order_by([s], desc: s.started_at)
    |> limit(1)
    |> preload([:analyzed_files, :analysis_insights])
    |> Repo.one()
  end

  @doc """
  Gets a single analysis session.

  Raises `Ecto.NoResultsError` if the AnalysisSession does not exist.
  """
  def get_analysis_session!(id) do
    Repo.get!(AnalysisSession, id)
    |> Repo.preload([:analyzed_files, :analysis_insights, :project])
  end

  @doc """
  Creates an analysis session.
  """
  def create_analysis_session(attrs \\ %{}) do
    %AnalysisSession{}
    |> AnalysisSession.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates analysis session status.
  """
  def update_analysis_session_status(%AnalysisSession{} = session, status, attrs \\ %{}) do
    session
    |> AnalysisSession.update_status_changeset(status, attrs)
    |> Repo.update()
  end

  @doc """
  Updates analysis session statistics.
  """
  def update_analysis_session_stats(%AnalysisSession{} = session, stats) do
    session
    |> AnalysisSession.update_stats_changeset(stats)
    |> Repo.update()
  end

  @doc """
  Completes an analysis session.
  """
  def complete_analysis_session(%AnalysisSession{} = session, stats \\ %{}) do
    session
    |> AnalysisSession.complete_changeset(stats)
    |> Repo.update()
  end

  @doc """
  Fails an analysis session.
  """
  def fail_analysis_session(%AnalysisSession{} = session, error_message, metadata \\ %{}) do
    session
    |> AnalysisSession.fail_changeset(error_message, metadata)
    |> Repo.update()
  end

  @doc """
  Cancels an analysis session.
  """
  def cancel_analysis_session(%AnalysisSession{} = session) do
    session
    |> AnalysisSession.cancel_changeset()
    |> Repo.update()
  end

  # Analyzed Files

  @doc """
  Returns the list of analyzed files for a session.
  """
  def list_analyzed_files(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    status_filter = Keyword.get(opts, :status)
    language_filter = Keyword.get(opts, :language)

    AnalyzedFile
    |> where([f], f.analysis_session_id == ^session_id)
    |> maybe_filter_by_status(status_filter)
    |> maybe_filter_by_language(language_filter)
    |> order_by([f], asc: f.file_path)
    |> limit(^limit)
    |> offset(^offset)
    |> preload([:violations])
    |> Repo.all()
  end

  @doc """
  Gets a single analyzed file.
  """
  def get_analyzed_file!(id) do
    Repo.get!(AnalyzedFile, id)
    |> Repo.preload([:violations, :analysis_session])
  end

  @doc """
  Creates an analyzed file.
  """
  def create_analyzed_file(attrs \\ %{}) do
    %AnalyzedFile{}
    |> AnalyzedFile.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates analyzed file status.
  """
  def update_analyzed_file_status(%AnalyzedFile{} = file, status, attrs \\ %{}) do
    file
    |> AnalyzedFile.update_status_changeset(status, attrs)
    |> Repo.update()
  end

  @doc """
  Completes analyzed file processing.
  """
  def complete_analyzed_file(%AnalyzedFile{} = file, analysis_result, processing_time_ms) do
    file
    |> AnalyzedFile.complete_changeset(analysis_result, processing_time_ms)
    |> Repo.update()
  end

  @doc """
  Fails analyzed file processing.
  """
  def fail_analyzed_file(%AnalyzedFile{} = file, error_message) do
    file
    |> AnalyzedFile.fail_changeset(error_message)
    |> Repo.update()
  end

  @doc """
  Skips analyzed file processing.
  """
  def skip_analyzed_file(%AnalyzedFile{} = file, reason) do
    file
    |> AnalyzedFile.skip_changeset(reason)
    |> Repo.update()
  end

  @doc """
  Updates an analyzed file with analysis results.

  ## Examples

      iex> update_analyzed_file(file_id, %{semantic_features: %{...}})
      {:ok, %AnalyzedFile{}}

      iex> update_analyzed_file(file_id, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_analyzed_file(file_id, attrs) when is_binary(file_id) do
    file = get_analyzed_file!(file_id)
    update_analyzed_file(file, attrs)
  end

  def update_analyzed_file(%AnalyzedFile{} = file, attrs) do
    file
    |> AnalyzedFile.update_analysis_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a scan result record for filesystem scanning.

  ## Examples

      iex> create_scan_result(%{session_id: session_id, status: "completed"})
      {:ok, %ScanResult{}}

  """
  def create_scan_result(attrs \\ %{}) do
    %{
      session_id: Map.get(attrs, :session_id),
      status: Map.get(attrs, :status, "pending"),
      files_scanned: Map.get(attrs, :files_scanned, 0),
      errors_count: Map.get(attrs, :errors_count, 0),
      scan_data: Map.get(attrs, :scan_data, %{}),
      started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
      completed_at: Map.get(attrs, :completed_at),
      id: Ecto.UUID.generate()
    }
    |> then(fn scan_result -> {:ok, scan_result} end)
  end

  # Violations

  @doc """
  Returns the list of violations for an analysis session.
  """
  def list_violations(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    severity_filter = Keyword.get(opts, :severity)
    status_filter = Keyword.get(opts, :status)
    category_filter = Keyword.get(opts, :category)

    query =
      from v in Violation,
        join: f in AnalyzedFile,
        on: v.analyzed_file_id == f.id,
        where: f.analysis_session_id == ^session_id,
        order_by: [desc: v.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:analyzed_file]

    query
    |> maybe_filter_by_severity(severity_filter)
    |> maybe_filter_by_status(status_filter)
    |> maybe_filter_by_category(category_filter)
    |> Repo.all()
  end

  @doc """
  Returns violation statistics for an analysis session.
  """
  def get_violation_stats(session_id) do
    query =
      from v in Violation,
        join: f in AnalyzedFile,
        on: v.analyzed_file_id == f.id,
        where: f.analysis_session_id == ^session_id

    total = Repo.aggregate(query, :count)

    by_severity =
      query
      |> group_by([v], v.severity)
      |> select([v], {v.severity, count()})
      |> Repo.all()
      |> Map.new()

    by_status =
      query
      |> group_by([v], v.status)
      |> select([v], {v.status, count()})
      |> Repo.all()
      |> Map.new()

    by_category =
      query
      |> group_by([v], v.rule_category)
      |> select([v], {v.rule_category, count()})
      |> Repo.all()
      |> Map.new()

    %{
      total: total,
      by_severity: by_severity,
      by_status: by_status,
      by_category: by_category
    }
  end

  @doc """
  Gets a single violation.
  """
  def get_violation!(id) do
    Repo.get!(Violation, id)
    |> Repo.preload([:analyzed_file])
  end

  @doc """
  Creates a violation.
  """
  def create_violation(attrs \\ %{}) do
    %Violation{}
    |> Violation.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates violation status.
  """
  def update_violation_status(%Violation{} = violation, status, attrs \\ %{}) do
    violation
    |> Violation.update_status_changeset(status, attrs)
    |> Repo.update()
  end

  @doc """
  Resolves a violation.
  """
  def resolve_violation(%Violation{} = violation, resolved_by, resolution_note \\ nil) do
    violation
    |> Violation.resolve_changeset(resolved_by, resolution_note)
    |> Repo.update()
  end

  @doc """
  Acknowledges a violation.
  """
  def acknowledge_violation(%Violation{} = violation, acknowledged_by, note \\ nil) do
    violation
    |> Violation.acknowledge_changeset(acknowledged_by, note)
    |> Repo.update()
  end

  @doc """
  Suppresses a violation.
  """
  def suppress_violation(%Violation{} = violation, suppressed_by, reason) do
    violation
    |> Violation.suppress_changeset(suppressed_by, reason)
    |> Repo.update()
  end

  @doc """
  Marks violation as false positive.
  """
  def mark_false_positive(%Violation{} = violation, marked_by, reason) do
    violation
    |> Violation.false_positive_changeset(marked_by, reason)
    |> Repo.update()
  end

  # Analysis Rules

  @doc """
  Returns the list of analysis rules.
  """
  def list_analysis_rules(opts \\ []) do
    enabled_only = Keyword.get(opts, :enabled_only, false)
    category_filter = Keyword.get(opts, :category)
    language_filter = Keyword.get(opts, :language)

    AnalysisRule
    |> maybe_filter_enabled(enabled_only)
    |> maybe_filter_by_category(category_filter)
    |> maybe_filter_by_language(language_filter)
    |> order_by([r], [r.category, r.name])
    |> Repo.all()
  end

  @doc """
  Gets project-specific rule configurations.
  """
  def get_project_rules(project_id) do
    from(prc in ProjectRuleConfig,
      join: ar in AnalysisRule,
      on: prc.analysis_rule_id == ar.id,
      where: prc.project_id == ^project_id,
      select: %{
        rule: ar,
        config: prc
      }
    )
    |> Repo.all()
  end

  # Analysis Processing

  @doc """
  Processes files for analysis in an analysis session.

  This function orchestrates the analysis process:
  1. Creates analyzed file records
  2. Queues files for processing
  3. Updates session statistics
  """
  def process_analysis_session(%AnalysisSession{} = session, files) when is_list(files) do
    Repo.transaction(fn ->
      try do
        # Update session status to processing
        {:ok, session} = update_analysis_session_status(session, "processing")

        # Create analyzed file records
        analyzed_files = create_analyzed_files(session.id, files)

        # Update initial session stats
        total_size = Enum.reduce(analyzed_files, 0, &(&1.file_size_bytes + &2))

        {:ok, session} =
          update_analysis_session_stats(session, %{
            file_count: length(analyzed_files),
            total_size_bytes: total_size
          })

        # Queue files for analysis (this would typically use a job queue)
        Enum.each(analyzed_files, &queue_file_analysis/1)

        {:ok, session}
      rescue
        e ->
          fail_analysis_session(session, "Failed to process files: #{Exception.message(e)}")
          Repo.rollback(e)
      end
    end)
  end

  # Private helper functions

  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, status), do: where(query, [item], item.status == ^status)

  defp maybe_filter_by_severity(query, nil), do: query
  defp maybe_filter_by_severity(query, severity), do: where(query, [v], v.severity == ^severity)

  defp maybe_filter_by_category(query, nil), do: query

  defp maybe_filter_by_category(query, category),
    do: where(query, [item], item.rule_category == ^category or item.category == ^category)

  defp maybe_filter_by_language(query, nil), do: query

  defp maybe_filter_by_language(query, language),
    do: where(query, [f], f.language_detected == ^language)

  defp maybe_filter_enabled(query, false), do: query
  defp maybe_filter_enabled(query, true), do: where(query, [r], r.enabled == true)

  defp create_analyzed_files(session_id, files) do
    files
    |> Enum.map(fn file_attrs ->
      attrs = Map.put(file_attrs, :analysis_session_id, session_id)

      case create_analyzed_file(attrs) do
        {:ok, file} -> file
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp queue_file_analysis(%AnalyzedFile{} = file) do
    # This is where you'd queue the file for actual analysis
    # For now, we'll just update the status to processing
    update_analyzed_file_status(file, "processing")

    # In a real implementation, this would:
    # 1. Send the file to a job queue (Oban, Broadway, etc.)
    # 2. The job would perform the actual tree-sitter parsing
    # 3. Apply analysis rules and create violations
    # 4. Update the file status to completed or failed
  end

  @doc """
  Returns analysis statistics for a user.
  """
  def get_user_analysis_stats(user_id) do
    # Get all projects for user
    projects_query = from p in Project, where: p.user_id == ^user_id, select: p.id

    # Get all sessions for user's projects
    sessions_query =
      from s in AnalysisSession,
        where: s.project_id in subquery(projects_query)

    # Get all files for user's sessions
    files_query =
      from f in AnalyzedFile,
        join: s in AnalysisSession,
        on: f.analysis_session_id == s.id,
        where: s.project_id in subquery(projects_query)

    # Get all violations for user's files
    violations_query =
      from v in Violation,
        join: f in AnalyzedFile,
        on: v.analyzed_file_id == f.id,
        join: s in AnalysisSession,
        on: f.analysis_session_id == s.id,
        where: s.project_id in subquery(projects_query)

    total_projects = Repo.aggregate(projects_query, :count)
    total_sessions = Repo.aggregate(sessions_query, :count)
    total_files = Repo.aggregate(files_query, :count)
    total_violations = Repo.aggregate(violations_query, :count)

    # Get violations by severity
    critical_violations =
      violations_query
      |> where([v], v.severity == "critical")
      |> Repo.aggregate(:count)

    high_violations =
      violations_query
      |> where([v], v.severity == "high")
      |> Repo.aggregate(:count)

    # Get recent activity (last 30 days)
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    recent_sessions =
      sessions_query
      |> where([s], s.started_at > ^thirty_days_ago)
      |> Repo.aggregate(:count)

    %{
      total_projects: total_projects,
      total_sessions: total_sessions,
      total_files: total_files,
      total_violations: total_violations,
      critical_violations: critical_violations,
      high_violations: high_violations,
      recent_sessions: recent_sessions
    }
  end
end
