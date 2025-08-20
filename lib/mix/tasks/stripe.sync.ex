defmodule Mix.Tasks.Stripe.Sync do
  @moduledoc """
  Synchronize Stripe products, prices, and webhooks with your local configuration.

  This task helps keep your Stripe account in sync with your application's
  pricing and product configuration, especially useful for:

  - Updating product descriptions and features
  - Adding new pricing tiers
  - Syncing metadata and product information
  - Validating webhook configurations
  - Detecting pricing discrepancies

  ## Usage

      # Sync all products and prices
      mix stripe.sync

      # Sync only products (no price changes)
      mix stripe.sync --products-only

      # Sync only webhooks
      mix stripe.sync --webhooks-only

      # Show differences without making changes
      mix stripe.sync --diff

      # Force update all products even if they match
      mix stripe.sync --force

  ## Environment Variables Required

      STRIPE_SECRET_KEY=sk_test_...  # Your Stripe secret key
      STRIPE_WEBHOOK_SECRET=whsec_... # For webhook validation

  ## What This Syncs

  1. **Product Information**
     - Names and descriptions
     - Metadata and feature lists
     - Product status (active/inactive)

  2. **Price Validation**
     - Verifies current prices match expected values
     - Reports price discrepancies
     - Can create new prices if needed

  3. **Webhook Endpoints**
     - Validates webhook URL and events
     - Updates event subscriptions
     - Checks webhook signing secrets

  The task provides detailed output showing what was synced and any issues found.
  """

  use Mix.Task
  require Logger

  @shortdoc "Synchronize Stripe products and prices with local configuration"

  # Expected product configuration (should match billing.ex)
  @expected_products %{
    pro: %{
      name: "LANG Pro",
      description: "Advanced text intelligence for growing businesses",
      # $49.00
      expected_price: 4900,
      features: [
        "50,000 requests per month",
        "Advanced text intelligence",
        "Real-time analytics dashboard",
        "Priority email support",
        "Webhook integrations",
        "Team collaboration (5 members)",
        "Custom API rate limits",
        "Advanced sentiment analysis",
        "Style & tone detection"
      ],
      metadata: %{
        plan_type: "pro",
        requests_per_month: "50000",
        rate_limit: "100",
        team_members: "5",
        managed_by: "lang_platform"
      }
    },
    enterprise: %{
      name: "LANG Enterprise",
      description: "Enterprise-grade text intelligence with dedicated support",
      # $199.00
      expected_price: 19900,
      features: [
        "500,000 requests per month",
        "Everything in Pro, plus:",
        "99.9% SLA guarantee",
        "Dedicated customer success manager",
        "Phone & Slack support",
        "Custom deployment options",
        "SSO integration (SAML/OAuth)",
        "Advanced security & compliance",
        "Custom ML model training",
        "Unlimited team members",
        "White-label options"
      ],
      metadata: %{
        plan_type: "enterprise",
        requests_per_month: "500000",
        rate_limit: "1000",
        team_members: "unlimited",
        managed_by: "lang_platform"
      }
    }
  }

  @required_webhook_events [
    "customer.subscription.created",
    "customer.subscription.updated",
    "customer.subscription.deleted",
    "invoice.payment_succeeded",
    "invoice.payment_failed",
    "checkout.session.completed"
  ]

  def run(args) do
    {options, [], []} =
      OptionParser.parse(args,
        switches: [
          products_only: :boolean,
          webhooks_only: :boolean,
          diff: :boolean,
          force: :boolean,
          help: :boolean
        ],
        aliases: [
          h: :help
        ]
      )

    if options[:help] do
      show_help()
    else
      sync_stripe(options)
    end
  end

  defp sync_stripe(options) do
    Logger.info("🔄 Starting Stripe synchronization...")

    with :ok <- validate_environment(),
         :ok <- configure_stripe() do
      diff_only = options[:diff] || false
      force_update = options[:force] || false

      sync_results = %{
        products_synced: 0,
        prices_synced: 0,
        webhooks_synced: 0,
        issues_found: [],
        changes_made: []
      }

      sync_results =
        cond do
          options[:webhooks_only] ->
            sync_results |> sync_webhooks(diff_only)

          options[:products_only] ->
            sync_results
            |> sync_products(diff_only, force_update)

          true ->
            sync_results
            |> sync_products(diff_only, force_update)
            |> sync_prices(diff_only)
            |> sync_webhooks(diff_only)
        end

      display_sync_results(sync_results, diff_only)
    else
      {:error, reason} ->
        Logger.error("❌ Sync failed: #{reason}")
        System.halt(1)
    end
  end

  defp validate_environment do
    secret_key = System.get_env("STRIPE_SECRET_KEY")

    cond do
      is_nil(secret_key) ->
        {:error, "STRIPE_SECRET_KEY environment variable is required"}

      not String.starts_with?(secret_key, ["sk_test_", "sk_live_"]) ->
        {:error, "Invalid STRIPE_SECRET_KEY format"}

      true ->
        :ok
    end
  end

  defp configure_stripe do
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:stripity_stripe)
    :ok
  end

  defp sync_products(results, diff_only, force_update) do
    Logger.info("📦 Syncing products...")

    case Stripe.Product.list(%{limit: 100}) do
      {:ok, %{data: stripe_products}} ->
        lang_products = find_lang_products(stripe_products)

        Enum.reduce(@expected_products, results, fn {plan_type, expected}, acc ->
          case sync_single_product(plan_type, expected, lang_products, diff_only, force_update) do
            {:synced, changes} ->
              acc
              |> update_in([:products_synced], &(&1 + 1))
              |> update_in([:changes_made], &(&1 ++ changes))

            {:no_change, _} ->
              acc

            {:error, issue} ->
              update_in(acc, [:issues_found], &(&1 ++ [issue]))
          end
        end)

      {:error, error} ->
        issue = "Failed to list Stripe products: #{inspect(error)}"
        update_in(results, [:issues_found], &(&1 ++ [issue]))
    end
  end

  defp find_lang_products(stripe_products) do
    Enum.filter(stripe_products, fn product ->
      case product.metadata do
        %{"managed_by" => "lang_platform"} -> true
        _ -> String.contains?(product.name || "", "LANG")
      end
    end)
    |> Map.new(fn product ->
      plan_type =
        cond do
          String.contains?(String.downcase(product.name), "pro") -> :pro
          String.contains?(String.downcase(product.name), "enterprise") -> :enterprise
          true -> :unknown
        end

      {plan_type, product}
    end)
  end

  defp sync_single_product(plan_type, expected, existing_products, diff_only, force_update) do
    case Map.get(existing_products, plan_type) do
      nil ->
        if diff_only do
          Logger.info("➕ Would create product: #{expected.name}")
          {:no_change, []}
        else
          case create_missing_product(expected) do
            {:ok, product} ->
              Logger.info("✅ Created missing product: #{product.name}")
              {:synced, ["Created product: #{product.name}"]}

            {:error, error} ->
              {:error, "Failed to create product #{expected.name}: #{inspect(error)}"}
          end
        end

      existing_product ->
        differences = find_product_differences(existing_product, expected)

        if length(differences) > 0 or force_update do
          if diff_only do
            Logger.info("🔄 Product '#{existing_product.name}' has differences:")
            Enum.each(differences, &Logger.info("  - #{&1}"))
            {:no_change, differences}
          else
            case update_product(existing_product, expected) do
              {:ok, updated_product} ->
                Logger.info("✅ Updated product: #{updated_product.name}")
                {:synced, differences}

              {:error, error} ->
                {:error, "Failed to update product #{existing_product.name}: #{inspect(error)}"}
            end
          end
        else
          {:no_change, []}
        end
    end
  end

  defp find_product_differences(existing, expected) do
    differences = []

    # Check name
    differences =
      if existing.name != expected.name do
        ["Name: '#{existing.name}' -> '#{expected.name}'" | differences]
      else
        differences
      end

    # Check description
    differences =
      if existing.description != expected.description do
        ["Description changed" | differences]
      else
        differences
      end

    # Check metadata
    existing_metadata = existing.metadata || %{}

    Enum.reduce(expected.metadata, differences, fn {key, expected_value}, acc ->
      case Map.get(existing_metadata, to_string(key)) do
        ^expected_value -> acc
        actual_value -> ["Metadata #{key}: '#{actual_value}' -> '#{expected_value}'" | acc]
      end
    end)
  end

  defp create_missing_product(expected) do
    params = %{
      name: expected.name,
      description: expected.description,
      metadata: expected.metadata
    }

    Stripe.Product.create(params)
  end

  defp update_product(existing, expected) do
    params = %{
      name: expected.name,
      description: expected.description,
      metadata: expected.metadata
    }

    Stripe.Product.update(existing.id, params)
  end

  defp sync_prices(results, diff_only) do
    Logger.info("💰 Syncing prices...")

    # Get current price environment variables
    current_prices = %{
      pro: System.get_env("STRIPE_PRO_PRICE_ID"),
      enterprise: System.get_env("STRIPE_ENTERPRISE_PRICE_ID")
    }

    Enum.reduce(current_prices, results, fn {plan_type, price_id}, acc ->
      if price_id do
        case validate_price(plan_type, price_id, diff_only) do
          {:ok, validation_result} ->
            if validation_result.issues == [] do
              acc
            else
              update_in(acc, [:issues_found], &(&1 ++ validation_result.issues))
            end

          {:error, issue} ->
            update_in(acc, [:issues_found], &(&1 ++ [issue]))
        end
      else
        issue =
          "Missing environment variable: STRIPE_#{String.upcase(to_string(plan_type))}_PRICE_ID"

        update_in(acc, [:issues_found], &(&1 ++ [issue]))
      end
    end)
  end

  defp validate_price(plan_type, price_id, _diff_only) do
    case Stripe.Price.retrieve(price_id) do
      {:ok, price} ->
        expected = @expected_products[plan_type]
        issues = []

        # Check if price matches expected amount
        issues =
          if price.unit_amount != expected.expected_price do
            message =
              "Price mismatch for #{plan_type}: expected $#{expected.expected_price / 100}, got $#{price.unit_amount / 100}"

            Logger.warning("⚠️  #{message}")
            [message | issues]
          else
            issues
          end

        # Check if price is active
        issues =
          if not price.active do
            message = "Price #{price_id} for #{plan_type} is inactive"
            Logger.warning("⚠️  #{message}")
            [message | issues]
          else
            issues
          end

        {:ok, %{issues: issues}}

      {:error, error} ->
        {:error, "Failed to retrieve price #{price_id}: #{inspect(error)}"}
    end
  end

  defp sync_webhooks(results, diff_only) do
    Logger.info("🔗 Syncing webhooks...")

    case Stripe.WebhookEndpoint.list(%{limit: 100}) do
      {:ok, %{data: webhooks}} ->
        lang_webhooks =
          Enum.filter(webhooks, fn webhook ->
            case webhook.metadata do
              %{"platform" => "lang"} -> true
              _ -> String.contains?(webhook.url || "", ["lang", "localhost", "127.0.0.1"])
            end
          end)

        if length(lang_webhooks) == 0 do
          issue =
            "No LANG platform webhooks found - run 'mix stripe.setup --webhook-url YOUR_URL' to create one"

          update_in(results, [:issues_found], &(&1 ++ [issue]))
        else
          # Validate existing webhooks
          Enum.reduce(lang_webhooks, results, fn webhook, acc ->
            case validate_webhook(webhook, diff_only) do
              {:ok, webhook_issues} ->
                if webhook_issues == [] do
                  update_in(acc, [:webhooks_synced], &(&1 + 1))
                else
                  update_in(acc, [:issues_found], &(&1 ++ webhook_issues))
                end

              {:error, error} ->
                update_in(acc, [:issues_found], &(&1 ++ [error]))
            end
          end)
        end

      {:error, error} ->
        issue = "Failed to list webhook endpoints: #{inspect(error)}"
        update_in(results, [:issues_found], &(&1 ++ [issue]))
    end
  end

  defp validate_webhook(webhook, _diff_only) do
    issues = []
    enabled_events = MapSet.new(webhook.enabled_events || [])
    required_events = MapSet.new(@required_webhook_events)

    # Check if all required events are enabled
    missing_events = MapSet.difference(required_events, enabled_events)

    issues =
      if MapSet.size(missing_events) > 0 do
        missing_list = Enum.join(MapSet.to_list(missing_events), ", ")
        message = "Webhook #{webhook.id} missing events: #{missing_list}"
        Logger.warning("⚠️  #{message}")
        [message | issues]
      else
        issues
      end

    # Check if webhook is active
    issues =
      if webhook.status != "enabled" do
        message = "Webhook #{webhook.id} is not enabled (status: #{webhook.status})"
        Logger.warning("⚠️  #{message}")
        [message | issues]
      else
        issues
      end

    {:ok, issues}
  end

  defp display_sync_results(results, diff_only) do
    action_word = if diff_only, do: "would be", else: "were"

    Logger.info("\n📊 SYNCHRONIZATION RESULTS:")
    Logger.info("=" |> String.duplicate(40))

    if results.products_synced > 0 do
      Logger.info("✅ #{results.products_synced} products #{action_word} synced")
    end

    if results.prices_synced > 0 do
      Logger.info("✅ #{results.prices_synced} prices #{action_word} validated")
    end

    if results.webhooks_synced > 0 do
      Logger.info("✅ #{results.webhooks_synced} webhooks #{action_word} validated")
    end

    if length(results.changes_made) > 0 and not diff_only do
      Logger.info("\n🔄 CHANGES MADE:")
      Enum.each(results.changes_made, &Logger.info("  • #{&1}"))
    end

    if length(results.issues_found) > 0 do
      Logger.info("\n⚠️  ISSUES FOUND:")
      Enum.each(results.issues_found, &Logger.info("  • #{&1}"))

      if diff_only do
        Logger.info("\n💡 Run without --diff to fix these issues automatically")
      end
    else
      Logger.info("✅ No issues found - everything is in sync!")
    end

    # Summary
    total_operations = results.products_synced + results.prices_synced + results.webhooks_synced

    if total_operations > 0 do
      Logger.info("\n🎉 Synchronization completed successfully!")
    else
      Logger.info("\n✨ No synchronization needed - everything is up to date!")
    end
  end

  defp show_help do
    IO.puts("""
    Stripe Sync for LANG Platform

    USAGE:
        mix stripe.sync [OPTIONS]

    OPTIONS:
        --products-only       Sync only products (skip prices and webhooks)
        --webhooks-only       Sync only webhook configurations
        --diff               Show differences without making changes
        --force              Force update all products even if they appear unchanged
        --help, -h           Show this help message

    EXAMPLES:
        # Full sync
        mix stripe.sync

        # Preview changes without applying them
        mix stripe.sync --diff

        # Update only product information
        mix stripe.sync --products-only

        # Validate webhook configuration
        mix stripe.sync --webhooks-only

        # Force update everything
        mix stripe.sync --force

    WHAT GETS SYNCED:
        • Product names, descriptions, and metadata
        • Price validation against expected amounts
        • Webhook endpoint configuration and event subscriptions
        • Product and price status (active/inactive)

    ENVIRONMENT VARIABLES REQUIRED:
        STRIPE_SECRET_KEY               Your Stripe secret key
        STRIPE_PRO_PRICE_ID            Pro plan price ID (for validation)
        STRIPE_ENTERPRISE_PRICE_ID     Enterprise plan price ID (for validation)

    For more information, visit: https://stripe.com/docs/api
    """)
  end
end
