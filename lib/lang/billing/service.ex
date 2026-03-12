defmodule Lang.Billing.Service do
  @moduledoc """
  Thin service layer around Ash resources and billing config.

  Provides compatibility helpers while Lang.Billing is the Ash Domain.
  """

  require Logger
  import Ash.Query
  alias Lang.AshHelpers
  alias Lang.Billing.StripeService

  # Count current month's API usage using Ash Events
  def get_current_usage(org_id) when is_binary(org_id) do
    now = DateTime.utc_now()
    from = DateTime.beginning_of_month(now)

    base =
      Lang.Events.ApiUsageEvent
      |> AshHelpers.scope_to_org(org_id)
      |> filter(inserted_at >= ^from and inserted_at <= ^now)

    case Ash.read(base) do
      {:ok, events} ->
        {:ok, length(events)}

      {:error, reason} ->
        Logger.warning("Failed to read usage via Ash",
          organization_id: org_id,
          reason: inspect(reason)
        )

        {:ok, 0}
    end
  end

  # Check if org can make a request based on plan limits from config
  def can_make_request?(org_id) when is_binary(org_id) do
    with {:ok, org} <- Lang.Accounts.Organization.by_id(org_id),
         {:ok, current} <- get_current_usage(org_id) do
      tier = normalize_tier(org.subscription_tier)
      limit = Lang.Billing.Config.plan_request_limit(tier)
      remaining = max(0, limit - current)

      if remaining > 0 do
        {true,
         %{
           current_usage: current,
           limit: limit,
           remaining: remaining,
           plan: tier,
           rate_limit: Lang.Billing.Config.plan_limit(tier, :requests_per_minute) || 10
         }}
      else
        {false, %{error: :limit_exceeded, current_usage: current, limit: limit}}
      end
    else
      _ -> {false, %{error: :unknown_organization}}
    end
  end

  # Track per-connection MCP usage (metered)
  def report_mcp_connection(org_id) when is_binary(org_id) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601()

    # Record generic usage (optional)
    _ =
      Lang.Billing.UsageRecord.record(%{
        organization_id: org_id,
        kind: "mcp_connection",
        metadata: %{occurred_at: ts}
      })

    # Emit event for pipelines/analytics
    Lang.Events.track_event(%{
      event_type: "mcp_connection_charge",
      organization_id: org_id,
      metadata: %{occurred_at: ts}
    })

    :ok
  end

  # Stripe integration functions

  @doc """
  Create a Stripe checkout session for plan upgrade.
  """
  def create_checkout_session(org_id, plan_type, opts \\ []) when is_binary(org_id) do
    with {:ok, org} <- Lang.Accounts.Organization.by_id(org_id) do
      StripeService.create_checkout_session(org, plan_type, opts)
    end
  end

  @doc """
  Create a Stripe billing portal session.
  """
  def create_portal_session(org_id, return_url \\ nil) when is_binary(org_id) do
    with {:ok, org} <- Lang.Accounts.Organization.by_id(org_id) do
      StripeService.create_portal_session(org, return_url)
    end
  end

  @doc """
  Cancel a subscription.
  """
  def cancel_subscription(org_id, opts \\ []) when is_binary(org_id) do
    with {:ok, org} <- Lang.Accounts.Organization.by_id(org_id),
         subscription_id when is_binary(subscription_id) <- org.stripe_subscription_id do
      StripeService.cancel_subscription(subscription_id, opts)
    else
      nil -> {:error, :no_subscription}
      error -> error
    end
  end

  @doc """
  Reactivate a cancelled subscription.
  """
  def reactivate_subscription(org_id) when is_binary(org_id) do
    with {:ok, org} <- Lang.Accounts.Organization.by_id(org_id),
         subscription_id when is_binary(subscription_id) <- org.stripe_subscription_id do
      StripeService.reactivate_subscription(subscription_id)
    else
      nil -> {:error, :no_subscription}
      error -> error
    end
  end

  @doc """
  Get current subscription details.
  """
  def get_subscription_details(org_id) when is_binary(org_id) do
    with {:ok, org} <- Lang.Accounts.Organization.by_id(org_id) do
      case StripeService.get_subscription(org) do
        {:ok, subscription} ->
          {:ok,
           %{
             id: subscription.id,
             status: subscription.status,
             current_period_end: DateTime.from_unix!(subscription.current_period_end),
             cancel_at_period_end: subscription.cancel_at_period_end,
             plan_type: org.subscription_tier
           }}

        error ->
          error
      end
    end
  end

  @doc """
  Handle Stripe webhook events.
  """
  def handle_webhook(event_type, stripe_event) do
    StripeService.handle_webhook(event_type, stripe_event)
  end

  defp normalize_tier(:professional), do: :pro
  defp normalize_tier(tier), do: tier
end
