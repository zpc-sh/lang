defmodule LangWeb.Api.AnalysisView do
  use LangWeb, :view

  alias Lang.Analysis.{Project, AnalysisSession, AnalyzedFile, Violation}

  # Phoenix View helpers for render_many and render_one
  def render_many(collection, view, template, assigns \\ %{}) do
    Enum.map(collection, fn item ->
      render_one(item, view, template, assigns)
    end)
  end

  def render_one(nil, _view, _template, _assigns), do: nil

  def render_one(item, view, template, assigns) do
    assigns = Map.put(assigns, assigns[:as] || :item, item)
    view.render(template, assigns)
  end

  # Projects

  def render("projects.json", %{projects: projects}) do
    %{
      data: %{
        projects: render_many(projects, __MODULE__, "project_summary.json", as: :project)
      }
    }
  end

  def render("project.json", %{translate_errorproject: project}) do
    %{
      data: %{
        project: render_one(project, __MODULE__, "project_detail.json", as: :project)
      }
    }
  end

  def render("project_summary.json", %{project: project}) do
    latest_session =
      project.analysis_sessions
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
      |> List.first()

    %{
      id: project.id,
      name: project.name,
      description: project.description,
      language: project.language,
      framework: project.framework,
      project_type: project.project_type,
      status: project.status,
      repository_url: project.repository_url,
      created_at: project.inserted_at,
      updated_at: project.updated_at,
      latest_session: render_latest_session(latest_session),
      session_count: length(project.analysis_sessions)
    }
  end

  def render("project_detail.json", %{project: project}) do
    %{
      id: project.id,
      name: project.name,
      description: project.description,
      language: project.language,
      framework: project.framework,
      project_type: project.project_type,
      status: project.status,
      repository_url: project.repository_url,
      settings: project.settings,
      created_at: project.inserted_at,
      updated_at: project.updated_at,
      analysis_sessions:
        render_many(project.analysis_sessions, __MODULE__, "session_summary.json", as: :session)
    }
  end

  # Analysis Sessions

  def render("sessions.json", %{sessions: sessions}) do
    %{
      data: %{
        sessions: render_many(sessions, __MODULE__, "session_summary.json", as: :session)
      }
    }
  end

  def render("session.json", %{session: session}) do
    %{
      data: %{
        session: render_one(session, __MODULE__, "session_detail.json", as: :session)
      }
    }
  end

  def render("session_summary.json", %{session: session}) do
    %{
      id: session.id,
      status: session.status,
      started_at: session.started_at,
      completed_at: session.completed_at,
      file_count: session.file_count,
      violations_count: session.violations_count,
      critical_issues_count: session.critical_issues_count,
      warnings_count: session.warnings_count,
      processing_time_ms: session.processing_time_ms,
      duration_ms: AnalysisSession.duration(session),
      status_description: AnalysisSession.status_description(session)
    }
  end

  def render("session_detail.json", %{session: session}) do
    %{
      id: session.id,
      status: session.status,
      started_at: session.started_at,
      completed_at: session.completed_at,
      file_count: session.file_count,
      total_size_bytes: session.total_size_bytes,
      violations_count: session.violations_count,
      critical_issues_count: session.critical_issues_count,
      warnings_count: session.warnings_count,
      processing_time_ms: session.processing_time_ms,
      metadata: session.metadata,
      error_message: session.error_message,
      duration_ms: AnalysisSession.duration(session),
      status_description: AnalysisSession.status_description(session),
      summary: AnalysisSession.summary(session),
      analyzed_files:
        render_many(session.analyzed_files, __MODULE__, "file_summary.json", as: :file),
      insights:
        render_many(session.analysis_insights || [], __MODULE__, "insight.json", as: :insight)
    }
  end

  # Analyzed Files

  def render("files.json", %{files: files}) do
    %{
      data: %{
        files: render_many(files, __MODULE__, "file_summary.json", as: :file)
      }
    }
  end

  def render("file.json", %{file: file}) do
    %{
      data: %{
        file: render_one(file, __MODULE__, "file_detail.json", as: :file)
      }
    }
  end

  def render("file_summary.json", %{file: file}) do
    %{
      id: file.id,
      file_name: file.file_name,
      file_path: file.file_path,
      file_extension: file.file_extension,
      file_size_bytes: file.file_size_bytes,
      file_size_human: AnalyzedFile.human_file_size(file),
      language_detected: file.language_detected,
      status: file.status,
      processed_at: file.processed_at,
      processing_time_ms: file.processing_time_ms,
      violation_count: length(file.violations || []),
      analysis_summary: AnalyzedFile.analysis_summary(file)
    }
  end

  def render("file_detail.json", %{file: file}) do
    %{
      id: file.id,
      file_name: file.file_name,
      file_path: file.file_path,
      file_extension: file.file_extension,
      file_size_bytes: file.file_size_bytes,
      file_size_human: AnalyzedFile.human_file_size(file),
      content_type: file.content_type,
      language_detected: file.language_detected,
      content_hash: file.content_hash,
      status: file.status,
      processed_at: file.processed_at,
      processing_time_ms: file.processing_time_ms,
      analysis_result: file.analysis_result,
      analysis_summary: AnalyzedFile.analysis_summary(file),
      violations:
        render_many(file.violations || [], __MODULE__, "violation_summary.json", as: :violation)
    }
  end

  # Violations

  def render("violations.json", %{violations: violations, stats: stats}) do
    %{
      data: %{
        violations: render_many(violations, __MODULE__, "violation_summary.json", as: :violation),
        statistics: %{
          total: stats.total,
          by_severity: stats.by_severity,
          by_status: stats.by_status,
          by_category: stats.by_category
        }
      }
    }
  end

  def render("violation.json", %{violation: violation}) do
    %{
      data: %{
        violation: render_one(violation, __MODULE__, "violation_detail.json", as: :violation)
      }
    }
  end

  def render("violation_summary.json", %{violation: violation}) do
    %{
      id: violation.id,
      rule_id: violation.rule_id,
      rule_name: violation.rule_name,
      rule_category: violation.rule_category,
      severity: violation.severity,
      severity_level: Violation.severity_level(violation),
      severity_color: Violation.severity_color(violation),
      status: violation.status,
      status_color: Violation.status_color(violation),
      message: violation.message,
      line_number: violation.line_number,
      column_number: violation.column_number,
      location: Violation.display_location(violation),
      confidence_score: violation.confidence_score,
      compliance_tags: violation.compliance_tags,
      resolved_at: violation.resolved_at,
      resolved_by: violation.resolved_by,
      actionable: Violation.actionable?(violation),
      file_name: violation.analyzed_file && violation.analyzed_file.file_name,
      file_path: violation.analyzed_file && violation.analyzed_file.file_path
    }
  end

  def render("violation_detail.json", %{violation: violation}) do
    %{
      id: violation.id,
      rule_id: violation.rule_id,
      rule_name: violation.rule_name,
      rule_category: violation.rule_category,
      severity: violation.severity,
      severity_level: Violation.severity_level(violation),
      severity_color: Violation.severity_color(violation),
      status: violation.status,
      status_color: Violation.status_color(violation),
      message: violation.message,
      description: violation.description,
      fix_suggestion: violation.fix_suggestion,
      line_number: violation.line_number,
      column_number: violation.column_number,
      line_content: violation.line_content,
      location: Violation.display_location(violation),
      impact_assessment: violation.impact_assessment,
      compliance_tags: violation.compliance_tags,
      confidence_score: violation.confidence_score,
      metadata: violation.metadata,
      resolved_at: violation.resolved_at,
      resolved_by: violation.resolved_by,
      estimated_fix_time: Violation.estimated_fix_time(violation),
      risk_score: Violation.risk_score(violation),
      actionable: Violation.actionable?(violation),
      created_at: violation.inserted_at,
      updated_at: violation.updated_at,
      analyzed_file:
        violation.analyzed_file &&
          render_one(violation.analyzed_file, __MODULE__, "file_summary.json", as: :file)
    }
  end

  # Insights

  def render("insight.json", %{insight: insight}) do
    %{
      id: insight.id,
      insight_type: insight.insight_type,
      title: insight.title,
      description: insight.description,
      suggestion: insight.suggestion,
      confidence_score: insight.confidence_score,
      impact_level: insight.impact_level,
      category: insight.category,
      files_affected: insight.files_affected,
      metadata: insight.metadata
    }
  end

  # Statistics

  def render("user_stats.json", %{stats: stats}) do
    %{
      data: %{
        statistics: %{
          projects: %{
            total: stats.total_projects
          },
          sessions: %{
            total: stats.total_sessions,
            recent: stats.recent_sessions
          },
          files: %{
            total: stats.total_files
          },
          violations: %{
            total: stats.total_violations,
            critical: stats.critical_violations,
            high: stats.high_violations
          }
        }
      }
    }
  end

  def render("session_stats.json", %{session: session, stats: stats}) do
    %{
      data: %{
        session: render_one(session, __MODULE__, "session_summary.json", as: :session),
        statistics: %{
          violations: %{
            total: stats.total,
            by_severity: stats.by_severity,
            by_status: stats.by_status,
            by_category: stats.by_category
          }
        }
      }
    }
  end

  # Error handling

  def render("errors.json", %{changeset: changeset}) do
    %{
      errors: Ecto.Changeset.traverse_errors(changeset, &translate_changeset_error/1)
    }
  end

  def render("error.json", %{message: message}) do
    %{error: message}
  end

  # Private helper functions

  defp render_latest_session(nil), do: nil

  defp render_latest_session(session) do
    %{
      id: session.id,
      status: session.status,
      started_at: session.started_at,
      completed_at: session.completed_at,
      file_count: session.file_count,
      violations_count: session.violations_count
    }
  end

  defp translate_changeset_error({msg, opts}) do
    Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
