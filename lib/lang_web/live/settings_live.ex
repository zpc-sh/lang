defmodule LangWeb.SettingsLive do
  @moduledoc """
  Settings LiveView for LANG Universal Text Intelligence Platform.

  Uses separate components for each settings section and handles
  inter-component communication via LiveView messages.
  """

  use LangWeb, :live_view
  alias Lang.Accounts.{User, Organization}
  alias LangWeb.SettingsLive.{ProfileComponent, SecurityComponent, OrganizationComponent}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization = socket.assigns.current_org

    # Load user with associations
    case User.by_id(user.id) |> Ash.Query.load([:organization, :api_keys]) |> Ash.read_one() do
      {:ok, loaded_user} ->
        {:ok,
         socket
         |> assign(:page_title, "Settings")
         |> assign(:active_tab, "profile")
         |> assign(:user, loaded_user)
         |> assign(:organization, organization)
         |> assign(:api_keys, loaded_user.api_keys || [])
         |> assign(:member_count, 1)
         |> assign(:api_key_count, length(loaded_user.api_keys || []))}

      {:error, error} ->
        require Logger
        Logger.error("Failed to load user data: #{inspect(error)}")

        {:ok,
         socket
         |> put_flash(:error, "Failed to load settings data.")
         |> assign(:page_title, "Settings")
         |> assign(:user, user)
         |> assign(:organization, organization)
         |> assign(:api_keys, [])
         |> assign(:member_count, 0)
         |> assign(:api_key_count, 0)}
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  # Handle component messages
  @impl true
  def handle_info({:profile_updated, updated_user}, socket) do
    {:noreply, assign(socket, :user, updated_user)}
  end

  def handle_info({:organization_updated, updated_org}, socket) do
    {:noreply, assign(socket, :organization, updated_org)}
  end

  def handle_info({:api_keys_updated}, socket) do
    # Reload API keys
    case User.by_id(socket.assigns.user.id) |> Ash.Query.load([:api_keys]) |> Ash.read_one() do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:api_keys, updated_user.api_keys || [])
         |> assign(:api_key_count, length(updated_user.api_keys || []))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={assigns[:current_user]}
      current_scope={assigns[:current_scope]}
    >
      <div class="max-w-6xl mx-auto px-6 py-8" id="settings-container" phx-hook="ClipboardHook">
        <!-- Header -->
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900 mb-2">Settings</h1>
          <p class="text-gray-600">Manage your account, organization, and API access</p>
        </div>
        
    <!-- Tab Navigation -->
        <div class="border-b border-gray-200 mb-8">
          <nav class="-mb-px flex space-x-8">
            <button
              phx-click="change_tab"
              phx-value-tab="profile"
              class={[
                "whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm",
                (@active_tab == "profile" &&
                   "border-blue-500 text-blue-600") ||
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              <.icon name="hero-user-circle" class="w-5 h-5 inline mr-2" /> Profile
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="security"
              class={[
                "whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm",
                (@active_tab == "security" &&
                   "border-blue-500 text-blue-600") ||
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              <.icon name="hero-lock-closed" class="w-5 h-5 inline mr-2" /> Security
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="organization"
              class={[
                "whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm",
                (@active_tab == "organization" &&
                   "border-blue-500 text-blue-600") ||
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              <.icon name="hero-building-office" class="w-5 h-5 inline mr-2" /> Organization
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="billing"
              class={[
                "whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm",
                (@active_tab == "billing" &&
                   "border-blue-500 text-blue-600") ||
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              <.icon name="hero-credit-card" class="w-5 h-5 inline mr-2" /> Billing
            </button>
          </nav>
        </div>
        
    <!-- Tab Content -->
        <div>
          <%= case @active_tab do %>
            <% "profile" -> %>
              <.live_component
                module={ProfileComponent}
                id="profile-component"
                user={@user}
              />
            <% "security" -> %>
              <.live_component
                module={SecurityComponent}
                id="security-component"
                user={@user}
                organization={@organization}
                api_keys={@api_keys}
              />
            <% "organization" -> %>
              <.live_component
                module={OrganizationComponent}
                id="organization-component"
                user={@user}
                organization={@organization}
                member_count={@member_count}
                api_key_count={@api_key_count}
              />
            <% "billing" -> %>
              <div class="space-y-8">
                <!-- Current Plan -->
                <div class="bg-white rounded-lg border p-6">
                  <div class="mb-6">
                    <h2 class="text-xl font-semibold text-gray-900">Current Plan</h2>
                    <p class="text-sm text-gray-600">
                      Manage your subscription and billing information.
                    </p>
                  </div>

                  <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                    <div>
                      <h3 class="font-semibold text-gray-900 text-lg">
                        {String.upcase(to_string(@user.subscription_tier))} Plan
                      </h3>
                      <p class="text-gray-600">
                        {@user.monthly_request_limit} API requests per month
                      </p>
                    </div>
                    <div class="text-right">
                      <div class="text-2xl font-bold text-gray-900">
                        <%= case @user.subscription_tier do %>
                          <% :free -> %>
                            $0
                          <% :professional -> %>
                            $29
                          <% :enterprise -> %>
                            $99
                          <% _ -> %>
                            $0
                        <% end %>
                      </div>
                      <div class="text-sm text-gray-600">/month</div>
                    </div>
                  </div>

                  <div class="mt-6 flex justify-center">
                    <button
                      class="px-6 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50"
                      disabled
                    >
                      Upgrade Plan (Coming Soon)
                    </button>
                  </div>
                </div>
                
    <!-- Usage Details -->
                <div class="bg-white rounded-lg border p-6">
                  <h3 class="text-lg font-semibold text-gray-900 mb-4">Usage This Month</h3>

                  <div class="mb-4">
                    <div class="flex justify-between text-sm text-gray-600 mb-2">
                      <span>API Requests</span>
                      <span>{@user.monthly_request_count} / {@user.monthly_request_limit}</span>
                    </div>
                    <div class="w-full bg-gray-200 rounded-full h-2">
                      <div
                        class={[
                          "h-2 rounded-full transition-all duration-300",
                          usage_bar_class(usage_percentage(@user))
                        ]}
                        style={"width: #{usage_percentage(@user)}%"}
                      >
                      </div>
                    </div>
                  </div>

                  <div class="text-sm text-gray-600">
                    <p>
                      Usage resets on:
                      <%= if @user.last_request_reset do %>
                        {@user.last_request_reset
                        |> DateTime.add(30, :day)
                        |> DateTime.to_date()
                        |> Date.to_string()}
                      <% else %>
                        End of month
                      <% end %>
                    </p>
                  </div>
                </div>
                
    <!-- Billing History Placeholder -->
                <div class="bg-white rounded-lg border p-6">
                  <h3 class="text-lg font-semibold text-gray-900 mb-4">Billing History</h3>
                  <div class="text-center py-8">
                    <.icon name="hero-document-text" class="w-12 h-12 text-gray-400 mx-auto mb-4" />
                    <p class="text-gray-600">No billing history yet</p>
                    <p class="text-sm text-gray-500">
                      Your invoices and payment history will appear here.
                    </p>
                  </div>
                </div>
              </div>
            <% _ -> %>
              <div class="bg-white rounded-lg border p-6">
                <p class="text-gray-600">Select a settings tab to continue.</p>
              </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp usage_percentage(user) do
    if user.monthly_request_limit > 0 do
      percentage = user.monthly_request_count / user.monthly_request_limit * 100
      min(percentage, 100) |> Float.round(1)
    else
      0.0
    end
  end

  defp usage_bar_class(percentage) do
    cond do
      percentage >= 90 -> "bg-red-500"
      percentage >= 75 -> "bg-yellow-500"
      true -> "bg-green-500"
    end
  end
end
