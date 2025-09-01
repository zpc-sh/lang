
defmodule Lang.Billing.StripeService do
  @moduledoc """
  Centralizes Stripe calls used by Billing.Service.

  Reads price IDs and return URLs from config/billing.exs and environment.
  """

  require Logger

  def create_checkout_session(org, plan_type), do: create_checkout_session(org, plan_type, [])
  def create_checkout_session(org, plan_type, opts) do
    price_id = price_for_plan(plan_type)
    base_url = LangWeb.Endpoint.url()
    customer = org.stripe_customer_id

    params = %{
      customer: customer,
      payment_method_types: ["card"],
      line_items: [
        %{
          price: price_id,
          quantity: 1
        }
      ],
      mode: "subscription",
      success_url: success_url(base_url),
      cancel_url: cancel_url(base_url),
      metadata: %{organization_id: org.id},
      subscription_data: %{metadata: %{organization_id: org.id, slug: org.slug}}
    }

    case Stripe.Checkout.Session.create(params) do
      {:ok, session} -> {:ok, %{url: session.url, id: session.id}}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_portal_session(org), do: create_portal_session(org, nil)
  def create_portal_session(org, return_url) do
    return_url = return_url || (LangWeb.Endpoint.url() <> "/billing")
    case Stripe.BillingPortal.Session.create(%{customer: org.stripe_customer_id, return_url: return_url}) do
      {:ok, sess} -> {:ok, %{url: sess.url}}
      {:error, reason} -> {:error, reason}
    end
  end

  def cancel_subscription(subscription_id), do: cancel_subscription(subscription_id, [])
  def cancel_subscription(subscription_id, _opts) do
    case Stripe.Subscription.update(subscription_id, %{cancel_at_period_end: true}) do
      {:ok, sub} -> {:ok, sub}
      {:error, reason} -> {:error, reason}
    end
  end

  def reactivate_subscription(subscription_id) do
    case Stripe.Subscription.update(subscription_id, %{cancel_at_period_end: false}) do
      {:ok, sub} -> {:ok, sub}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_subscription(org) do
    case org.stripe_subscription_id do
      nil -> {:error, :no_subscription}
      sub_id -> Stripe.Subscription.retrieve(sub_id)
    end
  end

  def handle_webhook(event_type, event) do
    Logger.info("Stripe webhook forwarded to StripeService: #{event_type}")
    {:ok, :handled}
  end

  defp price_for_plan(plan) do
    # price IDs should come from env/config; fallback per plan name for dev
    case to_string(plan) do
      "free" -> System.get_env("STRIPE_PRICE_FREE") || "price_free"
      "plus" -> System.get_env("STRIPE_PRICE_PLUS") || "price_plus"
      "pro" -> System.get_env("STRIPE_PRICE_PRO") || "price_pro"
      "business" -> System.get_env("STRIPE_PRICE_BUSINESS") || "price_business"
      other -> System.get_env("STRIPE_PRICE_" <> String.upcase(other)) || "price_#{other}"
    end
  end

  defp success_url(base), do: base <> "/billing?tab=overview&session_id={CHECKOUT_SESSION_ID}"
  defp cancel_url(base), do: base <> "/billing?tab=overview"
end
