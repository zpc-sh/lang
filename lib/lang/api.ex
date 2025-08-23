defmodule Lang.Api do
  use AshJsonApi, domain: Lang.Accounts

  json_api "/api/v1" do
    # User authentication and management endpoints
    resource "/users", Lang.Accounts.User do
      # Public registration endpoint
      post(:register)

      # User profile management (authenticated)
      get(:show, route: "/:id")
      patch(:update, route: "/:id")
      delete(:destroy, route: "/:id")

      # Get current user info
      get(:me, route: "/me")
    end

    # Organization management endpoints
    resource "/organizations", Lang.Accounts.Organization do
      get(:show, route: "/:id")
      patch(:update, route: "/:id")
      delete(:destroy, route: "/:id")

      # Organization users
      get(:users, route: "/:id/users")
    end

    # API Key management endpoints
    resource "/api-keys", Lang.Accounts.ApiKey do
      index(:list_by_user)
      post(:create)
      patch(:update, route: "/:id")
      delete(:destroy, route: "/:id")

      # API key actions
      patch(:revoke, route: "/:id/revoke")
      patch(:activate, route: "/:id/activate")
    end
  end

  # Authentication endpoints (separate from JSON:API spec)
  json_api "/auth" do
    # These follow a more REST-like pattern for auth
    post("/sign-in", to: LangWeb.AuthController, action: :sign_in)
    post("/sign-out", to: LangWeb.AuthController, action: :sign_out)
    post("/register", to: LangWeb.AuthController, action: :register)
    post("/forgot-password", to: LangWeb.AuthController, action: :forgot_password)
    post("/reset-password", to: LangWeb.AuthController, action: :reset_password)
  end
end
