defmodule LangWeb.DevRoutes do
  @moduledoc """
  Opt-in Dev routes for model registry/docs (non-invasive).

  Usage (in your Phoenix router, within the dev-only block):

      if Application.compile_env(:lang, :dev_routes) do
        use LangWeb, :router
        import LangWeb.DevRoutes

        dev_model_routes(scope: "/dev/api", pipe: :api)
      end

  Defaults to scope: "/dev/api" and pipe: :api.
  """

  defmacro dev_model_routes(opts \\ []) do
    scope_path = Keyword.get(opts, :scope, "/dev/api")
    pipe = Keyword.get(opts, :pipe, :api)

    quote do
      scope unquote(scope_path), LangWeb do
        pipe_through unquote(pipe)

        get "/models", DevModelsController, :index
        get "/models/drift", DevModelsController, :drift
        get "/models/:id", DevModelsController, :show
        get "/models/:id/history", DevModelsController, :history
        get "/models/:id/history/diff", DevModelsController, :diff
        post "/models/:id/render", DevModelsController, :render_one
        post "/models/ingest", DevModelsController, :ingest
        post "/models/:id/status", DevModelsController, :status_update


      scope unquote(scope_path), LangWeb do
        pipe_through unquote(pipe)
        get "/lsp/clients/:id/trace", DevLspAdminController, :trace
        post "/lsp/clients/:id/tap", DevLspAdminController, :tap
        get "/lsp/capabilities", DevLspAdminController, :methods
      end


      # Proxy session WS (dev-only mount under /api)
      scope "/api", LangWeb do
        pipe_through unquote(pipe)
        get "/sessions/:id/connect", ProxySessionController, :connect
        post "/sessions/:id/connect", ProxySessionController, :create
      end
      end
    end
  end
end
