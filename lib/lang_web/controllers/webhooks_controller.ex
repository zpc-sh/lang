defmodule LangWeb.WebhooksController do
  @moduledoc """
  Handles Stripe webhook events for real-time billing and subscription updates.

  This controller processes webhook events from Stripe to keep our local
  billing data in sync with Stripe's records. It handles:

  - Payment success and failure events
  - Subscription creation, updates, and cancellations
  - Customer updates and deletions
  - Invoice events

  Security:
  - Validates webhook signatures using Stripe's webhook secret
  - Implements idempotency to handle duplicate events
  - Rate limiting to prevent abuse
  """

  use LangWeb, :controller
  alias LangWeb.ApiError

  alias Lang.{Billing, Events}
  require Logger

  @stripe_webhook_secret System.get_env(
                           "STRIPE_WEBHOOK_SECRET",
                           "whsec_test_webhook_secret_for_development"
                         )

  @doc """
  Main webhook endpoint that processes all Stripe events.
  """
  def stripe(conn, _params) do
    with {:ok, body} <- get_request_body(conn),
         {:ok, event} <- verify_webhook_signature(conn, body),
         {:ok, result} <- process_webhook_event(event) do
      Logger.info("Successfully processed Stripe webhook: #{event.type}")

      json(conn, %{
        status: "success",
        event_type: event.type,
        processed: true,
        result: result
      })
    else
      {:error, :invalid_signature} ->
        Logger.warning("Invalid Stripe webhook signature")
        ApiError.json(conn, :unauthorized, "Invalid signature")

      {:error, :duplicate_event} ->
        Logger.info("Duplicate Stripe webhook event, ignoring")

        json(conn, %{
          status: "success",
          processed: false,
          reason: "duplicate_event"
        })

      {:error, reason} when is_binary(reason) ->
        Logger.error("Failed to process Stripe webhook: #{reason}")
        ApiError.json(conn, :unprocessable_entity, to_string(reason))

      {:error, reason} ->
        Logger.error("Failed to process Stripe webhook: #{inspect(reason)}")
        ApiError.json(conn, :internal_server_error, "Internal server error")
    end
  end

  # Private Functions

  defp get_request_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} -> {:ok, body}
      {:error, reason} -> {:error, "Failed to read request body: #{reason}"}
    end
  end

  defp verify_webhook_signature(conn, body) do
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case Stripe.Webhook.construct_event(body, signature, @stripe_webhook_secret) do
      {:ok, event} ->
        # Check for duplicate events using idempotency
        if event_already_processed?(event.id) do
          {:error, :duplicate_event}
        else
          mark_event_as_processed(event.id)
          {:ok, event}
        end

      {:error, reason} ->
        {:error, :invalid_signature}
    end
  end

  defp process_webhook_event(%{type: event_type} = event) do
    case event_type do
      # Payment Events
      "payment_intent.succeeded" ->
        handle_payment_succeeded(event)

      "payment_intent.payment_failed" ->
        handle_payment_failed(event)

      # Invoice Events
      "invoice.payment_succeeded" ->
        Billing.handle_webhook("invoice.payment_succeeded", event)

      "invoice.payment_failed" ->
        Billing.handle_webhook("invoice.payment_failed", event)

      "invoice.finalized" ->
        handle_invoice_finalized(event)

      # Subscription Events
      "customer.subscription.created" ->
        handle_subscription_created(event)

      "customer.subscription.updated" ->
        Billing.handle_webhook("customer.subscription.updated", event)

      "customer.subscription.deleted" ->
        Billing.handle_webhook("customer.subscription.deleted", event)

      # Customer Events
      "customer.updated" ->
        handle_customer_updated(event)

      "customer.deleted" ->
        handle_customer_deleted(event)

      # Checkout Events
      "checkout.session.completed" ->
        handle_checkout_completed(event)

      # Product/Price Events
      "price.updated" ->
        handle_price_updated(event)

      # Default case for unhandled events
      _ ->
        Logger.info("Unhandled Stripe webhook event type: #{event_type}")
        {:ok, :ignored}
    end
  end

  # Event Handlers

  defp handle_payment_succeeded(event) do
    payment_intent = event.data.object

    # Track successful payment
    Events.track_event(%{
      event_type: "payment_completed",
      organization_id: get_org_id_from_metadata(payment_intent.metadata),
      metadata: %{
        payment_intent_id: payment_intent.id,
        amount: payment_intent.amount,
        currency: payment_intent.currency,
        payment_method: payment_intent.payment_method_types
      }
    })

    {:ok, :payment_processed}
  end

  defp handle_payment_failed(event) do
    payment_intent = event.data.object

    # Track failed payment
    Events.track_event(%{
      event_type: "payment_failed",
      organization_id: get_org_id_from_metadata(payment_intent.metadata),
      metadata: %{
        payment_intent_id: payment_intent.id,
        amount: payment_intent.amount,
        currency: payment_intent.currency,
        failure_reason: payment_intent.last_payment_error.message,
        failure_code: payment_intent.last_payment_error.code
      }
    })

    {:ok, :payment_failure_recorded}
  end

  defp handle_invoice_finalized(event) do
    invoice = event.data.object

    # Notify customer about new invoice
    if org_id = get_org_id_from_customer_id(invoice.customer) do
      Phoenix.PubSub.broadcast(Lang.PubSub, "org:#{org_id}", {
        :invoice_created,
        %{
          invoice_id: invoice.id,
          amount: invoice.amount_due,
          due_date: DateTime.from_unix!(invoice.due_date)
        }
      })
    end

    {:ok, :invoice_notification_sent}
  end

  defp handle_subscription_created(event) do
    subscription = event.data.object

    if org_id = get_org_id_from_metadata(subscription.metadata) do
      # Broadcast subscription activation to LiveViews
      Phoenix.PubSub.broadcast(Lang.PubSub, "org:#{org_id}", {
        :subscription_activated,
        %{
          subscription_id: subscription.id,
          status: subscription.status,
          current_period_end: DateTime.from_unix!(subscription.current_period_end)
        }
      })

      Events.track_event(%{
        event_type: "subscription_activated",
        organization_id: org_id,
        metadata: %{
          subscription_id: subscription.id,
          status: subscription.status
        }
      })
    end

    {:ok, :subscription_created}
  end

  defp handle_customer_updated(event) do
    customer = event.data.object

    if org_id = get_org_id_from_customer_id(customer.id) do
      # Update local customer data if needed
      Events.track_event(%{
        event_type: "customer_updated",
        organization_id: org_id,
        metadata: %{
          customer_id: customer.id,
          email: customer.email,
          name: customer.name
        }
      })
    end

    {:ok, :customer_updated}
  end

  defp handle_customer_deleted(event) do
    customer = event.data.object

    if org_id = get_org_id_from_customer_id(customer.id) do
      # Handle customer deletion (rare, but possible)
      Events.track_event(%{
        event_type: "customer_deleted",
        organization_id: org_id,
        metadata: %{customer_id: customer.id}
      })

      Logger.warning("Stripe customer deleted: #{customer.id} for org: #{org_id}")
    end

    {:ok, :customer_deletion_recorded}
  end

  defp handle_checkout_completed(event) do
    session = event.data.object

    case session.mode do
      "subscription" ->
        # Handle subscription checkout completion
        if org_id = get_org_id_from_metadata(session.metadata) do
          Events.track_event(%{
            event_type: "subscription_checkout_completed",
            organization_id: org_id,
            metadata: %{
              session_id: session.id,
              subscription_id: session.subscription,
              amount_total: session.amount_total
            }
          })
        end

      "payment" ->
        # Handle one-time payment completion
        if org_id = get_org_id_from_metadata(session.metadata) do
          Events.track_event(%{
            event_type: "payment_checkout_completed",
            organization_id: org_id,
            metadata: %{
              session_id: session.id,
              payment_intent_id: session.payment_intent,
              amount_total: session.amount_total
            }
          })
        end

      _ ->
        Logger.info("Unhandled checkout session mode: #{session.mode}")
    end

    {:ok, :checkout_processed}
  end

  defp handle_price_updated(event) do
    price = event.data.object

    # Log price changes for monitoring
    Logger.info("Stripe price updated: #{price.id} - #{price.unit_amount} #{price.currency}")

    Events.track_event(%{
      event_type: "price_updated",
      # System-level event
      organization_id: nil,
      metadata: %{
        price_id: price.id,
        unit_amount: price.unit_amount,
        currency: price.currency,
        product_id: price.product
      }
    })

    {:ok, :price_change_logged}
  end

  # Helper Functions

  defp event_already_processed?(event_id) do
    # Check if we've already processed this event using a simple cache
    # In production, you might want to use Redis or a database table
    case Cachex.get(:webhook_cache, "stripe_event:#{event_id}") do
      {:ok, nil} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp mark_event_as_processed(event_id) do
    # Mark event as processed with a TTL of 24 hours
    Cachex.put(:webhook_cache, "stripe_event:#{event_id}", true, ttl: :timer.hours(24))
  end

  defp get_org_id_from_metadata(%{"org_id" => org_id}) when is_binary(org_id), do: org_id
  defp get_org_id_from_metadata(%{org_id: org_id}) when is_binary(org_id), do: org_id
  defp get_org_id_from_metadata(_), do: nil

  defp get_org_id_from_customer_id(customer_id) when is_binary(customer_id) do
    # Query the database to find organization by Stripe customer ID
    import Ecto.Query

    query =
      from o in Lang.Accounts.Organization,
        where: o.stripe_customer_id == ^customer_id,
        select: o.id

    case Lang.Repo.one(query) do
      nil -> nil
      org_id -> org_id
    end
  end

  defp get_org_id_from_customer_id(_), do: nil
end
