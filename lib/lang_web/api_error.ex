defmodule LangWeb.ApiError do
  @moduledoc """
  Helper for consistent API error responses.

  Produces a JSON body like:
  %{error: message, details: %{...}} when details are provided.
  """

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @spec json(Plug.Conn.t(), Plug.Conn.status(), String.t(), map() | nil) :: Plug.Conn.t()
  def json(conn, status, message, details \\ nil) do
    body =
      case details do
        nil -> %{error: message}
        _ -> %{error: message, details: details}
      end

    conn
    |> put_status(status)
    |> json(body)
  end
end
