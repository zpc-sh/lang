defmodule LangWeb.ProxySessionController do
  use LangWeb, :controller

  def connect(conn, %{"id" => id}) do
    opts = []
    actor = resolve_actor(conn)
    if actor == nil and not Application.get_env(:lang, :dev_routes) do
      conn |> send_resp(401, "unauthorized")
    else
      state = %{id: id, actor: actor || %{user_id: "dev", org_id: "dev"}}
      WebSockAdapter.upgrade(conn, LangWeb.WS.ProxySessionWS, state, opts)
    end
  end

  # POST /api/sessions/:id/connect -> returns WS URL for client to attach
  def create(conn, %{"id" => id}) do
    base = LangWeb.Endpoint.url()
    ws_url = to_ws_url(base) <> "/api/sessions/" <> id <> "/connect"
    json(conn, %{ok: true, wss_url: ws_url})
  end

  defp to_ws_url(http_url) when is_binary(http_url) do
    cond do
      String.starts_with?(http_url, "https://") -> String.replace_prefix(http_url, "https://", "wss://")
      String.starts_with?(http_url, "http://") -> String.replace_prefix(http_url, "http://", "ws://")
      true -> http_url
    end
  end

end

