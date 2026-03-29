import Config

# Production runtime configuration for LANG
# This configuration works with the existing Lang.Security.Secrets system
# while providing fallbacks for standard deployment practices.

# Load secrets with proper fallbacks for production deployment
secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

live_view_salt =
  System.get_env("LIVE_VIEW_SIGNING_SALT") ||
    System.get_env("SECRET_KEY_BASE") |> String.slice(0, 32)

ash_auth_secret =
  System.get_env("ASH_AUTHENTICATION_SECRET") ||
    System.get_env("SECRET_KEY_BASE") |> String.slice(32, 32)

# Configure LiveView with proper signing salt
config :lang, LangWeb.Endpoint, live_view: [signing_salt: live_view_salt]

# Configure AshAuthentication with proper secret
config :lang, :ash_authentication, signing_secret: ash_auth_secret

# Database configuration - support both individual vars and DATABASE_URL
database_url = System.get_env("DATABASE_URL")
maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

if database_url do
  config :lang, Lang.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true,
    ssl_opts: [verify: :verify_none],
    socket_options: maybe_ipv6,
    # Important for Neon/Supabase compatibility
    prepare: :unnamed
else
  config :lang, Lang.Repo,
    username: System.get_env("DATABASE_USERNAME") || "postgres",
    password: System.get_env("DATABASE_PASSWORD") || raise("DATABASE_PASSWORD is required"),
    hostname: System.get_env("DATABASE_HOST") || "localhost",
    database: System.get_env("DATABASE_NAME") || "lang_prod",
    port: String.to_integer(System.get_env("DATABASE_PORT") || "5432"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6
end

# Phoenix endpoint configuration
host = System.get_env("PHX_HOST") || "lang.nocsi.com"
port = String.to_integer(System.get_env("PORT") || "4000")

config :lang, LangWeb.Endpoint,
  url: [host: host, port: 443, scheme: "https"],
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: port
  ],
  secret_key_base: secret_key_base,
  server: true

# Stripe configuration
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY"),
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

# Oban configuration for background jobs
config :lang, Oban,
  repo: Lang.Repo,
  queues: [
    default: 10,
    analysis: 5,
    lsp: 20,
    metrics: 15,
    cleanup: 2,
    billing: 3,
    # For your LANG 2.0 orchestration system
    orchestration: 8,
    # For Rust NIF processing
    native: 4
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 2 * * *", Lang.Workers.CleanupWorker},
       {"*/15 * * * *", Lang.Workers.MetricsWorker},
       {"0 */6 * * *", Lang.Workers.BillingSync}
     ]}
  ]

# Redis configuration for caching
redis_url = System.get_env("REDIS_URL") || "redis://localhost:6379/0"
config :lang, :redis_url, redis_url

# Configure Redix for health checks
config :redix,
  host: System.get_env("REDIS_HOST") || "localhost",
  port: String.to_integer(System.get_env("REDIS_PORT") || "6379"),
  database: String.to_integer(System.get_env("REDIS_DB") || "0")

# External API configurations (optional)
if openai_key = System.get_env("OPENAI_API_KEY") do
  config :lang, :openai, api_key: openai_key
end

if sendgrid_key = System.get_env("SENDGRID_API_KEY") do
  config :lang, Lang.Mailer,
    adapter: Swoosh.Adapters.Sendgrid,
    api_key: sendgrid_key
end

# R2/S3 configuration for file storage (optional)
if r2_key = System.get_env("R2_ACCESS_KEY") do
  config :ex_aws,
    access_key_id: r2_key,
    secret_access_key: System.get_env("R2_SECRET_KEY"),
    region: "auto",
    s3: [
      scheme: "https://",
      host: System.get_env("R2_ENDPOINT"),
      region: "auto"
    ]
end

# Security configurations
config :lang, :rate_limiting,
  enabled: true,
  global_limit: String.to_integer(System.get_env("RATE_LIMIT_GLOBAL") || "10000"),
  per_user_limit: String.to_integer(System.get_env("RATE_LIMIT_PER_USER") || "1000"),
  window_minutes: String.to_integer(System.get_env("RATE_LIMIT_WINDOW") || "60")

config :lang, :cors,
  origins: String.split(System.get_env("CORS_ORIGINS") || "https://lang.nocsi.com", ","),
  max_age: 86400

# Text processing limits for production
config :lang, :text_processing,
  max_file_size_mb: String.to_integer(System.get_env("MAX_FILE_SIZE_MB") || "50"),
  max_text_length: String.to_integer(System.get_env("MAX_TEXT_LENGTH") || "1000000"),
  timeout_seconds: String.to_integer(System.get_env("PROCESSING_TIMEOUT") || "30")

# Telemetry and logging
config :logger,
  level: String.to_atom(System.get_env("LOG_LEVEL") || "info"),
  metadata: [:request_id, :user_id, :session_id]

# DNS cluster configuration (if using clustering)
if cluster_query = System.get_env("DNS_CLUSTER_QUERY") do
  config :lang, :dns_cluster_query, cluster_query
end

# Enable server
if System.get_env("PHX_SERVER") do
  config :lang, LangWeb.Endpoint, server: true
end

# Sentry configuration for error tracking (optional)
if sentry_dsn = System.get_env("SENTRY_DSN") do
  config :sentry,
    dsn: sentry_dsn,
    environment_name: :prod,
    included_environments: [:prod],
    enable_source_code_context: true,
    root_source_code_path: File.cwd!()
end

# Custom application settings that work with existing architecture
config :lang, :deployment,
  environment: :production,
  version: System.get_env("APP_VERSION") || "0.1.0",
  build_time: DateTime.utc_now(),
  health_checks_enabled: System.get_env("HEALTH_CHECK_ENABLED") == "true"

# Billing plan configuration - use environment variables to override defaults
config :lang, :billing_overrides,
  stripe_starter_price_id: System.get_env("STRIPE_STARTER_PRICE_ID"),
  stripe_pro_price_id: System.get_env("STRIPE_PRO_PRICE_ID"),
  stripe_enterprise_price_id: System.get_env("STRIPE_ENTERPRISE_PRICE_ID")
