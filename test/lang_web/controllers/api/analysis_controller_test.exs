defmodule LangWeb.Api.AnalysisControllerTest do
  use LangWeb.ConnCase, async: true

  alias Lang.Analysis
  alias Lang.Analyses.{Project, Run, File, Violation}

  setup do
    user1 = create_user!(%{email: "user1@example.com"})
    user2 = create_user!(%{email: "user2@example.com"})

    {:ok, project1} = Analysis.create_project(%{
      "name" => "Project 1",
      "user_id" => user1.id
    })

    {:ok, project2} = Analysis.create_project(%{
      "name" => "Project 2",
      "user_id" => user2.id
    })

    {:ok, session1} = Analysis.create_analysis_session(%{
      "project_id" => project1.id,
      "metadata" => %{}
    })

    {:ok, session2} = Analysis.create_analysis_session(%{
      "project_id" => project2.id,
      "metadata" => %{}
    })

    {:ok, file1} = Analysis.create_analyzed_file(%{
      "file_path" => "file1.txt",
      "file_name" => "file1.txt",
      "analysis_session_id" => session1.id
    })

    {:ok, file2} = Analysis.create_analyzed_file(%{
      "file_path" => "file2.txt",
      "file_name" => "file2.txt",
      "analysis_session_id" => session2.id
    })

    {:ok, violation1} = Analysis.create_violation(%{
      "rule_id" => "R1",
      "rule_name" => "Rule 1",
      "severity" => :info,
      "message" => "Message 1",
      "analyzed_file_id" => file1.id
    })

    {:ok, violation2} = Analysis.create_violation(%{
      "rule_id" => "R2",
      "rule_name" => "Rule 2",
      "severity" => :info,
      "message" => "Message 2",
      "analyzed_file_id" => file2.id
    })

    %{
      user1: user1,
      user2: user2,
      project1: project1,
      project2: project2,
      session1: session1,
      session2: session2,
      file1: file1,
      file2: file2,
      violation1: violation1,
      violation2: violation2
    }
  end

  describe "show_session" do
    test "allows user to see their own session", %{conn: conn, user1: user, session1: session} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/sessions/#{session.id}")

      assert json_response(conn, 200)["id"] == session.id
    end

    test "denies user access to another user's session", %{conn: conn, user1: user, session2: session} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/sessions/#{session.id}")

      assert json_response(conn, 404)
    end
  end

  describe "cancel_session" do
    test "allows user to cancel their own session", %{conn: conn, user1: user, session1: session} do
      conn = conn
      |> assign(:current_user, user)
      |> post(~p"/api/v1/sessions/#{session.id}/cancel")

      assert json_response(conn, 200)["status"] == "failed"
    end

    test "denies user canceling another user's session", %{conn: conn, user1: user, session2: session} do
      conn = conn
      |> assign(:current_user, user)
      |> post(~p"/api/v1/sessions/#{session.id}/cancel")

      assert json_response(conn, 404)
    end
  end

  describe "show_file" do
    test "allows user to see their own file", %{conn: conn, user1: user, file1: file} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/files/#{file.id}")

      assert json_response(conn, 200)["id"] == file.id
    end

    test "denies user access to another user's file", %{conn: conn, user1: user, file2: file} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/files/#{file.id}")

      assert json_response(conn, 404)
    end
  end

  describe "show_violation" do
    test "allows user to see their own violation", %{conn: conn, user1: user, violation1: violation} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/violations/#{violation.id}")

      assert json_response(conn, 200)["id"] == violation.id
    end

    test "denies user access to another user's violation", %{conn: conn, user1: user, violation2: violation} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/violations/#{violation.id}")

      assert json_response(conn, 404)
    end
  end

  describe "update_violation" do
    test "allows user to update their own violation", %{conn: conn, user1: user, violation1: violation} do
      conn = conn
      |> assign(:current_user, user)
      |> put(~p"/api/v1/violations/#{violation.id}", %{"action" => "acknowledge", "note" => "test"})

      assert json_response(conn, 200)["status"] == "acknowledged"
    end

    test "denies user updating another user's violation", %{conn: conn, user1: user, violation2: violation} do
      conn = conn
      |> assign(:current_user, user)
      |> put(~p"/api/v1/violations/#{violation.id}", %{"action" => "acknowledge", "note" => "test"})

      assert json_response(conn, 404)
    end
  end

  describe "session_stats" do
    test "allows user to see their own session stats", %{conn: conn, user1: user, session1: session} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/stats/sessions/#{session.id}")

      assert json_response(conn, 200)["session"]["id"] == session.id
    end

    test "denies user access to another user's session stats", %{conn: conn, user1: user, session2: session} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/stats/sessions/#{session.id}")

      assert json_response(conn, 404)
    end
  end

  describe "Edge Case: Orphaned Resources" do
    test "denies access to session with no associated user", %{conn: conn, user1: user} do
      # Create a project with no user (if possible in schema)
      # Or just simulate by using a generated UUID that doesn't exist
      non_existent_id = Ecto.UUID.generate()

      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/sessions/#{non_existent_id}")

      assert json_response(conn, 404)
    end
  end

  describe "API Identity / AI Agent use cases" do
    test "verifies user1 cannot access project1 if current_user is user2", %{conn: conn, user2: user, project1: project} do
      conn = conn
      |> assign(:current_user, user)
      |> get(~p"/api/v1/projects/#{project.id}")

      assert json_response(conn, 404)
    end
  end
end
