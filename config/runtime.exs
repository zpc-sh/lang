import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# LANG Security Configuration - Always use proper secrets management
alias Lang.Security.Secrets

# Load secrets with fallbacks for development
secret_key_base =
  System.get_env("SECRET_KEY_BASE") || "dev_secret_key_base_placeholder_#{Mix.env()}"

live_view_salt = System.get_env("LIVE_VIEW_SIGNING_SALT") || "dev_live_view_salt_#{Mix.env()}"

ash_auth_secret =
  System.get_env("ASH_AUTHENTICATION_SECRET") || "dev_ash_auth_secret_#{Mix.env()}"

# Configure LiveView with proper signing salt from environment
config :lang, LangWeb.Endpoint, live_view: [signing_salt: live_view_salt]

# Configure AshAuthentication with proper secret
config :lang, :ash_authentication, signing_secret: ash_auth_secret

# Configure rate limiting
rate_limit_config = Secrets.rate_limit_config()
config :lang, :rate_limiting, rate_limit_config

# Configure CORS
cors_config = Secrets.cors_config()
config :lang, :cors, cors_config

# Configure text processing limits
text_limits = Secrets.text_processing_limits()
config :lang, :text_processing, text_limits

# Configure telemetry
telemetry_config = Secrets.telemetry_config()
config :logger, level: telemetry_config.log_level

# Configure external services (only if keys are present)
external_config = Secrets.external_services_config()

if external_config.openai_api_key do
  config :lang, :openai, api_key: external_config.openai_api_key
end

# Configure Stripe
stripe_config = %{
  api_key: System.get_env("STRIPE_SECRET_KEY"),
  webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET"),
  publishable_key: System.get_env("STRIPE_PUBLISHABLE_KEY"),
  pro_price_id: System.get_env("STRIPE_PRO_PRICE_ID"),
  enterprise_price_id: System.get_env("STRIPE_ENTERPRISE_PRICE_ID")
}

if stripe_config.api_key do
  config :stripity_stripe,
    api_key: stripe_config.api_key,
    webhook_secret: stripe_config.webhook_secret

  config :lang, :stripe,
    publishable_key: stripe_config.publishable_key,
    pro_price_id: stripe_config.pro_price_id,
    enterprise_price_id: stripe_config.enterprise_price_id
end

if external_config.sendgrid_api_key do
  config :lang, Lang.Mailer,
    adapter: Swoosh.Adapters.Sendgrid,
    api_key: external_config.sendgrid_api_key
end

# Configure Redis URL from environment
redis_url = System.get_env("REDIS_URL") || "redis://localhost:6379/0"
config :lang, :redis_url, redis_url

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/lang start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :lang, LangWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Use our centralized secrets management for database configuration
  database_url = Secrets.database_url()

  if database_url do
    maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    config :lang, Lang.Repo,
      # ssl: true,
      url: database_url,
      pool_size: Secrets.database_config().pool_size,
      # For machines with several cores, consider starting multiple pools of `pool_size`
      # pool_count: 4,
      socket_options: maybe_ipv6
  else
    # Fall back to individual database configuration
    db_config = Secrets.database_config()
    maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    config :lang, Lang.Repo,
      username: db_config.username,
      password: db_config.password,
      hostname: db_config.hostname,
      database: db_config.database,
      port: db_config.port,
      pool_size: db_config.pool_size,
      socket_options: maybe_ipv6
  end

  # Use centralized secrets for Phoenix configuration
  host = Secrets.app_host()
  port = Secrets.app_port()

  config :lang, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :lang, LangWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :lang, LangWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :lang, LangWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :lang, Lang.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
