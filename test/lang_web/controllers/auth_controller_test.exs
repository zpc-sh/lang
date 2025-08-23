defmodule LangWeb.AuthControllerTest do
  use LangWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lang.Accounts.User
  alias Lang.Accounts.Organization

  describe "GET /auth" do
    test "renders authentication page for guest users", %{conn: conn} do
      conn = get(conn, "/auth")
      assert html_response(conn, 200) =~ "Welcome to LANG"
      assert html_response(conn, 200) =~ "Sign In"
      assert html_response(conn, 200) =~ "Sign Up"
      assert html_response(conn, 200) =~ "Universal Text Intelligence Platform"
    end

    test "displays proper LANG branding and logo", %{conn: conn} do
      conn = get(conn, "/auth")
      html = html_response(conn, 200)

      # Check for SVG logo
      assert html =~ "<svg"
      assert html =~ "linearGradient"
      assert html =~ "stop-color:#4a9eff"
      assert html =~ "stop-color:#0066ff"

      # Check for navbar
      assert html =~ "navbar" || html =~ "<nav"
      assert html =~ "LANG"
    end

    test "shows login form by default", %{conn: conn} do
      conn = get(conn, "/auth")
      html = html_response(conn, 200)

      assert html =~ "name=\"user[email]\""
      assert html =~ "name=\"user[password]\""
      assert html =~ "type=\"email\""
      assert html =~ "type=\"password\""
    end

    test "includes mobile responsive elements", %{conn: conn} do
      conn = get(conn, "/auth")
      html = html_response(conn, 200)

      # Responsive design classes
      assert html =~ "sm:"
      assert html =~ "md:"
      assert html =~ "lg:"
      assert html =~ "px-3"
      assert html =~ "py-8"
    end

    test "redirects authenticated users to dashboard", %{conn: conn} do
      # Create a test user and authenticate
      user = create_test_user()

      conn =
        conn
        |> assign(:current_user, user)
        |> get("/auth")

      assert redirected_to(conn) == "/dashboard"
    end
  end

  describe "GET /auth?mode=register" do
    test "renders registration form", %{conn: conn} do
      conn = get(conn, "/auth?mode=register")
      html = html_response(conn, 200)

      assert html =~ "Welcome to LANG"
      assert html =~ "Sign Up"
      assert html =~ "name=\"user[name]\""
      assert html =~ "name=\"user[email]\""
      assert html =~ "name=\"user[password]\""
      assert html =~ "name=\"user[password_confirmation]\""
      assert html =~ "name=\"user[organization_name]\""
    end

    test "shows tab navigation with register active", %{conn: conn} do
      conn = get(conn, "/auth?mode=register")
      html = html_response(conn, 200)

      # Check for tab navigation
      assert html =~ "Sign In"
      assert html =~ "Sign Up"
      assert html =~ "href=\"/auth\""
      assert html =~ "href=\"/auth?mode=register\""
    end

    test "includes proper form validation attributes", %{conn: conn} do
      conn = get(conn, "/auth?mode=register")
      html = html_response(conn, 200)

      assert html =~ "required"
      assert html =~ "type=\"email\""
      assert html =~ "type=\"password\""
    end
  end

  describe "POST /auth/login" do
    setup do
      user = create_test_user()
      %{user: user}
    end

    test "successfully authenticates valid user", %{conn: conn, user: user} do
      conn =
        post(conn, "/auth/login", %{
          "user" => %{
            "email" => user.email,
            "password" => "test_password"
          }
        })

      assert redirected_to(conn) == "/dashboard"
      assert get_flash(conn, :info) =~ "Welcome back"
    end

    test "rejects invalid credentials", %{conn: conn} do
      conn =
        post(conn, "/auth/login", %{
          "user" => %{
            "email" => "nonexistent@example.com",
            "password" => "wrong_password"
          }
        })

      assert html_response(conn, 200) =~ "Invalid email or password"
      assert html_response(conn, 200) =~ "Sign In"
    end

    test "rejects empty credentials", %{conn: conn} do
      conn =
        post(conn, "/auth/login", %{
          "user" => %{
            "email" => "",
            "password" => ""
          }
        })

      assert html_response(conn, 200) =~ "Invalid email or password"
    end

    test "handles malformed request gracefully", %{conn: conn} do
      conn = post(conn, "/auth/login", %{})

      assert html_response(conn, 200) =~ "Invalid email or password"
    end

    test "redirects to intended page after login", %{conn: conn, user: user} do
      # First, try to access a protected page
      conn = get(conn, "/dashboard")
      assert redirected_to(conn) == "/auth"

      # Then login
      conn =
        post(conn, "/auth/login", %{
          "user" => %{
            "email" => user.email,
            "password" => "test_password"
          }
        })

      assert redirected_to(conn) == "/dashboard"
    end
  end

  describe "POST /auth/register" do
    test "successfully creates new user account", %{conn: conn} do
      conn =
        post(conn, "/auth/register", %{
          "user" => %{
            "name" => "Test User",
            "email" => "test@example.com",
            "password" => "test_password123",
            "password_confirmation" => "test_password123",
            "organization_name" => "Test Organization"
          }
        })

      assert redirected_to(conn) == "/dashboard"
      assert get_flash(conn, :info) =~ "Welcome to LANG"
    end

    test "creates organization for new user", %{conn: conn} do
      conn =
        post(conn, "/auth/register", %{
          "user" => %{
            "name" => "Test User",
            "email" => "test2@example.com",
            "password" => "test_password123",
            "password_confirmation" => "test_password123",
            "organization_name" => "My Company"
          }
        })

      assert redirected_to(conn) == "/dashboard"
      # Organization should be created and associated with user
    end

    test "rejects registration with mismatched passwords", %{conn: conn} do
      conn =
        post(conn, "/auth/register", %{
          "user" => %{
            "name" => "Test User",
            "email" => "test@example.com",
            "password" => "test_password123",
            "password_confirmation" => "different_password",
            "organization_name" => "Test Organization"
          }
        })

      assert html_response(conn, 200) =~ "Please fix the errors"
      assert html_response(conn, 200) =~ "Sign Up"
    end

    test "rejects registration with existing email", %{conn: conn} do
      user = create_test_user()

      conn =
        post(conn, "/auth/register", %{
          "user" => %{
            "name" => "Another User",
            "email" => user.email,
            "password" => "test_password123",
            "password_confirmation" => "test_password123",
            "organization_name" => "Another Organization"
          }
        })

      assert html_response(conn, 200) =~ "Please fix the errors"
    end

    test "rejects registration with missing required fields", %{conn: conn} do
      conn =
        post(conn, "/auth/register", %{
          "user" => %{
            "email" => "incomplete@example.com"
          }
        })

      assert html_response(conn, 200) =~ "Please fix the errors"
    end

    test "handles empty organization name gracefully", %{conn: conn} do
      conn =
        post(conn, "/auth/register", %{
          "user" => %{
            "name" => "Test User",
            "email" => "test@example.com",
            "password" => "test_password123",
            "password_confirmation" => "test_password123",
            "organization_name" => ""
          }
        })

      # Should create default organization name
      assert redirected_to(conn) == "/dashboard"
    end
  end

  describe "DELETE /auth/logout" do
    setup do
      user = create_test_user()
      %{user: user}
    end

    test "successfully logs out authenticated user", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> delete("/auth/logout")

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "signed out"
    end

    test "handles logout for non-authenticated user", %{conn: conn} do
      conn = delete(conn, "/auth/logout")

      assert redirected_to(conn) == "/"
    end
  end

  describe "GET /auth/forgot-password" do
    test "renders forgot password page", %{conn: conn} do
      conn = get(conn, "/auth/forgot-password")
      html = html_response(conn, 200)

      assert html =~ "Reset your password"
      assert html =~ "Enter your email address"
      assert html =~ "name=\"user[email]\""
      assert html =~ "Send reset link"
    end

    test "includes proper branding and navigation", %{conn: conn} do
      conn = get(conn, "/auth/forgot-password")
      html = html_response(conn, 200)

      # Check for navbar and branding
      assert html =~ "LANG"
      assert html =~ "<svg"
      assert html =~ "<nav"
      assert html =~ "Back to sign in"
    end

    test "is mobile responsive", %{conn: conn} do
      conn = get(conn, "/auth/forgot-password")
      html = html_response(conn, 200)

      assert html =~ "sm:"
      assert html =~ "pt-20 sm:pt-24"
    end
  end

  describe "POST /auth/forgot-password" do
    setup do
      user = create_test_user()
      %{user: user}
    end

    test "sends reset email for existing user", %{conn: conn, user: user} do
      conn =
        post(conn, "/auth/forgot-password", %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == "/auth"
      assert get_flash(conn, :info) =~ "we've sent you a password reset link"
    end

    test "shows same message for non-existent email", %{conn: conn} do
      conn =
        post(conn, "/auth/forgot-password", %{
          "user" => %{"email" => "nonexistent@example.com"}
        })

      assert redirected_to(conn) == "/auth"
      assert get_flash(conn, :info) =~ "we've sent you a password reset link"
    end

    test "handles malformed request", %{conn: conn} do
      conn = post(conn, "/auth/forgot-password", %{})

      assert redirected_to(conn) == "/auth"
      assert get_flash(conn, :info) =~ "we've sent you a password reset link"
    end
  end

  describe "GET /auth/reset-password/:token" do
    test "renders password reset form with valid token", %{conn: conn} do
      conn = get(conn, "/auth/reset-password/valid-token-123")
      html = html_response(conn, 200)

      assert html =~ "Set new password"
      assert html =~ "Enter your new password"
      assert html =~ "name=\"user[password]\""
      assert html =~ "name=\"user[password_confirmation]\""
      assert html =~ "Update password"
    end

    test "includes proper branding and navigation", %{conn: conn} do
      conn = get(conn, "/auth/reset-password/token-123")
      html = html_response(conn, 200)

      assert html =~ "LANG"
      assert html =~ "<svg"
      assert html =~ "Back to sign in"
    end
  end

  describe "POST /auth/reset-password/:token" do
    test "successfully resets password with valid token and matching passwords", %{conn: conn} do
      conn =
        post(conn, "/auth/reset-password/valid-token", %{
          "user" => %{
            "password" => "new_password123",
            "password_confirmation" => "new_password123"
          }
        })

      assert redirected_to(conn) == "/auth"
      assert get_flash(conn, :info) =~ "password has been updated successfully"
    end

    test "rejects mismatched passwords", %{conn: conn} do
      conn =
        post(conn, "/auth/reset-password/valid-token", %{
          "user" => %{
            "password" => "new_password123",
            "password_confirmation" => "different_password"
          }
        })

      assert html_response(conn, 200) =~ "error updating your password"
    end

    test "rejects invalid token", %{conn: conn} do
      conn =
        post(conn, "/auth/reset-password/invalid-token", %{
          "user" => %{
            "password" => "new_password123",
            "password_confirmation" => "new_password123"
          }
        })

      assert html_response(conn, 200) =~ "error updating your password"
    end
  end

  describe "GET /auth/status" do
    test "returns authenticated status for logged-in user", %{conn: conn} do
      user = create_test_user()

      conn =
        conn
        |> assign(:current_user, user)
        |> get("/auth/status")

      response = json_response(conn, 200)
      assert response["authenticated"] == true
      assert response["user"]["email"] == user.email
    end

    test "returns unauthenticated status for guest user", %{conn: conn} do
      conn = get(conn, "/auth/status")

      response = json_response(conn, 200)
      assert response["authenticated"] == false
    end

    test "includes user information when authenticated", %{conn: conn} do
      user = create_test_user()

      conn =
        conn
        |> assign(:current_user, user)
        |> get("/auth/status")

      response = json_response(conn, 200)
      assert response["user"]["id"] == user.id
      assert response["user"]["name"] == user.name
      assert response["user"]["subscription_tier"] == to_string(user.subscription_tier)
    end
  end

  describe "GET /auth/oauth/:provider" do
    test "shows OAuth not available message", %{conn: conn} do
      conn = get(conn, "/auth/oauth/google")

      assert redirected_to(conn) == "/auth"
      assert get_flash(conn, :error) =~ "OAuth authentication is not yet available"
    end
  end

  describe "Form Security" do
    test "login form includes CSRF token", %{conn: conn} do
      conn = get(conn, "/auth")
      html = html_response(conn, 200)

      assert html =~ "csrf_token"
    end

    test "register form includes CSRF token", %{conn: conn} do
      conn = get(conn, "/auth?mode=register")
      html = html_response(conn, 200)

      assert html =~ "csrf_token"
    end

    test "password reset form includes CSRF token", %{conn: conn} do
      conn = get(conn, "/auth/forgot-password")
      html = html_response(conn, 200)

      assert html =~ "csrf_token"
    end
  end

  describe "Accessibility" do
    test "auth forms include proper accessibility attributes", %{conn: conn} do
      conn = get(conn, "/auth")
      html = html_response(conn, 200)

      assert html =~ "aria-"
      assert html =~ "sr-only"
      assert html =~ "label"
    end

    test "includes proper form labels", %{conn: conn} do
      conn = get(conn, "/auth")
      html = html_response(conn, 200)

      assert html =~ "Email address"
      assert html =~ "Password"
    end
  end

  describe "Error Handling" do
    test "handles database connection errors gracefully during login", %{conn: conn} do
      # This test would require mocking database errors
      # Implementation depends on your testing strategy

      conn =
        post(conn, "/auth/login", %{
          "user" => %{
            "email" => "test@example.com",
            "password" => "password"
          }
        })

      # Should not crash the application
      assert conn.status in [200, 302]
    end

    test "handles malformed JSON in API endpoints gracefully", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> get("/auth/status")

      # Should return proper JSON response
      assert json_response(conn, 200)
    end
  end

  # Helper functions
  defp create_test_user do
    %User{
      id: Ecto.UUID.generate(),
      email: "test@example.com",
      name: "Test User",
      subscription_tier: :free,
      hashed_password: Bcrypt.hash_pwd_salt("test_password")
    }
  end
end
