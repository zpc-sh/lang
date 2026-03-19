defmodule LangWeb.AuthLive do
  @moduledoc """
  Authentication LiveViews for user registration, sign in, and password reset.

  This module provides a complete authentication flow using Ash Authentication
  with support for user registration, organization creation, and API key management.
  """

  use LangWeb, :live_view
  alias Lang.Accounts.User
  alias Lang.Accounts.Organization
  alias AshAuthentication.Phoenix.Components

  @impl true
  def mount(params, _session, socket) do
    action = Map.get(params, "action", "sign_in")

    socket =
      socket
      |> assign(:action, action)
      |> assign(:page_title, page_title(action))
      |> assign(:form, to_form(%{}))
      |> assign(:errors, [])
      |> assign(:loading, false)
      |> assign(:show_organization_form, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    action = Map.get(params, "action", "sign_in")

    socket =
      socket
      |> assign(:action, action)
      |> assign(:page_title, page_title(action))

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_auth_mode", %{"mode" => mode}, socket) do
    socket =
      socket
      |> push_patch(to: ~p"/auth?action=#{mode}")
      |> assign(:errors, [])
      |> assign(:form, to_form(%{}))

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_organization_form", _params, socket) do
    socket = assign(socket, :show_organization_form, !socket.assigns.show_organization_form)
    {:noreply, socket}
  end

  @impl true
  def handle_event("sign_up", params, socket) do
    socket = assign(socket, :loading, true)

    user_params = Map.get(params, "user", %{})

    case socket.assigns.show_organization_form do
      true -> handle_sign_up_with_organization(user_params, socket)
      false -> handle_sign_up_with_existing_organization(user_params, socket)
    end
  end

  @impl true
  def handle_event("sign_in", params, socket) do
    socket = assign(socket, :loading, true)

    user_params = Map.get(params, "user", %{})
    email = Map.get(user_params, "email", "")
    password = Map.get(user_params, "password", "")

    case AshAuthentication.authenticate(User, :password, %{
           "email" => email,
           "password" => password
         }) do
      {:ok, user} ->
        # Update last login
        User.update_last_login!(user)

        socket =
          socket
          |> put_flash(:info, "Welcome back!")
          |> redirect(to: ~p"/dashboard")

        {:noreply, socket}

      {:error, %AshAuthentication.Errors.AuthenticationFailed{}} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:errors, ["Invalid email or password"])

        {:noreply, socket}

      {:error, error} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:errors, ["Authentication failed: #{inspect(error)}"])

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("request_password_reset", params, socket) do
    socket = assign(socket, :loading, true)

    user_params = Map.get(params, "user", %{})
    email = Map.get(user_params, "email", "")

    case AshAuthentication.Strategy.Password.request_password_reset(User, %{"email" => email}) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(:info, "Password reset instructions sent to your email")
          |> push_patch(to: ~p"/auth?action=sign_in")

        {:noreply, socket}

      {:error, _} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:errors, ["Unable to send password reset instructions"])

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reset_password", params, socket) do
    socket = assign(socket, :loading, true)

    user_params = Map.get(params, "user", %{})
    token = Map.get(user_params, "token", "")
    password = Map.get(user_params, "password", "")
    password_confirmation = Map.get(user_params, "password_confirmation", "")

    case AshAuthentication.Strategy.Password.reset_password(User, %{
           "token" => token,
           "password" => password,
           "password_confirmation" => password_confirmation
         }) do
      {:ok, _user} ->
        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(
            :info,
            "Password reset successfully. Please sign in with your new password."
          )
          |> push_patch(to: ~p"/auth?action=sign_in")

        {:noreply, socket}

      {:error, error} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:errors, format_errors(error))

        {:noreply, socket}
    end
  end

  # Private functions

  defp handle_sign_up_with_organization(user_params, socket) do
    organization_name = Map.get(user_params, "organization_name", "")
    organization_slug = Map.get(user_params, "organization_slug", "")

    case User.register_with_organization(%{
           "email" => Map.get(user_params, "email", ""),
           "password" => Map.get(user_params, "password", ""),
           "password_confirmation" => Map.get(user_params, "password_confirmation", ""),
           "organization_name" => organization_name,
           "organization_slug" => organization_slug,
           "name" => Map.get(user_params, "name", ""),
           "role" => "Owner"
         }) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(
            :info,
            "Account created successfully! Please check your email to confirm your account."
          )
          |> push_patch(to: ~p"/auth?action=sign_in")

        {:noreply, socket}

      {:error, error} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:errors, format_errors(error))

        {:noreply, socket}
    end
  end

  defp handle_sign_up_with_existing_organization(user_params, socket) do
    organization_id = Map.get(user_params, "organization_id", "")

    case User.register(%{
           "email" => Map.get(user_params, "email", ""),
           "password" => Map.get(user_params, "password", ""),
           "password_confirmation" => Map.get(user_params, "password_confirmation", ""),
           "organization_id" => organization_id,
           "name" => Map.get(user_params, "name", ""),
           "role" => Map.get(user_params, "role", "Member")
         }) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:loading, false)
          |> put_flash(
            :info,
            "Account created successfully! Please check your email to confirm your account."
          )
          |> push_patch(to: ~p"/auth?action=sign_in")

        {:noreply, socket}

      {:error, error} ->
        socket =
          socket
          |> assign(:loading, false)
          |> assign(:errors, format_errors(error))

        {:noreply, socket}
    end
  end

  defp format_errors(%Ash.Error.Invalid{} = error) do
    error.errors
    |> Enum.map(fn
      %Ash.Error.Changes.InvalidAttribute{message: message} -> message
      %Ash.Error.Query.InvalidArgument{message: message} -> message
      %{message: message} -> message
      error -> inspect(error)
    end)
  end

  defp format_errors(error) when is_binary(error), do: [error]
  defp format_errors(error), do: [inspect(error)]

  defp page_title("sign_up"), do: "Sign Up"
  defp page_title("sign_in"), do: "Sign In"
  defp page_title("password_reset"), do: "Reset Password"
  defp page_title("reset_password"), do: "Set New Password"
  defp page_title(_), do: "Authentication"
end
