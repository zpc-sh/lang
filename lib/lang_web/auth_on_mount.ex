defmodule LangWeb.AuthOnMount do
  @moduledoc """
  LiveView on_mount hooks for assigning current_user and enforcing authentication.

  This module integrates with AshAuthentication to provide consistent
  authentication across LiveViews using proper Ash patterns.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias Lang.Accounts.User
  alias Lang.Events
  alias LangWeb.AuthHelpers
  require Logger

  @doc """
  Assigns current_user and current_scope using AshAuthentication session helpers.
  """
  def mount_current_user(_params, session, socket) do
    socket =
      case get_current_user_from_session(session) do
        {:ok, user} ->
          org =
            case AuthHelpers.ensure_user_organization(user) do
              {:ok, org} -> org
              _ -> nil
            end

          socket
          |> assign(:current_user, user)
          |> assign(:current_org, org)
          |> assign(:current_scope, %{type: :user, id: user.id})
          |> assign(:authenticated?, true)

        {:error, _reason} ->
          assign_development_user(socket)
      end

    {:cont, socket}
  end

  defp get_current_user_from_session(session) do
    # Try multiple session key formats for compatibility
    token =
      session["user_token"] || session[:user_token] ||
        session["_ash_authentication_user_token"] || session[:_ash_authentication_user_token]

    case token do
      nil ->
        {:error, :no_token}

      token ->
        try do
          # Use AshAuthentication's subject_to_user function
          case AshAuthentication.subject_to_user(token, Lang.Accounts.User) do
            {:ok, user} ->
              # Ensure user is loaded with associations
              case Lang.Accounts.User.by_id(user.id)
                   |> Ash.Query.load([:organization])
                   |> Ash.read_one() do
                {:ok, loaded_user} -> {:ok, loaded_user}
                _ -> {:ok, user}
              end

            {:error, _} ->
              {:error, :invalid_token}
          end
        rescue
          error ->
            Logger.warning("Token verification failed: #{inspect(error)}")
            {:error, :token_verification_failed}
        end
    end
  end

  @doc """
  Requires authentication for the LiveView. Redirects to /auth if no user.
  """
  def require_authenticated(_params, _session, socket) do
    case socket.assigns do
      %{authenticated?: true, current_user: user} when not is_nil(user) ->
        {:cont, socket}

      %{current_scope: %{type: :development}} ->
        if Mix.env() in [:dev, :test] do
          {:cont, socket}
        else
          Logger.info("Unauthenticated access to protected LiveView")

          socket =
            socket
            |> put_flash(:error, "You must be signed in to access this page.")
            |> redirect(to: "/auth")

          {:halt, socket}
        end

      _ ->
        Logger.info("Unauthenticated access to protected LiveView")

        socket =
          socket
          |> put_flash(:error, "You must be signed in to access this page.")
          |> redirect(to: "/auth")

        {:halt, socket}
    end
  end

  @doc """
  Assigns current organization from user data or loads from database.
  """
  def mount_current_org(_params, _session, socket) do
    socket =
      case socket.assigns do
        %{current_user: %{} = user, current_org: nil} ->
          case AuthHelpers.ensure_user_organization(user) do
            {:ok, org} ->
              assign(socket, :current_org, org)

            {:error, reason} ->
              Logger.warning(
                "Failed to load organization for user #{user.id}: #{inspect(reason)}"
              )

              socket
          end

        %{current_org: %{}} ->
          socket

        _ ->
          socket
      end

    {:cont, socket}
  end

  # Private helper functions

  # Organization helpers are delegated to LangWeb.AuthHelpers

  defp assign_development_user(socket) do
    if Mix.env() in [:dev, :test] do
      dev_user = %{
        id: "dev_user_#{:rand.uniform(10000)}",
        email: "dev@lang.local",
        name: "Development User",
        subscription_tier: :pro,
        organization_id: "dev_org_stub"
      }

      dev_org = %{
        id: "dev_org_#{:rand.uniform(10000)}",
        name: "Development Organization",
        plan: :pro,
        subscription_status: :active,
        owner_id: dev_user.id
      }

      socket
      |> assign(:current_user, dev_user)
      |> assign(:current_org, dev_org)
      |> assign(:current_scope, %{type: :development, id: "dev"})
      |> assign(:authenticated?, false)
    else
      socket
      |> assign(:current_user, nil)
      |> assign(:current_org, nil)
      |> assign(:current_scope, %{type: :guest, id: nil})
      |> assign(:authenticated?, false)
    end
  end
end
