defmodule Lang.DevKit.Router do
  @moduledoc """
  DevKit router helpers for mounting dev-only tools and APIs.

  Usage (in your router):
      if Application.compile_env(:lang, :dev_routes) do
        use Lang.DevKit.Router
        codex_devkit_routes(scope: "/dev", web_module: LangWeb)
      end

  Options
  - `:scope` (default "/dev"): URL scope under which to mount routes
  - `:web_module` (default `LangWeb`): your app's web module where LiveViews/controllers reside

  Mounted routes
  - Dev Hub: GET /dev/test
  - JSON-LD Runner: GET /dev/jsonld
  - NIF Health: GET /dev/nif
  - Impersonate: GET /dev/auth/impersonate/:email
  - Metrics APIs: /dev/api/metrics/summary, /lsp, /nif
  - LSP Admin APIs: /dev/api/lsp/clients, /methods, /heartbeat

  Notes
  - This macro only mounts generic DevKit modules. Keep app-specific dev pages separate.
  - Intended for extraction as a standalone library later (rename to Codex.DevKit).
  """

  defmacro __using__(_opts) do
    quote do
      import Lang.DevKit.Router, only: [codex_devkit_routes: 1]
    end
  end

  defmacro codex_devkit_routes(opts \\ []) do
    scope_path = Keyword.get(opts, :scope, "/dev")
    web_mod = Keyword.get(opts, :web_module, LangWeb)

    quote bind_quoted: [scope_path: scope_path, web_mod: web_mod] do
      scope scope_path, web_mod do
        pipe_through :browser

        # Dev Hub + tools
        live "/test", Module.concat(web_mod, DevHubLive), :index
        live "/jsonld", Module.concat(web_mod, JSONLDRunnerLive), :index
        live "/nif", Module.concat(web_mod, DevNifHealthLive), :index
        get "/auth/impersonate/:email", Module.concat(web_mod, DevAuthController), :impersonate

        # Metrics APIs
        get "/api/metrics/summary", Module.concat(web_mod, DevMetricsController), :summary
        get "/api/metrics/lsp", Module.concat(web_mod, DevMetricsController), :lsp
        get "/api/metrics/nif", Module.concat(web_mod, DevMetricsController), :nif

        # LSP Admin APIs
        get "/api/lsp/clients", Module.concat(web_mod, DevLspAdminController), :clients
        get "/api/lsp/methods", Module.concat(web_mod, DevLspAdminController), :methods
        get "/api/lsp/heartbeat", Module.concat(web_mod, DevLspAdminController), :heartbeat
      end
    end
  end
end
