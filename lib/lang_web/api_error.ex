defmodule LangWeb.ApiError do
  @moduledoc """
  Helper for consistent API error responses.

  Produces a JSON body like:
  %{error: message, details: %{...}} when details are provided.
  """

  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]
  alias Phoenix.Controller

  @spec json(Plug.Conn.t(), Plug.Conn.status(), String.t(), map() | nil) :: Plug.Conn.t()
  def json(conn, status, message, details \\ nil) do
    body =
      case Controller.get_format(conn) do
        "jsonld" ->
          %{
            "@context" => "https://lang.nulity.com/context/error",
            "@type" => "Error",
            "status" => "error",
            "error" =>
              case details do
                nil ->
                  %{message: message, timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}

                _ ->
                  %{
                    message: message,
                    details: details,
                    timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
                  }
              end
          }

        _ ->
          case details do
            nil -> %{error: message}
            _ -> %{error: message, details: details}
          end
      end

    conn
    |> put_status(status)
    |> json(body)
  end
end
