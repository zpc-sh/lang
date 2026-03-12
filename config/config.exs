# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Import billing configuration
import_config "billing.exs"

# AI Provider API Keys
config :lang, :ai_providers,
  xai_api_key: System.get_env("XAI_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

config :lang,
  ecto_repos: [Lang.Repo],
  generators: [timestamp_type: :utc_datetime],
  env: Mix.env(),
  # Register Ash Domains used across the app
  ash_domains: [
    Lang.Accounts,
    Lang.Events,
    Lang.MCP,
    Lang.Git,
    Lang.Billing,
    Lang.Analyses,
    Lang.Think,
    Lang.Generate,
    Lang.Spatial,
    Lang.Tokens,
    Lang.Query
  ]

# Configures the endpoint
config :lang, LangWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LangWeb.ErrorHTML, json: LangWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Lang.PubSub,
  live_view: [signing_salt: "placeholder-will-be-replaced-in-runtime"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :lang, Lang.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  lang: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --alias:phoenix-colocated=../_build/dev/phoenix-colocated),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  lang: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# JSON-LD MIME and encoders
config :mime, :types, %{
  "application/ld+json" => ["jsonld"],
  "application/markdown-ld+json" => ["mdld", "markdownld", "markdown-ld"]
}

config :mime, :extensions, %{
  "json" => "application/json",
  "jsonld" => "application/ld+json",
  "mdld" => "application/markdown-ld+json"
}

config :phoenix, :format_encoders, jsonld: Jason, mdld: Jason

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, Swoosh.ApiClient.Finch

# Configure the mailer
config :lang, Lang.Mailer, adapter: Swoosh.Adapters.Local

# Force local compilation of Rust NIFs instead of downloading precompiled binaries
config :rustler_precompiled, :force_build,
  lang_parser: true,
  lang_perf: true,
  fs_watcher: true,
  tree_parser: true

# Configure Ash
config :ash, :validate_domain_resource_inclusion?, false
config :ash, :validate_domain_config_inclusion?, false

# Configure Oban
config :lang, Oban,
  repo: Lang.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       # Generate MCP spec monthly at 03:15 UTC on the 1st
       {"15 3 1 * *", Lang.Workers.MCPEnvironment, args: %{"task" => "generate_spec"}},
       # Billing/usage background pipeline
       {"0 * * * *", Lang.Workers.BillingAggregateUsageWorker, args: %{}},
       {"30 3 * * *", Lang.Workers.BillingCleanupUsageWorker, args: %{}},
       {"15 * * * *", Lang.Workers.BillingStripeUsageReporter, args: %{}}
     ]}
  ],
  queues: [
    default: 10,
    # Increased for document processing
    analysis: 20,
    # For filesystem operations
    lsp: 20,
    # For telemetry and monitoring
    metrics: 15,
    cleanup: 2,
    # New queue for SDK generation
    sdk_generation: 5,
    # New queue for publishing
    publishing: 3,
    # New queue for marketing content
    marketing: 2
  ]

# Analysis pipeline configuration
config :lang, :analysis,
  finalize_delay_seconds: 120,
  run_finalize_reschedule_seconds: 60

# Configure LANG-specific settings
config :lang, :text_intelligence,
  default_analysis_timeout: 30_000,
  max_document_size_mb: 50,
  supported_formats: ["markdown", "javascript", "python", "conversation", "json", "yaml"]

config :lang, :lsp,
  port: 4001,
  host: "127.0.0.1",
  max_connections: 1000

config :lang, :conversation_rehearsal,
  max_session_duration_hours: 2,
  max_conversation_turns: 1000,
  prediction_model_timeout: 5_000

config :lang, :stylometrics,
  min_text_length_for_analysis: 100,
  confidence_threshold: 0.7,
  obfuscation_intensity_default: 0.5

config :lang, :timeline,
  max_states_per_timeline: 10000,
  cleanup_interval_minutes: 30,
  snapshot_retention_days: 90

config :lang, :security,
  rate_limit_cleanup_interval: 60_000,
  default_rate_limit: %{limit: 100, window: 3600, block_duration: 300}

# Configure Stripe payment processing
config :stripity_stripe,
  api_key: {:system, "STRIPE_SECRET_KEY"},
  public_key: {:system, "STRIPE_PUBLISHABLE_KEY"}

config :lang, :stripe,
  webhook_secret: {:system, "STRIPE_WEBHOOK_SECRET"},
  success_url: {:system, "STRIPE_SUCCESS_URL", "http://localhost:4000/billing?success=true"},
  cancel_url: {:system, "STRIPE_CANCEL_URL", "http://localhost:4000/billing?cancelled=true"},
  # Price IDs for each plan (set in environment)
  price_ids: %{
    plus: {:system, "STRIPE_PLUS_PRICE_ID"},
    pro: {:system, "STRIPE_PRO_PRICE_ID"},
    business: {:system, "STRIPE_BUSINESS_PRICE_ID"}
  }

# Configure Redis for caching and metrics
config :lang,
  redis_url: "redis://localhost:6379/0"

config :nx, :default_defn_options, compiler: EXLA
# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

import_config "events.exs"
