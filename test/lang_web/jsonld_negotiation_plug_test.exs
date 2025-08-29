defmodule LangWeb.JSONLDNegotiationPlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias LangWeb.Plugs.JSONLDNegotiationPlug

  test "sets Content-Type application/ld+json when Accept is application/ld+json" do
    conn =
      conn(:get, "/test")
      |> put_req_header("accept", "application/ld+json")
      |> JSONLDNegotiationPlug.call(%{})

    # Build a body to trigger before_send compaction path
    body = %{
      "@context" => %{"name" => "https://schema.org/name"},
      "https://schema.org/name" => "Alice"
    }

    conn = Plug.Conn.resp(conn, 200, Jason.encode!(body))
    conn = Plug.Conn.send_resp(conn)

    # Asserting header set and body compacted
    ct = Plug.Conn.get_resp_header(conn, "content-type") |> List.first()
    assert ct =~ "application/ld+json"

    {:ok, decoded} = Jason.decode(conn.resp_body)
    assert decoded["@context"] == %{"name" => "https://schema.org/name"}
    # key compacted from full IRI to term
    assert decoded["name"] == "Alice"
    refute Map.has_key?(decoded, "https://schema.org/name")
  end
end

