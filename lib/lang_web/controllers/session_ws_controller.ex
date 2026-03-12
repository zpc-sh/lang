defmodule LangWeb.SessionWsController do
  use LangWeb, :controller

  def attach(conn, _params) do
    with [ticket] <- Plug.Conn.get_req_header(conn, "sec-websocket-protocol") |> Enum.filter(&(&1 != "")) |> List.wrap() |> default_ticket(conn.params["ticket"]) |> ensure_list(),
         {:ok, claims} <- Phoenix.Token.verify(LangWeb.Endpoint, "session_ws_ticket", ticket, max_age: 300) do
      state = %{claims: claims}
      opts = [compress: false]
      WebSockAdapter.upgrade(conn, LangWeb.SessionWebSocket, state, opts)
    else
      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "invalid_or_missing_ticket"})
    end
  end

  defp default_ticket([], nil), do: []
  defp default_ticket([], from_param), do: [from_param]
  defp default_ticket(list, _), do: list

  defp ensure_list([nil]), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list(_), do: []
end
