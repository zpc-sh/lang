defmodule Lang.Billing do
  @moduledoc """
  Billing and subscription management using Stripe.

  This module handles:
  - Customer creation and management
  - Subscription lifecycle (create, update, cancel)
  - Payment method management
  - Invoice and billing history
  - Webhook processing for real-time updates
  - Usage-based billing calculations
  """

  alias Lang.{Accounts, Events, Repo}
  alias Lang.Accounts.Organization
  alias Lang.Billing.ConfigManager
  import Ecto.Query

  @stripe_price_ids %{
    pro: System.get_env("STRIPE_PRO_PRICE_ID"),
    enterprise: System.get_env("STRIPE_ENTERPRISE_PRICE_ID")
  }

  # Public API

  @doc """
  Gets plan configuration for a given plan type.
  """
  def get_plan(plan_type) when plan_type in [:free, :pro, :enterprise] do
    case ConfigManager.get_plan(plan_type) do
      {:ok, plan} -> plan
      {:error, _} -> nil
    end
  end

  def get_plan(_), do: nil

  @doc """
  Lists all available plans.
  """
  def list_plans do
    ConfigManager.list_plans()
  end

  @doc """
  Creates a Stripe customer for an organization.
  """
  def create_customer(%Organization{} = organization) do
    params = %{
      email: organization.email,
      name: organization.name,
      metadata: %{
        org_id: organization.id,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    case Stripe.Customer.create(params) do
      {:ok, customer} ->
        # Store Stripe customer ID
        changeset = Ecto.Changeset.change(organization, stripe_customer_id: customer.id)

        case Repo.update(changeset) do
          {:ok, updated_org} -> {:ok, updated_org, customer}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Creates a subscription for an organization.
  """
  def create_subscription(organization_id, plan_type) when plan_type in [:pro, :enterprise] do
    with {:ok, organization} <- get_organization_with_customer(organization_id),
         {:ok, subscription} <- create_stripe_subscription(organization, plan_type),
         {:ok, updated_org} <-
           update_organization_subscription(organization, subscription, plan_type) do
      # Track the subscription event
      Events.track_event(%{
        event_type: "subscription_created",
        organization_id: organization_id,
        metadata: %{
          plan: plan_type,
          stripe_subscription_id: subscription.id,
          amount: (get_plan(plan_type) || %{price_cents: 0}).price_cents
        }
      })

      {:ok, updated_org}
    end
  end

  def create_subscription(_organization_id, :free),
    do: {:error, "Free plan doesn't require subscription"}

  def create_subscription(_organization_id, _), do: {:error, "Invalid plan type"}

  @doc """
  Updates an existing subscription to a new plan.
  """
  def update_subscription(organization_id, new_plan_type)
      when new_plan_type in [:pro, :enterprise] do
    with {:ok, organization} <- get_organization_with_subscription(organization_id),
         {:ok, updated_subscription} <-
           update_stripe_subscription(organization.stripe_subscription_id, new_plan_type),
         {:ok, updated_org} <-
           update_organization_subscription(organization, updated_subscription, new_plan_type) do
      # Track the plan change event
      Events.track_event(%{
        event_type: "subscription_updated",
        organization_id: organization_id,
        metadata: %{
          old_plan: organization.plan,
          new_plan: new_plan_type,
          stripe_subscription_id: updated_subscription.id
        }
      })

      # Broadcast plan change to LiveViews
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "org:#{organization_id}",
        {:plan_changed, %{plan: new_plan_type}}
      )

      {:ok, updated_org}
    end
  end

  def update_subscription(organization_id, :free) do
    case cancel_subscription(organization_id) do
      {:ok, organization} ->
        # Update to free plan
        changeset =
          Ecto.Changeset.change(organization,
            plan: :free,
            stripe_subscription_id: nil,
            subscription_status: "inactive"
          )

        case Repo.update(changeset) do
          {:ok, updated_org} ->
            Events.track_event(%{
              event_type: "subscription_downgraded_to_free",
              organization_id: organization_id,
              metadata: %{old_plan: organization.plan}
            })

            Phoenix.PubSub.broadcast(
              Lang.PubSub,
              "org:#{organization_id}",
              {:plan_changed, %{plan: :free}}
            )

            {:ok, updated_org}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Cancels a subscription immediately.
  """
  def cancel_subscription(organization_id) do
    with {:ok, organization} <- get_organization_with_subscription(organization_id),
         {:ok, _cancelled_subscription} <-
           Stripe.Subscription.delete(organization.stripe_subscription_id) do
      # Update organization
      changeset =
        Ecto.Changeset.change(organization,
          subscription_status: "cancelled",
          cancelled_at: DateTime.utc_now()
        )

      case Repo.update(changeset) do
        {:ok, updated_org} ->
          Events.track_event(%{
            event_type: "subscription_cancelled",
            organization_id: organization_id,
            metadata: %{plan: organization.plan}
          })

          {:ok, updated_org}

        error ->
          error
      end
    end
  end

  @doc """
  Gets billing history for an organization.
  """
  def get_billing_history(organization_id) do
    with {:ok, organization} <- get_organization_with_customer(organization_id) do
      case Stripe.Invoice.list(%{customer: organization.stripe_customer_id, limit: 50}) do
        {:ok, %{data: invoices}} ->
          formatted_invoices = Enum.map(invoices, &format_invoice/1)
          {:ok, formatted_invoices}

        error ->
          error
      end
    end
  end

  @doc """
  Gets current usage for an organization.
  """
  def get_current_usage(organization_id) do
    now = DateTime.utc_now()
    start_of_month = DateTime.beginning_of_month(now)

    query =
      from e in "events",
        where: e.organization_id == ^organization_id,
        where: e.event_type == "api_request",
        where: e.inserted_at >= ^start_of_month and e.inserted_at <= ^now,
        select: count(e.id)

    case Repo.one(query) do
      nil -> {:ok, 0}
      count -> {:ok, count}
    end
  end

  @doc """
  Checks if organization can make API requests based on plan limits.
  """
  def can_make_request?(organization_id) do
    with {:ok, organization} <- Accounts.get_organization(organization_id),
         {:ok, current_usage} <- get_current_usage(organization_id) do
      plan = get_plan(organization.plan)

      if plan do
        requests_remaining = plan.requests_per_month - current_usage
        limits = plan.limits || %{}

        {requests_remaining > 0,
         %{
           current_usage: current_usage,
           limit: plan.requests_per_month,
           remaining: max(0, requests_remaining),
           plan: organization.plan,
           cost_per_1k: plan.cost_per_1k,
           rate_limit: Map.get(limits, :requests_per_minute, 10),
           team_members: Map.get(limits, :team_members, 1)
         }}
      else
        {false, %{error: "Invalid plan configuration"}}
      end
    else
      _ -> {false, %{error: "Unable to check usage limits"}}
    end
  end

  @doc """
  Gets pricing comparison for upgrade recommendations.
  """
  def get_pricing_comparison(current_plan) do
    recommendation = ConfigManager.get_upgrade_recommendation(current_plan)
    all_plans = ConfigManager.list_plans()
    current_plan_data = ConfigManager.get_plan!(current_plan) || get_plan(:free)

    %{
      current: current_plan_data,
      all_plans: all_plans,
      recommendations: recommendation
    }
  end

  @doc """
  Processes Stripe webhooks.
  """
  def handle_webhook(event_type, stripe_event) do
    case event_type do
      "invoice.payment_succeeded" ->
        handle_payment_succeeded(stripe_event)

      "invoice.payment_failed" ->
        handle_payment_failed(stripe_event)

      "customer.subscription.updated" ->
        handle_subscription_updated(stripe_event)

      "customer.subscription.deleted" ->
        handle_subscription_deleted(stripe_event)

      _ ->
        {:ok, :ignored}
    end
  end

  # Private Functions

  defp get_organization_with_customer(organization_id) do
    case Accounts.get_organization(organization_id) do
      {:ok, %{stripe_customer_id: nil} = org} ->
        case create_customer(org) do
          {:ok, updated_org, _customer} -> {:ok, updated_org}
          error -> error
        end

      {:ok, organization} ->
        {:ok, organization}

      error ->
        error
    end
  end

  defp get_organization_with_subscription(organization_id) do
    with {:ok, organization} <- Accounts.get_organization(organization_id) do
      if organization.stripe_subscription_id do
        {:ok, organization}
      else
        {:error, "Organization has no active subscription"}
      end
    end
  end

  defp create_stripe_subscription(organization, plan_type) do
    price_id = @stripe_price_ids[plan_type]

    params = %{
      customer: organization.stripe_customer_id,
      items: [%{price: price_id}],
      metadata: %{
        org_id: organization.id,
        plan: plan_type
      }
    }

    Stripe.Subscription.create(params)
  end

  defp update_stripe_subscription(subscription_id, new_plan_type) do
    with {:ok, subscription} <- Stripe.Subscription.retrieve(subscription_id) do
      [item] = subscription.items.data
      new_price_id = @stripe_price_ids[new_plan_type]

      params = %{
        items: [
          %{
            id: item.id,
            price: new_price_id
          }
        ],
        proration_behavior: "create_prorations"
      }

      Stripe.Subscription.update(subscription_id, params)
    end
  end

  defp update_organization_subscription(organization, subscription, plan_type) do
    changeset =
      Ecto.Changeset.change(organization,
        stripe_subscription_id: subscription.id,
        plan: plan_type,
        subscription_status: subscription.status,
        subscribed_at: DateTime.utc_now()
      )

    Repo.update(changeset)
  end

  defp format_invoice(invoice) do
    %{
      id: invoice.id,
      amount: invoice.amount_due,
      currency: String.upcase(invoice.currency),
      status: invoice.status,
      created: DateTime.from_unix!(invoice.created),
      description: invoice.description || "Monthly subscription",
      pdf_url: invoice.invoice_pdf
    }
  end

  defp handle_payment_succeeded(stripe_event) do
    invoice = stripe_event.data.object
    customer_id = invoice.customer

    with {:ok, organization} <- find_organization_by_customer_id(customer_id) do
      Events.track_event(%{
        event_type: "payment_succeeded",
        organization_id: organization.id,
        metadata: %{
          amount: invoice.amount_paid,
          invoice_id: invoice.id
        }
      })

      {:ok, :processed}
    end
  end

  defp handle_payment_failed(stripe_event) do
    invoice = stripe_event.data.object
    customer_id = invoice.customer

    with {:ok, organization} <- find_organization_by_customer_id(customer_id) do
      Events.track_event(%{
        event_type: "payment_failed",
        organization_id: organization.id,
        metadata: %{
          amount: invoice.amount_due,
          invoice_id: invoice.id,
          failure_reason: invoice.failure_reason
        }
      })

      # You might want to send an email notification here
      {:ok, :processed}
    end
  end

  defp handle_subscription_updated(stripe_event) do
    subscription = stripe_event.data.object

    with {:ok, organization} <- find_organization_by_customer_id(subscription.customer) do
      changeset =
        Ecto.Changeset.change(organization,
          subscription_status: subscription.status
        )

      case Repo.update(changeset) do
        {:ok, _updated_org} ->
          Phoenix.PubSub.broadcast(
            Lang.PubSub,
            "org:#{organization.id}",
            {:subscription_updated, %{status: subscription.status}}
          )

          {:ok, :processed}

        error ->
          error
      end
    end
  end

  defp handle_subscription_deleted(stripe_event) do
    subscription = stripe_event.data.object

    with {:ok, organization} <- find_organization_by_customer_id(subscription.customer) do
      changeset =
        Ecto.Changeset.change(organization,
          subscription_status: "cancelled",
          plan: :free,
          stripe_subscription_id: nil,
          cancelled_at: DateTime.utc_now()
        )

      case Repo.update(changeset) do
        {:ok, _updated_org} ->
          Phoenix.PubSub.broadcast(
            Lang.PubSub,
            "org:#{organization.id}",
            {:plan_changed, %{plan: :free}}
          )

          {:ok, :processed}

        error ->
          error
      end
    end
  end

  defp find_organization_by_customer_id(customer_id) do
    query =
      from o in Organization,
        where: o.stripe_customer_id == ^customer_id

    case Repo.one(query) do
      nil -> {:error, "Organization not found for customer #{customer_id}"}
      org -> {:ok, org}
    end
  end
end
