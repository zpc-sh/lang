defmodule LangWeb.AuthOnMount do
  @moduledoc """
  LiveView on_mount hooks for assigning current_user and enforcing authentication.

  This module stubs the logic for now: in non-prod environments, it will
  assign a development user and organization to allow flows to render.
  In production, unauthenticated users are redirected to /auth.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  @doc """
  Assigns a current_user and current_scope.

  In dev/test, if no user is present in the session, assigns a stub user.
  """
  def mount_current_user(params, session, socket) do
    socket =
      case Map.get(session, "current_user") do
        %{} = user ->
          assign(socket, current_user: user, current_scope: :user)

        _ ->
          if Mix.env() in [:dev, :test] do
            dev_user = %{
              id: "dev_user_stub",
              email: "dev@example.com",
              name: "Development User",
              organization_id: "dev_org_stub"
            }

            assign(socket, current_user: dev_user, current_scope: :user)
          else
            socket
          end
      end

    {:cont, socket}
  end

  @doc """
  Requires authentication for the LiveView. Redirects to /auth if no user.
  """
  def require_authenticated(_params, _session, socket) do
    case socket.assigns do
      %{current_user: %{} = _user} -> {:cont, socket}
      _ ->
        if Mix.env() in [:dev, :test] do
          {:cont, socket}
        else
          {:halt, redirect(socket, to: "/auth")}
        end
    end
  end

  @doc """
  Assigns a current organization stub based on current_user.organization_id.
  """
  def mount_current_org(_params, _session, socket) do
    socket =
      case socket.assigns do
        %{current_user: %{organization_id: org_id}} when is_binary(org_id) ->
          # Stub org assign for now; replace with Ash read in real implementation
          org = %{
            id: org_id,
            name: "Stub Organization",
            plan: :pro,
            subscription_status: :active
          }

          assign(socket, current_org: org)

        _ ->
          socket
      end

    {:cont, socket}
  end
end
