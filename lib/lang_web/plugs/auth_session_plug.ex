defmodule LangWeb.AuthSessionPlug do
  @moduledoc """
  Auth plug for loading users from session.
  """
  use AshAuthentication.Plug, otp_app: :lang

  @impl true
  def handle_success(conn, _activity, user, _token) do
    conn
    |> put_session(:user_id, user.id)
    |> assign(:current_user, user)
  end

  @impl true
  def handle_failure(conn, _activity, _reason) do
    conn
    |> assign(:current_user, nil)
  end
end
