defmodule LangWeb.Sitemap do
  @moduledoc """
  Generates sitemap.xml for SEO.
  """

  @site_url "https://lang.ai"

  def generate do
    pages = [
      %{loc: "/", changefreq: "weekly", priority: "1.0"},
      %{loc: "/analyze", changefreq: "monthly", priority: "0.9"},
      %{loc: "/demo", changefreq: "monthly", priority: "0.8"},
      %{loc: "/design-system", changefreq: "monthly", priority: "0.7"},
      %{loc: "/docs", changefreq: "weekly", priority: "0.8"},
      %{loc: "/pricing", changefreq: "weekly", priority: "0.9"},
      %{loc: "/auth", changefreq: "monthly", priority: "0.7"},
      %{loc: "/api-portal", changefreq: "monthly", priority: "0.8"}
    ]

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(pages, "\n", &page_to_xml/1)}
    </urlset>
    """

    xml
  end

  defp page_to_xml(page) do
    """
      <url>
        <loc>#{@site_url}#{page.loc}</loc>
        <lastmod>#{Date.utc_today()}</lastmod>
        <changefreq>#{page.changefreq}</changefreq>
        <priority>#{page.priority}</priority>
      </url>
    """
  end
end
