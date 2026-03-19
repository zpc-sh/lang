defmodule LangWeb.LspWsController do
  use LangWeb, :controller

  # GET /ws/lsp?ticket=...
  def attach(conn, _params) do
    ticket = extract_ticket(conn)
    case Lang.Security.JWT.verify_ticket(ticket) do
      {:ok, claims} ->
        state = %{claims: claims}
        opts = [compress: false]
        WebSockAdapter.upgrade(conn, LangWeb.LspWebSocket, state, opts)
      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "invalid_or_missing_ticket"})
    end
  end

  defp extract_ticket(conn) do
    # Prefer Sec-WebSocket-Protocol header like "lsp, jwt.<token>" or just token
    header = List.first(get_req_header(conn, "sec-websocket-protocol"))
    case header do
      nil -> conn.params["ticket"]
      h ->
        h
        |> String.split([",", " "], trim: true)
        |> Enum.find(fn part -> part != "lsp" end)
    end
  end
end

