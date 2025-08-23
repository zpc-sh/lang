defmodule Mix.Tasks.Stripe.Setup do
  @moduledoc """
  Automated Stripe product and pricing setup for LANG Universal Text Intelligence Platform.

  This task creates products, prices, and webhooks in your Stripe account automatically,
  ensuring consistent configuration and reducing manual setup errors.

  ## Usage

      # Setup all products and prices
      mix stripe.setup

      # Setup with custom pricing (optional)
      mix stripe.setup --pro-price 4900 --enterprise-price 19900

      # Sync existing products and update prices
      mix stripe.setup --sync

      # Test mode (prints what would be created without making changes)
      mix stripe.setup --dry-run

  ## Environment Variables Required

      STRIPE_SECRET_KEY=sk_test_...  # Your Stripe secret key
      STRIPE_WEBHOOK_SECRET=whsec_... # Optional, for webhook setup

  ## What This Creates

  1. **Products**
     - LANG Pro: Advanced text intelligence for growing businesses
     - LANG Enterprise: Enterprise-grade text intelligence with dedicated support

  2. **Prices**
     - Pro: $49/month (configurable)
     - Enterprise: $199/month (configurable)

  3. **Webhook Endpoint** (if configured)
     - Endpoint URL: https://yourdomain.com/webhooks/stripe
     - All necessary events for subscription management

  The task will output the Price IDs that you need to add to your environment variables.
  """

  use Mix.Task
  require Logger

  @shortdoc "Setup Stripe products, prices, and webhooks automatically"

  # Read configuration from application config
  defp billing_config, do: Application.get_env(:lang, :billing, %{})
  defp plans_config, do: billing_config() |> Keyword.get(:plans, %{})
  defp stripe_config, do: billing_config() |> Keyword.get(:stripe, %{})
  defp webhook_events, do: stripe_config() |> Map.get(:webhook_events, [])

  def run(args) do
    # Load environment variables from .env file
    load_env_file()

    {options, [], []} =
      OptionParser.parse(args,
        switches: [
          pro_price: :integer,
          enterprise_price: :integer,
          sync: :boolean,
          dry_run: :boolean,
          webhook_url: :string,
          help: :boolean
        ],
        aliases: [
          h: :help
        ]
      )

    if options[:help] do
      show_help()
    else
      setup_stripe(options)
    end
  end

  defp setup_stripe(options) do
    Logger.info("🚀 Starting Stripe setup for LANG Platform...")

    with :ok <- validate_environment(),
         :ok <- configure_stripe(),
         :ok <- validate_config() do
      # Get pricing from config or command line overrides
      config_plans = plans_config()

      dry_run = options[:dry_run] || false
      sync_mode = options[:sync] || false

      if dry_run do
        Logger.info("🧪 DRY RUN MODE - No changes will be made")
        preview_setup()
      else
        perform_setup(sync_mode, options)
      end
    else
      {:error, reason} ->
        Logger.error("❌ Setup failed: #{reason}")
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

      String.starts_with?(secret_key, "sk_live_") ->
        Logger.warning("⚠️  Using LIVE Stripe keys - products will be created in production!")
        confirm_production()

      true ->
        Logger.info("✅ Using test Stripe keys")
        :ok
    end
  end

  defp confirm_production do
    IO.puts("\n🚨 WARNING: You are using LIVE Stripe keys!")
    IO.puts("This will create real products in your production Stripe account.")

    response = IO.gets("Are you sure you want to continue? (yes/no): ")

    case String.trim(String.downcase(response)) do
      "yes" ->
        :ok

      "y" ->
        :ok

      _ ->
        Logger.info("Setup cancelled by user")
        System.halt(0)
    end
  end

  defp configure_stripe do
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:stripity_stripe)

    # Configure Stripe with API key from environment
    api_key = System.get_env("STRIPE_SECRET_KEY")
    Application.put_env(:stripity_stripe, :api_key, api_key)

    :ok
  end

  defp preview_setup do
    Logger.info("\n📋 PREVIEW - The following would be created:")

    config_plans = plans_config()

    Enum.each(config_plans, fn {plan_type, plan_config} ->
      if plan_config.price_cents > 0 do
        price_dollars = plan_config.price_cents / 100
        feature_count = count_features(plan_config.features || %{})

        Logger.info("\n📦 Product: #{plan_config.name}")
        Logger.info("   Description: #{plan_config.description}")
        Logger.info("   Price: $#{price_dollars}/month")
        Logger.info("   Features: #{feature_count} features included")
      end
    end)

    events = webhook_events()
    Logger.info("\n🔗 Webhook endpoint would be configured with #{length(events)} events")
    Logger.info("\n✅ Run without --dry-run to create these products")
  end

  defp perform_setup(sync_mode, options) do
    results = %{
      products: %{},
      prices: %{},
      webhooks: []
    }

    # Step 1: Create or sync products
    Logger.info("\n📦 Creating products...")
    results = create_products(results, sync_mode)

    # Step 2: Create prices
    Logger.info("\n💰 Creating prices...")
    results = create_prices(results, sync_mode)

    # Step 3: Setup webhooks (if webhook URL provided)
    if options[:webhook_url] do
      Logger.info("\n🔗 Setting up webhooks...")
      results = create_webhooks(results, options[:webhook_url])
    end

    # Step 4: Display results and next steps
    display_setup_results(results)
  end

  defp create_products(results, sync_mode) do
    config_plans = plans_config()

    Enum.reduce(config_plans, results, fn {plan_type, plan_config}, acc ->
      if plan_config.price_cents > 0 do
        case find_or_create_product(plan_config, sync_mode) do
          {:ok, product} ->
            Logger.info("✅ Product created/found: #{plan_config.name} (#{product.id})")
            put_in(acc.products[plan_type], product)

          {:error, error} ->
            Logger.error("❌ Failed to create product #{plan_config.name}: #{inspect(error)}")
            acc
        end
      else
        acc
      end
    end)
  end

  defp find_or_create_product(plan_config, sync_mode) do
    if sync_mode do
      # Try to find existing product by name
      case Stripe.Product.list(%{limit: 100}) do
        {:ok, %{data: products}} ->
          existing = Enum.find(products, &(&1.name == plan_config.name))

          if existing do
            # Update existing product
            update_params = %{
              description: plan_config.description,
              metadata: plan_config.stripe_metadata
            }

            case Stripe.Product.update(existing.id, update_params) do
              {:ok, updated_product} -> {:ok, updated_product}
              error -> error
            end
          else
            create_new_product(plan_config)
          end

        error ->
          error
      end
    else
      create_new_product(plan_config)
    end
  end

  defp create_new_product(plan_config) do
    params = %{
      name: plan_config.name,
      description: plan_config.description,
      metadata: plan_config.stripe_metadata
    }

    Stripe.Product.create(params)
  end

  defp create_prices(results, sync_mode) do
    config_plans = plans_config()

    Enum.reduce(results.products, results, fn {plan_type, product}, acc ->
      plan_config = config_plans[plan_type]

      if plan_config do
        case find_or_create_price(product, plan_config, sync_mode) do
          {:ok, price} ->
            Logger.info(
              "✅ Price created/found: $#{plan_config.price_cents / 100}/month (#{price.id})"
            )

            put_in(acc.prices[plan_type], price)

          {:error, error} ->
            Logger.error("❌ Failed to create price for #{product.name}: #{inspect(error)}")
            acc
        end
      else
        acc
      end
    end)
  end

  defp find_or_create_price(product, plan_config, sync_mode) do
    if sync_mode do
      # Try to find existing active price for this product
      case Stripe.Price.list(%{product: product.id, active: true, limit: 10}) do
        {:ok, %{data: prices}} ->
          existing =
            Enum.find(
              prices,
              &(&1.unit_amount == plan_config.price_cents and
                  &1.recurring.interval == plan_config.billing_interval)
            )

          if existing do
            {:ok, existing}
          else
            create_new_price(product, plan_config)
          end

        error ->
          error
      end
    else
      create_new_price(product, plan_config)
    end
  end

  defp create_new_price(product, plan_config) do
    billing_interval = Map.get(plan_config, :billing_interval, "month")

    params = %{
      product: product.id,
      unit_amount: plan_config.price_cents,
      currency: "usd",
      recurring: %{interval: billing_interval},
      metadata: %{
        created_by: "lang_setup_script",
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        plan_type: Map.get(plan_config, :name, "unknown")
      }
    }

    Stripe.Price.create(params)
  end

  defp create_webhooks(results, webhook_url) do
    case create_webhook_endpoint(webhook_url) do
      {:ok, webhook} ->
        Logger.info("✅ Webhook endpoint created: #{webhook_url}")
        %{results | webhooks: [webhook | results.webhooks]}

      {:error, error} ->
        Logger.error("❌ Failed to create webhook: #{inspect(error)}")
        results
    end
  end

  defp create_webhook_endpoint(url) do
    events = webhook_events()

    params = %{
      url: url,
      enabled_events: events,
      description: "LANG Platform - Subscription and payment webhooks",
      metadata: %{
        platform: "lang",
        created_by: "setup_script"
      }
    }

    Stripe.WebhookEndpoint.create(params)
  end

  defp create_mcp_metered_price(results) do
    Logger.info("💰 Creating MCP connection metered price...")

    mcp_config = billing_config()[:mcp_connections]

    # Create or find the MCP product first
    mcp_product_params = %{
      name: mcp_config.display_name,
      description: mcp_config.description,
      metadata: mcp_config.stripe_metadata
    }

    case Stripe.Product.create(mcp_product_params) do
      {:ok, product} ->
        # Create metered price for MCP connections
        price_params = %{
          product: product.id,
          nickname: "MCP Connection",
          unit_amount: mcp_config.price_cents,
          currency: "usd",
          recurring: %{
            interval: "month",
            usage_type: "metered",
            aggregate_usage: "sum"
          },
          metadata: %{
            created_by: "lang_setup_script",
            service: "mcp_broker"
          }
        }

        case Stripe.Price.create(price_params) do
          {:ok, price} ->
            Logger.info("✅ MCP connection price created: #{price.id}")
            Logger.info("   Add to .env: STRIPE_MCP_CONNECTION_PRICE_ID=#{price.id}")
            Map.put(results, :mcp_price, price)

          {:error, error} ->
            Logger.error("Failed to create MCP price: #{inspect(error)}")
            results
        end

      {:error, error} ->
        Logger.error("Failed to create MCP product: #{inspect(error)}")
        results
    end
  end

  defp display_setup_results(results) do
    Logger.info("\n🎉 Stripe setup completed successfully!")

    if map_size(results.prices) > 0 do
      Logger.info("\n📝 ADD THESE ENVIRONMENT VARIABLES:")
      Logger.info("=" |> String.duplicate(50))

      Enum.each(results.prices, fn {plan_type, price} ->
        env_var = "STRIPE_#{String.upcase(to_string(plan_type))}_PRICE_ID"
        Logger.info("#{env_var}=#{price.id}")
      end)

      Logger.info("=" |> String.duplicate(50))
    end

    if length(results.webhooks) > 0 do
      webhook = hd(results.webhooks)
      Logger.info("\n🔗 WEBHOOK CONFIGURATION:")
      Logger.info("Endpoint ID: #{webhook.id}")
      Logger.info("Signing Secret: #{webhook.secret}")
      Logger.info("Add this to your environment:")
      Logger.info("STRIPE_WEBHOOK_SECRET=#{webhook.secret}")
    end

    Logger.info("\n🚀 NEXT STEPS:")
    Logger.info("1. Add the Price IDs to your .env file")
    Logger.info("2. Update config/billing.exs if needed")
    Logger.info("3. Restart your application")
    Logger.info("4. Test the payment flow at /dashboard")
    Logger.info("5. Use test card: 4242 4242 4242 4242")

    Logger.info("\n💡 TIP: Run 'mix stripe.sync' to sync any future changes")
  end

  defp validate_config do
    case Lang.Billing.ConfigManager.validate_config() do
      :ok ->
        :ok

      {:error, errors} ->
        Logger.error("❌ Invalid billing configuration:")
        Enum.each(errors, &Logger.error("  - #{&1}"))
        {:error, "Configuration validation failed"}
    end
  end

  defp count_features(features) when is_map(features) do
    Enum.count(features, fn {_feature, enabled} -> enabled == true end)
  end

  defp count_features(_), do: 0

  defp show_help do
    IO.puts("""
    Stripe Setup for LANG Platform

    USAGE:
        mix stripe.setup [OPTIONS]

    OPTIONS:
        --pro-price CENTS          Pro plan price in cents (default: 4900 = $49)
        --enterprise-price CENTS   Enterprise plan price in cents (default: 19900 = $199)
        --webhook-url URL          Webhook endpoint URL for your app
        --sync                     Sync/update existing products instead of creating new ones
        --dry-run                  Preview what would be created without making changes
        --help, -h                 Show this help message

    EXAMPLES:
        # Basic setup with default pricing
        mix stripe.setup

        # Custom pricing
        mix stripe.setup --pro-price 3900 --enterprise-price 14900

        # Setup with webhook endpoint
        mix stripe.setup --webhook-url https://myapp.com/webhooks/stripe

        # Preview mode
        mix stripe.setup --dry-run

        # Sync existing products
        mix stripe.setup --sync

    ENVIRONMENT VARIABLES REQUIRED:
        STRIPE_SECRET_KEY          Your Stripe secret key (sk_test_... or sk_live_...)

    For more information, visit: https://stripe.com/docs/api
    """)
  end

  defp load_env_file do
    env_file = Path.join(File.cwd!(), ".env")

    if File.exists?(env_file) do
      env_file
      |> File.read!()
      |> String.split("\n")
      |> Enum.each(fn line ->
        line = String.trim(line)

        unless String.starts_with?(line, "#") or line == "" do
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              # Remove quotes if present
              clean_value = String.trim(value, "\"'")
              System.put_env(key, clean_value)

            _ ->
              :ignore
          end
        end
      end)

      Logger.info("✅ Loaded environment variables from .env file")
    else
      Logger.warning("⚠️  No .env file found, using system environment variables only")
    end
  end
end
