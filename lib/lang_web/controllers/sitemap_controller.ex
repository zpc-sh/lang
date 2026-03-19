defmodule LangWeb.SitemapController do
  use LangWeb, :controller

  def index(conn, _params) do
    sitemap = LangWeb.Sitemap.generate()

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, sitemap)
  end
end
