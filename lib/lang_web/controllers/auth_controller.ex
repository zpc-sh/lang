defmodule LangWeb.AuthController do
  @moduledoc """
  Authentication controller for LANG Universal Text Intelligence Platform.

  Uses AshAuthentication for secure user authentication, registration,
  and password management with proper token handling.
  """

  use LangWeb, :controller
  use AshAuthentication.Phoenix.Controller

  alias Lang.Accounts.User
  alias Lang.Events
  require Logger

  @doc """
  Shows the authentication page with login/register forms.
  """
  def show(conn, _params) do
    if AshAuthentication.Phoenix.current_user(conn) do
      redirect_after_login(conn)
    else
      render(conn, :show, %{
        changeset: User.changeset_for_create(%{}),
        login_changeset: AshPhoenix.Form.for_action(User, :sign_in_with_password, %{}),
        page_title: "Sign In - LANG"
      })
    end
  end

  @doc """
  Handles user sign-in with email and password using AshAuthentication.
  """
  def sign_in(conn, %{"user" => user_params}, _resource) do
    case AshAuthentication.authenticate(User, :password, user_params) do
      {:ok, user} ->
        Events.track_event(%{
          event_type: "user_login_success",
          user_id: user.id,
          metadata: %{email: user.email, ip_address: get_client_ip(conn)}
        })

        conn
        |> put_flash(:info, "Welcome back, #{user.name}!")
        |> redirect_after_login()

      {:error, _error} ->
        Events.track_event(%{
          event_type: "user_login_failed",
          metadata: %{
            email: Map.get(user_params, "email"),
            reason: "invalid_credentials",
            ip_address: get_client_ip(conn)
          }
        })

        conn
        |> put_flash(:error, "Invalid email or password.")
        |> render(:show, %{
          changeset: User.changeset_for_create(%{}),
          login_changeset: AshPhoenix.Form.for_action(User, :sign_in_with_password, user_params),
          page_title: "Sign In - LANG"
        })
    end
  end

  @doc """
  Handles user registration using AshAuthentication.
  """
  def register(conn, %{"user" => user_params}, _resource) do
    case User.register_with_password(user_params) do
      {:ok, user} ->
        Events.track_event(%{
          event_type: "user_registered",
          user_id: user.id,
          metadata: %{
            email: user.email,
            registration_ip: get_client_ip(conn)
          }
        })

        conn
        |> put_flash(:info, "Welcome to LANG, #{user.name}! Your account has been created.")
        |> redirect(to: "/dashboard")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Please fix the errors below.")
        |> render(:show, %{
          changeset: changeset,
          login_changeset: AshPhoenix.Form.for_action(User, :sign_in_with_password, %{}),
          page_title: "Sign In - LANG"
        })
    end
  end

  @doc """
  Handles user sign-out using AshAuthentication.
  """
  def sign_out(conn, _params) do
    user = AshAuthentication.Phoenix.current_user(conn)

    if user do
      Events.track_event(%{
        event_type: "user_logged_out",
        user_id: user.id,
        metadata: %{
          logout_ip: get_client_ip(conn)
        }
      })
    end

    conn = AshAuthentication.Phoenix.sign_out(conn)

    conn
    |> put_flash(:info, "You have been signed out.")
    |> redirect(to: "/")
  end

  @doc """
  Shows the forgot password form.
  """
  def forgot_password(conn, _params) do
    render(conn, :forgot_password, %{
      page_title: "Reset Password - LANG"
    })
  end

  @doc """
  Handles forgot password form submission using AshAuthentication.
  """
  def send_reset_email(conn, %{"user" => %{"email" => email}}) do
    # For now, we'll implement a simple placeholder
    # TODO: Implement proper AshAuthentication password reset
    case User.by_email(email) do
      {:ok, _user} ->
        Events.track_event(%{
          event_type: "password_reset_requested",
          metadata: %{email: email}
        })

        conn
        |> put_flash(
          :info,
          "If that email address is in our system, we've sent you a password reset link."
        )
        |> redirect(to: "/auth")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "There was an error sending the reset email. Please try again.")
        |> render(:forgot_password, %{
          page_title: "Reset Password - LANG"
        })
    end
  end

  @doc """
  Shows the password reset form with token.
  """
  def reset_password(conn, %{"token" => token}) do
    # TODO: Implement proper token validation with AshAuthentication
    changeset = User.changeset_for_create(%{})

    render(conn, :reset_password, %{
      user: %{},
      token: token,
      changeset: changeset,
      page_title: "Reset Password - LANG"
    })
  end

  @doc """
  Handles password reset form submission using AshAuthentication.
  """
  def update_password(conn, %{"token" => token, "user" => user_params}) do
    # TODO: Implement proper AshAuthentication password reset
    case User.change_password(%{}, user_params) do
      {:ok, user} ->
        Events.track_event(%{
          event_type: "password_reset_completed",
          user_id: user.id,
          metadata: %{
            reset_ip: get_client_ip(conn)
          }
        })

        conn
        |> put_flash(:info, "Your password has been updated successfully.")
        |> redirect(to: "/dashboard")

      {:error, changeset} ->
        render(conn, :reset_password, %{
          user: %{},
          token: token,
          changeset: changeset,
          page_title: "Reset Password - LANG"
        })
    end
  end

  @doc """
  API endpoint for checking authentication status.
  """
  def status(conn, _params) do
    case AshAuthentication.Phoenix.current_user(conn) do
      %{} = user ->
        json(conn, %{
          authenticated: true,
          user: %{
            id: user.id,
            email: user.email,
            name: user.name,
            subscription_tier: user.subscription_tier
          }
        })

      nil ->
        json(conn, %{authenticated: false})
    end
  end

  @doc """
  Handles OAuth callbacks (placeholder for future implementation).
  """
  def oauth_callback(conn, %{"provider" => provider} = _params) do
    # Placeholder for OAuth integration (Google, GitHub, etc.)
    Logger.info("OAuth callback received for provider: #{provider}")

    conn
    |> put_flash(:error, "OAuth authentication is not yet available.")
    |> redirect(to: "/auth")
  end

  # Private helper functions

  defp redirect_after_login(conn) do
    case get_session(conn, :return_to) do
      nil ->
        redirect(conn, to: "/dashboard")

      return_to ->
        conn
        |> delete_session(:return_to)
        |> redirect(to: return_to)
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] when is_binary(ip) ->
        ip |> String.split(",") |> List.first() |> String.trim()

      [] ->
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          _ -> "unknown"
        end
    end
  end
end
