defmodule LangWeb.AuthController do
  @moduledoc """
  Authentication controller for LANG Universal Text Intelligence Platform.

  Handles user authentication including login, logout, registration,
  and password reset functionality with proper security measures.
  """

  use LangWeb, :controller

  alias LangWeb.AuthHelpers
  alias Lang.Accounts.User
  alias Lang.Events
  require Logger

  @doc """
  Shows the authentication page with login/register forms.
  """
  def show(conn, _params) do
    if AuthHelpers.authenticated?(conn) do
      redirect_after_login(conn)
    else
      render(conn, :show, %{
        changeset: User.changeset_for_create(%{}),
        login_changeset: User.changeset_for_login(%{}),
        page_title: "Sign In - LANG"
      })
    end
  end

  @doc """
  Handles user login with email and password.
  """
  def login(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    case AuthHelpers.authenticate_user(email, password) do
      {:ok, user} ->
        ip_address = get_client_ip(conn)

        # Update login info
        AuthHelpers.update_user_login_info(user, ip_address)

        conn
        |> AuthHelpers.sign_in_user(user)
        |> put_flash(:info, "Welcome back, #{user.name}!")
        |> redirect_after_login()

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Invalid email or password.")
        |> render(:show, %{
          changeset: User.changeset_for_create(%{}),
          login_changeset: User.changeset_for_login(user_params, action: :validate),
          page_title: "Sign In - LANG"
        })

      {:error, reason} ->
        Logger.error("Login error: #{inspect(reason)}")

        conn
        |> put_flash(:error, "An error occurred during login. Please try again.")
        |> render(:show, %{
          changeset: User.changeset_for_create(%{}),
          login_changeset: User.changeset_for_login(user_params),
          page_title: "Sign In - LANG"
        })
    end
  end

  @doc """
  Handles user registration.
  """
  def register(conn, %{"user" => user_params}) do
    case AuthHelpers.create_user_account(user_params) do
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
        |> AuthHelpers.sign_in_user(user)
        |> put_flash(:info, "Welcome to LANG, #{user.name}! Your account has been created.")
        |> redirect(to: "/dashboard")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Please fix the errors below.")
        |> render(:show, %{
          changeset: changeset,
          login_changeset: User.changeset_for_login(%{}),
          page_title: "Sign In - LANG"
        })
    end
  end

  @doc """
  Handles user logout.
  """
  def logout(conn, _params) do
    user = AuthHelpers.current_user(conn)

    if user do
      Events.track_event(%{
        event_type: "user_logged_out",
        user_id: user.id,
        metadata: %{
          logout_ip: get_client_ip(conn)
        }
      })
    end

    conn
    |> AuthHelpers.sign_out_user()
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
  Handles forgot password form submission.
  """
  def send_reset_email(conn, %{"user" => %{"email" => email}}) do
    case AuthHelpers.send_password_reset_email(email) do
      {:ok, :email_sent} ->
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
    case verify_reset_token(token) do
      {:ok, user} ->
        changeset = User.changeset_for_password_reset(user, %{})

        render(conn, :reset_password, %{
          user: user,
          token: token,
          changeset: changeset,
          page_title: "Reset Password - LANG"
        })

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "Invalid or expired password reset link.")
        |> redirect(to: "/auth/forgot-password")

      {:error, :expired_token} ->
        conn
        |> put_flash(:error, "Password reset link has expired. Please request a new one.")
        |> redirect(to: "/auth/forgot-password")
    end
  end

  @doc """
  Handles password reset form submission.
  """
  def update_password(conn, %{"token" => token, "user" => user_params}) do
    case verify_reset_token(token) do
      {:ok, user} ->
        case User.update_password(user, user_params) do
          {:ok, updated_user} ->
            # Clear reset token
            User.update(updated_user, %{
              password_reset_token: nil,
              password_reset_token_expires_at: nil
            })

            Events.track_event(%{
              event_type: "password_reset_completed",
              user_id: user.id,
              metadata: %{
                reset_ip: get_client_ip(conn)
              }
            })

            conn
            |> AuthHelpers.sign_in_user(updated_user)
            |> put_flash(:info, "Your password has been updated successfully.")
            |> redirect(to: "/dashboard")

          {:error, changeset} ->
            render(conn, :reset_password, %{
              user: user,
              token: token,
              changeset: changeset,
              page_title: "Reset Password - LANG"
            })
        end

      {:error, reason} ->
        Logger.warning("Password reset attempted with invalid token: #{token}")

        conn
        |> put_flash(:error, "Invalid or expired password reset link.")
        |> redirect(to: "/auth/forgot-password")
    end
  end

  @doc """
  API endpoint for checking authentication status.
  """
  def status(conn, _params) do
    case AuthHelpers.current_user(conn) do
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
  def oauth_callback(conn, %{"provider" => provider} = params) do
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

  defp verify_reset_token(token) when is_binary(token) do
    import Ash.Query

    case User
         |> Ash.Query.filter(
           password_reset_token == ^token and
             password_reset_token_expires_at > ^DateTime.utc_now()
         )
         |> Ash.read_one() do
      {:ok, user} ->
        {:ok, user}

      nil ->
        # Check if token exists but is expired
        case User
             |> Ash.Query.filter(password_reset_token == ^token)
             |> Ash.read_one() do
          {:ok, _user} -> {:error, :expired_token}
          nil -> {:error, :invalid_token}
        end

      {:error, _reason} ->
        {:error, :invalid_token}
    end
  end

  defp verify_reset_token(_), do: {:error, :invalid_token}

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
