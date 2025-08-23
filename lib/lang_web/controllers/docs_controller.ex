defmodule LangWeb.DocsController do
  use LangWeb, :controller

  def show(conn, %{"path" => path}) do
    doc_path = Path.join(["docs"] ++ path)

    cond do
      # Check if it's a markdown file
      String.ends_with?(doc_path, ".md") && File.exists?(doc_path) ->
        case File.read(doc_path) do
          {:ok, content} ->
            html = render_markdown(content)

            conn
            |> render(:show, content: html, title: extract_title(content))

          {:error, _} ->
            conn
            |> put_status(404)
            |> render(:not_found)
        end

      # Check if it's a directory with README.md
      File.dir?(doc_path) ->
        readme_path = Path.join(doc_path, "README.md")

        if File.exists?(readme_path) do
          show(conn, %{"path" => path ++ ["README.md"]})
        else
          # List directory contents
          list_directory(conn, doc_path, path)
        end

      true ->
        conn
        |> put_status(404)
        |> render(:not_found)
    end
  end

  defp render_markdown(content) do
    # Simple markdown to HTML conversion without external dependencies
    html =
      content
      |> String.split("\n")
      |> Enum.map(&process_line/1)
      |> Enum.join("\n")
      |> wrap_in_paragraphs()

    style_html(html)
  end

  defp process_line(line) do
    cond do
      # Headers
      String.starts_with?(line, "### ") ->
        "<h3>" <> String.slice(line, 4..-1) <> "</h3>"

      String.starts_with?(line, "## ") ->
        "<h2>" <> String.slice(line, 3..-1) <> "</h2>"

      String.starts_with?(line, "# ") ->
        "<h1>" <> String.slice(line, 2..-1) <> "</h1>"

      # Lists
      String.starts_with?(line, "- ") ->
        "<li>" <> String.slice(line, 2..-1) <> "</li>"

      String.starts_with?(line, "* ") ->
        "<li>" <> String.slice(line, 2..-1) <> "</li>"

      Regex.match?(~r/^\d+\. /, line) ->
        "<li>" <> String.replace(line, ~r/^\d+\. /, "") <> "</li>"

      # Code blocks
      String.starts_with?(line, "```") ->
        if String.length(line) > 3 do
          "<pre><code class='language-" <> String.slice(line, 3..-1) <> "'>"
        else
          "</code></pre>"
        end

      # Links and formatting
      true ->
        line
        |> String.replace(~r/\[([^\]]+)\]\(([^\)]+)\)/, ~s(<a href="\\2">\\1</a>))
        |> String.replace(~r/\*\*([^\*]+)\*\*/, "<strong>\\1</strong>")
        |> String.replace(~r/\*([^\*]+)\*/, "<em>\\1</em>")
        |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    end
  end

  defp wrap_in_paragraphs(html) do
    html
    |> String.split("\n\n")
    |> Enum.map(fn block ->
      cond do
        String.contains?(block, ["<h1>", "<h2>", "<h3>", "<pre>", "<ul>", "<ol>"]) -> block
        String.contains?(block, "<li>") -> "<ul>" <> block <> "</ul>"
        String.trim(block) == "" -> ""
        true -> "<p>" <> block <> "</p>"
      end
    end)
    |> Enum.join("\n")
  end

  defp style_html(html) do
    html
    |> String.replace(
      ~r/<h1>/m,
      ~s(<h1 class="text-4xl font-bold mb-6 bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">)
    )
    |> String.replace(~r/<h2>/m, ~s(<h2 class="text-3xl font-semibold mt-8 mb-4 text-white">))
    |> String.replace(~r/<h3>/m, ~s(<h3 class="text-2xl font-semibold mt-6 mb-3 text-gray-100">))
    |> String.replace(~r/<p>/m, ~s(<p class="mb-4 text-gray-300 leading-relaxed">))
    |> String.replace(
      ~r/<ul>/m,
      ~s(<ul class="list-disc list-inside mb-4 space-y-2 text-gray-300">)
    )
    |> String.replace(
      ~r/<ol>/m,
      ~s(<ol class="list-decimal list-inside mb-4 space-y-2 text-gray-300">)
    )
    |> String.replace(
      ~r/<code>/m,
      ~s(<code class="bg-gray-800 px-2 py-1 rounded text-blue-300 font-mono text-sm">)
    )
    |> String.replace(
      ~r/<pre>/m,
      ~s(<pre class="bg-gray-900 border border-gray-700 rounded-lg p-4 mb-4 overflow-x-auto">)
    )
    |> String.replace(
      ~r/<a href/m,
      ~s(<a class="text-blue-400 hover:text-blue-300 underline" href)
    )
  end

  defp extract_title(content) do
    case Regex.run(~r/^# (.+)$/m, content) do
      [_, title] -> title
      _ -> "Documentation"
    end
  end

  defp list_directory(conn, path, url_path) do
    case File.ls(path) do
      {:ok, entries} ->
        items =
          entries
          |> Enum.sort()
          |> Enum.map(fn entry ->
            full_path = Path.join(path, entry)

            %{
              name: entry,
              path: Path.join(url_path ++ [entry]),
              is_dir: File.dir?(full_path),
              is_markdown: String.ends_with?(entry, ".md")
            }
          end)
          |> Enum.filter(fn item -> item.is_dir || item.is_markdown end)

        conn
        |> render(:index, items: items, current_path: url_path)

      {:error, _} ->
        conn
        |> put_status(404)
        |> render(:not_found)
    end
  end
end
