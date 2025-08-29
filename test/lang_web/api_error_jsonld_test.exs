defmodule LangWeb.ApiErrorJSONLDTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias LangWeb.ApiError
  alias Phoenix.Controller

  test "adds @context and JSON-LD shape when format is jsonld" do
    conn = conn(:get, "/") |> Controller.put_format("jsonld")
    conn = ApiError.json(conn, :bad_request, "oops", %{reason: "bad"})

    assert conn.status == 400
    {:ok, body} = Jason.decode(conn.resp_body)
    assert body["@context"] == "https://lang.nulity.com/context/error"
    assert body["@type"] == "Error"
    assert body["status"] == "error"
    assert get_in(body, ["error", "message"]) == "oops"
    assert get_in(body, ["error", "details", "reason"]) == "bad"
  end

  test "plain JSON body when format is json" do
    conn = conn(:get, "/") |> Controller.put_format("json")
    conn = ApiError.json(conn, :not_found, "missing")

    assert conn.status == 404
    {:ok, body} = Jason.decode(conn.resp_body)
    refute Map.has_key?(body, "@context")
    assert body["error"] == "missing"
  end
end

