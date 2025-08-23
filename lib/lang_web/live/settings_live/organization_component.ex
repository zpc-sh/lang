defmodule LangWeb.SettingsLive.OrganizationComponent do
  @moduledoc """
  Organization management component for user settings.

  Handles organization information updates and statistics display.
  """

  use LangWeb, :live_component
  alias Lang.Accounts.Organization
  alias Lang.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%= if @organization do %>
        <!-- Organization Information -->
        <div class="bg-white rounded-lg border p-6">
          <div class="mb-6">
            <h2 class="text-xl font-semibold text-gray-900">Organization Information</h2>
            <p class="text-sm text-gray-600">Update your organization details and settings.</p>
          </div>

          <.form
            for={@form}
            id="org-form"
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
          >
            <div class="space-y-4">
              <div>
                <.input
                  field={@form[:name]}
                  type="text"
                  label="Organization Name"
                  placeholder="Enter organization name"
                  required
                />
              </div>
              <div>
                <.input
                  field={@form[:billing_email]}
                  type="email"
                  label="Billing Email"
                  placeholder="Enter billing email address"
                />
              </div>
              <div>
                <.input
                  field={@form[:slug]}
                  type="text"
                  label="Organization Slug"
                  placeholder="organization-slug"
                  disabled
                  help_text="Used in API endpoints and URLs"
                />
              </div>
            </div>

            <div class="mt-6 flex justify-end">
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50"
                disabled={!@form.valid?}
              >
                Save Organization
              </button>
            </div>
          </.form>
        </div>
        
    <!-- Organization Statistics -->
        <div class="bg-white rounded-lg border p-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-4">Organization Statistics</h3>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div class="text-center">
              <div class="text-2xl font-bold text-blue-600">{@member_count}</div>
              <div class="text-sm text-gray-600">Active Members</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold text-green-600">{@api_key_count}</div>
              <div class="text-sm text-gray-600">API Keys</div>
            </div>
            <div class="text-center">
              <div class="text-2xl font-bold text-orange-600">
                {days_active(@organization)}
              </div>
              <div class="text-sm text-gray-600">Days Active</div>
            </div>
          </div>
        </div>
        
    <!-- Organization Subscription -->
        <div class="bg-white rounded-lg border p-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-4">Subscription Details</h3>
          <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
            <div>
              <div class="flex items-center space-x-3">
                <h4 class="font-semibold text-gray-900">
                  {String.upcase(to_string(@organization.subscription_tier))} Plan
                </h4>
                <span class={[
                  "px-2 py-1 text-xs font-medium rounded",
                  subscription_badge_class(@organization.subscription_tier)
                ]}>
                  {subscription_status_text(@organization.subscription_status)}
                </span>
              </div>
              <p class="text-sm text-gray-600 mt-1">
                {subscription_description(@organization.subscription_tier)}
              </p>
            </div>
            <div class="text-right">
              <div class="text-lg font-bold text-gray-900">
                {subscription_price(@organization.subscription_tier)}
              </div>
              <div class="text-sm text-gray-600">/month</div>
            </div>
          </div>
        </div>
        
    <!-- Organization Settings -->
        <div class="bg-white rounded-lg border p-6">
          <h3 class="text-lg font-semibold text-gray-900 mb-4">Organization Settings</h3>
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <div>
                <label class="text-sm font-medium text-gray-700">API Rate Limiting</label>
                <p class="text-sm text-gray-500">Enable rate limiting for API requests</p>
              </div>
              <button
                type="button"
                class={[
                  "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
                  if(@organization.rate_limiting_enabled,
                    do: "bg-blue-600",
                    else: "bg-gray-200"
                  )
                ]}
                role="switch"
                aria-checked={@organization.rate_limiting_enabled || false}
                phx-click="toggle_rate_limiting"
                phx-target={@myself}
              >
                <span class={[
                  "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                  if(@organization.rate_limiting_enabled,
                    do: "translate-x-5",
                    else: "translate-x-0"
                  )
                ]}>
                </span>
              </button>
            </div>

            <div class="flex items-center justify-between">
              <div>
                <label class="text-sm font-medium text-gray-700">Usage Analytics</label>
                <p class="text-sm text-gray-500">Track detailed usage analytics</p>
              </div>
              <button
                type="button"
                class={[
                  "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
                  if(@organization.analytics_enabled,
                    do: "bg-blue-600",
                    else: "bg-gray-200"
                  )
                ]}
                role="switch"
                aria-checked={@organization.analytics_enabled || false}
                phx-click="toggle_analytics"
                phx-target={@myself}
              >
                <span class={[
                  "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                  if(@organization.analytics_enabled,
                    do: "translate-x-5",
                    else: "translate-x-0"
                  )
                ]}>
                </span>
              </button>
            </div>
          </div>
        </div>
      <% else %>
        <!-- No Organization -->
        <div class="bg-white rounded-lg border p-6">
          <div class="text-center py-8">
            <.icon name="hero-building-office" class="w-12 h-12 text-gray-400 mx-auto mb-4" />
            <h3 class="text-lg font-semibold text-gray-900 mb-2">No Organization</h3>
            <p class="text-gray-600 mb-4">
              You don't have an organization associated with your account.
            </p>
            <p class="text-sm text-gray-500">
              Contact support to set up an organization for your account.
            </p>
            <div class="mt-6">
              <button
                type="button"
                class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
                disabled
              >
                Contact Support (Coming Soon)
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    form =
      if assigns.organization do
        create_form(assigns.organization)
      else
        nil
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"organization" => params}, socket) do
    form = create_form(socket.assigns.organization, params)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"organization" => params}, socket) do
    case Organization.update(socket.assigns.organization, params) do
      {:ok, updated_org} ->
        Events.track_event(%{
          event_type: "organization_updated",
          user_id: socket.assigns.user.id,
          organization_id: updated_org.id,
          metadata: %{
            changes: Map.keys(params),
            ip_address: get_connect_ip(socket)
          }
        })

        send(self(), {:organization_updated, updated_org})

        {:noreply,
         socket
         |> put_flash(:info, "Organization updated successfully!")
         |> assign(:organization, updated_org)
         |> assign(:form, create_form(updated_org))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to update organization. Please check the errors below.")
         |> assign(:form, changeset)}
    end
  end

  @impl true
  def handle_event("toggle_rate_limiting", _params, socket) do
    current_value = socket.assigns.organization.rate_limiting_enabled || false

    case Organization.update(socket.assigns.organization, %{rate_limiting_enabled: !current_value}) do
      {:ok, updated_org} ->
        Events.track_event(%{
          event_type: "organization_rate_limiting_toggled",
          user_id: socket.assigns.user.id,
          organization_id: updated_org.id,
          metadata: %{
            enabled: !current_value,
            ip_address: get_connect_ip(socket)
          }
        })

        send(self(), {:organization_updated, updated_org})

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Rate limiting #{if !current_value, do: "enabled", else: "disabled"}."
         )
         |> assign(:organization, updated_org)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to update rate limiting setting.")}
    end
  end

  @impl true
  def handle_event("toggle_analytics", _params, socket) do
    current_value = socket.assigns.organization.analytics_enabled || false

    case Organization.update(socket.assigns.organization, %{analytics_enabled: !current_value}) do
      {:ok, updated_org} ->
        Events.track_event(%{
          event_type: "organization_analytics_toggled",
          user_id: socket.assigns.user.id,
          organization_id: updated_org.id,
          metadata: %{
            enabled: !current_value,
            ip_address: get_connect_ip(socket)
          }
        })

        send(self(), {:organization_updated, updated_org})

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Usage analytics #{if !current_value, do: "enabled", else: "disabled"}."
         )
         |> assign(:organization, updated_org)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to update analytics setting.")}
    end
  end

  defp create_form(organization, params \\ %{}) do
    AshPhoenix.Form.for_action(organization, :update, params)
  end

  defp days_active(organization) do
    if organization.inserted_at do
      Date.diff(Date.utc_today(), DateTime.to_date(organization.inserted_at))
    else
      0
    end
  end

  defp subscription_badge_class(tier) do
    case tier do
      :free -> "bg-gray-100 text-gray-800"
      :professional -> "bg-blue-100 text-blue-800"
      :enterprise -> "bg-purple-100 text-purple-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp subscription_status_text(status) do
    case status do
      :active -> "Active"
      :canceled -> "Canceled"
      :past_due -> "Past Due"
      :unpaid -> "Unpaid"
      :trialing -> "Trial"
      _ -> "Unknown"
    end
  end

  defp subscription_description(tier) do
    case tier do
      :free -> "Basic features with limited API requests"
      :professional -> "Advanced features with higher API limits"
      :enterprise -> "Full features with unlimited API requests"
      _ -> "Basic plan"
    end
  end

  defp subscription_price(tier) do
    case tier do
      :free -> "$0"
      :professional -> "$29"
      :enterprise -> "$99"
      _ -> "$0"
    end
  end

  defp get_connect_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: {a, b, c, d}} -> "#{a}.#{b}.#{c}.#{d}"
      _ -> "unknown"
    end
  end
end
