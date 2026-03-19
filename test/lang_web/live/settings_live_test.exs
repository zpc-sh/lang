defmodule LangWeb.SettingsLiveTest do
  use LangWeb.ConnCase
  import Phoenix.LiveViewTest
  import Lang.Factory

  describe "Settings LiveView" do
    setup do
      {:ok, user_data} =
        create_complete_user(%{
          email: "test@example.com",
          name: "Test User",
          subscription_tier: "professional"
        })

      %{
        user: user_data.user,
        organization: user_data.organization,
        api_key: user_data.api_key
      }
    end

    test "renders settings page with profile tab active by default", %{conn: conn, user: user} do
      conn = authenticate_conn(conn, user)

      {:ok, _view, html} = live(conn, "/settings")

      assert html =~ "Settings"
      assert html =~ "Profile"
      assert html =~ "Security"
      assert html =~ "Organization"
      assert html =~ "Billing"
      assert html =~ "Profile Information"
    end

    test "can switch between tabs", %{conn: conn, user: user} do
      conn = authenticate_conn(conn, user)

      {:ok, view, _html} = live(conn, "/settings")

      # Switch to security tab
      html = view |> element("button", "Security") |> render_click()
      assert html =~ "Change Password"
      assert html =~ "API Keys"

      # Switch to organization tab
      html = view |> element("button", "Organization") |> render_click()
      assert html =~ "Organization Information"

      # Switch to billing tab
      html = view |> element("button", "Billing") |> render_click()
      assert html =~ "Current Plan"
      assert html =~ "PROFESSIONAL Plan"
    end

    test "displays user subscription tier correctly", %{conn: conn, user: user} do
      conn = authenticate_conn(conn, user)

      {:ok, _view, html} = live(conn, "/settings")

      assert html =~ "PROFESSIONAL"
    end

    test "shows usage statistics", %{conn: conn, user: user} do
      conn = authenticate_conn(conn, user)

      {:ok, _view, html} = live(conn, "/settings")

      assert html =~ "Usage Statistics"
      assert html =~ "Requests This Month"
      assert html =~ "Monthly Limit"
    end

    test "profile component can update user information", %{conn: conn, user: user} do
      conn = authenticate_conn(conn, user)

      {:ok, view, _html} = live(conn, "/settings")

      # Update profile
      view
      |> form("#profile-form", %{user: %{name: "Updated Name", email: "updated@example.com"}})
      |> render_submit()

      assert render(view) =~ "Updated Name"
    end

    test "security tab shows API keys", %{conn: conn, user: user, api_key: api_key} do
      conn = authenticate_conn(conn, user)

      {:ok, view, _html} = live(conn, "/settings")

      # Switch to security tab
      html = view |> element("button", "Security") |> render_click()

      assert html =~ "API Keys"
      assert html =~ api_key.name
    end

    test "can create new API key from security tab", %{conn: conn, user: user} do
      conn = authenticate_conn(conn, user)

      {:ok, view, _html} = live(conn, "/settings")

      # Switch to security tab
      view |> element("button", "Security") |> render_click()

      # Show API key form
      view |> element("button", "New API Key") |> render_click()

      assert render(view) =~ "Create New API Key"

      # Fill and submit form
      view
      |> form("#api-key-form", %{api_key: %{name: "Test API Key"}})
      |> render_submit()

      assert render(view) =~ "API key created successfully"
      assert render(view) =~ "Test API Key"
    end

    test "organization tab shows organization details", %{
      conn: conn,
      user: user,
      organization: org
    } do
      conn = authenticate_conn(conn, user)

      {:ok, view, _html} = live(conn, "/settings")

      # Switch to organization tab
      html = view |> element("button", "Organization") |> render_click()

      assert html =~ "Organization Information"
      assert html =~ org.name
    end

    test "billing tab shows subscription details", %{conn: conn, user: user} do
      conn = authenticate_conn(conn, user)

      {:ok, view, _html} = live(conn, "/settings")

      # Switch to billing tab
      html = view |> element("button", "Billing") |> render_click()

      assert html =~ "Current Plan"
      assert html =~ "PROFESSIONAL Plan"
      assert html =~ "$29"
      assert html =~ "Usage This Month"
    end

    test "handles missing organization gracefully", %{conn: conn} do
      {:ok, user} =
        create_user(%{
          email: "noorg@example.com",
          name: "No Org User"
        })

      conn = authenticate_conn(conn, user)

      {:ok, view, _html} = live(conn, "/settings")

      # Switch to organization tab
      html = view |> element("button", "Organization") |> render_click()

      assert html =~ "No Organization"
      assert html =~ "Contact support"
    end
  end

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: "/auth"}}} = live(conn, "/settings")
    end

    test "loads user data on mount", %{conn: conn} do
      {:ok, user_data} = create_complete_user()
      conn = authenticate_conn(conn, user_data.user)

      {:ok, view, _html} = live(conn, "/settings")

      assert view.assigns.user.id == user_data.user.id
      assert view.assigns.organization.id == user_data.organization.id
    end
  end
end
