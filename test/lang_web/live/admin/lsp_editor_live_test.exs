defmodule LangWeb.Admin.LspEditorLiveTest do
  use LangWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "LSP Editor LiveView" do
    setup do
      # Create test user and organization
      user = insert(:user, admin: true)
      organization = insert(:organization, owner: user)

      # Ensure LSP doc exists
      File.mkdir_p!("docs")

      File.write!("docs/lsp.md", """
      # LSP Master Tracker

      ## Core LSP Methods

      ### General

      | Method | Status | Priority | Description | File Path |
      |--------|--------|----------|-------------|-----------|
      | initialize | ✅ | Critical | Initialize the language server | lib/lang/lsp/server.ex |
      | shutdown | ✅ | Critical | Shutdown the language server | lib/lang/lsp/server.ex |
      | textDocument/completion | 🔄 | Critical | Code completion | lib/lang/lsp/text_document/completion.ex |
      """)

      %{user: user, organization: organization}
    end

    test "renders LSP editor with authentication", %{
      conn: conn,
      user: user,
      organization: organization
    } do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, _view, html} = live(conn, ~p"/admin/lsp-editor")

      assert html =~ "LSP Master Tracker"
      assert html =~ "First of Its Kind"
      assert html =~ "Table View"
      assert html =~ "Edit Mode"
      assert html =~ "Raw Edit"
    end

    test "requires admin authentication", %{conn: conn} do
      # Non-admin user should be redirected
      regular_user = insert(:user, admin: false)
      conn = log_in_user(conn, regular_user)

      assert_raise Phoenix.Router.NoRouteError, fn ->
        live(conn, ~p"/admin/lsp-editor")
      end
    end

    test "redirects unauthenticated users", %{conn: conn} do
      # Unauthenticated users should be redirected to login
      assert {:error, {:redirect, %{to: "/auth/sign_in"}}} = live(conn, ~p"/admin/lsp-editor")
    end

    test "loads and parses LSP methods from markdown", %{
      conn: conn,
      user: user,
      organization: organization
    } do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Check that methods are loaded
      assert has_element?(view, "[data-method='initialize']")
      assert has_element?(view, "[data-method='shutdown']")
      assert has_element?(view, "[data-method='textDocument/completion']")
    end

    test "switches between edit modes", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Switch to Edit mode
      view |> element("button[phx-value-mode='edit']") |> render_click()
      assert has_element?(view, "#contenteditable-markdown")

      # Switch to Raw mode
      view |> element("button[phx-value-mode='raw']") |> render_click()
      assert has_element?(view, "#raw-markdown-editor")

      # Switch back to Table view
      view |> element("button[phx-value-mode='view']") |> render_click()
      assert has_element?(view, "#lsp-master-table")
    end

    test "filters methods by category", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Filter by category (if categories exist in test data)
      view |> form("#filter-form", %{"category" => "general"}) |> render_change()

      # Should update URL params
      assert_patch(view, ~p"/admin/lsp-editor?category=general")
    end

    test "searches methods", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Search for "completion"
      view
      |> form("form[phx-change='search']", %{"search" => %{"query" => "completion"}})
      |> render_change()

      # Should show completion-related methods
      assert has_element?(view, "[data-method='textDocument/completion']")
    end

    test "updates method status", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Update initialize method status
      view
      |> form("select[phx-value-method='initialize']", %{"status" => "implemented"})
      |> render_change()

      # Should show success message
      assert render(view) =~ "Updated initialize status"
    end

    test "opens TipTap editor modal", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Click edit button for initialize method
      view
      |> element(
        "button[phx-click='open_in_tiptap'][phx-value-file_path='lib/lang/lsp/server.ex']"
      )
      |> render_click()

      # Should open TipTap modal
      assert has_element?(view, "#tiptap-editor")
      assert render(view) =~ "TipTap/Elim Editor"
      assert render(view) =~ "lib/lang/lsp/server.ex"
    end

    test "closes TipTap editor modal", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Open modal first
      view
      |> element(
        "button[phx-click='open_in_tiptap'][phx-value-file_path='lib/lang/lsp/server.ex']"
      )
      |> render_click()

      assert has_element?(view, "#tiptap-editor")

      # Close modal
      view |> element("button[phx-click='close_tiptap']") |> render_click()
      refute has_element?(view, "#tiptap-editor")
    end

    test "saves markdown content in edit mode", %{
      conn: conn,
      user: user,
      organization: organization
    } do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Switch to edit mode
      view |> element("button[phx-value-mode='edit']") |> render_click()

      # Update content
      new_content = "# Updated LSP Content\n\nThis is new content."
      view |> render_hook("update_markdown_content", %{"content" => new_content})

      # Save the changes
      view |> element("button[phx-click='save_markdown']") |> render_click()

      # Should show success message
      assert render(view) =~ "LSP markdown saved successfully"
    end

    test "exports CSV", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Click export CSV button
      view |> element("button[phx-click='export_csv']") |> render_click()

      # Should trigger CSV export (exact behavior depends on implementation)
      # This is a basic test to ensure the event handler exists
      refute render(view) =~ "error"
    end

    test "displays progress statistics", %{conn: conn, user: user, organization: organization} do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      html = render(view)

      # Should show statistics
      assert html =~ "total"
      assert html =~ "Implemented"
      assert html =~ "In Progress"
      assert html =~ "Not Started"
    end

    test "handles real-time updates via PubSub", %{
      conn: conn,
      user: user,
      organization: organization
    } do
      conn =
        conn
        |> log_in_user(user)
        |> assign(:current_org, organization)

      {:ok, view, _html} = live(conn, ~p"/admin/lsp-editor")

      # Simulate external update via PubSub
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "lsp_editor:progress",
        {:method_updated, "initialize", "implemented"}
      )

      # Should handle the update (exact behavior depends on implementation)
      refute render(view) =~ "error"
    end
  end

  # Helper functions for creating test data
  defp insert(schema, attrs \\ %{}) do
    case schema do
      :user ->
        %Lang.Accounts.User{
          id: System.unique_integer([:positive]),
          name: Map.get(attrs, :name, "Test User"),
          email: Map.get(attrs, :email, "test@example.com"),
          admin: Map.get(attrs, :admin, false)
        }

      :organization ->
        %Lang.Accounts.Organization{
          id: System.unique_integer([:positive]),
          name: Map.get(attrs, :name, "Test Org"),
          owner: Map.get(attrs, :owner)
        }
    end
  end

  defp log_in_user(conn, user) do
    conn
    |> assign(:current_user, user)
    |> assign(:user_token, "test-token")
  end
end
