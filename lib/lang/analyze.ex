defmodule Lang.Analyze do
  @moduledoc """
  Public API for starting and managing analyses (verb-focused facade).

  Delegates to Ash resources under `Lang.Analysis.*` (soon `Lang.Analyses.*`).
  """
  # Project operations (legacy/optional)
  defdelegate list_projects(user_id, opts \\ []), to: Lang.Analysis
  defdelegate get_project!(id), to: Lang.Analysis
  defdelegate get_user_project(user_id, project_id), to: Lang.Analysis
  defdelegate create_project(attrs \\ %{}), to: Lang.Analysis
  defdelegate update_project(project, attrs), to: Lang.Analysis
  defdelegate archive_project(project), to: Lang.Analysis
  defdelegate activate_project(project), to: Lang.Analysis
  defdelegate delete_project(project), to: Lang.Analysis
  defdelegate change_project(project, attrs \\ %{}), to: Lang.Analysis

  # Run/session operations
  def start(attrs \\ %{}), do: Lang.Analysis.create_analysis_session(attrs)
  def get_run!(id), do: Lang.Analysis.get_analysis_session!(id)

  def list_runs(project_id, opts \\ []),
    do: Lang.Analysis.list_analysis_sessions(project_id, opts)

  def latest_run(project_id), do: Lang.Analysis.get_latest_analysis_session(project_id)

  def update_run_status(session, status, attrs \\ %{}),
    do: Lang.Analysis.update_analysis_session_status(session, status, attrs)

  def update_run_stats(session, stats),
    do: Lang.Analysis.update_analysis_session_stats(session, stats)

  def complete_run(session, stats \\ %{}),
    do: Lang.Analysis.complete_analysis_session(session, stats)

  def fail_run(session, error_message, metadata \\ %{}),
    do: Lang.Analysis.fail_analysis_session(session, error_message, metadata)

  # Files
  def ingest_file(attrs \\ %{}), do: Lang.Analysis.create_analyzed_file(attrs)

  def update_file_status(file, status, attrs \\ %{}),
    do: Lang.Analysis.update_analyzed_file_status(file, status, attrs)

  def complete_file(file, result, ms), do: Lang.Analysis.complete_analyzed_file(file, result, ms)
  def fail_file(file, error_msg), do: Lang.Analysis.fail_analyzed_file(file, error_msg)
  def skip_file(file, reason), do: Lang.Analysis.skip_analyzed_file(file, reason)
  def update_file(file, attrs), do: Lang.Analysis.update_analyzed_file(file, attrs)

  # Violations
  def list_violations(session_id, opts \\ []), do: Lang.Analysis.list_violations(session_id, opts)
  def violation_stats(session_id), do: Lang.Analysis.get_violation_stats(session_id)
  def get_violation!(id), do: Lang.Analysis.get_violation!(id)
  def create_violation(attrs \\ %{}), do: Lang.Analysis.create_violation(attrs)

  def update_violation_status(violation, status, attrs \\ %{}),
    do: Lang.Analysis.update_violation_status(violation, status, attrs)

  def resolve_violation(violation, resolved_by, note \\ nil),
    do: Lang.Analysis.resolve_violation(violation, resolved_by, note)

  def acknowledge_violation(violation, who, note \\ nil),
    do: Lang.Analysis.acknowledge_violation(violation, who, note)

  def suppress_violation(violation, who, reason),
    do: Lang.Analysis.suppress_violation(violation, who, reason)

  def mark_false_positive(violation, who, reason),
    do: Lang.Analysis.mark_false_positive(violation, who, reason)

  # Ephemeral / batch helpers
  def analyze_ephemeral(files), do: Lang.Analysis.analyze_ephemeral(files)

  def ingest_file_content(session_id, attrs),
    do: Lang.Analysis.ingest_file_content(session_id, attrs)

  def create_scan_result(attrs \\ %{}), do: Lang.Analysis.create_scan_result(attrs)
end
