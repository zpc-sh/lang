# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Import billing configuration
import_config "billing.exs"

config :lang,
  ecto_repos: [Lang.Repo],
  generators: [timestamp_type: :utc_datetime]

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
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10, analysis: 5, lsp: 20, metrics: 15, cleanup: 2]

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

config :lang, :timemachine,
  max_states_per_timeline: 10000,
  cleanup_interval_minutes: 30,
  snapshot_retention_days: 90

config :lang, :security,
  rate_limit_cleanup_interval: 60_000,
  default_rate_limit: %{limit: 100, window: 3600, block_duration: 300}

# Configure Redis for caching and metrics
config :lang,
  redis_url: "redis://localhost:6379/0"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
