defmodule LangWeb.Router do
  use LangWeb, :router
  use Lang.DevKit.Router
  use AshAuthentication.Phoenix.Router
  import Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LangWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LangWeb.Plugs.AuthPlug, :load_from_session
  end

  # Browser JSON pipeline for authenticated JSON endpoints used by the web UI
  pipeline :browser_json do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LangWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LangWeb.Plugs.AuthPlug, :load_from_session
  end

  # Browser JSON pipeline with Admin-only guard
  pipeline :browser_json_admin do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LangWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug LangWeb.Plugs.AuthPlug, :load_from_session
    plug LangWeb.Plugs.AdminOnlyPlug
  end

  pipeline :api do
    plug :accepts, ["json", "jsonld", "mdld"]
    plug LangWeb.Plugs.JSONLDNegotiationPlug
    plug LangWeb.Plugs.AuthPlug, :load_from_bearer
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    # Skip CSRF protection for webhooks
    plug :put_secure_browser_headers
  end

  # Authentication pipelines
  pipeline :require_authenticated_user do
    plug :ensure_authenticated
  end

  pipeline :require_authenticated_api do
    plug :ensure_authenticated
  end

  scope "/", LangWeb do
    pipe_through :browser

    live "/", LandingLive, :index
    get "/health", HealthController, :check
    live "/analyze", TextAnalysisLive, :index
    live "/demo", DemoLive, :index
    live "/font", FontShowcaseLive, :index
    live "/design-system", DesignSystemLive, :index

    # Documentation routes
    live "/docs", DocsLive, :index
    get "/docs/*path", DocsController, :show

    # SEO routes
    get "/sitemap.xml", SitemapController, :index
    get "/robots.txt", RobotsController, :index
  end

  # WS proxy endpoint for session attachments
  scope "/ws", LangWeb do
    pipe_through :api
    get "/sessions/attach", SessionWsController, :attach
    get "/lsp", LspWsController, :attach
  end

  # API connect route for agents (Bearer auth)
  scope "/api", LangWeb do
    pipe_through [:api, :require_authenticated_api]
    post "/sessions/:id/connect", SessionConnectController, :connect
  end

  # Authentication routes
  scope "/auth", LangWeb do
    pipe_through :browser

    get "/", AuthController, :show
    post "/login", AuthController, :login
    post "/register", AuthController, :register
    delete "/logout", AuthController, :logout
    post "/sign-out", AuthController, :logout
    get "/forgot-password", AuthController, :forgot_password
    post "/forgot-password", AuthController, :send_reset_email
    get "/reset-password/:token", AuthController, :reset_password
    get "/status", AuthController, :status

    # OAuth authentication routes
    sign_in_route()
    sign_out_route(AuthController)
    auth_routes_for(Lang.Accounts.User, to: AuthController)
    reset_route()
  end

  # Authenticated live session (stubs current_user in dev/test)
  live_session :authenticated,
    on_mount: [
      {LangWeb.AuthOnMount, :mount_current_user},
      {LangWeb.AuthOnMount, :require_authenticated},
      {LangWeb.AuthOnMount, :mount_current_org}
    ] do
    scope "/", LangWeb do
      pipe_through [:browser, :require_authenticated_user]

      live "/dashboard", DashboardLive, :index
      live "/workspaces/:workspace_id/symbols", WorkspaceSymbolsLive, :index
      live "/workspaces/:workspace_id/references", WorkspaceReferencesLive, :index
      live "/proxy/pipeline/:pipeline_id", ProxyPipelineLive, :index
      live "/proxy/intent", ProxyIntentLive, :index
      live "/proxy/session", ProxySessionLive, :index
      live "/lsp/status", LspStatusLive, :index
      live "/lsp/kg_build", KGBuildIndexLive, :index
      live "/security", SecurityDashboardLive, :index
      live "/lsp/kg_build/:stream_id", KGBuildLive, :show
      live "/api-portal", ApiPortalLive, :index
      live "/settings", SettingsLive, :index
      live "/billing", BillingLive, :index
      live "/billing/usage", BillingUsageLive, :index
      live "/agents/swarms", SwarmsLive, :index
      live "/agents/swarms/:swarm_id", SwarmShowLive, :show
      live "/fs/watch", FSWatchLive, :index
      live "/audits/sessions", SessionAuditLive, :index

      # Markdown-LD Session Connect (browser-authenticated JSON endpoint)
      # Use a browser_json pipeline to accept JSON requests
      pipeline :admin_api do
        plug :accepts, ["json"]
        plug LangWeb.Plugs.AdminOnlyPlug
      end

      # Markdown-LD Session Connect (browser-authenticated JSON endpoint)
      # Use a browser_json pipeline to accept JSON requests
      scope "/api", LangWeb do
        pipe_through [:browser_json, :admin_api]
        post "/sessions/:id/connect", SessionConnectController, :connect
        get "/exports/:id", ExportsController, :download
        get "/exports/bundle", ExportsController, :bundle
        get "/exports/sign", ExportsController, :sign
      end
    end
  end

  # API routes
  scope "/api/v1", LangWeb.Api do
    pipe_through [:api, :require_authenticated_api]

    # Projects
    get "/projects", AnalysisController, :list_projects
    post "/projects", AnalysisController, :create_project
    get "/projects/:id", AnalysisController, :show_project
    put "/projects/:id", AnalysisController, :update_project
    delete "/projects/:id", AnalysisController, :delete_project
    post "/projects/:id/archive", AnalysisController, :archive_project

    # Analysis Sessions
    get "/projects/:project_id/sessions", AnalysisController, :list_sessions
    post "/projects/:project_id/sessions", AnalysisController, :create_session
    get "/sessions/:id", AnalysisController, :show_session
    post "/sessions/:id/cancel", AnalysisController, :cancel_session

    # File Upload and Analysis
    post "/sessions/:session_id/upload", AnalysisController, :upload_files
    post "/sessions/:session_id/analyze-text", AnalysisController, :analyze_text

    # Results
    get "/sessions/:session_id/files", AnalysisController, :list_files
    get "/files/:id", AnalysisController, :show_file
    get "/sessions/:session_id/violations", AnalysisController, :list_violations
    get "/violations/:id", AnalysisController, :show_violation
    put "/violations/:id", AnalysisController, :update_violation

    # Statistics
    get "/stats/user", AnalysisController, :user_stats
    get "/stats/sessions/:session_id", AnalysisController, :session_stats
  end

  # API v2 routes - Text Intelligence endpoints
  scope "/api/v2", LangWeb.Api.V2 do
    pipe_through [:api, :require_authenticated_api]

    # Text Intelligence endpoints matching OpenAPI specification
    post "/text/parse", TextController, :parse
    post "/text/entities", TextController, :entities
    post "/text/semantic", TextController, :semantic
    post "/text/stylometry", TextController, :stylometry
    post "/text/markdown-ld", TextController, :markdown_ld
    post "/text/analyze", TextController, :analyze

    # LSP connect + preflight (agent-first)
    post "/lsp/connect", LspController, :connect
    post "/lsp/preflight", LspController, :preflight

    # MCP (Model Context Protocol) Broker endpoints - Secure wrapper for MCP servers
    post "/mcp/connect", McpController, :connect
    # Backwards-compatible status route
    get "/mcp/status/:stream_id", McpController, :status
    # Support disconnect by stream_id (existing) and connection_id (preferred)
    delete "/mcp/disconnect/:stream_id", McpController, :disconnect
    delete "/mcp/disconnect/:connection_id", McpController, :disconnect
    # List active connections
    get "/mcp/connections", McpController, :list_active
    # Billing usage for MCP
    get "/mcp/billing/usage", MCPBillingController, :usage

    # Advanced MCP Proxy Patterns with SSE Transport
    post "/mcp/sse/connect", McpSseController, :connect
    post "/mcp/sse/heartbeat/:connection_id", McpSseController, :heartbeat
    get "/mcp/sse/stats", McpSseController, :stats

    # OAuth Integration for External MCP Servers
    post "/mcp/oauth/initiate", McpOAuthController, :initiate_oauth_flow
    get "/mcp/oauth/callback", McpOAuthController, :oauth_callback
    post "/mcp/oauth/connect", McpOAuthController, :connect_with_oauth
    get "/mcp/oauth/status/:server_type", McpOAuthController, :oauth_status
    delete "/mcp/oauth/revoke/:server_type", McpOAuthController, :revoke_oauth_consent
    get "/mcp/oauth/servers", McpOAuthController, :list_oauth_servers
    # Billing usage endpoints
    get "/billing/aggregates", BillingUsageController, :aggregates
    get "/billing/summary", BillingUsageController, :summary

    # Spatial API
    get "/spatial/map/:project_id", SpatialController, :map_summary
    get "/spatial/trace_path/:project_id", SpatialController, :trace_path
    get "/spatial/find_related/:project_id", SpatialController, :find_related
        get "/spatial/traverse/:project_id", SpatialController, :traverse

    # Proxy endpoints
    post "/proxy", ProxyController, :call
    post "/proxy/intent", ProxyController, :issue_intent
    post "/proxy/session", ProxyController, :run_session

    # MCP JSON:API (AshJsonApi) - mounting Domain resources
    forward "/mcp", AshJsonApi.Router, domains: [Lang.MCP]

    # Spatial JSON:API (AshJsonApi) - read-only maps
    forward "/spatial", AshJsonApi.Router, domains: [Lang.Spatial]

    # Agent JSON:API (AshJsonApi) - expose swarm read endpoints
    forward "/agent", AshJsonApi.Router, domains: [Lang.Agent]
  end

  # Public signed download routes (signature required, no session)
  scope "/dl", LangWeb do
    pipe_through :api
    get "/exports/:id", ExportsController, :signed_download
    get "/exports/bundle", ExportsController, :signed_bundle
  end


  # Webhook routes
  scope "/webhooks", LangWeb do
    pipe_through :webhook

    post "/stripe", WebhooksController, :stripe
  end

  # Well-known dynamic endpoints (e.g., JWKS)
  scope "/.well-known", LangWeb do
    pipe_through :api
    get "/jwks.json", WellKnownController, :jwks
  end

  # Internal diagnostics webhook (HMAC-signed)
  scope "/internal", LangWeb.Internal do
    pipe_through :api

    post "/agent/diagnostics", AgentDiagnosticsController, :create
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:lang, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    # Mount DevKit routes (defines its own /dev scope)
    codex_devkit_routes(scope: "/dev", web_module: LangWeb)

    # Additional dev pages not in DevKit (avoid double-wrapping /dev)
      live "/dev/lsp", LangWeb.LspEditor.LspEditorLive, :index
      live "/dev/lsp/harness", LangWeb.LSPHarnessLive, :index
    live "/dev/lsp/kg_build/:stream_id", LangWeb.KGBuildLive, :show
    live "/dev/agents", LangWeb.AgentsLive, :index
    live "/dev/proxy/terminal", LangWeb.ProxyTerminalLive, :index
    live "/dev/examples", LangWeb.DevJsonldExamplesLive, :index

    live "/dev/agents-doc", LangWeb.DevAgentsDocLive, :index
    live_dashboard "/dev/dashboard", metrics: LangWeb.Telemetry
    forward "/dev/mailbox", Plug.Swoosh.MailboxPreview

    # Mount Oban Web UI only when available (dev only)
    if Code.ensure_loaded?(Oban.Web) do
      scope "/" do
        pipe_through :browser
        forward "/oban", Oban.Web, oban: Oban
      end
    end
  end

  # Authentication helper plugs

  defp ensure_authenticated(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_session(:return_to, conn.request_path)
        |> put_flash(:error, "You must be signed in to access this page.")
        |> redirect(to: "/auth")
        |> halt()

      _user ->
        conn
    end
  end
end
