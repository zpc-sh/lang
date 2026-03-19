defmodule LangWeb.Plugs.AdminOnlyPlug do
  @moduledoc """
  Simple admin-only access guard. Assumes `conn.assigns.current_user` has a `role`
  field or `is_admin` boolean; falls back to blocking if absent.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]
    if admin?(user) do
      conn
    else
      conn
      |> Phoenix.Controller.put_status(:forbidden)
      |> Phoenix.Controller.json(%{error: "admin_required"})
      |> halt()
    end
  end

  defp admin?(%{is_admin: true}), do: true
  defp admin?(%{role: role}) when is_binary(role), do: String.downcase(role) in ["admin", "owner"]
  defp admin?(_), do: false
end

