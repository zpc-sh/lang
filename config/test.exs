import Config

config :lang, Lang.Mailer, adapter: Swoosh.Adapters.Test
config :logger, level: :warning
config :phoenix, :stacktrace_depth, 20
config :phoenix_live_view, :debug_heex_propagation, true

# Disable Repo for swarm validation
# config :lang, Lang.Repo, pool: Ecto.Adapters.SQL.Sandbox
