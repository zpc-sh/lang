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
      "invoice.finalized",
      "checkout.session.completed",
      "customer.updated",
      "customer.deleted",
      "payment_intent.succeeded",
      "payment_intent.payment_failed",
      "price.updated",
      "product.updated"
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
      requests_per_month: 100,
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
        all_text_formats: false,
        email_support: false,
        network_analysis: false,
        filesystem_scanning: false,
        database_analysis: false,
        log_intelligence: false,
        advanced_analytics: false,
        priority_support: false,
        webhook_integrations: false,
        team_collaboration: false,
        custom_integrations: false,
        sla_guarantee: false,
        sso_integration: false,
        mfa_support: false,
        audit_logs: false
      },
      limits: %{
        documents_per_month: 100,
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
    plus: %{
      name: "Plus",
      display_name: "Plus Plan",
      price_cents: 1900,
      price_dollars: 19,
      billing_interval: "month",
      requests_per_month: 2_500,
      description: "More access to text intelligence",
      stripe_metadata: %{
        plan_type: "plus",
        managed_by: "lang_platform",
        category: "professional"
      },
      features: %{
        # All free features
        basic_text_analysis: true,
        api_access: true,
        community_support: true,
        # Plus features
        all_text_formats: true,
        email_support: true,
        # Advanced features (disabled)
        network_analysis: false,
        filesystem_scanning: false,
        database_analysis: false,
        log_intelligence: false,
        advanced_analytics: false,
        priority_support: false,
        webhook_integrations: false,
        team_collaboration: false,
        custom_integrations: false,
        sla_guarantee: false,
        sso_integration: false,
        mfa_support: false,
        audit_logs: false
      },
      limits: %{
        documents_per_month: 2_500,
        requests_per_minute: 50,
        requests_per_hour: 500,
        team_members: 1,
        api_keys: 3,
        webhook_endpoints: 0,
        custom_integrations: 0,
        data_retention_days: 60,
        support_response_time_hours: 48
      }
    },
    pro: %{
      name: "Pro",
      display_name: "Pro Plan",
      price_cents: 4900,
      price_dollars: 49,
      billing_interval: "month",
      requests_per_month: 10_000,
      description: "Universal intelligence beyond text",
      # Show "Most Popular" badge
      popular: true,
      stripe_metadata: %{
        plan_type: "pro",
        managed_by: "lang_platform",
        category: "business",
        popular: "true"
      },
      features: %{
        # All previous features
        basic_text_analysis: true,
        api_access: true,
        community_support: true,
        all_text_formats: true,
        email_support: true,
        # Pro features - Beyond text!
        network_analysis: true,
        filesystem_scanning: true,
        database_analysis: true,
        log_intelligence: true,
        advanced_analytics: true,
        priority_support: true,
        webhook_integrations: true,
        # Business features (disabled)
        team_collaboration: false,
        custom_integrations: false,
        sla_guarantee: false,
        sso_integration: false,
        mfa_support: false,
        audit_logs: false
      },
      limits: %{
        documents_per_month: 10_000,
        requests_per_minute: 200,
        requests_per_hour: 5_000,
        team_members: 3,
        api_keys: 10,
        webhook_endpoints: 5,
        custom_integrations: 0,
        data_retention_days: 90,
        support_response_time_hours: 24
      }
    },
    business: %{
      name: "Business",
      display_name: "Business Plan",
      price_cents: 2500,
      price_dollars: 25,
      billing_interval: "month",
      billing_type: "per_user",
      minimum_users: 2,
      requests_per_month: 999_999_999,
      description: "Secure team workspace with collaboration",
      stripe_metadata: %{
        plan_type: "business",
        managed_by: "lang_platform",
        category: "team",
        billing_type: "per_user",
        minimum_users: "2"
      },
      features: %{
        # All Pro features
        basic_text_analysis: true,
        api_access: true,
        community_support: true,
        all_text_formats: true,
        email_support: true,
        network_analysis: true,
        filesystem_scanning: true,
        database_analysis: true,
        log_intelligence: true,
        advanced_analytics: true,
        priority_support: true,
        webhook_integrations: true,
        # Business features
        team_collaboration: true,
        custom_integrations: true,
        sla_guarantee: true,
        sso_integration: true,
        mfa_support: true,
        audit_logs: true
      },
      limits: %{
        documents_per_month: :unlimited,
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
    text_processing: [:all_text_formats],
    beyond_text: [:network_analysis, :filesystem_scanning, :database_analysis, :log_intelligence],
    analytics: [:advanced_analytics],
    support: [:email_support, :priority_support],
    integrations: [:webhook_integrations, :custom_integrations],
    team: [:team_collaboration, :audit_logs],
    security: [:sso_integration, :mfa_support, :sla_guarantee]
  },

  # Overage pricing (when customers exceed plan limits)
  overage: %{
    # Cost per 1K documents beyond plan limit
    price_per_1k_documents_cents: 500,
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
          limits: %{documents_per_month: 10, requests_per_minute: 2}
        },
        plus: %{
          name: "Test Plus",
          price_cents: 100,
          requests_per_month: 50,
          limits: %{documents_per_month: 50, requests_per_minute: 5}
        },
        pro: %{
          name: "Test Pro",
          price_cents: 200,
          requests_per_month: 100,
          limits: %{documents_per_month: 100, requests_per_minute: 10}
        }
      }

  :prod ->
    config :lang, :billing,
      stripe: %{
        auto_sync: true,
        sync_interval_minutes: 60
      }
end
