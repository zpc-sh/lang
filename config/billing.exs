import Config

# Billing Configuration for LANG Universal Text Intelligence Platform
#
# This file contains all pricing plans, features, and limits for the platform.
# It serves as the single source of truth for billing configuration that
# automatically syncs with Stripe.

config :lang, :billing,
  # Stripe integration settings
  stripe: %{
    auto_sync: System.get_env("STRIPE_AUTO_SYNC", "true") == "true",
    sync_interval_minutes: String.to_integer(System.get_env("STRIPE_SYNC_INTERVAL", "60")),
    webhook_events: [
      "customer.subscription.created",
      "customer.subscription.updated",
      "customer.subscription.deleted",
      "invoice.payment_succeeded",
      "invoice.payment_failed",
      "checkout.session.completed",
      "customer.updated",
      "customer.deleted",
      "payment_intent.succeeded",
      "payment_intent.payment_failed"
    ]
  },

  # Plan definitions - single source of truth
  plans: %{
    free: %{
      name: "Free",
      display_name: "Free Plan",
      price_cents: 0,
      price_dollars: 0,
      billing_interval: "month",
      requests_per_month: 1_000,
      description: "Perfect for getting started with text intelligence",
      stripe_metadata: %{
        plan_type: "free",
        managed_by: "lang_platform",
        category: "starter"
      },
      features: %{
        # Core features
        basic_text_analysis: true,
        api_access: true,
        community_support: true,
        # Advanced features (disabled)
        advanced_analytics: false,
        priority_support: false,
        webhook_integrations: false,
        team_collaboration: false,
        custom_integrations: false,
        sla_guarantee: false,
        dedicated_support: false,
        sso_integration: false,
        white_label: false,
        custom_deployment: false
      },
      limits: %{
        requests_per_month: 1_000,
        requests_per_minute: 10,
        requests_per_hour: 100,
        team_members: 1,
        api_keys: 1,
        webhook_endpoints: 0,
        custom_integrations: 0,
        data_retention_days: 30,
        support_response_time_hours: 72
      }
    },
    pro: %{
      name: "Pro",
      display_name: "Pro Plan",
      # $49.00
      price_cents: 4900,
      price_dollars: 49,
      billing_interval: "month",
      requests_per_month: 50_000,
      description: "Advanced text intelligence for growing businesses",
      # Show "Most Popular" badge
      popular: true,
      stripe_metadata: %{
        plan_type: "pro",
        managed_by: "lang_platform",
        category: "business",
        popular: "true"
      },
      features: %{
        # All free features
        basic_text_analysis: true,
        api_access: true,
        community_support: true,
        # Pro features
        advanced_analytics: true,
        priority_support: true,
        webhook_integrations: true,
        team_collaboration: true,
        custom_integrations: true,
        # Enterprise features (disabled)
        sla_guarantee: false,
        dedicated_support: false,
        sso_integration: false,
        white_label: false,
        custom_deployment: false
      },
      limits: %{
        requests_per_month: 50_000,
        requests_per_minute: 100,
        requests_per_hour: 2_500,
        team_members: 5,
        api_keys: 5,
        webhook_endpoints: 5,
        custom_integrations: 10,
        data_retention_days: 90,
        support_response_time_hours: 24
      }
    },
    enterprise: %{
      name: "Enterprise",
      display_name: "Enterprise Plan",
      # $199.00
      price_cents: 19900,
      price_dollars: 199,
      billing_interval: "month",
      requests_per_month: 500_000,
      description: "Enterprise-grade text intelligence with dedicated support",
      stripe_metadata: %{
        plan_type: "enterprise",
        managed_by: "lang_platform",
        category: "enterprise",
        sla_guarantee: "true",
        dedicated_support: "true"
      },
      features: %{
        # All previous features
        basic_text_analysis: true,
        api_access: true,
        community_support: true,
        advanced_analytics: true,
        priority_support: true,
        webhook_integrations: true,
        team_collaboration: true,
        custom_integrations: true,
        # Enterprise features
        sla_guarantee: true,
        dedicated_support: true,
        sso_integration: true,
        white_label: true,
        custom_deployment: true
      },
      limits: %{
        requests_per_month: 500_000,
        requests_per_minute: 1_000,
        requests_per_hour: 25_000,
        team_members: :unlimited,
        api_keys: :unlimited,
        webhook_endpoints: :unlimited,
        custom_integrations: :unlimited,
        data_retention_days: 365,
        support_response_time_hours: 4
      }
    }
  },

  # Feature categories for easy management
  feature_categories: %{
    core: [:basic_text_analysis, :api_access, :community_support],
    analytics: [:advanced_analytics],
    support: [:priority_support, :dedicated_support],
    integrations: [:webhook_integrations, :custom_integrations, :sso_integration],
    collaboration: [:team_collaboration],
    enterprise: [:sla_guarantee, :white_label, :custom_deployment]
  },

  # Overage pricing (when customers exceed plan limits)
  overage: %{
    # Cost per 1K requests beyond plan limit (multiplier of plan rate)
    requests_multiplier: 2.0,
    # Minimum overage charge in cents
    minimum_charge_cents: 100,
    # Grace period before charging overages (hours)
    grace_period_hours: 24
  },

  # Revenue optimization settings
  optimization: %{
    # Show upgrade prompts at usage percentage
    upgrade_prompt_threshold: 0.8,
    # Show critical warnings at usage percentage
    critical_warning_threshold: 0.95,
    # Enable usage-based upgrade recommendations
    smart_recommendations: true
  }

# Environment-specific overrides
case config_env() do
  :dev ->
    config :lang, :billing,
      stripe: %{
        auto_sync: false,
        sync_interval_minutes: 5
      }

  :test ->
    config :lang, :billing,
      stripe: %{
        auto_sync: false,
        sync_interval_minutes: 999_999
      },
      plans: %{
        # Test plans with lower limits for faster testing
        free: %{
          name: "Test Free",
          price_cents: 0,
          requests_per_month: 10,
          limits: %{requests_per_minute: 2}
        },
        pro: %{
          name: "Test Pro",
          # $1.00 for testing
          price_cents: 100,
          requests_per_month: 100,
          limits: %{requests_per_minute: 10}
        }
      }

  :prod ->
    config :lang, :billing,
      stripe: %{
        auto_sync: true,
        sync_interval_minutes: 60
      }
end
