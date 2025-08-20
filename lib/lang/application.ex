defmodule Lang.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Validate billing configuration on startup
    case Lang.Billing.ConfigManager.validate_config() do
      :ok ->
        :ok

      {:error, errors} ->
        IO.puts("❌ Invalid billing configuration:")
        Enum.each(errors, &IO.puts("  - #{&1}"))
        IO.puts("Fix configuration in config/billing.exs before starting")
    end

    children = [
      LangWeb.Telemetry,
      Lang.Repo,
      {DNSCluster, query: Application.get_env(:lang, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Lang.PubSub},
      {Finch, name: Lang.Finch},

      # Redis for caching and background processing
      {Redix,
       name: Lang.Redis, url: Application.get_env(:lang, :redis_url, "redis://localhost:6379/0")},

      # Core LANG services
      {Lang.TextIntelligence.ParserRegistry, []},
      {Lang.Conversation.RehearsalEngine, []},
      {Lang.TimeMachine.StateManager, []},
      {Lang.Security.RateLimiter, []},

      # Background processing
      {Oban, Application.fetch_env!(:lang, Oban)},

      # LSP Server
      {Lang.LSP.Server, []},

      # Web endpoint
      LangWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Lang.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LangWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
