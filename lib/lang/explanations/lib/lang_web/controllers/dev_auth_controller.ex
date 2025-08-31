defmodule LangWeb.DevAuthController do
  use LangWeb, :controller
  require Logger

  alias Lang.Accounts.User
  alias LangWeb.Plugs.AuthPlug
  import Ash.Query

  def impersonate(conn, %{"email" => email} = params) when is_binary(email) do
    unless Application.get_env(:lang, :dev_routes) do
      # Extra guard; this route is only mounted when dev_routes is true
      send_resp(conn, 404, "Not Found")
    else
      name = params["name"] || email_name(email)
      return_to = params["return_to"] || "/"

      case get_or_create_user(email, name) do
        {:ok, user} ->
          conn
          |> AuthPlug.store_in_session(user)
          |> configure_session(renew: true)
          |> put_flash(:info, "Impersonated #{email}")
          |> redirect(to: return_to)

        {:error, reason} ->
          Logger.error("Impersonate failed: #{inspect(reason)}")
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: to_string(reason)})
      end
    end
  end

  defp get_or_create_user(email, name) do
    case User |> filter(email == ^email) |> load([:organization]) |> Ash.read_one() do
      {:ok, %User{} = user} -> {:ok, user}
      nil -> register_user(email, name)
      {:error, reason} -> {:error, reason}
    end
  end

  defp register_user(email, name) do
    # Use the OAuth-style upsert action to avoid password requirements
    attrs = %{user_info: %{"email" => email, "name" => name}, oauth_tokens: %{}}

    case User.register_with_oauth(attrs) do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  defp email_name(email) do
    email
    |> String.split("@")
    |> List.first()
    |> to_string()
    |> String.replace([".", "_", "-"], " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
