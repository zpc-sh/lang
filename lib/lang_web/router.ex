defmodule LangWeb.Router do
  use LangWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LangWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    # Skip CSRF protection for webhooks
    plug :put_secure_browser_headers
  end

  pipeline :require_authenticated_user do
    plug AshAuthentication.Plug, otp_app: :lang
  end

  scope "/", LangWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/auth", AuthLive, :index
    live "/analyze", TextAnalysisLive, :index
  end

  scope "/", LangWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/dashboard", DashboardLive, :index
    live "/api-portal", ApiPortalLive, :index
  end

  # API routes
  scope "/api/v1", LangWeb.API do
    pipe_through :api

    post "/analyze", AnalyzeController, :analyze
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
