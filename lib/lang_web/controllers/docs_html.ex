defmodule LangWeb.DocsHTML do
  use LangWeb, :html

  embed_templates "docs_html/*"

  def show(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 text-gray-100">
      <div class="max-w-4xl mx-auto px-6 py-12">
        <article class="prose prose-invert prose-lg max-w-none">
          {raw(@content)}
        </article>

        <div class="mt-12 pt-8 border-t border-gray-800">
          <a href="/docs" class="text-blue-400 hover:text-blue-300">
            ← Back to Documentation Index
          </a>
        </div>
      </div>
    </div>
    """
  end

  def index(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 text-gray-100">
      <div class="max-w-4xl mx-auto px-6 py-12">
        <h1 class="text-4xl font-bold mb-8 bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
          Documentation Directory
        </h1>

        <nav class="space-y-2">
          <%= for item <- @items do %>
            <a
              href={"/docs/" <> item.path}
              class="block px-4 py-3 bg-gray-900 hover:bg-gray-800 rounded-lg transition-colors"
            >
              <div class="flex items-center gap-3">
                <%= if item.is_dir do %>
                  <.icon name="hero-folder" class="w-5 h-5 text-blue-400" />
                <% else %>
                  <.icon name="hero-document-text" class="w-5 h-5 text-gray-400" />
                <% end %>
                <span class="text-gray-200">
                  {humanize_name(item.name)}
                </span>
              </div>
            </a>
          <% end %>
        </nav>

        <%= if @current_path != [] do %>
          <div class="mt-8">
            <a href={parent_path(@current_path)} class="text-blue-400 hover:text-blue-300">
              ← Back to {parent_name(@current_path)}
            </a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def not_found(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 text-gray-100 flex items-center justify-center">
      <div class="text-center">
        <h1 class="text-6xl font-bold text-gray-600 mb-4">404</h1>
        <p class="text-xl text-gray-400 mb-8">Documentation not found</p>
        <a href="/docs" class="text-blue-400 hover:text-blue-300">
          Return to Documentation Index
        </a>
      </div>
    </div>
    """
  end

  defp humanize_name(name) do
    name
    |> String.replace(~r/\.(md|markdown)$/, "")
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp parent_path([]), do: "/docs"

  defp parent_path(path) do
    parent = path |> Enum.drop(-1)
    if parent == [], do: "/docs", else: "/docs/" <> Enum.join(parent, "/")
  end

  defp parent_name([]), do: "Documentation"

  defp parent_name(path) do
    path
    |> Enum.drop(-1)
    |> List.last()
    |> case do
      nil -> "Documentation"
      name -> humanize_name(name)
    end
  end
end
