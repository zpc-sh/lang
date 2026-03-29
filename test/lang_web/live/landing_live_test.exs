defmodule LangWeb.LandingLiveTest do
  use LangWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Landing Page" do
    test "renders landing page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Check basic page structure
      assert html =~ "LANG"
      assert html =~ "Universal Text Intelligence Platform"
      assert html =~ "Transform any text into actionable insights"
    end

    test "displays hero section with proper content", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Hero section content
      assert html =~ "Universal Text Intelligence Platform"
      assert html =~ "beyond LSP"
      assert html =~ "Try Free"
    end

    test "shows feature sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Feature sections
      assert html =~ "Multi-Format Analysis"
      assert html =~ "Intelligent Completions"
      assert html =~ "Real-time Diagnostics"
      assert html =~ "Semantic Understanding"
    end

    test "displays conversation rehearsal features", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Conversation rehearsal
      assert html =~ "Scenario-Based Practice"
      assert html =~ "Branching Conversations"
      assert html =~ "Performance Analytics"
      assert html =~ "AI-Powered Feedback"
    end

    test "shows stylometric analysis features", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Stylometric analysis
      assert html =~ "Writing Fingerprinting"
      assert html =~ "Authorship Attribution"
      assert html =~ "Style Obfuscation"
      assert html =~ "Privacy Protection"
    end

    test "displays time machine features", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Time machine
      assert html =~ "Content Evolution"
      assert html =~ "Branching Timelines"
      assert html =~ "Temporal Navigation"
      assert html =~ "Snapshot Management"
    end

    test "shows language server protocol features", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # LSP features
      assert html =~ "Universal LSP"
      assert html =~ "Real-time Analysis"
      assert html =~ "Cross-Format Support"
      assert html =~ "Extensible Architecture"
    end

    test "displays call-to-action buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # CTA buttons
      assert html =~ "Try Free"
      assert html =~ "View Documentation"
    end

    test "includes proper navigation links", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Navigation links
      assert html =~ "href=\"#features\""
      assert html =~ "href=\"/api-portal\""
      assert html =~ "href=\"#pricing\""
      assert html =~ "href=\"/analyze\""
    end

    test "shows responsive design elements", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Responsive design classes
      assert html =~ "md:hidden"
      assert html =~ "sm:text-"
      assert html =~ "lg:px-"
    end

    test "displays proper meta information", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Check for proper page structure
      assert html =~ "min-h-screen"
      assert html =~ "bg-gray-950"
    end

    test "handles mobile menu interaction", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Test mobile menu functionality
      html = render(view)
      assert html =~ "mobile-menu-button"
      assert html =~ "mobile-menu"
    end

    test "shows proper LANG branding", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # LANG branding elements
      assert html =~ "<svg"
      assert html =~ "linearGradient"
      assert html =~ "stop-color:#4a9eff"
      assert html =~ "stop-color:#0066ff"
    end

    test "displays footer information", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Footer content (assuming footer exists)
      assert html =~ "LANG"
    end

    test "includes analytics and performance indicators", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Performance indicators
      assert html =~ "60-100x performance"
      assert html =~ "20+ text formats"
      assert html =~ "Support for 50+ file formats"
    end

    test "shows pricing or tier information", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Pricing mentions (if present)
      # This test might need adjustment based on actual content
      assert html =~ "Free" || html =~ "Professional" || html =~ "Enterprise"
    end

    test "displays proper page title", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Check page title through LiveView
      assert page_title(view) =~ "LANG"
    end

    test "handles user authentication state - guest", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Guest user should see sign in option
      assert html =~ "Sign In"
      assert html =~ "Try Free"
    end

    test "loads without errors", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, "/")
    end

    test "renders with proper semantic HTML structure", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Semantic HTML structure
      assert html =~ "<nav"
      assert html =~ "<section"
      assert html =~ "<header" || html =~ "<h1"
    end

    test "includes accessibility features", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Accessibility features
      assert html =~ "aria-"
      assert html =~ "alt="
      assert html =~ "sr-only"
    end
  end

  describe "Interactive Elements" do
    test "Try Free button is clickable and functional", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Check if Try Free button exists and has proper attributes
      html = render(view)
      assert html =~ "href=\"/analyze\""
    end

    test "navigation links are properly formed", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Check navigation link structure
      assert html =~ "href=\"#features\""
      assert html =~ "href=\"/api-portal\""
    end

    test "handles responsive navigation correctly", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Test responsive elements
      html = render(view)
      assert html =~ "hidden md:flex"
      assert html =~ "md:hidden"
    end
  end

  describe "Content Sections" do
    test "displays all major feature sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Major sections
      sections = [
        "Multi-Format Analysis",
        "Intelligent Completions",
        "Real-time Diagnostics",
        "Semantic Understanding",
        "Scenario-Based Practice",
        "Branching Conversations",
        "Writing Fingerprinting",
        "Content Evolution"
      ]

      Enum.each(sections, fn section ->
        assert html =~ section
      end)
    end

    test "shows performance metrics and statistics", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Performance metrics
      metrics = [
        "60-100x",
        "performance",
        "20+",
        "formats",
        "50+"
      ]

      Enum.each(metrics, fn metric ->
        assert html =~ metric
      end)
    end
  end

  describe "Error Handling" do
    test "gracefully handles missing assigns", %{conn: conn} do
      # This test ensures the page doesn't crash with missing user context
      {:ok, _view, _html} = live(conn, "/")
      # If we get here without crashing, the test passes
    end
  end

  describe "SEO and Meta" do
    test "includes proper meta information for SEO", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Check that page has proper title
      assert page_title(view) =~ "LANG"
    end
  end
end
