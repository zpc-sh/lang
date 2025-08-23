defmodule LangWeb.Router do
  use LangWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LangWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    # Skip CSRF protection for webhooks
    plug :put_secure_browser_headers
  end

  # Authentication pipelines
  pipeline :require_authenticated_user do
    plug LangWeb.Plugs.AuthPlug, strategy: :session, required: true
  end

  pipeline :require_authenticated_api do
    plug LangWeb.Plugs.AuthPlug, strategy: :api_key, required: true
  end

  pipeline :optional_auth do
    plug LangWeb.Plugs.AuthPlug, strategy: :optional, required: false
  end

  scope "/", LangWeb do
    pipe_through [:browser, :optional_auth]

    live "/", LandingLive, :index
    get "/health", HealthController, :check
    live "/analyze", TextAnalysisLive, :index
    live "/demo", DemoLive, :index
    live "/design-system", DesignSystemLive, :index
  end

  # Authentication routes
  scope "/auth", LangWeb do
    pipe_through :browser

    get "/", AuthController, :show
    post "/login", AuthController, :login
    post "/register", AuthController, :register
    delete "/logout", AuthController, :logout
    get "/forgot-password", AuthController, :forgot_password
    post "/forgot-password", AuthController, :send_reset_email
    get "/reset-password/:token", AuthController, :reset_password
    post "/reset-password/:token", AuthController, :update_password
    get "/status", AuthController, :status
    get "/oauth/:provider", AuthController, :oauth_callback
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
      live "/api-portal", ApiPortalLive, :index
      live "/settings", SettingsLive, :index
    end
  end

  # Public marketing pages
  scope "/", LangWeb do
    pipe_through :browser

    live "/font", FontShowcaseLive, :index
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

  # Webhook routes
  scope "/webhooks", LangWeb do
    pipe_through :webhook

    post "/stripe", WebhooksController, :stripe
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:lang, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LangWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
