defmodule LangWeb.DocsController do
  use LangWeb, :controller
  alias Lang.Native.FSScanner

  def show(conn, %{"path" => path}) do
    doc_path = Path.join(["docs"] ++ path)

    cond do
      # Markdown file: use native preview to read content
      String.ends_with?(doc_path, ".md") ->
        case FSScanner.preview(doc_path, max_lines: 10_000) do
          {:ok, lines} ->
            content = Enum.join(lines, "\n")
            {html, has_sessions?} = render_markdown(content)
            limits = session_limits()

            conn
            |> render(:show,
              content: html,
              title: extract_title(content),
              has_sessions?: has_sessions?,
              session_limits: limits
            )

          {:error, _} ->
            conn
            |> put_status(404)
            |> render(:not_found)
        end

      # Directory: scan shallow and either redirect to README or list
      true ->
        case FSScanner.scan(doc_path, max_depth: 1, include_hidden: false) do
          {:ok, %{tree: %{children: children}}} when is_list(children) ->
            case Enum.find(children, fn c -> (c.name == "README.md") end) do
              %{name: _} -> show(conn, %{"path" => path ++ ["README.md"]})
              _ -> list_directory(conn, doc_path, path, children)
            end

          {:ok, %{tree: %{children: nil}}} ->
            # Empty directory
            list_directory(conn, doc_path, path, [])

          {:error, _} ->
            conn
            |> put_status(404)
            |> render(:not_found)
        end
    end
  end

  defp render_markdown(content) do
    # Simple markdown to HTML conversion without external dependencies
    # First, transform Markdown-LD session fences into HTML blocks
    {content, has_sessions?} = transform_mdld_sessions(content)

    html =
      content
      |> String.split("\n")
      |> Enum.map(&process_line/1)
      |> Enum.join("\n")
      |> wrap_in_paragraphs()

    {style_html(html), has_sessions?}
  end

  defp transform_mdld_sessions(content) when is_binary(content) do
    lines = String.split(content, "\n")

    {acc, _state} =
      Enum.reduce(lines, {[], :normal}, fn line, {out, state} ->
        case state do
          :normal ->
            # Match ```session {lds:...}
            case Regex.run(~r/^```session\s*(\{[^}]*\})?\s*$/, line) do
              [_, attrs_str] ->
                attrs = parse_session_attrs(attrs_str)
                # Accumulate until closing fence
                {out ++ [{:session_start, attrs}], :in_session}

              nil ->
                {out ++ [line], :normal}
            end

          :in_session ->
            if String.trim(line) == "```" do
              {out ++ [:session_end], :normal}
            else
              # Ignore inner lines for now; could be description
              {out, :in_session}
            end
        end
      end)

    # Now render the accumulated tokens into content
    has_sessions? = Enum.any?(acc, fn
      {:session_start, _} -> true
      _ -> false
    end)

    acc
    |> Enum.reduce({[], nil}, fn token, {out, current_attrs} ->
      case token do
        {:session_start, attrs} -> {out, attrs}
        :session_end ->
          html = render_session_block(current_attrs || %{})
          {out ++ [html], nil}
        line when is_binary(line) -> {out ++ [line], current_attrs}
      end
    end)
    |> elem(0)
    |> Enum.join("\n")
    |> then(fn transformed -> {transformed, has_sessions?} end)
  end

  defp transform_mdld_sessions(content), do: {content, false}

  defp parse_session_attrs(nil), do: %{}
  defp parse_session_attrs(""), do: %{}
  defp parse_session_attrs(braced) when is_binary(braced) do
    # Strip braces { ... }
    inner =
      braced
      |> String.trim()
      |> String.trim_leading("{")
      |> String.trim_trailing("}")

    # Split on whitespace boundaries while preserving quoted values
    # Accept keys like lds:session=val or lds:session="val with spaces"
    regex = ~r/(\S+?=\"[^\"]*\"|\S+?='[^']*'|\S+?=\S+)/

    Regex.scan(regex, inner)
    |> Enum.map(&List.first/1)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [k, v] ->
          v = String.trim(v)
          v =
            v
            |> String.trim_leading("\"")
            |> String.trim_trailing("\"")
            |> String.trim_leading("'")
            |> String.trim_trailing("'")

          Map.put(acc, k, v)

        _ -> acc
      end
    end)
  end

  defp render_session_block(attrs) when is_map(attrs) do
    id = Map.get(attrs, "lds:session", "sess-unknown")
    title = Map.get(attrs, "lds:title", "Interactive Session")
    policy = Map.get(attrs, "lds:policy", "disabled")
    cap = Map.get(attrs, "lds:cap", "interactive")
    cols = Map.get(attrs, "lds:cols", "100")
    rows = Map.get(attrs, "lds:rows", "28")
    mode = Map.get(attrs, "lds:mode", "pty")
    renderer = Map.get(attrs, "lds:renderer", "rio")
    connect = Map.get(attrs, "lds:connect", "")
    proto = Map.get(attrs, "lds:proto", "ssh")

    disabled? = policy not in ["attach", "trusted"] or connect == ""

    ~s(<div class="mdld-session my-4" data-mdld-session data-session-id="#{html_escape(id)}" data-connect="#{html_escape(connect)}" data-cap="#{html_escape(cap)}" data-cols="#{html_escape(cols)}" data-rows="#{html_escape(rows)}" data-mode="#{html_escape(mode)}" data-proto="#{html_escape(proto)}" data-renderer="#{html_escape(renderer)}" phx-hook="MdldSession">)
    <> ~s(<div class="flex items-center justify-between mb-2">)
    <> ~s(<div class="text-sm text-gray-400">#{html_escape(title)} · #{html_escape(String.upcase(proto))}</div>)
    <> if disabled?, do: ~s(<button class="btn btn-sm btn-disabled" disabled>Connect</button>), else: ~s(<button class="btn btn-sm btn-primary" data-action="connect">Connect</button>)
    <> ~s(</div>)
    <> ~s(<div class="terminal border border-gray-700 rounded bg-black text-gray-100 p-2 h-72 overflow-auto" data-terminal></div>)
    <> ~s|<div class="mt-1 text-[11px] text-gray-500">Server-mediated only. Do not connect directly (telnet/ssh).</div>|
    <> ~s(</div>)
  end

  defp html_escape(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace(~S("), "&quot;")
    |> String.replace("'", "&#39;")
  end
  defp html_escape(other), do: to_string(other)

  defp session_limits do
    cfg = Application.get_env(:lang, :session_proxy, [])
    %{
      idle_timeout_ms: Keyword.get(cfg, :idle_timeout_ms, 10 * 60_000),
      bandwidth_limit_bytes: Keyword.get(cfg, :bandwidth_limit_bytes, 50 * 1024 * 1024)
    }
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
        # Preserve injected Markdown-LD session blocks as-is
        String.contains?(block, ["data-mdld-session", "class=\"mdld-session"]) -> block
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

  defp list_directory(conn, _path, url_path, children) when is_list(children) do
    items =
      children
      |> Enum.sort_by(& &1.name)
      |> Enum.map(fn node ->
        %{
          name: node.name,
          path: Path.join(url_path ++ [node.name]),
          is_dir: match?(:directory, node.node_type) || node.children != nil,
          is_markdown: String.ends_with?(node.name, ".md")
        }
      end)
      |> Enum.filter(fn item -> item.is_dir || item.is_markdown end)

    conn
    |> render(:index, items: items, current_path: url_path)
  end
end
