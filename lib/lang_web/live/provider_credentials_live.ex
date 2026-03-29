defmodule LangWeb.ProviderCredentialsLive do
  use LangWeb, :live_view
  import Ash.Query

  alias Lang.Accounts.ProviderCredential
  alias LangWeb.AuthHelpers

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    current_org = socket.assigns[:current_org]

    providers = [:openai, :anthropic, :xai, :gemini]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:current_org, current_org)
      |> assign(:providers, providers)
      |> assign(:creds, list_org_credentials(current_org))
      |> assign(:form, empty_form())

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"cred" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :cred))}
  end

  @impl true
  def handle_event("save", %{"cred" => params}, socket) do
    org = socket.assigns.current_org
    provider = params["provider"] |> String.to_existing_atom()
    default? = Map.get(params, "default", "false") in [true, "true", "on", "1"]
    scopes = Map.get(params, "scopes", "") |> parse_scopes()

    attrs = %{
      provider: provider,
      organization_id: org.id,
      default: default?,
      scopes: scopes,
      api_key: Map.get(params, "api_key", "")
    }

    case ProviderCredential.create(attrs) do
      {:ok, _cred} ->
        _ = Lang.Events.track_event(%{
          event_type: "provider_credential_created",
          user_id: socket.assigns.current_user && socket.assigns.current_user.id,
          organization_id: org.id,
          metadata: %{provider: provider}
        })
        {:noreply,
         socket
         |> put_flash(:info, "Credential stored")
         |> assign(:creds, list_org_credentials(org))
         |> assign(:form, empty_form())}

      {:error, %Ash.Error.Invalid{errors: errs}} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(errs)}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("revoke", %{"id" => id}, socket) do
    with {:ok, cred} <- ProviderCredential.by_id(id),
         {:ok, _} <- ProviderCredential.update(cred, %{status: :revoked}) do
      _ = Lang.Events.track_event(%{
        event_type: "provider_credential_revoked",
        user_id: socket.assigns.current_user && socket.assigns.current_user.id,
        organization_id: socket.assigns.current_org && socket.assigns.current_org.id,
        metadata: %{provider: cred.provider, id: cred.id}
      })
      {:noreply, socket |> put_flash(:info, "Credential revoked") |> refresh_creds()}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed to revoke: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("activate", %{"id" => id}, socket) do
    with {:ok, cred} <- ProviderCredential.by_id(id),
         {:ok, _} <- ProviderCredential.update(cred, %{status: :active}) do
      _ = Lang.Events.track_event(%{
        event_type: "provider_credential_activated",
        user_id: socket.assigns.current_user && socket.assigns.current_user.id,
        organization_id: socket.assigns.current_org && socket.assigns.current_org.id,
        metadata: %{provider: cred.provider, id: cred.id}
      })
      {:noreply, socket |> put_flash(:info, "Credential activated") |> refresh_creds()}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed to activate: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("make_default", %{"id" => id}, socket) do
    with {:ok, cred} <- ProviderCredential.by_id(id),
         {:ok, _} <- ProviderCredential.update(cred, %{default: true}) do
      _ = Lang.Events.track_event(%{
        event_type: "provider_credential_defaulted",
        user_id: socket.assigns.current_user && socket.assigns.current_user.id,
        organization_id: socket.assigns.current_org && socket.assigns.current_org.id,
        metadata: %{provider: cred.provider, id: cred.id}
      })
      {:noreply, socket |> put_flash(:info, "Marked as default") |> refresh_creds()}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed to set default: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("rotate", %{"id" => id, "api_key" => api_key} = params, socket) do
    default_flag = Map.get(params, "default", "false")
    default? = default_flag in [true, "true", "on", "1"]
    with {:ok, cred} <- ProviderCredential.by_id(id),
         {:ok, _} <- ProviderCredential.rotate(cred, %{api_key: api_key, default: default?}) do
      _ = Lang.Events.track_event(%{
        event_type: "provider_credential_rotated",
        user_id: socket.assigns.current_user && socket.assigns.current_user.id,
        organization_id: socket.assigns.current_org && socket.assigns.current_org.id,
        metadata: %{provider: cred.provider, id: cred.id, default: default?}
      })
      {:noreply, socket |> put_flash(:info, "Credential rotated") |> refresh_creds()}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Failed to rotate: #{inspect(reason)}")}
    end
  end

  defp refresh_creds(socket) do
    assign(socket, :creds, list_org_credentials(socket.assigns.current_org))
  end

  defp list_org_credentials(nil), do: []
  defp list_org_credentials(org) do
    ProviderCredential
    |> Ash.Query.filter(organization_id == ^org.id)
    |> Ash.Query.sort([inserted_at: :desc])
    |> Ash.read!()
  rescue
    _ -> []
  end

  defp empty_form do
    to_form(%{"provider" => "openai", "api_key" => "", "default" => false, "scopes" => ""}, as: :cred)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto space-y-8">
        <div>
          <h1 class="text-2xl font-semibold">Provider Credentials</h1>
          <p class="text-sm text-zinc-500">Manage API keys per organization. Keys are encrypted at rest.</p>
        </div>

        <.form for={@form} id="provider-credentials-form" phx-submit="save" phx-change="validate">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium">Provider</label>
              <select name="cred[provider]" class="mt-1 block w-full rounded border px-3 py-2">
                <%= for p <- @providers do %>
                  <option value={to_string(p)} selected={@form.params["provider"] == to_string(p)}><%= to_string(p) %></option>
                <% end %>
              </select>
            </div>

            <.input field={@form[:api_key]} type="password" label="API Key" value={@form.params["api_key"]} />

            <.input field={@form[:scopes]} type="text" label="Scopes (comma-separated)" value={@form.params["scopes"]} />

            <div class="flex items-center gap-2">
              <input type="checkbox" name="cred[default]" value="true" checked={@form.params["default"]} />
              <label class="text-sm">Default for provider</label>
            </div>
          </div>

          <div class="mt-4">
            <button class="px-4 py-2 rounded bg-blue-600 text-white">Save Credential</button>
          </div>
        </.form>

        <div>
          <h2 class="text-xl font-semibold mb-2">Existing Credentials</h2>
          <div class="divide-y rounded border">
            <%= if @creds == [] do %>
              <div class="p-4 text-sm text-zinc-500">No credentials yet.</div>
            <% else %>
              <%= for cred <- @creds do %>
                <div class="p-4 flex items-start justify-between gap-4">
                  <div class="space-y-1">
                    <div class="font-medium">
                      <%= cred.provider %>
                      <span :if={cred.default} class="ml-2 text-xs rounded px-2 py-0.5 bg-emerald-100 text-emerald-700">default</span>
                    </div>
                    <div class="text-xs text-zinc-500">
                      status: <%= cred.status %> • usage: <%= cred.usage_count %>
                      <%= if cred.last_used_at do %>
                        • last used: <%= Calendar.strftime(cred.last_used_at, "%Y-%m-%d %H:%M") %>
                      <% end %>
                    </div>
                  </div>
                  <div class="flex-1"></div>
                  <div class="space-y-2 w-80">
                    <div class="flex gap-2 justify-end">
                      <%= if cred.status != :revoked do %>
                        <button phx-click="revoke" phx-value-id={cred.id} class="px-2 py-1 text-xs rounded bg-zinc-200 hover:bg-zinc-300">Revoke</button>
                      <% end %>
                      <%= if cred.status != :active do %>
                        <button phx-click="activate" phx-value-id={cred.id} class="px-2 py-1 text-xs rounded bg-emerald-100 text-emerald-700 hover:bg-emerald-200">Activate</button>
                      <% end %>
                      <%= unless cred.default do %>
                        <button phx-click="make_default" phx-value-id={cred.id} class="px-2 py-1 text-xs rounded bg-blue-600 text-white">Make default</button>
                      <% end %>
                    </div>
                    <.form for={to_form(%{}, as: :rotate)} phx-submit="rotate">
                      <input type="hidden" name="id" value={cred.id} />
                      <div class="flex gap-2 items-center">
                        <input type="password" name="api_key" placeholder="New API key" class="flex-1 rounded border px-2 py-1" />
                        <label class="text-xs flex items-center gap-1">
                          <input type="checkbox" name="default" value="true" /> default
                        </label>
                        <button class="px-2 py-1 text-xs rounded bg-indigo-600 text-white">Rotate</button>
                      </div>
                    </.form>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp parse_scopes(<<>>), do: []
  defp parse_scopes(nil), do: []
  defp parse_scopes(s) when is_binary(s) do
    s
    |> String.split([",", " "], trim: true)
    |> Enum.reject(&(&1 == ""))
  end
end
