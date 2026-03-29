defmodule LangWeb.SettingsLive.SecurityComponent do
  @moduledoc """
  Security management component for user settings.

  Handles password changes and API key management.
  """

  use LangWeb, :live_component
  alias Lang.Accounts.{User, ApiKey}
  alias Lang.Events

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <!-- Change Password -->
      <div class="bg-white rounded-lg border p-6">
        <div class="mb-6">
          <h2 class="text-xl font-semibold text-gray-900">Change Password</h2>
          <p class="text-sm text-gray-600">Update your password to keep your account secure.</p>
        </div>

        <.form
          for={@password_form}
          id="password-form"
          phx-change="validate_password"
          phx-submit="change_password"
          phx-target={@myself}
        >
          <div class="space-y-4">
            <div>
              <.input
                field={@password_form[:current_password]}
                type="password"
                label="Current Password"
                placeholder="Enter your current password"
                required
              />
            </div>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <.input
                  field={@password_form[:password]}
                  type="password"
                  label="New Password"
                  placeholder="Enter new password"
                  required
                />
              </div>
              <div>
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password"
                  label="Confirm New Password"
                  placeholder="Confirm new password"
                  required
                />
              </div>
            </div>
          </div>

          <div class="mt-6 flex justify-end">
            <button
              type="submit"
              class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:opacity-50"
              disabled={!@password_form.valid?}
            >
              Change Password
            </button>
          </div>
        </.form>
      </div>
      
    <!-- API Key Management -->
      <div class="bg-white rounded-lg border p-6">
        <div class="flex items-center justify-between mb-6">
          <div>
            <h2 class="text-xl font-semibold text-gray-900">API Keys</h2>
            <p class="text-sm text-gray-600">Manage API keys for programmatic access to LANG.</p>
          </div>
          <%= if not @show_api_key_form do %>
            <button
              phx-click="show_api_key_form"
              phx-target={@myself}
              class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
            >
              <.icon name="hero-plus" class="w-4 h-4 inline mr-2" /> New API Key
            </button>
          <% end %>
        </div>
        
    <!-- New API Key Generated Alert -->
        <%= if @generated_api_key do %>
          <div class="mb-6 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
            <div class="flex items-start">
              <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-yellow-400 mt-0.5 mr-3" />
              <div class="flex-1">
                <h3 class="text-sm font-medium text-yellow-800">New API Key Generated</h3>
                <p class="text-sm text-yellow-700 mt-1">
                  Copy this key now - you won't be able to see it again.
                </p>
                <div class="mt-3 bg-white p-3 rounded border">
                  <code class="text-sm font-mono text-gray-900 break-all" id="generated-key">
                    {@generated_api_key.key}
                  </code>
                </div>
                <div class="mt-3 flex space-x-3">
                  <button
                    phx-click="copy_api_key"
                    phx-value-key={@generated_api_key.key}
                    phx-target={@myself}
                    class="text-sm bg-yellow-100 text-yellow-800 px-3 py-1 rounded hover:bg-yellow-200"
                  >
                    Copy Key
                  </button>
                  <button
                    phx-click="dismiss_generated_key"
                    phx-target={@myself}
                    class="text-sm text-yellow-600 hover:text-yellow-800"
                  >
                    Dismiss
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>
        
    <!-- API Key Creation Form -->
        <%= if @show_api_key_form do %>
          <div class="mb-6 p-4 bg-gray-50 border border-gray-200 rounded-lg">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Create New API Key</h3>

            <.form
              for={@api_key_form}
              id="api-key-form"
              phx-change="validate_api_key"
              phx-submit="create_api_key"
              phx-target={@myself}
            >
              <div class="space-y-4">
                <div>
                  <.input
                    field={@api_key_form[:name]}
                    type="text"
                    label="API Key Name"
                    placeholder="e.g., Production App, Development Testing"
                    required
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">
                    Permissions (Scopes)
                  </label>
                  <div class="space-y-2">
                    <label class="flex items-center">
                      <input
                        type="checkbox"
                        name="api_key[scopes][]"
                        value="read"
                        checked
                        class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                      <span class="ml-2 text-sm text-gray-700">Read access</span>
                    </label>
                    <label class="flex items-center">
                      <input
                        type="checkbox"
                        name="api_key[scopes][]"
                        value="write"
                        checked
                        class="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                      />
                      <span class="ml-2 text-sm text-gray-700">Write access</span>
                    </label>
                  </div>
                </div>
              </div>

              <div class="mt-4 flex justify-end space-x-3">
                <button
                  type="button"
                  phx-click="hide_api_key_form"
                  phx-target={@myself}
                  class="px-4 py-2 text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50"
                  disabled={!@api_key_form.valid?}
                >
                  Create API Key
                </button>
              </div>
            </.form>
          </div>
        <% end %>
        
    <!-- API Keys List -->
        <div class="space-y-4">
          <%= if length(@api_keys) == 0 do %>
            <div class="text-center py-8">
              <.icon name="hero-key" class="w-12 h-12 text-gray-400 mx-auto mb-4" />
              <p class="text-gray-600">No API keys yet</p>
              <p class="text-sm text-gray-500">Create your first API key to get started.</p>
            </div>
          <% else %>
            <%= for api_key <- @api_keys do %>
              <div class="flex items-center justify-between p-4 border border-gray-200 rounded-lg">
                <div class="flex-1">
                  <div class="flex items-center space-x-3">
                    <h4 class="font-medium text-gray-900">{api_key.name}</h4>
                    <span class={[
                      "px-2 py-1 text-xs font-medium rounded",
                      if(api_key.status == :active,
                        do: "bg-green-100 text-green-800",
                        else: "bg-red-100 text-red-800"
                      )
                    ]}>
                      {if api_key.status == :active, do: "Active", else: "Revoked"}
                    </span>
                  </div>
                  <div class="mt-1 text-sm text-gray-600">
                    <span class="font-mono">{format_api_key(api_key.key)}</span>
                    <span class="ml-4">Created: {format_created_at(api_key.inserted_at)}</span>
                  </div>
                  <%= if api_key.scopes do %>
                    <div class="mt-1">
                      <%= for scope <- api_key.scopes do %>
                        <span class="inline-block px-2 py-1 text-xs bg-blue-100 text-blue-800 rounded mr-2">
                          {scope}
                        </span>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <%= if api_key.status == :active do %>
                  <button
                    phx-click="revoke_api_key"
                    phx-value-id={api_key.id}
                    phx-target={@myself}
                    data-confirm="Are you sure you want to revoke this API key? This action cannot be undone."
                    class="px-3 py-1 text-sm text-red-600 hover:text-red-800 border border-red-200 hover:border-red-300 rounded"
                  >
                    Revoke
                  </button>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    password_form = create_password_form()
    api_key_form = create_api_key_form()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:password_form, password_form)
     |> assign(:api_key_form, api_key_form)
     |> assign(:show_api_key_form, false)
     |> assign(:generated_api_key, nil)}
  end

  @impl true
  def handle_event("validate_password", %{"user" => params}, socket) do
    form = create_password_form(params)
    {:noreply, assign(socket, :password_form, form)}
  end

  @impl true
  def handle_event("change_password", %{"user" => params}, socket) do
    case User.change_password(socket.assigns.user, params) do
      {:ok, _updated_user} ->
        Events.track_event(%{
          event_type: "user_password_changed",
          user_id: socket.assigns.user.id,
          metadata: %{ip_address: get_connect_ip(socket)}
        })

        {:noreply,
         socket
         |> put_flash(:info, "Password changed successfully!")
         |> assign(:password_form, create_password_form())}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to change password. Please check the errors below.")
         |> assign(:password_form, changeset)}
    end
  end

  @impl true
  def handle_event("show_api_key_form", _params, socket) do
    {:noreply, assign(socket, :show_api_key_form, true)}
  end

  @impl true
  def handle_event("hide_api_key_form", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_api_key_form, false)
     |> assign(:api_key_form, create_api_key_form())}
  end

  @impl true
  def handle_event("validate_api_key", %{"api_key" => params}, socket) do
    form = create_api_key_form(params)
    {:noreply, assign(socket, :api_key_form, form)}
  end

  @impl true
  def handle_event("create_api_key", %{"api_key" => params}, socket) do
    api_key_params =
      Map.merge(params, %{
        "user_id" => socket.assigns.user.id,
        "organization_id" => socket.assigns.organization.id
      })

    case ApiKey.create(api_key_params) do
      {:ok, api_key} ->
        Events.track_event(%{
          event_type: "api_key_created",
          user_id: socket.assigns.user.id,
          organization_id: socket.assigns.organization.id,
          metadata: %{
            api_key_name: api_key.name,
            scopes: api_key.scopes,
            ip_address: get_connect_ip(socket)
          }
        })

        send(self(), {:api_keys_updated})

        {:noreply,
         socket
         |> put_flash(:info, "API key created successfully!")
         |> assign(:show_api_key_form, false)
         |> assign(:api_key_form, create_api_key_form())
         |> assign(:generated_api_key, api_key)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create API key. Please check the errors below.")
         |> assign(:api_key_form, changeset)}
    end
  end

  @impl true
  def handle_event("revoke_api_key", %{"id" => api_key_id}, socket) do
    case ApiKey.by_id(api_key_id) |> Ash.read_one() do
      {:ok, api_key} ->
        case ApiKey.revoke(api_key) do
          {:ok, _revoked_key} ->
            Events.track_event(%{
              event_type: "api_key_revoked",
              user_id: socket.assigns.user.id,
              organization_id: socket.assigns.organization.id,
              metadata: %{
                api_key_name: api_key.name,
                ip_address: get_connect_ip(socket)
              }
            })

            send(self(), {:api_keys_updated})

            {:noreply,
             socket
             |> put_flash(:info, "API key revoked successfully.")}

          {:error, _error} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to revoke API key.")}
        end

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "API key not found.")}
    end
  end

  @impl true
  def handle_event("copy_api_key", %{"key" => key}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "API key copied to clipboard!")
     |> push_event("copy-to-clipboard", %{text: key})}
  end

  @impl true
  def handle_event("dismiss_generated_key", _params, socket) do
    {:noreply, assign(socket, :generated_api_key, nil)}
  end

  defp create_password_form(params \\ %{}) do
    AshPhoenix.Form.for_action(User, :change_password, params)
  end

  defp create_api_key_form(params \\ %{}) do
    AshPhoenix.Form.for_action(ApiKey, :create, params)
  end

  defp format_api_key(key) do
    if String.length(key) > 8 do
      prefix = String.slice(key, 0, 8)
      "#{prefix}..." <> String.duplicate("*", 12)
    else
      key
    end
  end

  defp format_created_at(datetime) do
    if datetime do
      datetime
      |> DateTime.to_date()
      |> Date.to_string()
    else
      "Unknown"
    end
  end

  defp get_connect_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: {a, b, c, d}} -> "#{a}.#{b}.#{c}.#{d}"
      _ -> "unknown"
    end
  end
end
