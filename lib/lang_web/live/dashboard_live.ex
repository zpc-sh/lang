defmodule LangWeb.DashboardLive do
  @moduledoc """
  Customer Dashboard - Usage Analytics, Billing & Plan Management

  The main dashboard where customers can:
  - View usage analytics and billing information
  - Manage their subscription and plan upgrades
  - Monitor API performance and rate limits
  - Manage team members and organization settings
  """

  use LangWeb, :live_view
  alias Lang.{Accounts, Events, Billing}
  import Money.Sigils

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to real-time updates
      Phoenix.PubSub.subscribe(Lang.PubSub, "user:#{socket.assigns.current_user.id}")
      Phoenix.PubSub.subscribe(Lang.PubSub, "org:#{socket.assigns.current_user.organization_id}")
    end

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:active_tab, "overview")
      |> load_dashboard_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    active_tab = Map.get(params, "tab", "overview")
    socket = assign(socket, :active_tab, active_tab)
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    socket =
      socket
      |> assign(:active_tab, tab)
      |> push_patch(to: ~p"/dashboard?tab=#{tab}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("upgrade_plan", %{"plan" => plan}, socket) do
    org_id = socket.assigns.current_user.organization_id
    plan_atom = String.to_atom(plan)

    socket = assign(socket, :loading_plan_change, plan_atom)

    case Billing.create_subscription(org_id, plan_atom) do
      {:ok, _organization} ->
        socket =
          socket
          |> put_flash(:info, "Successfully upgraded to #{String.capitalize(plan)} plan!")
          |> assign(:loading_plan_change, nil)
          |> load_dashboard_data()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to upgrade plan: #{reason}")
          |> assign(:loading_plan_change, nil)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("downgrade_plan", %{"plan" => plan}, socket) do
    org_id = socket.assigns.current_user.organization_id
    plan_atom = String.to_atom(plan)

    socket = assign(socket, :loading_plan_change, plan_atom)

    case Billing.update_subscription(org_id, plan_atom) do
      {:ok, _organization} ->
        socket =
          socket
          |> put_flash(:info, "Plan updated to #{String.capitalize(plan)}!")
          |> assign(:loading_plan_change, nil)
          |> load_dashboard_data()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to change plan: #{reason}")
          |> assign(:loading_plan_change, nil)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_subscription", _params, socket) do
    org_id = socket.assigns.current_user.organization_id

    socket = assign(socket, :loading_plan_change, :cancelling)

    case Billing.cancel_subscription(org_id) do
      {:ok, _organization} ->
        socket =
          socket
          |> put_flash(:info, "Subscription cancelled successfully")
          |> assign(:loading_plan_change, nil)
          |> load_dashboard_data()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to cancel subscription: #{reason}")
          |> assign(:loading_plan_change, nil)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("view_billing_history", _params, socket) do
    org_id = socket.assigns.current_user.organization_id

    case Billing.get_billing_history(org_id) do
      {:ok, invoices} ->
        socket = assign(socket, :billing_history, invoices)
        {:noreply, socket}

      {:error, _reason} ->
        socket = put_flash(socket, :error, "Unable to load billing history")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create_checkout_session", %{"plan" => plan}, socket) do
    org_id = socket.assigns.current_user.organization_id
    plan_atom = String.to_atom(plan)

    case create_stripe_checkout_session(org_id, plan_atom) do
      {:ok, checkout_url} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to create checkout session: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_billing_portal", _params, socket) do
    org_id = socket.assigns.current_user.organization_id

    case create_billing_portal_session(org_id) do
      {:ok, portal_url} ->
        {:noreply, redirect(socket, external: portal_url)}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to open billing portal: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh_usage", _params, socket) do
    socket =
      socket
      |> put_flash(:info, "Usage data refreshed")
      |> load_dashboard_data()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:usage_updated, _data}, socket) do
    {:noreply, load_dashboard_data(socket)}
  end

  @impl true
  def handle_info({:plan_changed, _data}, socket) do
    socket =
      socket
      |> put_flash(:info, "Your plan has been updated")
      |> load_dashboard_data()

    {:noreply, socket}
  end

  # Private Functions

  defp load_dashboard_data(socket) do
    user = socket.assigns.current_user
    org_id = user.organization_id

    # Load organization data
    organization = get_organization(org_id)

    # Load billing and usage data
    billing_data = get_billing_info(org_id)
    current_usage = get_current_usage(user.id, org_id)
    usage_history = get_usage_history(user.id, org_id)
    team_stats = get_team_stats(org_id)

    # Load usage limits based on current plan
    {can_make_requests, usage_limits} = Billing.can_make_request?(org_id)

    socket
    |> assign(:organization, organization)
    |> assign(:current_usage, current_usage)
    |> assign(:usage_history, usage_history)
    |> assign(:billing_info, billing_data)
    |> assign(:team_stats, team_stats)
    |> assign(:events, get_recent_activity(org_id, 10))
    |> assign(:available_plans, Billing.list_plans())
    |> assign(:can_make_requests, can_make_requests)
    |> assign(:usage_limits, usage_limits)
    |> assign(:loading_plan_change, Map.get(socket.assigns, :loading_plan_change))
  end

  defp create_stripe_checkout_session(org_id, plan_type) do
    with {:ok, organization} <- Accounts.get_organization(org_id) do
      price_id =
        case plan_type do
          :pro -> System.get_env("STRIPE_PRO_PRICE_ID")
          :enterprise -> System.get_env("STRIPE_ENTERPRISE_PRICE_ID")
          _ -> {:error, "Invalid plan type"}
        end

      case price_id do
        {:error, reason} ->
          {:error, reason}

        nil ->
          {:error, "Price ID not configured for #{plan_type}"}

        price_id ->
          # Ensure customer exists
          customer_id =
            case organization.stripe_customer_id do
              nil ->
                case Billing.create_customer(organization) do
                  {:ok, updated_org, customer} -> customer.id
                  {:error, _} -> nil
                end

              existing_id ->
                existing_id
            end

          if customer_id do
            checkout_params = %{
              mode: "subscription",
              customer: customer_id,
              line_items: [%{price: price_id, quantity: 1}],
              success_url:
                "#{get_base_url()}/dashboard?success=true&session_id={CHECKOUT_SESSION_ID}",
              cancel_url: "#{get_base_url()}/dashboard?canceled=true",
              metadata: %{
                org_id: org_id,
                plan: plan_type
              }
            }

            case Stripe.Session.create(checkout_params) do
              {:ok, session} -> {:ok, session.url}
              {:error, error} -> {:error, error.message}
            end
          else
            {:error, "Failed to create or retrieve customer"}
          end
      end
    end
  end

  defp create_billing_portal_session(org_id) do
    with {:ok, organization} <- Accounts.get_organization(org_id) do
      if organization.stripe_customer_id do
        portal_params = %{
          customer: organization.stripe_customer_id,
          return_url: "#{get_base_url()}/dashboard"
        }

        case Stripe.BillingPortal.Session.create(portal_params) do
          {:ok, session} -> {:ok, session.url}
          {:error, error} -> {:error, error.message}
        end
      else
        {:error, "No customer record found"}
      end
    end
  end

  defp get_base_url do
    endpoint_config = Application.get_env(:lang, LangWeb.Endpoint, [])
    host = Keyword.get(endpoint_config, :url, []) |> Keyword.get(:host, "localhost")
    port = Keyword.get(endpoint_config, :url, []) |> Keyword.get(:port, 4000)
    scheme = if port == 443, do: "https", else: "http"

    case {scheme, port} do
      {"https", 443} -> "https://#{host}"
      {"http", 80} -> "http://#{host}"
      {scheme, port} -> "#{scheme}://#{host}:#{port}"
    end
  end

  defp get_organization(org_id) do
    # TODO: Replace with actual Ash query when Organization resource is ready
    %{
      id: org_id,
      name: "Acme Corporation",
      plan: :pro,
      subscription_status: :active,
      current_period_end: Date.add(Date.utc_today(), 15),
      monthly_request_limit: 50_000,
      monthly_request_count: 7_234,
      billing_cycle_start: ~D[2024-08-01],
      features: [:basic_analysis, :api_access, :advanced_analysis, :conversation_rehearsal],
      max_users: 25,
      storage_limit_gb: 10,
      stripe_customer_id: "cus_test_123456"
    }
  end

  defp get_current_usage(_user_id, _org_id) do
    # TODO: Replace with actual usage queries
    %{
      total_requests: 7_234,
      successful_requests: 7_103,
      failed_requests: 131,
      rate_limited_requests: 23,
      total_characters_processed: 2_847_392,
      avg_response_time_ms: 143,
      top_operations: [
        %{name: "Text Analysis", count: 4_821, percentage: 66.7},
        %{name: "Language Detection", count: 1_456, percentage: 20.1},
        %{name: "Sentiment Analysis", count: 957, percentage: 13.2}
      ],
      hourly_usage: generate_hourly_usage(),
      daily_usage: generate_daily_usage()
    }
  end

  defp get_usage_history(_user_id, _org_id) do
    # Generate last 6 months of usage data
    for month <- 5..0//-1 do
      date = Date.add(Date.beginning_of_month(Date.utc_today()), -month * 30)
      base_usage = :rand.uniform(8000) + 2000

      %{
        month: Calendar.strftime(date, "%b %Y"),
        total_requests: base_usage,
        successful_requests: round(base_usage * 0.98),
        cost: calculate_cost_for_usage(base_usage)
      }
    end
  end

  defp get_recent_activity(_org_id, limit) do
    # TODO: Replace with actual activity/events queries
    activities = [
      %{
        id: 1,
        type: "api_request",
        description: "Text analysis completed",
        user_name: "Alice Johnson",
        timestamp: DateTime.add(DateTime.utc_now(), -3600),
        metadata: %{operation: "analyze", characters: 1247}
      },
      %{
        id: 2,
        type: "plan_change",
        description: "Upgraded to Pro plan",
        user_name: "System",
        timestamp: DateTime.add(DateTime.utc_now(), -7200),
        metadata: %{from_plan: "free", to_plan: "pro"}
      },
      %{
        id: 3,
        type: "api_key",
        description: "New API key generated",
        user_name: "Bob Smith",
        timestamp: DateTime.add(DateTime.utc_now(), -10800),
        metadata: %{key_name: "production-key"}
      },
      %{
        id: 4,
        type: "usage_alert",
        description: "80% of monthly limit reached",
        user_name: "System",
        timestamp: DateTime.add(DateTime.utc_now(), -14400),
        metadata: %{usage_percentage: 80}
      },
      %{
        id: 5,
        type: "team_invite",
        description: "Team member invited",
        user_name: "Carol Davis",
        timestamp: DateTime.add(DateTime.utc_now(), -18000),
        metadata: %{invited_email: "new.member@company.com"}
      }
    ]

    Enum.take(activities, limit)
  end

  defp get_billing_info(_org_id) do
    %{
      current_plan: %{
        name: "Professional",
        price: "$99/month",
        features: [
          "10,000 API requests/month",
          "Advanced text analysis",
          "Conversation rehearsal",
          "Email support"
        ]
      },
      next_billing_date: Date.add(Date.utc_today(), 12),
      payment_method: %{
        type: "card",
        last4: "4242",
        brand: "visa",
        exp_month: 12,
        exp_year: 2025
      },
      recent_invoices: [
        %{id: "inv_001", amount: "$99.00", date: ~D[2024-07-01], status: "paid"},
        %{id: "inv_002", amount: "$99.00", date: ~D[2024-06-01], status: "paid"},
        %{id: "inv_003", amount: "$49.00", date: ~D[2024-05-01], status: "paid"}
      ]
    }
  end

  defp get_team_stats(_org_id) do
    %{
      total_members: 8,
      active_members: 6,
      admin_members: 2,
      recent_activity: [
        %{
          user: "Alice Johnson",
          action: "Generated API key",
          timestamp: DateTime.add(DateTime.utc_now(), -3600)
        },
        %{
          user: "Bob Smith",
          action: "Analyzed document",
          timestamp: DateTime.add(DateTime.utc_now(), -7200)
        },
        %{
          user: "Carol Davis",
          action: "Updated team settings",
          timestamp: DateTime.add(DateTime.utc_now(), -10800)
        }
      ]
    }
  end

  defp calculate_usage_percentage(usage, organization) do
    if organization.monthly_request_limit > 0 do
      (usage.total_requests / organization.monthly_request_limit * 100)
      |> min(100)
      |> Float.round(1)
    else
      0.0
    end
  end

  defp calculate_cost_for_usage(usage) do
    # Simple tiered pricing calculation
    cond do
      usage <= 1000 -> "$0"
      usage <= 10_000 -> "$49"
      usage <= 50_000 -> "$99"
      true -> "$299"
    end
  end

  defp generate_hourly_usage do
    # Generate 24 hours of usage data
    for hour <- 0..23 do
      base_usage =
        case hour do
          # Business hours
          h when h in 9..17 -> :rand.uniform(100) + 50
          # Peak times
          h when h in 6..8 or h in 18..22 -> :rand.uniform(50) + 20
          # Off hours
          _ -> :rand.uniform(20) + 5
        end

      %{hour: hour, requests: base_usage}
    end
  end

  defp generate_daily_usage do
    # Generate last 30 days of usage
    for day <- 29..0//-1 do
      date = Date.add(Date.utc_today(), -day)
      base_usage = :rand.uniform(400) + 200

      %{
        date: Calendar.strftime(date, "%m/%d"),
        requests: base_usage
      }
    end
  end

  defp format_number(number) when is_integer(number) do
    Number.Delimit.number_to_delimited(number, delimiter: ",")
  end

  defp format_number(number) when is_float(number) do
    :erlang.float_to_binary(number, decimals: 1)
  end

  defp status_color(status) do
    case status do
      "paid" -> "text-green-600"
      "pending" -> "text-yellow-600"
      "failed" -> "text-red-600"
      _ -> "text-gray-600"
    end
  end

  defp plan_color(tier) do
    case tier do
      :free -> "border-gray-200 bg-gray-50"
      :pro -> "border-blue-200 bg-blue-50"
      :enterprise -> "border-purple-200 bg-purple-50"
      _ -> "border-gray-200 bg-gray-50"
    end
  end
end
