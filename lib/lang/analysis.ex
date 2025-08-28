defmodule Lang.Analysis do
  @moduledoc """
  Analysis Domain for LANG Platform

  This domain provides the main API for managing analysis projects,
  sessions, files, and violations using Ash Framework with full
  integration to Workspace Store (Redis) and MCP Broker systems.

  Integrates with:
  - Lang.Workspace.Store for Redis-backed session state
  - Lang.MCP.Broker for Model Context Protocol integration
  - Kyozo.Lang.UniversalParser for text intelligence
  - Lang.Native.* modules for high-performance parsing
  """

  use Ash.Domain

  alias Lang.Analysis.{Project, AnalysisSession, AnalyzedFile, Violation}
  alias Lang.Workspace.Store
  alias Lang.MCP.Broker
  alias Kyozo.Lang.UniversalParser

  resources do
    resource(Project)
    resource(AnalysisSession)
    resource(AnalyzedFile)
    resource(Violation)
  end

  # === PROJECT OPERATIONS ===

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

    query =
      Project
      |> Ash.Query.filter(user_id == ^user_id)
      |> maybe_filter_by_status(status_filter)
      |> Ash.Query.sort([{order_dir, order_by}])
      |> Ash.Query.load([:analysis_sessions])

    case Ash.read(query) do
      {:ok, projects} -> projects
      {:error, _error} -> []
    end
  end

  @doc """
  Gets a single project.

  Raises if the Project does not exist.
  """
  def get_project!(id) do
    case Project.by_id(id, load: [:analysis_sessions]) do
      {:ok, project} -> project
      {:error, %Ash.Error.Query.NotFound{}} -> raise Ecto.NoResultsError, queryable: Project
      {:error, error} -> raise error
    end
  end

  @doc """
  Gets a project for a specific user.

  Returns nil if the project doesn't exist or doesn't belong to the user.
  """
  def get_user_project(user_id, project_id) do
    query =
      Project
      |> Ash.Query.filter(id == ^project_id and user_id == ^user_id)
      |> Ash.Query.load([:analysis_sessions])

    case Ash.read_one(query) do
      {:ok, project} -> project
      {:ok, nil} -> nil
      {:error, _error} -> nil
    end
  end

  @doc """
  Creates a project.

  ## Examples

      iex> create_project(%{name: "My Project", user_id: user_id})
      {:ok, %Project{}}

      iex> create_project(%{name: ""})
      {:error, %Ash.Error.Invalid{}}

  """
  def create_project(attrs \\ %{}) do
    Project.create(attrs)
  end

  @doc """
  Updates a project.

  ## Examples

      iex> update_project(project, %{name: "Updated Name"})
      {:ok, %Project{}}

      iex> update_project(project, %{name: ""})
      {:error, %Ash.Error.Invalid{}}

  """
  def update_project(%Project{} = project, attrs) do
    Project.update(project, attrs)
  end

  @doc """
  Archives a project.
  """
  def archive_project(%Project{} = project) do
    Project.archive(project)
  end

  @doc """
  Activates a project.
  """
  def activate_project(%Project{} = project) do
    Project.activate(project)
  end

  @doc """
  Deletes a project.

  ## Examples

      iex> delete_project(project)
      {:ok, %Project{}}

      iex> delete_project(project)
      {:error, %Ash.Error.Invalid{}}

  """
  def delete_project(%Project{} = project) do
    Project.destroy(project)
  end

  @doc """
  Returns an `%Ash.Changeset{}` for tracking project changes.

  ## Examples

      iex> change_project(project)
      %Ash.Changeset{data: %Project{}}

  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Ash.Changeset.for_update(project, :update, attrs)
  end

  # === ANALYSIS SESSION OPERATIONS ===

  @doc """
  Returns the list of analysis sessions for a project.
  """
  def list_analysis_sessions(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    status_filter = Keyword.get(opts, :status)

    query =
      AnalysisSession
      |> Ash.Query.filter(project_id == ^project_id)
      |> maybe_filter_session_by_status(status_filter)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)
      |> Ash.Query.load([:analyzed_files])

    case Ash.read(query) do
      {:ok, sessions} -> sessions
      {:error, _error} -> []
    end
  end

  @doc """
  Gets the latest analysis session for a project.
  """
  def get_latest_analysis_session(project_id) do
    query =
      AnalysisSession
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(1)
      |> Ash.Query.load([:analyzed_files])

    case Ash.read_one(query) do
      {:ok, session} -> session
      {:ok, nil} -> nil
      {:error, _error} -> nil
    end
  end

  @doc """
  Gets a single analysis session.

  Raises if the AnalysisSession does not exist.
  """
  def get_analysis_session!(id) do
    case AnalysisSession.by_id(id, load: [:analyzed_files, :project]) do
      {:ok, session} ->
        session

      {:error, %Ash.Error.Query.NotFound{}} ->
        raise Ecto.NoResultsError, queryable: AnalysisSession

      {:error, error} ->
        raise error
    end
  end

  @doc """
  Creates an analysis session with workspace store integration.
  """
  def create_analysis_session(attrs \\ %{}) do
    with {:ok, session} <- AnalysisSession.create(attrs) do
      # Initialize workspace store for this session
      session_id = session.id
      
      # Set up initial workspace context
      workspace_context = %{
        "session_id" => session_id,
        "project_id" => session.project_id,
        "root_path" => Map.get(attrs, :root_path),
        "file_tree_hash" => nil,
        "active_files" => [],
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
      
      case Store.put_context(session_id, workspace_context) do
        :ok -> {:ok, session}
        {:error, reason} -> 
          # Clean up session if workspace setup fails
          AnalysisSession.destroy(session)
          {:error, {:workspace_setup_failed, reason}}
      end
    end
  end

  @doc """
  Updates analysis session status.
  """
  def update_analysis_session_status(%AnalysisSession{} = session, status, attrs \\ %{}) do
    AnalysisSession.update_status(session, %{status: status}, %{
      error_message: attrs[:error_message],
      metadata: attrs[:metadata]
    })
  end

  @doc """
  Updates analysis session statistics.
  """
  def update_analysis_session_stats(%AnalysisSession{} = session, stats) do
    AnalysisSession.update_stats(session, stats)
  end

  @doc """
  Completes an analysis session.
  """
  def complete_analysis_session(%AnalysisSession{} = session, stats \\ %{}) do
    AnalysisSession.complete(session, stats)
  end

  @doc """
  Fails an analysis session.
  """
  def fail_analysis_session(%AnalysisSession{} = session, error_message, metadata \\ %{}) do
    AnalysisSession.fail(session, %{error_message: error_message}, %{metadata: metadata})
  end

  @doc """
  Cancels an analysis session and cleans up workspace state.
  """
  def cancel_analysis_session(%AnalysisSession{} = session) do
    with {:ok, cancelled_session} <- AnalysisSession.cancel(session)
  end

  # === ANALYZED FILE OPERATIONS ===

  @doc """
  Returns the list of analyzed files for a session.
  """
  def list_analyzed_files(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    status_filter = Keyword.get(opts, :status)
    language_filter = Keyword.get(opts, :language)

    query =
      AnalyzedFile
      |> Ash.Query.filter(analysis_session_id == ^session_id)
      |> maybe_filter_file_by_status(status_filter)
      |> maybe_filter_file_by_language(language_filter)
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)
      |> Ash.Query.load([:violations])

    case Ash.read(query) do
      {:ok, files} -> files
      {:error, _error} -> []
    end
  end

  @doc """
  Gets a single analyzed file.

  Raises if the AnalyzedFile does not exist.
  """
  def get_analyzed_file!(id) do
    case AnalyzedFile.by_id(id, load: [:violations]) do
      {:ok, file} -> file
      {:error, %Ash.Error.Query.NotFound{}} -> raise Ecto.NoResultsError, queryable: AnalyzedFile
      {:error, error} -> raise error
    end
  end

  @doc """
  Creates an analyzed file.
  """
  def create_analyzed_file(attrs \\ %{}) do
    AnalyzedFile.create(attrs)
  end

  @doc """
  Updates analyzed file status.
  """
  def update_analyzed_file_status(%AnalyzedFile{} = file, status, attrs \\ %{}) do
    AnalyzedFile.update_status(file, %{status: status})
  end

  @doc """
  Completes analyzed file processing.
  """
  def complete_analyzed_file(%AnalyzedFile{} = file, analysis_result, processing_time_ms) do
    AnalyzedFile.complete(file, %{analysis_result: analysis_result}, %{
      processing_time_ms: processing_time_ms
    })
  end

  @doc """
  Fails analyzed file processing.
  """
  def fail_analyzed_file(%AnalyzedFile{} = file, error_message) do
    AnalyzedFile.fail(file, %{}, %{error_message: error_message})
  end

  @doc """
  Skips analyzed file processing.
  """
  def skip_analyzed_file(%AnalyzedFile{} = file, reason) do
    AnalyzedFile.skip(file, %{}, %{reason: reason})
  end

  @doc """
  Updates an analyzed file.

  ## Examples

      iex> update_analyzed_file(file_id, %{field: new_value})
      {:ok, %AnalyzedFile{}}

  """
  def update_analyzed_file(file_id, attrs) when is_binary(file_id) do
    case AnalyzedFile.by_id(file_id) do
      {:ok, file} -> update_analyzed_file(file, attrs)
      error -> error
    end
  end

  def update_analyzed_file(%AnalyzedFile{} = file, attrs) do
    # For analysis result updates, merge with existing data
    if Map.has_key?(attrs, :analysis_result) do
      current_analysis = file.analysis_result || %{}
      updated_analysis = Map.merge(current_analysis, attrs.analysis_result)
      attrs = Map.put(attrs, :analysis_result, updated_analysis)
    end

    Ash.update(file, attrs)
  end

  @doc """
  Creates a scan result (legacy compatibility).

  ## Examples

      iex> create_scan_result(%{session_id: session_id, files: files})
      {:ok, %{files: [%AnalyzedFile{}]}}

  """
  def create_scan_result(attrs \\ %{}) do
    session_id = Map.get(attrs, :session_id) || Map.get(attrs, "session_id")
    files = Map.get(attrs, :files) || Map.get(attrs, "files", [])

    created_files =
      files
      |> Enum.map(fn file_attrs ->
        file_attrs = Map.put(file_attrs, :analysis_session_id, session_id)

        case create_analyzed_file(file_attrs) do
          {:ok, file} -> file
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, %{files: created_files}}
  end

  # === VIOLATION OPERATIONS ===

  @doc """
  Returns the list of violations for a session.
  """
  def list_violations(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    status_filter = Keyword.get(opts, :status)
    severity_filter = Keyword.get(opts, :severity)
    category_filter = Keyword.get(opts, :category)

    # Get violations through analyzed files
    analyzed_file_ids =
      AnalyzedFile
      |> Ash.Query.filter(analysis_session_id == ^session_id)
      |> Ash.Query.select([:id])
      |> Ash.read!()
      |> Enum.map(& &1.id)

    query =
      Violation
      |> Ash.Query.filter(analyzed_file_id in ^analyzed_file_ids)
      |> maybe_filter_violation_by_status(status_filter)
      |> maybe_filter_violation_by_severity(severity_filter)
      |> maybe_filter_violation_by_category(category_filter)
      |> Ash.Query.sort([{:desc, :severity_level}, {:asc, :inserted_at}])
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(offset)

    case Ash.read(query) do
      {:ok, violations} -> violations
      {:error, _error} -> []
    end
  end

  @doc """
  Gets violation statistics for a session.
  """
  def get_violation_stats(session_id) do
    # Get analyzed file IDs for this session
    analyzed_file_ids =
      AnalyzedFile
      |> Ash.Query.filter(analysis_session_id == ^session_id)
      |> Ash.Query.select([:id])
      |> Ash.read!()
      |> Enum.map(& &1.id)

    # Get all violations for these files
    violations =
      Violation
      |> Ash.Query.filter(analyzed_file_id in ^analyzed_file_ids)
      |> Ash.read!()

    total_count = length(violations)

    # Count by status
    status_counts =
      violations
      |> Enum.group_by(& &1.status)
      |> Map.new(fn {status, violations} -> {status, length(violations)} end)

    # Count by severity
    severity_counts =
      violations
      |> Enum.group_by(& &1.severity)
      |> Map.new(fn {severity, violations} -> {severity, length(violations)} end)

    # Count by category
    category_counts =
      violations
      |> Enum.group_by(& &1.rule_category)
      |> Map.new(fn {category, violations} -> {category, length(violations)} end)

    %{
      total_count: total_count,
      by_status: %{
        open: Map.get(status_counts, :open, 0),
        acknowledged: Map.get(status_counts, :acknowledged, 0),
        resolved: Map.get(status_counts, :resolved, 0),
        suppressed: Map.get(status_counts, :suppressed, 0),
        false_positive: Map.get(status_counts, :false_positive, 0)
      },
      by_severity: %{
        info: Map.get(severity_counts, :info, 0),
        low: Map.get(severity_counts, :low, 0),
        medium: Map.get(severity_counts, :medium, 0),
        high: Map.get(severity_counts, :high, 0),
        critical: Map.get(severity_counts, :critical, 0)
      },
      by_category: category_counts
    }
  end

  @doc """
  Gets a single violation.

  Raises if the Violation does not exist.
  """
  def get_violation!(id) do
    case Violation.by_id(id) do
      {:ok, violation} -> violation
      {:error, %Ash.Error.Query.NotFound{}} -> raise Ecto.NoResultsError, queryable: Violation
      {:error, error} -> raise error
    end
  end

  @doc """
  Creates a violation.
  """
  def create_violation(attrs \\ %{}) do
    Violation.create(attrs)
  end

  @doc """
  Updates violation status.
  """
  def update_violation_status(%Violation{} = violation, status, attrs \\ %{}) do
    Violation.update_status(violation, %{status: status}, %{
      resolved_by: attrs[:resolved_by],
      metadata: attrs[:metadata]
    })
  end

  @doc """
  Resolves a violation.
  """
  def resolve_violation(%Violation{} = violation, resolved_by, resolution_note \\ nil) do
    Violation.resolve(violation, %{}, %{
      resolved_by: resolved_by,
      resolution_note: resolution_note
    })
  end

  @doc """
  Acknowledges a violation.
  """
  def acknowledge_violation(%Violation{} = violation, acknowledged_by, note \\ nil) do
    Violation.acknowledge(violation, %{}, %{acknowledged_by: acknowledged_by, note: note})
  end

  @doc """
  Suppresses a violation.
  """
  def suppress_violation(%Violation{} = violation, suppressed_by, reason) do
    Violation.suppress(violation, %{}, %{suppressed_by: suppressed_by, reason: reason})
  end

  @doc """
  Marks a violation as false positive.
  """
  def mark_false_positive(%Violation{} = violation, marked_by, reason) do
    Violation.mark_false_positive(violation, %{}, %{marked_by: marked_by, reason: reason})
  end

  # === LEGACY COMPATIBILITY ===

  @doc """
  Lists analysis rules (legacy compatibility - returns empty list).
  """
  def list_analysis_rules(_opts \\ []) do
    # This was referencing a non-existent AnalysisRule module
    # Return empty list for backward compatibility
    []
  end

  @doc """
  Gets project rules (legacy compatibility - returns empty list).
  """
  def get_project_rules(_project_id) do
    # This was referencing non-existent ProjectRuleConfig module
    # Return empty list for backward compatibility
    []
  end

  @doc """
  Processes an analysis session with files.
  """
  def process_analysis_session(%AnalysisSession{} = session, files) when is_list(files) do
    # Update session status to processing
    with {:ok, session} <- update_analysis_session_status(session, :processing),
         {:ok, created_files} <- create_analyzed_files_for_session(session.id, files) do
      # Queue analysis jobs for each file
      Enum.each(created_files, &queue_file_analysis/1)

      {:ok, %{session: session, files: created_files}}
    end
  end

  @doc """
  Gets user analysis statistics.
  """
  def get_user_analysis_stats(user_id) do
    # Get user projects
    projects = list_projects(user_id)
    project_ids = Enum.map(projects, & &1.id)

    # Get all sessions for these projects
    all_sessions =
      AnalysisSession
      |> Ash.Query.filter(project_id in ^project_ids)
      |> Ash.read!()

    session_ids = Enum.map(all_sessions, & &1.id)

    # Get all files for these sessions
    all_files =
      AnalyzedFile
      |> Ash.Query.filter(analysis_session_id in ^session_ids)
      |> Ash.read!()

    file_ids = Enum.map(all_files, & &1.id)

    # Get all violations for these files
    all_violations =
      Violation
      |> Ash.Query.filter(analyzed_file_id in ^file_ids)
      |> Ash.read!()

    # Calculate statistics
    %{
      total_projects: length(projects),
      total_sessions: length(all_sessions),
      total_files_analyzed: length(all_files),
      total_violations: length(all_violations),
      sessions_by_status:
        Enum.group_by(all_sessions, & &1.status) |> Map.new(fn {k, v} -> {k, length(v)} end),
      violations_by_severity:
        Enum.group_by(all_violations, & &1.severity) |> Map.new(fn {k, v} -> {k, length(v)} end),
      recent_activity: get_recent_activity(user_id, 10)
    }
  end

  # === PRIVATE HELPER FUNCTIONS ===

  defp maybe_filter_by_status(query, nil), do: query

  defp maybe_filter_by_status(query, status) do
    Ash.Query.filter(query, status == ^status)
  end

  defp maybe_filter_session_by_status(query, nil), do: query

  defp maybe_filter_session_by_status(query, status) do
    Ash.Query.filter(query, status == ^status)
  end

  defp maybe_filter_file_by_status(query, nil), do: query

  defp maybe_filter_file_by_status(query, status) do
    Ash.Query.filter(query, status == ^status)
  end

  defp maybe_filter_file_by_language(query, nil), do: query

  defp maybe_filter_file_by_language(query, language) do
    Ash.Query.filter(query, language_detected == ^language)
  end

  defp maybe_filter_violation_by_status(query, nil), do: query

  defp maybe_filter_violation_by_status(query, status) do
    Ash.Query.filter(query, status == ^status)
  end

  defp maybe_filter_violation_by_severity(query, nil), do: query

  defp maybe_filter_violation_by_severity(query, severity) do
    Ash.Query.filter(query, severity == ^severity)
  end

  defp maybe_filter_violation_by_category(query, nil), do: query

  defp maybe_filter_violation_by_category(query, category) do
    Ash.Query.filter(query, rule_category == ^category)
  end

  defp create_analyzed_files_for_session(session_id, files) do
    created_files =
      files
      |> Enum.map(fn file_attrs ->
        file_attrs = Map.put(file_attrs, :analysis_session_id, session_id)

        case create_analyzed_file(file_attrs) do
          {:ok, file} -> file
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, created_files}
  end

  defp queue_file_analysis(%AnalyzedFile{} = file) do
    # Queue background analysis job (using Oban)
    %{
      analyzed_file_id: file.id,
      analysis_session_id: file.analysis_session_id,
      content: file.content,
      language: file.language_detected
    }
    |> Lang.Workers.SemanticAnalysisWorker.new()
    |> Oban.insert()

    {:ok, :queued}
  end

  defp get_recent_activity(user_id, limit) do
    # Get recent sessions for user projects
    projects = list_projects(user_id, limit: 10)
    project_ids = Enum.map(projects, & &1.id)

    AnalysisSession
    |> Ash.Query.filter(project_id in ^project_ids)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load([:project])
    |> Ash.read!()
  end
end
