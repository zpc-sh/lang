defmodule LangWeb.AuthOnMount do
  @moduledoc """
  LiveView on_mount hooks for assigning current_user and enforcing authentication.

  This module integrates with the AuthPlug system to provide consistent
  authentication across LiveViews and regular controllers.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias LangWeb.Plugs.AuthPlug
  alias Lang.Accounts.User
  alias Lang.Events
  require Logger

  @doc """
  Assigns current_user and current_scope from session or creates development user.
  """
  def mount_current_user(_params, session, socket) do
    socket =
      case get_user_from_session(session) do
        {:ok, user, org} ->
          socket
          |> assign(:current_user, user)
          |> assign(:current_org, org)
          |> assign(:current_scope, :user)
          |> assign(:authenticated?, true)

        {:error, :not_found} ->
          # Session references non-existent user, clear it
          assign_development_user(socket)

        {:error, _reason} ->
          assign_development_user(socket)

        :no_session ->
          assign_development_user(socket)
      end

    {:cont, socket}
  end

  @doc """
  Requires authentication for the LiveView. Redirects to /auth if no user.
  """
  def require_authenticated(_params, _session, socket) do
    case socket.assigns do
      %{authenticated?: true, current_user: %{}} ->
        {:cont, socket}

      %{current_scope: :development} ->
        if Application.get_env(:lang, :env) in [:dev, :test] do
          {:cont, socket}
        else
          Logger.info("Unauthenticated access to protected LiveView")
          {:halt, redirect(socket, to: "/auth")}
        end

      _ ->
        Logger.info("Unauthenticated access to protected LiveView")
        {:halt, redirect(socket, to: "/auth")}
    end
  end

  @doc """
  Assigns current organization from user data or loads from database.
  """
  def mount_current_org(_params, _session, socket) do
    socket =
      case socket.assigns do
        %{current_user: %{} = user, current_org: nil} ->
          case load_user_organization(user) do
            {:ok, org} ->
              assign(socket, :current_org, org)

            {:error, reason} ->
              Logger.warning(
                "Failed to load organization for user #{user.id}: #{inspect(reason)}"
              )

              socket
          end

        %{current_org: %{}} ->
          # Organization already assigned
          socket

        _ ->
          # No user or organization context
          socket
      end

    {:cont, socket}
  end

  # Private helper functions

  defp get_user_from_session(session) do
    case Map.get(session, "current_user_id") do
      nil ->
        :no_session

      user_id when is_binary(user_id) ->
        load_user_with_org(user_id)

      _ ->
        {:error, :invalid_session}
    end
  end

  defp load_user_with_org(user_id) do
    import Ash.Query

    case User
         |> Ash.Query.filter(id == ^user_id)
         |> Ash.Query.load([:organization])
         |> Ash.read_one() do
      {:ok, %{organization: org} = user} when not is_nil(org) ->
        {:ok, user, org}

      {:ok, user} ->
        # User exists but no organization
        case create_default_organization(user) do
          {:ok, org} -> {:ok, user, org}
          error -> error
        end

      {:error, _} = error ->
        error

      nil ->
        {:error, :not_found}
    end
  end

  defp load_user_organization(%{organization_id: org_id}) when is_binary(org_id) do
    import Ash.Query

    case Lang.Accounts.Organization
         |> Ash.Query.filter(id == ^org_id)
         |> Ash.read_one() do
      {:ok, org} -> {:ok, org}
      error -> error
    end
  end

  defp load_user_organization(%{id: user_id}) do
    # Load organization through user relationship
    import Ash.Query

    case User
         |> Ash.Query.filter(id == ^user_id)
         |> Ash.Query.load([:organization])
         |> Ash.read_one() do
      {:ok, %{organization: org}} when not is_nil(org) ->
        {:ok, org}

      {:ok, user} ->
        create_default_organization(user)

      error ->
        error
    end
  end

  defp create_default_organization(user) do
    Lang.Accounts.Organization.create(%{
      name: "#{user.name}'s Organization",
      owner_id: user.id,
      plan: :free,
      subscription_status: :trial
    })
  end

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
      |> assign(:current_scope, :development)
      |> assign(:authenticated?, false)
    else
      socket
      |> assign(:current_user, nil)
      |> assign(:current_org, nil)
      |> assign(:current_scope, :guest)
      |> assign(:authenticated?, false)
    end
  end
end
