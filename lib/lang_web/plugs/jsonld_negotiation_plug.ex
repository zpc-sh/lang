defmodule LangWeb.Plugs.JSONLDNegotiationPlug do
  @moduledoc """
  Lightweight JSON-LD negotiation and optional compaction.

  - If `Accept: application/ld+json` is sent or `?format=jsonld`,
    switches response format to `jsonld` and sets the proper Content-Type.
  - If `?compact=true`, attempts a local compaction using any inline @context.

  No remote context fetches are performed.
  """

  import Plug.Conn
  alias Lang.JSONLD

  def init(opts), do: opts

  def call(conn, _opts) do
    prefer_ld? = prefer_ld?(conn)
    prefer_mdld? = prefer_mdld?(conn)
    compact? = compact?(conn)

    conn
    |> maybe_put_format(prefer_ld?, prefer_mdld?)
    |> register_before_send(fn conn ->
      conn
      |> maybe_set_content_type(prefer_ld?, prefer_mdld?)
      |> maybe_compact_body(prefer_ld? or prefer_mdld?, compact?)
    end)
  end

  defp prefer_ld?(conn) do
    accept = get_req_header(conn, "accept") |> List.first() |> to_string()
    format_param = conn.params["format"] || conn.params["ld"]

    String.contains?(String.downcase(accept), "application/ld+json") or
      (is_binary(format_param) and String.downcase(format_param) in ["jsonld", "ld+json"])
  end

  defp prefer_mdld?(conn) do
    accept = get_req_header(conn, "accept") |> List.first() |> to_string()
    format_param = conn.params["format"]

    String.contains?(String.downcase(accept), "application/markdown-ld+json") or
      (is_binary(format_param) and
         String.downcase(format_param) in ["mdld", "markdownld", "markdown-ld"])
  end

  defp compact?(conn) do
    case conn.params["compact"] do
      v when v in [true, "true", "1", 1] -> true
      _ -> false
    end
  end

  defp maybe_put_format(conn, true, _mdld), do: Phoenix.Controller.put_format(conn, "jsonld")
  defp maybe_put_format(conn, _ld, true), do: Phoenix.Controller.put_format(conn, "mdld")
  defp maybe_put_format(conn, _ld, _mdld), do: conn

  defp maybe_set_content_type(conn, true, _mdld) do
    # Only override JSON content types, leave others intact
    case get_resp_header(conn, "content-type") do
      [ct | _] when is_binary(ct) ->
        if String.contains?(ct, "application/json") do
          put_resp_content_type(conn, "application/ld+json")
        else
          conn
        end

      [] ->
        put_resp_content_type(conn, "application/ld+json")

      _ ->
        conn
    end
  end

  defp maybe_set_content_type(conn, _ld, true) do
    case get_resp_header(conn, "content-type") do
      [ct | _] when is_binary(ct) ->
        if String.contains?(ct, "application/json") do
          put_resp_content_type(conn, "application/markdown-ld+json")
        else
          conn
        end

      [] ->
        put_resp_content_type(conn, "application/markdown-ld+json")

      _ ->
        conn
    end
  end

  defp maybe_set_content_type(conn, _ld, _mdld), do: conn

  defp maybe_compact_body(conn, true, true) do
    body = conn.resp_body

    with true <- is_binary(body),
         {:ok, map} <- Jason.decode(body),
         %{} = context <- Map.get(map, "@context") do
      {compacted, ctx} = JSONLD.compact(map, context)

      # Ensure @context remains present
      compacted =
        compacted
        |> Map.put_new("@context", ctx)

      {:ok, new_body} = Jason.encode(compacted)
      %{conn | resp_body: new_body}
    else
      _ -> conn
    end
  end

  defp maybe_compact_body(conn, _prefer_ld, _compact), do: conn
end
