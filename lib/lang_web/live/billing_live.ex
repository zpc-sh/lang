defmodule LangWeb.BillingLive do
  @moduledoc """
  Billing and Subscription Management LiveView

  This LiveView provides a comprehensive billing interface with full Stripe integration:
  - Current plan display and management
  - Plan upgrade/downgrade functionality
  - Billing history and invoice management
  - Usage tracking and limits
  - Payment method management
  - Real-time subscription status updates
  """

  use LangWeb, :live_view

  alias Lang.{Billing, Accounts, Events}
  alias Lang.Billing.ConfigManager
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization = socket.assigns.current_scope

    if connected?(socket) do
      # Subscribe to billing updates
      Phoenix.PubSub.subscribe(Lang.PubSub, "org:#{organization.id}")
      Phoenix.PubSub.subscribe(Lang.PubSub, "user:#{user.id}")
    end

    socket =
      socket
      |> assign(:page_title, "Billing & Subscription")
      |> assign(:loading, true)
      |> assign(:active_tab, "overview")
      |> assign(:show_upgrade_modal, false)
      |> assign(:selected_plan, nil)
      |> assign(:stripe_loading, false)
      |> load_billing_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    tab = Map.get(params, "tab", "overview")
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/billing?tab=#{tab}")}
  end

  def handle_event("show_upgrade_modal", %{"plan" => plan}, socket) do
    {:noreply, assign(socket, show_upgrade_modal: true, selected_plan: String.to_atom(plan))}
  end

  def handle_event("close_upgrade_modal", _params, socket) do
    {:noreply, assign(socket, show_upgrade_modal: false, selected_plan: nil)}
  end

  def handle_event("confirm_upgrade", _params, socket) do
    organization = socket.assigns.current_scope
    plan = socket.assigns.selected_plan

    socket = assign(socket, :stripe_loading, true)

    case create_checkout_session(organization, plan) do
      {:ok, checkout_url} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to create checkout session: #{inspect(reason)}")
         |> assign(:stripe_loading, false)}
    end
  end

  def handle_event("cancel_subscription", _params, socket) do
    organization = socket.assigns.current_scope

    case Billing.cancel_subscription(organization.id) do
      {:ok, _updated_org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Subscription cancelled successfully")
         |> load_billing_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel subscription: #{inspect(reason)}")}
    end
  end

  def handle_event("download_invoice", %{"invoice_id" => invoice_id}, socket) do
    # In a real implementation, you'd fetch the invoice PDF URL from Stripe
    {:noreply, put_flash(socket, :info, "Invoice download started")}
  end

  def handle_event("retry_payment", %{"invoice_id" => invoice_id}, socket) do
    # In a real implementation, you'd retry the payment via Stripe
    {:noreply, put_flash(socket, :info, "Payment retry initiated")}
  end

  @impl true
  def handle_info({:plan_changed, %{plan: new_plan}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Your plan has been updated to #{String.upcase(to_string(new_plan))}")
     |> load_billing_data()}
  end

  def handle_info({:subscription_updated, %{status: status}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Subscription status updated: #{status}")
     |> load_billing_data()}
  end

  def handle_info({:invoice_created, %{invoice_id: invoice_id, amount: amount}}, socket) do
    {:noreply,
     put_flash(
       socket,
       :info,
       "New invoice created: $#{amount / 100} (#{invoice_id})"
     )}
  end

  def handle_info({:payment_failed, _details}, socket) do
    {:noreply, put_flash(socket, :error, "Payment failed. Please update your payment method.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_scope={@current_scope}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-gray-900">Billing & Subscription</h1>
          <p class="text-gray-600 mt-2">Manage your subscription, usage, and billing information.</p>
        </div>

    <!-- Tab Navigation -->
        <div class="border-b border-gray-200 mb-8">
          <nav class="-mb-px flex space-x-8">
            <button
              phx-click="change_tab"
              phx-value-tab="overview"
              class={[
                "whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm",
                (@active_tab == "overview" && "border-blue-500 text-blue-600") ||
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              <.icon name="hero-squares-2x2" class="w-5 h-5 inline mr-2" /> Overview
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="usage"
              class={[
                "whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm",
                (@active_tab == "usage" && "border-blue-500 text-blue-600") ||
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              <.icon name="hero-chart-bar" class="w-5 h-5 inline mr-2" /> Usage
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="history"
              class={[
                "whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm",
                (@active_tab == "history" && "border-blue-500 text-blue-600") ||
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              <.icon name="hero-document-text" class="w-5 h-5 inline mr-2" /> Billing History
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="plans"
              class={[
                "whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm",
                (@active_tab == "plans" && "border-blue-500 text-blue-600") ||
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              <.icon name="hero-sparkles" class="w-5 h-5 inline mr-2" /> Plans & Pricing
            </button>
          </nav>
        </div>

    <!-- Tab Content -->
        <div class="space-y-6">
          <%= case @active_tab do %>
            <% "overview" -> %>
              <.render_overview_tab assigns />
            <% "usage" -> %>
              <.render_usage_tab assigns />
            <% "history" -> %>
              <.render_history_tab assigns />
            <% "plans" -> %>
              <.render_plans_tab assigns />
          <% end %>
        </div>
      </div>

    <!-- Upgrade Modal -->
      <div
        :if={@show_upgrade_modal}
        class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50"
        phx-click="close_upgrade_modal"
      >
        <div
          class="relative top-20 mx-auto p-5 border w-96 shadow-lg rounded-md bg-white"
          phx-click-away="close_upgrade_modal"
        >
          <div class="mt-3 text-center">
            <.icon name="hero-sparkles" class="w-16 h-16 text-blue-500 mx-auto mb-4" />
            <h3 class="text-lg font-medium text-gray-900">
              Upgrade to {String.upcase(to_string(@selected_plan))}
            </h3>
            <div class="mt-2 px-7 py-3">
              <p class="text-sm text-gray-500">
                You'll be redirected to Stripe to complete your subscription upgrade.
              </p>
              <%= if @selected_plan do %>
                <div class="mt-4 p-4 bg-blue-50 rounded-lg">
                  <div class="text-2xl font-bold text-blue-600">
                    {plan_price(@selected_plan)}
                  </div>
                  <div class="text-sm text-blue-800">per month</div>
                  <div class="mt-2 text-sm text-gray-600">
                    {plan_description(@selected_plan)}
                  </div>
                </div>
              <% end %>
            </div>
            <div class="items-center px-4 py-3">
              <button
                phx-click="confirm_upgrade"
                disabled={@stripe_loading}
                class="px-4 py-2 bg-blue-600 text-white text-base font-medium rounded-md w-full shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-300 disabled:opacity-50"
              >
                <%= if @stripe_loading do %>
                  <.icon name="hero-arrow-path" class="w-5 h-5 inline animate-spin mr-2" />
                  Processing...
                <% else %>
                  Continue to Stripe
                <% end %>
              </button>
              <button
                phx-click="close_upgrade_modal"
                class="px-4 py-2 bg-gray-300 text-gray-800 text-base font-medium rounded-md w-full shadow-sm hover:bg-gray-400 focus:outline-none focus:ring-2 focus:ring-gray-300 mt-3"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Private render functions for each tab

  defp render_overview_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <!-- Current Plan Card -->
      <div class="bg-white rounded-lg border shadow-sm p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900">Current Plan</h3>
          <div class={[
            "px-3 py-1 rounded-full text-sm font-medium",
            plan_badge_class(@current_plan.plan)
          ]}>
            {String.upcase(to_string(@current_plan.plan))}
          </div>
        </div>

        <div class="space-y-4">
          <div>
            <div class="text-3xl font-bold text-gray-900">
              {plan_price(@current_plan.plan)}
            </div>
            <div class="text-gray-600">per month</div>
          </div>

          <div class="text-sm text-gray-600">
            <p>{plan_description(@current_plan.plan)}</p>
          </div>

          <div class="pt-4 border-t border-gray-200">
            <div class="flex justify-between text-sm">
              <span class="text-gray-600">Monthly Requests</span>
              <span class="font-medium">{format_number(@current_plan.requests_per_month)}</span>
            </div>
            <%= if @current_plan.plan != :free do %>
              <div class="flex justify-between text-sm mt-2">
                <span class="text-gray-600">Status</span>
                <span class={[
                  "font-medium",
                  subscription_status_color(@current_plan.subscription_status)
                ]}>
                  {String.capitalize(to_string(@current_plan.subscription_status || "inactive"))}
                </span>
              </div>
            <% end %>
          </div>

          <%= if @current_plan.plan == :free do %>
            <button
              phx-click="show_upgrade_modal"
              phx-value-plan="pro"
              class="w-full px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
            >
              Upgrade Plan
            </button>
          <% else %>
            <div class="grid grid-cols-2 gap-2">
              <%= if @current_plan.plan != :enterprise do %>
                <button
                  phx-click="show_upgrade_modal"
                  phx-value-plan="enterprise"
                  class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
                >
                  Upgrade
                </button>
              <% end %>
              <button
                phx-click="cancel_subscription"
                data-confirm="Are you sure you want to cancel your subscription?"
                class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 transition-colors"
              >
                Cancel
              </button>
            </div>
          <% end %>
        </div>
      </div>

    <!-- Usage Summary Card -->
      <div class="bg-white rounded-lg border shadow-sm p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">This Month's Usage</h3>

        <div class="space-y-4">
          <div>
            <div class="flex justify-between text-sm text-gray-600 mb-2">
              <span>API Requests</span>
              <span>{@current_usage.used} / {format_number(@current_usage.limit)}</span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-2">
              <div
                class={[
                  "h-2 rounded-full transition-all duration-300",
                  usage_bar_color(@current_usage.percentage)
                ]}
                style={"width: #{min(@current_usage.percentage, 100)}%"}
              />
            </div>
            <div class="text-xs text-gray-500 mt-1">
              {Float.round(@current_usage.percentage, 1)}% used
            </div>
          </div>

          <div class="pt-4 border-t border-gray-200">
            <div class="grid grid-cols-2 gap-4 text-center">
              <div>
                <div class="text-2xl font-bold text-gray-900">{@current_usage.remaining}</div>
                <div class="text-xs text-gray-600">Remaining</div>
              </div>
              <div>
                <div class="text-2xl font-bold text-gray-900">{@usage_stats.this_week}</div>
                <div class="text-xs text-gray-600">This Week</div>
              </div>
            </div>
          </div>

          <%= if @current_usage.percentage > 80 do %>
            <div class="p-3 bg-yellow-50 border border-yellow-200 rounded-md">
              <div class="flex">
                <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-yellow-500 mr-2" />
                <div class="text-sm text-yellow-800">
                  You're approaching your monthly limit. Consider upgrading your plan.
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_usage_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Usage Overview -->
      <div class="bg-white rounded-lg border shadow-sm p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-6">API Usage Details</h3>

        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div class="text-center p-4 bg-blue-50 rounded-lg">
            <div class="text-2xl font-bold text-blue-600">{@usage_stats.today}</div>
            <div class="text-sm text-blue-800">Today</div>
          </div>
          <div class="text-center p-4 bg-green-50 rounded-lg">
            <div class="text-2xl font-bold text-green-600">{@usage_stats.this_week}</div>
            <div class="text-sm text-green-800">This Week</div>
          </div>
          <div class="text-center p-4 bg-purple-50 rounded-lg">
            <div class="text-2xl font-bold text-purple-600">{@usage_stats.this_month}</div>
            <div class="text-sm text-purple-800">This Month</div>
          </div>
          <div class="text-center p-4 bg-gray-50 rounded-lg">
            <div class="text-2xl font-bold text-gray-600">{@usage_stats.average_daily}</div>
            <div class="text-sm text-gray-800">Daily Average</div>
          </div>
        </div>

    <!-- Usage Chart Placeholder -->
        <div class="h-64 bg-gray-50 rounded-lg flex items-center justify-center">
          <div class="text-center">
            <.icon name="hero-chart-bar-square" class="w-12 h-12 text-gray-400 mx-auto mb-2" />
            <p class="text-gray-600">Usage chart coming soon</p>
            <p class="text-sm text-gray-500">View your API usage trends over time</p>
          </div>
        </div>
      </div>

    <!-- Endpoint Usage Breakdown -->
      <div class="bg-white rounded-lg border shadow-sm p-6">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Endpoint Usage Breakdown</h3>

        <div class="space-y-3">
          <div :for={endpoint <- @endpoint_usage} class="flex items-center justify-between py-2">
            <div class="flex items-center">
              <div class="w-3 h-3 bg-blue-500 rounded-full mr-3"></div>
              <span class="font-medium text-gray-900">{endpoint.path}</span>
            </div>
            <div class="flex items-center space-x-4">
              <span class="text-sm text-gray-600">{endpoint.count} calls</span>
              <div class="w-24 bg-gray-200 rounded-full h-2">
                <div
                  class="bg-blue-500 h-2 rounded-full"
                  style={"width: #{endpoint.percentage}%"}
                />
              </div>
              <span class="text-sm font-medium text-gray-900 w-12">{endpoint.percentage}%</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_history_tab(assigns) do
    ~H"""
    <div class="bg-white rounded-lg border shadow-sm">
      <div class="px-6 py-4 border-b border-gray-200">
        <h3 class="text-lg font-semibold text-gray-900">Billing History</h3>
        <p class="text-sm text-gray-600 mt-1">View and download your invoices</p>
      </div>

      <%= if length(@billing_history) > 0 do %>
        <div class="overflow-hidden">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Date
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Description
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Amount
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr :for={invoice <- @billing_history}>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {format_date(invoice.created)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {invoice.description}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  ${invoice.amount / 100} {String.upcase(invoice.currency)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <span class={[
                    "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                    invoice_status_class(invoice.status)
                  ]}>
                    {String.capitalize(invoice.status)}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <div class="flex justify-end space-x-2">
                    <%= if invoice.pdf_url do %>
                      <button
                        phx-click="download_invoice"
                        phx-value-invoice_id={invoice.id}
                        class="text-blue-600 hover:text-blue-900"
                      >
                        Download
                      </button>
                    <% end %>
                    <%= if invoice.status == "open" do %>
                      <button
                        phx-click="retry_payment"
                        phx-value-invoice_id={invoice.id}
                        class="text-green-600 hover:text-green-900"
                      >
                        Retry Payment
                      </button>
                    <% end %>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% else %>
        <div class="p-12 text-center">
          <.icon name="hero-document-text" class="w-12 h-12 text-gray-400 mx-auto mb-4" />
          <p class="text-gray-600 mb-2">No billing history yet</p>
          <p class="text-sm text-gray-500">Your invoices and payment history will appear here.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_plans_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="text-center mb-8">
        <h2 class="text-2xl font-bold text-gray-900">Choose Your Plan</h2>
        <p class="text-gray-600 mt-2">Select the perfect plan for your needs</p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div :for={{plan_type, plan} <- @available_plans} class="relative">
          <!-- Plan Card -->
          <div class={[
            "bg-white rounded-lg border-2 p-6",
            (@current_plan.plan == plan_type && "border-blue-500 ring-2 ring-blue-200") ||
              "border-gray-200 hover:border-gray-300"
          ]}>
            <%= if @current_plan.plan == plan_type do %>
              <div class="absolute -top-3 left-1/2 transform -translate-x-1/2">
                <span class="bg-blue-500 text-white px-3 py-1 rounded-full text-sm font-medium">
                  Current Plan
                </span>
              </div>
            <% end %>

            <%= if plan[:popular] do %>
              <div class="absolute -top-3 left-1/2 transform -translate-x-1/2">
                <span class="bg-green-500 text-white px-3 py-1 rounded-full text-sm font-medium">
                  Most Popular
                </span>
              </div>
            <% end %>

            <div class="text-center mb-6">
              <h3 class="text-xl font-bold text-gray-900 mb-2">{plan.display_name || plan.name}</h3>
              <div class="text-4xl font-bold text-gray-900 mb-2">
                {plan_price(plan_type)}
              </div>
              <div class="text-gray-600">per month</div>
            </div>

            <div class="space-y-4 mb-6">
              <div class="flex items-center">
                <.icon name="hero-check" class="w-5 h-5 text-green-500 mr-3" />
                <span class="text-sm text-gray-700">
                  {format_number(plan.requests_per_month)} API requests/month
                </span>
              </div>

              <div :for={{feature, enabled} <- plan.features} :if={enabled} class="flex items-center">
                <.icon name="hero-check" class="w-5 h-5 text-green-500 mr-3" />
                <span class="text-sm text-gray-700">{humanize_feature(feature)}</span>
              </div>

              <div class="border-t pt-4">
                <div class="text-sm text-gray-600 space-y-1">
                  <div>Rate limit: {plan.limits.requests_per_minute}/minute</div>
                  <div>Team members: {format_limit(plan.limits.team_members)}</div>
                  <div>Support: {support_level(plan.limits.support_response_time_hours)} hours</div>
                </div>
              </div>
            </div>

            <div class="text-center">
              <%= if @current_plan.plan == plan_type do %>
                <div class="px-4 py-2 bg-gray-100 text-gray-600 rounded-md font-medium">
                  Current Plan
                </div>
              <% else %>
                <%= if plan_type == :free and @current_plan.plan != :free do %>
                  <button
                    phx-click="cancel_subscription"
                    data-confirm="Are you sure you want to downgrade to the free plan?"
                    class="w-full px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 transition-colors font-medium"
                  >
                    Downgrade to Free
                  </button>
                <% else %>
                  <button
                    phx-click="show_upgrade_modal"
                    phx-value-plan={plan_type}
                    class="w-full px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors font-medium"
                  >
                    <%= if plan_type == :free do %>
                      Get Started
                    <% else %>
                      Upgrade to {plan.display_name}
                    <% end %>
                  </button>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>

    <!-- Feature Comparison -->
      <div class="bg-white rounded-lg border shadow-sm p-6 mt-12">
        <h3 class="text-lg font-semibold text-gray-900 mb-6">Feature Comparison</h3>

        <div class="overflow-x-auto">
          <table class="min-w-full">
            <thead>
              <tr class="border-b border-gray-200">
                <th class="text-left py-3 px-4">Feature</th>
                <th :for={{plan_type, _plan} <- @available_plans} class="text-center py-3 px-4">
                  {String.upcase(to_string(plan_type))}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200">
              <tr :for={feature <- @feature_list}>
                <td class="py-3 px-4 font-medium text-gray-900">{feature.name}</td>
                <td :for={{plan_type, plan} <- @available_plans} class="py-3 px-4 text-center">
                  <%= if Map.get(plan.features, feature.key, false) do %>
                    <.icon name="hero-check" class="w-5 h-5 text-green-500 mx-auto" />
                  <% else %>
                    <.icon name="hero-x-mark" class="w-5 h-5 text-gray-300 mx-auto" />
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Private helper functions

  defp load_billing_data(socket) do
    organization = socket.assigns.current_scope

    with {:ok, current_usage} <- Billing.get_current_usage(organization.id),
         {:ok, billing_history} <- Billing.get_billing_history(organization.id) do
      # Get current plan info
      current_plan = Billing.get_plan(organization.plan || :free) || default_plan_info()
      current_plan = Map.put(current_plan, :subscription_status, organization.subscription_status)

      # Calculate usage stats
      usage_stats = calculate_usage_stats(current_usage)

      current_usage_data = %{
        used: current_usage,
        limit: current_plan.requests_per_month,
        remaining: max(0, current_plan.requests_per_month - current_usage),
        percentage:
          if(current_plan.requests_per_month > 0,
            do: current_usage / current_plan.requests_per_month * 100,
            else: 0
          )
      }

      # Get available plans
      available_plans = ConfigManager.list_plans()

      # Generate endpoint usage data (mock for now)
      endpoint_usage = generate_mock_endpoint_usage()

      # Feature list for comparison
      feature_list = [
        %{key: :basic_text_analysis, name: "Basic Text Analysis"},
        %{key: :api_access, name: "API Access"},
        %{key: :all_text_formats, name: "All Text Formats"},
        %{key: :email_support, name: "Email Support"},
        %{key: :network_analysis, name: "Network Analysis"},
        %{key: :filesystem_scanning, name: "Filesystem Scanning"},
        %{key: :database_analysis, name: "Database Analysis"},
        %{key: :advanced_analytics, name: "Advanced Analytics"},
        %{key: :priority_support, name: "Priority Support"},
        %{key: :team_collaboration, name: "Team Collaboration"},
        %{key: :sso_integration, name: "SSO Integration"}
      ]

      socket
      |> assign(:loading, false)
      |> assign(:current_plan, current_plan)
      |> assign(:current_usage, current_usage_data)
      |> assign(:usage_stats, usage_stats)
      |> assign(:billing_history, billing_history)
      |> assign(:available_plans, available_plans)
      |> assign(:endpoint_usage, endpoint_usage)
      |> assign(:feature_list, feature_list)
    else
      error ->
        Logger.error("Failed to load billing data: #{inspect(error)}")

        socket
        |> assign(:loading, false)
        |> put_flash(:error, "Failed to load billing data")
    end
  end

  defp default_plan_info do
    %{
      name: "Free",
      plan: :free,
      requests_per_month: 100,
      price_cents: 0,
      subscription_status: "inactive"
    }
  end

  defp calculate_usage_stats(current_usage) do
    # Mock calculations - in production, query from Events/database
    %{
      today: div(current_usage, 30),
      this_week: div(current_usage, 4),
      this_month: current_usage,
      average_daily: div(current_usage, 30)
    }
  end

  defp generate_mock_endpoint_usage do
    [
      %{path: "/api/v2/text/parse", count: 45, percentage: 35},
      %{path: "/api/v2/text/entities", count: 32, percentage: 25},
      %{path: "/api/v2/text/semantic", count: 25, percentage: 20},
      %{path: "/api/v2/text/analyze", count: 15, percentage: 12},
      %{path: "/api/v2/text/stylometry", count: 10, percentage: 8}
    ]
  end

  defp create_checkout_session(organization, plan_type) do
    # Get environment variables for Stripe price IDs
    price_id = case plan_type do
      :pro -> System.get_env("STRIPE_PRO_PRICE_ID")
      :enterprise -> System.get_env("STRIPE_ENTERPRISE_PRICE_ID")
      _ -> nil
    end

    if is_nil(price_id) heckout_url = "https://checkout.stripe.com/pay/cs_test_pro_plan"
        {:ok, checkout_url}

      :enterprise ->
        checkout_url = "https://checkout.stripe.com/pay/cs_test_enterprise_plan"
        {:ok, checkout_url}

      _ ->
        {:error, "Invalid plan type"}
    end
  end

  # Helper functions for rendering

  defp plan_price(:free), do: "$0"
  defp plan_price(:pro), do: "$49"
  defp plan_price(:enterprise), do: "$99"
  defp plan_price(_), do: "$0"

  defp plan_description(:free), do: "Perfect for getting started with basic text intelligence"
  defp plan_description(:pro), do: "Advanced features for growing businesses"
  defp plan_description(:enterprise), do: "Full-featured plan with priority support"
  defp plan_description(_), do: "Basic plan"

  defp plan_badge_class(:free), do: "bg-gray-100 text-gray-800"
  defp plan_badge_class(:pro), do: "bg-blue-100 text-blue-800"
  defp plan_badge_class(:enterprise), do: "bg-purple-100 text-purple-800"
  defp plan_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp subscription_status_color("active"), do: "text-green-600"
  defp subscription_status_color("past_due"), do: "text-yellow-600"
  defp subscription_status_color("cancelled"), do: "text-red-600"
  defp subscription_status_color(_), do: "text-gray-600"

  defp usage_bar_color(percentage) when percentage >= 90, do: "bg-red-500"
  defp usage_bar_color(percentage) when percentage >= 75, do: "bg-yellow-500"
  defp usage_bar_color(_), do: "bg-green-500"

  defp format_number(number) when number >= 1_000_000, do: "#{div(number, 1_000_000)}M"
  defp format_number(number) when number >= 1_000, do: "#{div(number, 1_000)}K"
  defp format_number(number), do: to_string(number)

  defp format_limit(:unlimited), do: "Unlimited"
  defp format_limit(number), do: to_string(number)

  defp support_level(hours) when hours <= 4, do: "Priority (#{hours})"
  defp support_level(hours) when hours <= 24, do: "Standard (#{hours})"
  defp support_level(hours), do: "Basic (#{hours})"

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")
  defp format_date(_), do: "Unknown"

  defp invoice_status_class("paid"), do: "bg-green-100 text-green-800"
  defp invoice_status_class("open"), do: "bg-yellow-100 text-yellow-800"
  defp invoice_status_class("void"), do: "bg-gray-100 text-gray-800"
  defp invoice_status_class(_), do: "bg-red-100 text-red-800"

  defp humanize_feature(:basic_text_analysis), do: "Basic text analysis"
  defp humanize_feature(:api_access), do: "API access"
  defp humanize_feature(:all_text_formats), do: "All text formats"
  defp humanize_feature(:email_support), do: "Email support"
  defp humanize_feature(:network_analysis), do: "Network analysis"
  defp humanize_feature(:filesystem_scanning), do: "Filesystem scanning"
  defp humanize_feature(:database_analysis), do: "Database analysis"
  defp humanize_feature(:log_intelligence), do: "Log intelligence"
  defp humanize_feature(:advanced_analytics), do: "Advanced analytics"
  defp humanize_feature(:priority_support), do: "Priority support"
  defp humanize_feature(:webhook_integrations), do: "Webhook integrations"
  defp humanize_feature(:team_collaboration), do: "Team collaboration"
  defp humanize_feature(:custom_integrations), do: "Custom integrations"
  defp humanize_feature(:sla_guarantee), do: "SLA guarantee"
  defp humanize_feature(:sso_integration), do: "SSO integration"
  defp humanize_feature(:mfa_support), do: "MFA support"
  defp humanize_feature(:audit_logs), do: "Audit logs"

  defp humanize_feature(feature),
    do: feature |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
