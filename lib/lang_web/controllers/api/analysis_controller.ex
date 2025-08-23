defmodule LangWeb.Api.AnalysisController do
  use LangWeb, :controller
  alias LangWeb.ApiError

  alias Lang.Analysis
  alias Lang.Analysis.{Project, AnalysisSession, AnalyzedFile, Violation}

  action_fallback LangWeb.Api.FallbackController

  # Projects

  def list_projects(conn, params) do
    user_id = conn.assigns.current_user.id

    opts = [
      status: params["status"],
      order_by: String.to_existing_atom(params["order_by"] || "inserted_at"),
      order_dir: String.to_existing_atom(params["order_dir"] || "desc")
    ]

    projects = Analysis.list_projects(user_id, opts)
    render(conn, "projects.json", projects: projects)
  end

  def show_project(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    case Analysis.get_user_project(user_id, id) do
      nil ->
        ApiError.json(conn, :not_found, "Project not found")

      project ->
        render(conn, "project.json", project: project)
    end
  end

  def create_project(conn, %{"project" => project_params}) do
    user_id = conn.assigns.current_user.id

    project_attrs =
      project_params
      |> Map.put("user_id", user_id)
      |> Map.put(
        "settings",
        Map.merge(Project.default_settings(), project_params["settings"] || %{})
      )

    case Analysis.create_project(project_attrs) do
      {:ok, project} ->
        conn
        |> put_status(:created)
        |> render("project.json", project: project)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("errors.json", changeset: changeset)
    end
  end

  def update_project(conn, %{"id" => id, "project" => project_params}) do
    user_id = conn.assigns.current_user.id

    case Analysis.get_user_project(user_id, id) do
      nil ->
        ApiError.json(conn, :not_found, "Project not found")

      project ->
        case Analysis.update_project(project, project_params) do
          {:ok, project} ->
            render(conn, "project.json", project: project)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render("errors.json", changeset: changeset)
        end
    end
  end

  def delete_project(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    case Analysis.get_user_project(user_id, id) do
      nil ->
        ApiError.json(conn, :not_found, "Project not found")

      project ->
        case Analysis.delete_project(project) do
          {:ok, _project} ->
            send_resp(conn, :no_content, "")

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render("errors.json", changeset: changeset)
        end
    end
  end

  def archive_project(conn, %{"id" => id}) do
    user_id = conn.assigns.current_user.id

    case Analysis.get_user_project(user_id, id) do
      nil ->
        ApiError.json(conn, :not_found, "Project not found")

      project ->
        case Analysis.archive_project(project) do
          {:ok, project} ->
            render(conn, "project.json", project: project)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render("errors.json", changeset: changeset)
        end
    end
  end

  # Analysis Sessions

  def list_sessions(conn, %{"project_id" => project_id} = params) do
    user_id = conn.assigns.current_user.id

    case Analysis.get_user_project(user_id, project_id) do
      nil ->
        ApiError.json(conn, :not_found, "Project not found")

      _project ->
        opts = [
          limit: min(String.to_integer(params["limit"] || "50"), 100),
          offset: String.to_integer(params["offset"] || "0"),
          status: params["status"]
        ]

        sessions = Analysis.list_analysis_sessions(project_id, opts)
        render(conn, "sessions.json", sessions: sessions)
    end
  end

  def show_session(conn, %{"id" => id}) do
    # TODO: Add user authorization check
    try do
      case Analysis.get_analysis_session!(id) do
        session ->
          render(conn, "session.json", session: session)
      end
    rescue
      Ecto.NoResultsError ->
        ApiError.json(conn, :not_found, "Analysis session not found")
    end
  end

  def create_session(conn, %{"project_id" => project_id} = params) do
    user_id = conn.assigns.current_user.id

    case Analysis.get_user_project(user_id, project_id) do
      nil ->
        ApiError.json(conn, :not_found, "Project not found")

      project ->
        unless Project.active?(project) do
          ApiError.json(conn, :unprocessable_entity, "Project is not active")
        else
          session_attrs = %{
            project_id: project_id,
            metadata: params["metadata"] || %{}
          }

          case Analysis.create_analysis_session(session_attrs) do
            {:ok, session} ->
              conn
              |> put_status(:created)
              |> render("session.json", session: session)

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> render("errors.json", changeset: changeset)
          end
        end
    end
  end

  def cancel_session(conn, %{"id" => id}) do
    # TODO: Add user authorization check
    case Analysis.get_analysis_session!(id) do
      session ->
        unless AnalysisSession.in_progress?(session) do
          ApiError.json(conn, :unprocessable_entity, "Cannot cancel session that is not in progress")
        else
          case Analysis.cancel_analysis_session(session) do
            {:ok, session} ->
              render(conn, "session.json", session: session)

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> render("errors.json", changeset: changeset)
          end
        end
    end
  rescue
    Ecto.NoResultsError ->
      ApiError.json(conn, :not_found, "Analysis session not found")
  end

  # File Upload and Analysis

  def upload_files(conn, %{"session_id" => session_id} = params) do
    # TODO: Add user authorization check
    try do
      case Analysis.get_analysis_session!(session_id) do
        session ->
          unless session.status == "pending" do
            ApiError.json(conn, :unprocessable_entity, "Session is not in pending state")
          else
            case extract_files_from_upload(params) do
              {:ok, files} ->
                case Analysis.process_analysis_session(session, files) do
                  {:ok, updated_session} ->
                    render(conn, "session.json", session: updated_session)

                  {:error, changeset} ->
                    conn
                    |> put_status(:unprocessable_entity)
                    |> render("errors.json", changeset: changeset)
                end

              {:error, reason} ->
                ApiError.json(conn, :bad_request, to_string(reason))
            end
          end
      end
    rescue
      Ecto.NoResultsError ->
        ApiError.json(conn, :not_found, "Analysis session not found")
    end
  end

  def analyze_text(conn, %{"session_id" => session_id} = params) do
    # For direct text analysis without file upload
    try do
      case Analysis.get_analysis_session!(session_id) do
        session ->
          unless session.status == "pending" do
            ApiError.json(conn, :unprocessable_entity, "Session is not in pending state")
          else
            text_content = params["content"]
            file_name = params["file_name"] || "untitled.txt"
            language = params["language"]

            unless text_content do
              ApiError.json(conn, :bad_request, "Content is required")
            else
              file_attrs = %{
                file_name: file_name,
                file_path: file_name,
                content: text_content,
                file_size_bytes: byte_size(text_content),
                language_detected: language,
                analysis_session_id: session_id
              }

              case Analysis.create_analyzed_file(file_attrs) do
                {:ok, file} ->
                  # Update file status to processing
                  {:ok, updated_file} = Analysis.update_analyzed_file_status(file, "processing")
                  render(conn, "file.json", file: updated_file)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> render("errors.json", changeset: changeset)
              end
            end
          end
      end
    rescue
      Ecto.NoResultsError ->
        ApiError.json(conn, :not_found, "Analysis session not found")
    end
  end

  # Results

  def list_files(conn, %{"session_id" => session_id} = params) do
    opts = [
      limit: min(String.to_integer(params["limit"] || "100"), 500),
      offset: String.to_integer(params["offset"] || "0"),
      status: params["status"],
      language: params["language"]
    ]

    files = Analysis.list_analyzed_files(session_id, opts)
    render(conn, "files.json", files: files)
  end

  def show_file(conn, %{"id" => id}) do
    try do
      case Analysis.get_analyzed_file!(id) do
        file ->
          render(conn, "file.json", file: file)
      end
    rescue
      Ecto.NoResultsError ->
        ApiError.json(conn, :not_found, "File not found")
    end
  end

  def list_violations(conn, %{"session_id" => session_id} = params) do
    opts = [
      limit: min(String.to_integer(params["limit"] || "100"), 500),
      offset: String.to_integer(params["offset"] || "0"),
      severity: params["severity"],
      status: params["status"],
      category: params["category"]
    ]

    violations = Analysis.list_violations(session_id, opts)
    stats = Analysis.get_violation_stats(session_id)

    render(conn, "violations.json", violations: violations, stats: stats)
  end

  def show_violation(conn, %{"id" => id}) do
    try do
      case Analysis.get_violation!(id) do
        violation ->
          render(conn, "violation.json", violation: violation)
      end
    rescue
      Ecto.NoResultsError ->
        ApiError.json(conn, :not_found, "Violation not found")
    end
  end

  def update_violation(conn, %{"id" => id} = params) do
    try do
      case Analysis.get_violation!(id) do
        violation ->
          action = params["action"]
          user_id = conn.assigns.current_user.id

          result =
            case action do
              "resolve" ->
                Analysis.resolve_violation(violation, user_id, params["note"])

              "acknowledge" ->
                Analysis.acknowledge_violation(violation, user_id, params["note"])

              "suppress" ->
                case params["reason"] do
                  nil ->
                    {:error, "Reason is required for suppression"}

                  reason ->
                    Analysis.suppress_violation(violation, user_id, reason)
                end

              "false_positive" ->
                case params["reason"] do
                  nil ->
                    {:error, "Reason is required for false positive marking"}

                  reason ->
                    Analysis.mark_false_positive(violation, user_id, reason)
                end

              _ ->
                {:error,
                 "Invalid action. Must be one of: resolve, acknowledge, suppress, false_positive"}
            end

          case result do
            {:ok, updated_violation} ->
              render(conn, "violation.json", violation: updated_violation)

            {:error, %Ecto.Changeset{} = changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> render("errors.json", changeset: changeset)

            {:error, message} ->
              ApiError.json(conn, :bad_request, to_string(message))
          end
      end
    rescue
      Ecto.NoResultsError ->
        ApiError.json(conn, :not_found, "Violation not found")
    end
  end

  # Statistics

  def user_stats(conn, _params) do
    user_id = conn.assigns.current_user.id
    stats = Analysis.get_user_analysis_stats(user_id)
    render(conn, "user_stats.json", stats: stats)
  end

  def session_stats(conn, %{"session_id" => session_id}) do
    try do
      case Analysis.get_analysis_session!(session_id) do
        session ->
          stats = Analysis.get_violation_stats(session_id)
          render(conn, "session_stats.json", session: session, stats: stats)
      end
    rescue
      Ecto.NoResultsError ->
        ApiError.json(conn, :not_found, "Analysis session not found")
    end
  end

  # Private functions

  defp extract_files_from_upload(params) do
    case params["files"] do
      nil ->
        {:error, "No files provided"}

      files when is_list(files) ->
        extracted_files =
          files
          |> Enum.map(&extract_file_data/1)
          |> Enum.filter(&(&1 != nil))

        if length(extracted_files) == 0 do
          {:error, "No valid files found"}
        else
          {:ok, extracted_files}
        end

      _ ->
        {:error, "Invalid file format"}
    end
  end

  defp extract_file_data(%{"content" => content, "name" => name} = file_data)
       when is_binary(content) and is_binary(name) do
    %{
      file_name: name,
      file_path: file_data["path"] || name,
      content: content,
      file_size_bytes: byte_size(content),
      content_type: file_data["content_type"] || "text/plain"
    }
  end

  defp extract_file_data(_), do: nil
end
