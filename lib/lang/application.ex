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

    # Assert telnet disabled in production unless explicitly enabled
    ensure_telnet_policy()

    children =
      [
        optional_child(LangWeb.Telemetry),
        # Attach optional LSP client telemetry logger
        (
          Lang.Telemetry.LSPClientLogger.maybe_attach()
          nil
        ),
        # Attach proxy telemetry logger (dev-friendly)
        (
          Lang.Proxy.TelemetryLogger.maybe_attach()
          nil
        ),
        db_enabled?() && optional_child(Lang.Repo),
        optional_child(
          {DNSCluster, query: Application.get_env(:lang, :dns_cluster_query) || :ignore}
        ),
        optional_child({Phoenix.PubSub, name: Lang.PubSub}),
        optional_child({Finch, name: Lang.Finch}),

        # Redis for caching and lightweight storage
        optional_child({Redix, redis_config()}),

        # Core LANG services
        optional_child({Lang.TextIntelligence.ParserRegistry, []}),
        optional_child({Lang.Conversation.RehearsalEngine, []}),
        optional_child({Lang.Timeline.StateManager, []}),
        optional_child({Lang.Security.RateLimiter, []}),
        optional_child({Lang.Proxy.CaptureStore, []}),

        # AST snapshot store (ETS-backed)
        optional_child({Lang.AST.Store, []}),

        # Background processing
        db_enabled?() && optional_child({Oban, Application.fetch_env!(:lang, Oban)}),

        # Orchestration system
        optional_child({Lang.Orchestration.Master, []}),
        optional_child(Lang.Orchestration.QwenAgent),
        optional_child(Lang.Orchestration.ClaudeAgent),
        optional_child(Lang.Orchestration.OpenAIAgent),

        # LSP Server Supervisor (keep late so deps are ready); disabled by default in test
        (if lsp_enabled?(), do: optional_child({Lang.LSP.Supervisor, []}), else: nil),
        (if lsp_enabled?(), do: optional_child({Lang.LSP.ClientPool, []}), else: nil),
        # Register LSP Engine defaults after the engine starts
        (if lsp_enabled?(), do: optional_child(Lang.LSP.EngineDefaultsStarter), else: nil),

        # Security Layer - Start early for protection
        optional_child({Lang.Monitoring.SecurityMonitor, []}),
        optional_child({Lang.MCP.SessionManager, []}),
        optional_child({Lang.MCP.SecurityBridge, []}),
        optional_child({Lang.LSP.SecurityHarness, []}),
        optional_child({Lang.Security.ThreatIntelligence, []}),
        optional_child({Lang.Security.PolicyEngine, []}),
        optional_child({Lang.Security.Orchestrator, []}),

        # MCP Broker Security Layer
        optional_child(
          {DynamicSupervisor, strategy: :one_for_one, name: Lang.MCP.ServerSupervisor}
        ),
        optional_child(Lang.MCP.Broker),
        optional_child(Lang.MCP.Pool),
        optional_child(Lang.MCP.StreamBridge),

        # Advanced MCP Proxy Patterns
        optional_child(Lang.MCP.AdvancedProxy),
        optional_child(Lang.MCP.OAuthIntegration),

        # mulsp/muyata instance management
        optional_child({Lang.Mulsp.Registry, []}),
        optional_child({Lang.Mulsp.InstanceSupervisor, []}),

        # Web endpoint
        optional_child(LangWeb.Endpoint)
      ]
      |> Enum.reject(&is_nil/1)
      |> maybe_add_dev_watchers()

    opts = [strategy: :one_for_one, name: Lang.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LangWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Parse Redis URL into Redix-compatible options
  defp redis_config do
    redis_url = Application.get_env(:lang, :redis_url, "redis://localhost:6379/0")

    case URI.parse(redis_url) do
      %URI{scheme: "redis", host: host, port: port, path: path} when is_binary(host) ->
        database =
          case path do
            "/" <> db when db != "" -> String.to_integer(db)
            _ -> 0
          end

        [
          name: Lang.Redis,
          host: host,
          port: port || 6379,
          database: database
        ]

      _ ->
        # Fallback to localhost if URL parsing fails
        [
          name: Lang.Redis,
          host: "localhost",
          port: 6379,
          database: 0
        ]
    end
  end

  defp optional_child({mod, _opts} = child) when is_atom(mod) do
    if Code.ensure_loaded?(mod), do: child, else: nil
  end

  defp optional_child(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod), do: mod, else: nil
  end

  defp optional_child(other), do: other

  defp lsp_enabled? do
    case Application.get_env(:lang, :lsp_enabled) do
      nil -> if Code.ensure_loaded?(Mix), do: Mix.env() != :test, else: true
      val -> val == true
    end
  end

  defp maybe_add_dev_watchers(children) do
    if Application.get_env(:lang, :dev_routes, false) do
      priv = :code.priv_dir(:lang) |> to_string()
      jsonld_dir = Path.join([priv, "dev", "jsonld"]) |> Path.expand()
      watcher = Supervisor.child_spec({Lang.Dev.DevFSWatcher, %{name: :jsonld, path: jsonld_dir, topic: "dev:fs:jsonld", interval_ms: 2_000}}, id: :dev_fs_watcher_jsonld)
      logger = {Lang.Dev.FSWatcherLogger, %{topic: "dev:fs:jsonld"}}
      # Auto-render JSON-LD changes to docs via Oban worker
      renderer = {Lang.Dev.JSONLDRenderSubscriber, %{topic: "dev:fs:jsonld"}}

      # Watch the docs output dir and auto-ingest back into JSON-LD on changes
      docs_dir = Lang.Dev.Config.docs_dir()
      docs_watcher = Supervisor.child_spec({Lang.Dev.DevFSWatcher, %{name: :docs, path: docs_dir, topic: "dev:fs:docs", interval_ms: 2_000}}, id: :dev_fs_watcher_docs)
      docs_ingestor = {Lang.Dev.DocsIngestSubscriber, %{topic: "dev:fs:docs"}}

      children ++ [watcher, logger, renderer, docs_watcher, docs_ingestor]
    else
      children
    end
  end

  defp db_enabled? do
    val = System.get_env("SKIP_DB") || "0"
    String.downcase(val) not in ["1", "true", "yes", "on"]
  end

  defp ensure_telnet_policy do
    env = to_string(Mix.env())
    enable_telnet = Application.get_env(:lang, :enable_telnet, false)
    allowlist = Application.get_env(:lang, :telnet_allowlist, [])

    if env == "prod" and (enable_telnet || (is_list(allowlist) and allowlist != [])) do
      IO.warn("Telnet adapter is enabled or allowlisted in production; disabling for safety")
      # Force disable by clearing allowlist
      Application.put_env(:lang, :telnet_allowlist, [])
    end
  end
end
