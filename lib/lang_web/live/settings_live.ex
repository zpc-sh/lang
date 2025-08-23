defmodule LangWeb.SettingsLive do
  @moduledoc """
  Settings LiveView (stub)

  Provides placeholders for Profile, Security, Organization, and Billing settings.
  """

  use LangWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_tab, "profile")}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end
end

