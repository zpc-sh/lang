defmodule LangWeb.SEO do
  @moduledoc """
  SEO helpers for LANG Universal Text Intelligence Platform.

  Provides meta tags, structured data, and SEO optimizations for all pages.
  """

  use Phoenix.Component
  import Phoenix.HTML

  @default_title "LANG - Universal Text Intelligence Platform"
  @default_description "Transform any text into actionable intelligence. LANG provides semantic understanding and intelligent editing for code, documents, logs, and more."
  @default_keywords "text intelligence, AI text analysis, code analysis, document intelligence, LSP, tree-sitter, semantic analysis"
  @default_image "/images/lang-og-image.png"
  @site_url "https://lang.ai"

  @doc """
  Renders comprehensive SEO meta tags for a page.
  """
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :keywords, :string, default: nil
  attr :image, :string, default: nil
  attr :type, :string, default: "website"
  attr :canonical, :string, default: nil
  attr :noindex, :boolean, default: false

  def meta_tags(assigns) do
    assigns =
      assigns
      |> assign_new(:site_url, fn -> @site_url end)
      |> assign_new(:full_title, fn ->
        if assigns[:title], do: "#{assigns.title} | LANG", else: @default_title
      end)
      |> assign_new(:meta_description, fn -> assigns[:description] || @default_description end)
      |> assign_new(:meta_keywords, fn -> assigns[:keywords] || @default_keywords end)
      |> assign_new(:meta_image, fn -> @site_url <> (assigns[:image] || @default_image) end)
      |> assign_new(:canonical_url, fn ->
        if assigns[:canonical], do: @site_url <> assigns.canonical, else: nil
      end)

    ~H"""
    <!-- Primary Meta Tags -->
    <title>{@full_title}</title>
    <meta name="title" content={@full_title} />
    <meta name="description" content={@meta_description} />
    <meta name="keywords" content={@meta_keywords} />
    <%= if @noindex do %>
      <meta name="robots" content="noindex, nofollow" />
    <% else %>
      <meta name="robots" content="index, follow" />
    <% end %>

    <!-- Canonical URL -->
    <%= if @canonical_url do %>
      <link rel="canonical" href={@canonical_url} />
    <% end %>

    <!-- Open Graph / Facebook -->
    <meta property="og:type" content={@type} />
    <meta property="og:url" content={@canonical_url || @site_url} />
    <meta property="og:title" content={@full_title} />
    <meta property="og:description" content={@meta_description} />
    <meta property="og:image" content={@meta_image} />
    <meta property="og:site_name" content="LANG" />

    <!-- Twitter -->
    <meta property="twitter:card" content="summary_large_image" />
    <meta property="twitter:url" content={@canonical_url || @site_url} />
    <meta property="twitter:title" content={@full_title} />
    <meta property="twitter:description" content={@meta_description} />
    <meta property="twitter:image" content={@meta_image} />

    <!-- Additional SEO -->
    <meta name="author" content="LANG Intelligence Platform" />
    <meta name="generator" content="Phoenix Framework" />
    <link rel="sitemap" type="application/xml" href="/sitemap.xml" />
    """
  end

  @doc """
  Generates JSON-LD structured data for a page.
  """
  attr :type, :atom, required: true
  attr :data, :map, default: %{}

  def structured_data(assigns) do
    assigns =
      assign_new(assigns, :json_ld, fn -> build_structured_data(assigns.type, assigns.data) end)

    ~H"""
    <script type="application/ld+json">
      <%= raw(Jason.encode!(@json_ld)) %>
    </script>
    """
  end

  defp build_structured_data(:organization, data) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => "LANG",
      "description" => @default_description,
      "url" => @site_url,
      "logo" => @site_url <> "/images/lang-logo.png",
      "sameAs" => [
        "https://github.com/lang-ai",
        "https://twitter.com/lang_ai"
      ]
    }
    |> Map.merge(data)
  end

  defp build_structured_data(:software, data) do
    %{
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "name" => "LANG Intelligence Platform",
      "applicationCategory" => "DeveloperApplication",
      "operatingSystem" => "Web, API",
      "offers" => %{
        "@type" => "Offer",
        "price" => "0",
        "priceCurrency" => "USD"
      }
    }
    |> Map.merge(data)
  end

  defp build_structured_data(:article, data) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Article",
      "publisher" => %{
        "@type" => "Organization",
        "name" => "LANG",
        "logo" => %{
          "@type" => "ImageObject",
          "url" => @site_url <> "/images/lang-logo.png"
        }
      }
    }
    |> Map.merge(data)
  end

  defp build_structured_data(:breadcrumb, items) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" =>
        items
        |> Enum.with_index(1)
        |> Enum.map(fn {{name, url}, position} ->
          %{
            "@type" => "ListItem",
            "position" => position,
            "name" => name,
            "item" => @site_url <> url
          }
        end)
    }
  end

  defp build_structured_data(:faq, questions) do
    %{
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" =>
        questions
        |> Enum.map(fn {question, answer} ->
          %{
            "@type" => "Question",
            "name" => question,
            "acceptedAnswer" => %{
              "@type" => "Answer",
              "text" => answer
            }
          }
        end)
    }
  end

  @doc """
  Generates a breadcrumb component for better navigation and SEO.
  """
  attr :items, :list, required: true

  def breadcrumb(assigns) do
    ~H"""
    <nav aria-label="Breadcrumb" class="text-sm text-gray-400">
      <ol class="flex items-center space-x-2">
        <%= for {{name, url}, index} <- Enum.with_index(@items) do %>
          <%= if index > 0 do %>
            <li class="flex items-center">
              <svg class="w-4 h-4 mx-1" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
                  clip-rule="evenodd"
                />
              </svg>
            </li>
          <% end %>
          <li>
            <%= if url do %>
              <a href={url} class="hover:text-white transition-colors">{name}</a>
            <% else %>
              <span class="text-white">{name}</span>
            <% end %>
          </li>
        <% end %>
      </ol>
    </nav>
    <.structured_data type={:breadcrumb} data={@items} />
    """
  end
end
