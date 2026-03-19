defmodule LangWeb.RobotsController do
  use LangWeb, :controller

  def index(conn, _params) do
    robots = """
    User-agent: *
    Allow: /
    Disallow: /api/
    Disallow: /admin/
    Disallow: /dashboard/
    Disallow: /settings/
    Disallow: /dev/

    Sitemap: https://lang.ai/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, robots)
  end
end
