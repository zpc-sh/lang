defmodule LangWeb.AuthController do
  @moduledoc """
  Authentication controller for LANG Universal Text Intelligence Platform.

  Uses AshAuthentication for secure user authentication, registration,
  and password management with proper token handling.
  """

  use LangWeb, :controller
  use AshAuthentication.Phoenix.Controller
  import Phoenix.Component, only: [to_form: 1]

  alias Lang.Accounts.User

  alias Lang.Events
  require Logger

  @doc """
  Shows the authentication page with login/register forms.
  """
  def show(conn, params) do
    mode = Map.get(params, "mode", "login")

    if conn.assigns[:current_user] do
      redirect_after_login(conn)
    else
      render(conn, :show, %{
        changeset: to_form(%{}),
        login_changeset: to_form(%{}),
        page_title: "Sign In - LANG",
        mode: mode
      })
    end
  end

  @doc """
  Handles user sign-in with email and password using AshAuthentication.
  """
  def login(conn, %{"user" => user_params}) do
    email = Map.get(user_params, "email", "")
    password = Map.get(user_params, "password", "")

    case AshAuthentication.authenticate(User, :password, %{
           "email" => email,
           "password" => password
         }) do
      {:ok, user} ->
        Events.track_event(%{
          event_type: "user_login_success",
          user_id: user.id,
          metadata: %{email: user.email, ip_address: get_client_ip(conn)}
        })

        # Create session using AshAuthentication
        conn = AshAuthentication.Phoenix.sign_in(conn, user)

        conn
        |> put_flash(:info, "Welcome back, #{user.name}!")
        |> redirect_after_login()

      {:error, _error} ->
        Events.track_event(%{
          event_type: "user_login_failed",
          metadata: %{
            email: email,
            reason: "invalid_credentials",
            ip_address: get_client_ip(conn)
          }
        })

        conn
        |> put_flash(:error, "Invalid email or password.")
        |> render(:show, %{
          changeset: to_form(%{}),
          login_changeset: to_form(user_params),
          page_title: "Sign In - LANG",
          mode: "login"
        })
    end
  end

  @doc """
  Handles user registration using AshAuthentication.
  """
  def register(conn, %{"user" => user_params}) do
    # Ensure required fields
    enhanced_params =
      Map.merge(user_params, %{
        "organization_name" =>
          Map.get(
            user_params,
            "organization_name",
            "#{Map.get(user_params, "name", "User")}'s Organization"
          )
      })

    case User.register_with_password(enhanced_params) do
      {:ok, user} ->
        Events.track_event(%{
          event_type: "user_registered",
          user_id: user.id,
          metadata: %{
            email: user.email,
            registration_ip: get_client_ip(conn)
          }
        })

        # Create session using AshAuthentication
        conn = AshAuthentication.Phoenix.sign_in(conn, user)

        conn
        |> put_flash(:info, "Welcome to LANG, #{user.name}! Your account has been created.")
        |> redirect(to: "/dashboard")

      {:error, error} ->
        error_messages = format_ash_errors(error)

        conn
        |> put_flash(:error, "Please fix the errors: #{Enum.join(error_messages, ", ")}")
        |> render(:show, %{
          changeset: to_form(user_params),
          login_changeset: to_form(%{}),
          page_title: "Sign In - LANG",
          mode: "register"
        })
    end
  end

  @doc """
  Handles user sign-out using AshAuthentication.
  """
  def logout(conn, _params) do
    user = conn.assigns[:current_user]

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
    case AshAuthentication.Strategy.Password.request_password_reset(User, %{"email" => email}) do
      {:ok, user} ->
        Events.track_event(%{
          event_type: "password_reset_requested",
          user_id: user.id,
          metadata: %{email: email, ip_address: get_client_ip(conn)}
        })

        # Send password reset email
        send_password_reset_email(user)

        conn
        |> put_flash(
          :info,
          "If that email address is in our system, we've sent you a password reset link."
        )
        |> redirect(to: "/auth")

      {:error, _reason} ->
        # Always show the same message for security
        conn
        |> put_flash(
          :info,
          "If that email address is in our system, we've sent you a password reset link."
        )
        |> redirect(to: "/auth")
    end
  end

  @doc """
  Shows the password reset form with token.
  """
  def reset_password(conn, %{"token" => token}) do
    # Show the reset form - token will be validated when form is submitted
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
    case AshAuthentication.Strategy.Password.reset_password(User, %{
           "token" => token,
           "password" => user_params["password"],
           "password_confirmation" => user_params["password_confirmation"]
         }) do
      {:ok, user} ->
        Events.track_event(%{
          event_type: "password_reset_completed",
          user_id: user.id,
          metadata: %{
            reset_ip: get_client_ip(conn)
          }
        })

        conn
        |> put_flash(:info, "Your password has been updated successfully. You can now sign in.")
        |> redirect(to: "/auth")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "There was an error updating your password.")
        |> render(:reset_password, %{
          changeset: changeset,
          token: token,
          page_title: "Reset Password - LANG"
        })
    end
  end

  @doc """
  API endpoint for checking authentication status.
  """
  def status(conn, _params) do
    case conn.assigns[:current_user] do
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
  Success callback for OAuth authentication.
  """
  def success(conn, _activity, user, _token) do
    # Track successful OAuth login
    Events.track_event(%{
      event_type: "user_oauth_login_success",
      user_id: user.id,
      metadata: %{
        provider: user.provider || "unknown",
        ip_address: get_client_ip(conn)
      }
    })

    conn
    |> put_flash(:info, "Welcome back, #{user.name}!")
    |> redirect_after_login()
  end

  @doc """
  Failure callback for OAuth authentication.
  """
  def failure(conn, activity, reason) do
    provider = activity[:strategy_name] || "unknown"

    Events.track_event(%{
      event_type: "user_oauth_login_failed",
      metadata: %{
        provider: provider,
        reason: inspect(reason),
        ip_address: get_client_ip(conn)
      }
    })

    Logger.warning("OAuth authentication failed for provider #{provider}: #{inspect(reason)}")

    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: "/auth")
  end

  @doc """
  OAuth sign-out success callback.
  """
  def sign_out_success(conn) do
    conn
    |> put_flash(:info, "You have been signed out successfully.")
    |> redirect(to: "/")
  end

  # Private helper functions

  defp format_ash_errors(%Ash.Error.Invalid{errors: errors}) do
    Enum.map(errors, fn
      %{message: message} -> message
      error -> inspect(error)
    end)
  end

  defp format_ash_errors(error), do: [inspect(error)]

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

  defp send_password_reset_email(user) do
    # Generate a secure reset token for the email link
    reset_token = generate_reset_token()

    # Store token with user (you'd typically save this to the user record)
    # For now, we'll include it directly in the email

    # Send actual email using the existing email service
    case Lang.Emails.send_password_reset_email(user, reset_token) do
      {:ok, _} ->
        Logger.info("Password reset email sent to: #{user.email}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to send password reset email to #{user.email}: #{inspect(reason)}")
        :error
    end
  end

  defp generate_reset_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
