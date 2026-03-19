defmodule LangWeb.SettingsLive.ProfileComponent do
  @moduledoc """
  Profile management component for user settings.

  Handles profile information updates and usage statistics display.
  """

  use LangWeb, :live_component
  alias Lang.Accounts.User
  alias Lang.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <!-- Profile Information -->
      <div class="bg-white rounded-lg border p-6">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h2 class="text-xl font-semibold text-gray-900">Profile Information</h2>
            <p class="text-sm text-gray-600">Update your account profile information.</p>
          </div>
          <div class={[
            "px-3 py-1 rounded-full text-xs font-medium",
            subscription_badge_class(@user.subscription_tier)
          ]}>
            {String.upcase(to_string(@user.subscription_tier))}
          </div>
        </div>

        <.form
          for={@form}
          id="profile-form"
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <.input
                field={@form[:name]}
                type="text"
                label="Full Name"
                placeholder="Enter your full name"
                required
              />
            </div>
            <div>
              <.input
                field={@form[:email]}
                type="email"
                label="Email Address"
                placeholder="Enter your email address"
                required
              />
            </div>
          </div>

          <div class="mt-6 flex justify-end">
            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50"
              disabled={!@form.valid?}
            >
              Save Profile
            </button>
          </div>
        </.form>
      </div>
      
    <!-- Usage Statistics -->
      <div class="bg-white rounded-lg border p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Usage Statistics</h3>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div class="text-center">
            <div class="text-2xl font-bold text-blue-600">{@user.monthly_request_count}</div>
            <div class="text-sm text-gray-600">Requests This Month</div>
          </div>
          <div class="text-center">
            <div class="text-2xl font-bold text-green-600">{@user.monthly_request_limit}</div>
            <div class="text-sm text-gray-600">Monthly Limit</div>
          </div>
          <div class="text-center">
            <div class="text-2xl font-bold text-orange-600">{usage_percentage(@user)}%</div>
            <div class="text-sm text-gray-600">Usage</div>
          </div>
        </div>
        
    <!-- Usage Bar -->
        <div class="mt-4">
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
      </div>
    </div>
    """
  end

  @impl true
  def update(%{user: user} = assigns, socket) do
    form = create_form(user)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    form = create_form(socket.assigns.user, params)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"user" => params}, socket) do
    case User.update_profile(socket.assigns.user, params) do
      {:ok, updated_user} ->
        Events.track_event(%{
          event_type: "user_profile_updated",
          user_id: updated_user.id,
          metadata: %{
            changes: Map.keys(params),
            ip_address: get_connect_ip(socket)
          }
        })

        send(self(), {:profile_updated, updated_user})

        {:noreply,
         socket
         |> put_flash(:info, "Profile updated successfully!")
         |> assign(:user, updated_user)
         |> assign(:form, create_form(updated_user))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to update profile. Please check the errors below.")
         |> assign(:form, changeset)}
    end
  end

  defp create_form(user, params \\ %{}) do
    AshPhoenix.Form.for_action(user, :update_profile, params)
  end

  defp subscription_badge_class(tier) do
    case tier do
      :free -> "bg-gray-100 text-gray-800"
      :professional -> "bg-blue-100 text-blue-800"
      :enterprise -> "bg-purple-100 text-purple-800"
      _ -> "bg-gray-100 text-gray-800"
    end
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

  defp get_connect_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: {a, b, c, d}} -> "#{a}.#{b}.#{c}.#{d}"
      _ -> "unknown"
    end
  end
end
