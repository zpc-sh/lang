# defmodule Kyozo.Markdown.Parser do
#   @moduledoc """
#   Consolidated hyper-tuned markdown parser for all Kyozo content.

#   This unified parser handles:
#   1. Simple markdown → mdast AST with Kyozo enhancements
#   2. Markdown-LD → JSON-LD frontmatter + QCP channels + annotations
#   3. QCP channel extraction (Task, Resources, Diagnostics, Meta)
#   4. HTML comment annotations with type parsing
#   5. Clean content extraction with position tracking

#   Automatically detects content type and uses optimal processing path.
#   Designed for performance and consciousness protection integration.
#   """

#   alias Kyozo.Markdown.AST
#   alias Kyozo.Markdown.Handlers

#   @doc """
#   Parse markdown content - automatically detects simple markdown vs Markdown-LD.

#   ## Simple Markdown Example

#       {:ok, ast} = Parser.parse("# Hello\\n<!-- kyozo: {\\"executable\\": true} -->\\n```elixir\\nIO.puts(:world)\\n```")
#       # => {:ok, %AST.Root{
#       #      type: :root,
#       #      children: [%AST.Heading{...}, %AST.Code{...}],
#       #      data: %{kyozo: %{...}}
#       #    }}

#   ## Markdown-LD Example

#       content = \"\"\"
#       ---
#       "@type": "AnalysisPrompt"
#       "@context":
#         "@vocab": "https://kyozo.store/vocab/"
#       ---

#       # Security Analysis

#       ## Channel: Task
#       <!-- @cognitive_load: 0.6 -->
#       Analyze the security patterns.
#       \"\"\"

#       {:ok, result} = Parser.parse(content)
#       # => {:ok, %{
#       #      type: :markdown_ld,
#       #      jsonld: %{"@type" => "AnalysisPrompt", ...},
#       #      channels: %{"task" => %{"content" => "...", ...}, ...},
#       #      annotations: %{"cognitive_load" => 0.6},
#       #      raw_content: "# Security Analysis\\n\\n## Channel: Task...",
#       #      original: content
#       #    }}
#   """
#   def parse(content, opts \\ []) when is_binary(content) do
#     if is_markdown_ld?(content) do
#       parse_markdown_ld(content, opts)
#     else
#       parse_simple_markdown(content, opts)
#     end
#   end

#   @doc """
#   Parse simple markdown into mdast AST with Kyozo enhancements.
#   """
#   def parse_simple_markdown(content, opts \\ []) do
#     with {:ok, tokens} <- tokenize_markdown(content),
#          {:ok, ast} <- build_ast(tokens),
#          {:ok, enhanced_ast} <- enhance_with_kyozo(ast, content) do
#       {:ok, enhanced_ast}
#     end
#   end

#   @doc """
#   Parse Markdown-LD with frontmatter and QCP channels.
#   """
#   def parse_markdown_ld(content, _opts \\ []) do
#     with {:ok, frontmatter, body} <- extract_frontmatter(content),
#          {:ok, jsonld} <- parse_yaml_ld(frontmatter),
#          {:ok, channels} <- extract_channels(body),
#          {:ok, annotations} <- extract_annotations(body) do
#       {:ok,
#        %{
#          type: :markdown_ld,
#          jsonld: jsonld,
#          channels: channels,
#          annotations: annotations,
#          raw_content: body,
#          original: content
#        }}
#     end
#   end

#   @doc """
#   Detect if content is Markdown-LD (has frontmatter or QCP channels).
#   """
#   def is_markdown_ld?(content) do
#     has_frontmatter?(content) or has_qcp_channels?(content)
#   end

#   @doc """
#   Extract frontmatter and body from markdown content.
#   Handles YAML frontmatter delimited by --- markers.
#   """
#   def extract_frontmatter(content) do
#     case String.split(content, ~r/^---$/m, parts: 3) do
#       ["", frontmatter, body] ->
#         {:ok, String.trim(frontmatter), String.trim(body)}

#       [body] ->
#         # No frontmatter, treat whole content as body
#         {:ok, "", String.trim(body)}

#       _ ->
#         {:error, :invalid_frontmatter}
#     end
#   end

#   @doc """
#   Parse YAML-formatted JSON-LD from frontmatter.
#   Expands context with Kyozo vocabulary defaults.
#   """
#   def parse_yaml_ld(""), do: {:ok, %{}}

#   def parse_yaml_ld(yaml) do
#     case YamlElixir.read_from_string(yaml) do
#       {:ok, data} ->
#         jsonld = expand_context(data)
#         {:ok, jsonld}

#       {:error, reason} ->
#         {:error, {:invalid_yaml, reason}}
#     end
#   end

#   @doc """
#   Extract QCP channels from markdown body.
#   Recognizes ## Channel: Name or ## Name headers.
#   """
#   def extract_channels(body) do
#     channels = %{
#       "task" => extract_channel(body, "Task"),
#       "resources" => extract_channel(body, "Resources"),
#       "diagnostics" => extract_channel(body, "Diagnostics"),
#       "meta" => extract_channel(body, "Meta")
#     }

#     {:ok, channels}
#   end

#   @doc """
#   Extract HTML comment annotations from markdown.
#   Parses <!-- @key: value --> format with type coercion.
#   """
#   def extract_annotations(body) do
#     annotations =
#       ~r/<!--\s*@(\w+):\s*(.+?)\s*-->/s
#       |> Regex.scan(body)
#       |> Enum.map(fn [_, key, value] ->
#         {key, parse_annotation_value(value)}
#       end)
#       |> Map.new()

#     {:ok, annotations}
#   end

#   @doc """
#   Convert parsed Markdown-LD back to markdown format.
#   Reconstructs frontmatter and channels.
#   """
#   def to_markdown(%{jsonld: jsonld, channels: channels}) do
#     frontmatter = format_frontmatter(jsonld)
#     body = format_channels(channels)

#     if frontmatter == "" do
#       body
#     else
#       """
#       ---
#       #{frontmatter}
#       ---

#       #{body}
#       """
#     end
#   end

#   # Private implementation

#   defp expand_context(data) when is_map(data) do
#     base_context = %{
#       "@vocab" => "https://kyozo.store/vocab/",
#       "schema" => "https://schema.org/",
#       "kyozo" => "https://kyozo.store/vocab/",
#       "qcp" => "https://kyozo.store/qcp/"
#     }

#     context = Map.get(data, "@context", %{})

#     data
#     |> Map.put("@context", Map.merge(base_context, context))
#     |> expand_nested_contexts()
#   end

#   defp expand_context(data), do: data

#   defp expand_nested_contexts(data) when is_map(data) do
#     Enum.map(data, fn {k, v} -> {k, expand_nested_contexts(v)} end)
#     |> Map.new()
#   end

#   defp expand_nested_contexts(data) when is_list(data) do
#     Enum.map(data, &expand_nested_contexts/1)
#   end

#   defp expand_nested_contexts(data), do: data

#   defp extract_channel(body, channel_name) do
#     # Match ## Channel: Name or ## Name
#     pattern = ~r/##\s+(?:Channel:\s+)?#{channel_name}\s*\n(.*?)(?=\n##\s+|$)/is

#     case Regex.run(pattern, body) do
#       [_, content] ->
#         content = String.trim(content)
#         annotations = extract_channel_annotations(content)

#         %{
#           "content" => clean_content(content),
#           "annotations" => annotations,
#           "size" => byte_size(content)
#         }

#       _ ->
#         nil
#     end
#   end

#   defp extract_channel_annotations(content) do
#     ~r/<!--\s*@(\w+):\s*(.+?)\s*-->/
#     |> Regex.scan(content)
#     |> Enum.map(fn [_, key, value] ->
#       {key, parse_annotation_value(value)}
#     end)
#     |> Map.new()
#   end

#   defp clean_content(content) do
#     # Remove HTML comments but preserve structure
#     String.replace(content, ~r/<!--.*?-->/s, "")
#     |> String.trim()
#   end

#   defp parse_annotation_value(value) do
#     cond do
#       # Try parsing as JSON first
#       String.starts_with?(value, "[") || String.starts_with?(value, "{") ->
#         case Jason.decode(value) do
#           {:ok, parsed} -> parsed
#           _ -> value
#         end

#       # Try parsing as number
#       String.match?(value, ~r/^\d+\.?\d*$/) ->
#         case Float.parse(value) do
#           {num, ""} -> num
#           _ -> value
#         end

#       # Boolean values
#       value in ["true", "false"] ->
#         value == "true"

#       # Default: string
#       true ->
#         String.trim(value)
#     end
#   end

#   defp format_frontmatter(jsonld) when jsonld == %{}, do: ""

#   defp format_frontmatter(jsonld) do
#     jsonld
#     |> Map.to_list()
#     |> Enum.map(fn {k, v} -> format_yaml_line(k, v, 0) end)
#     |> Enum.join("\n")
#   end

#   defp format_yaml_line(key, value, indent) do
#     spaces = String.duplicate("  ", indent)

#     cond do
#       is_map(value) ->
#         "#{spaces}#{key}:\n" <> format_yaml_map(value, indent + 1)

#       is_list(value) ->
#         "#{spaces}#{key}:\n" <> format_yaml_list(value, indent + 1)

#       true ->
#         "#{spaces}#{key}: #{format_yaml_value(value)}"
#     end
#   end

#   defp format_yaml_map(map, indent) do
#     map
#     |> Map.to_list()
#     |> Enum.map(fn {k, v} -> format_yaml_line(k, v, indent) end)
#     |> Enum.join("\n")
#   end

#   defp format_yaml_list(list, indent) do
#     spaces = String.duplicate("  ", indent)

#     list
#     |> Enum.map(fn item ->
#       if is_map(item) do
#         "#{spaces}- " <> format_yaml_map(item, indent + 1)
#       else
#         "#{spaces}- #{format_yaml_value(item)}"
#       end
#     end)
#     |> Enum.join("\n")
#   end

#   defp format_yaml_value(value) when is_binary(value) do
#     if String.contains?(value, "\n") || String.contains?(value, "\"") do
#       "\"#{String.replace(value, "\"", "\\\"")}\""
#     else
#       value
#     end
#   end

#   defp format_yaml_value(value), do: to_string(value)

#   defp format_channels(channels) when is_map(channels) do
#     ["task", "resources", "diagnostics", "meta"]
#     |> Enum.map(fn name ->
#       channel = Map.get(channels, name)

#       if channel && channel["content"] do
#         format_channel(name, channel)
#       end
#     end)
#     |> Enum.reject(&is_nil/1)
#     |> Enum.join("\n\n")
#   end

#   defp format_channel(name, channel) do
#     annotations = format_annotations(channel["annotations"] || %{})
#     content = channel["content"]

#     header = "## Channel: #{String.capitalize(name)}"

#     if annotations == "" do
#       "#{header}\n#{content}"
#     else
#       "#{header}\n#{annotations}\n#{content}"
#     end
#   end

#   defp format_annotations(annotations) when annotations == %{}, do: ""

#   defp format_annotations(annotations) do
#     annotations
#     |> Map.to_list()
#     |> Enum.map(fn {k, v} ->
#       value = if is_binary(v), do: v, else: Jason.encode!(v)
#       "<!-- @#{k}: #{value} -->"
#     end)
#     |> Enum.join("\n")
#   end

#   # Simple markdown parsing functions

#   defp has_frontmatter?(content) do
#     String.starts_with?(String.trim(content), "---")
#   end

#   defp has_qcp_channels?(content) do
#     String.contains?(content, "## Channel:") or
#       String.contains?(content, "```task") or
#       String.contains?(content, "```resources") or
#       String.contains?(content, "```diagnostics") or
#       String.contains?(content, "```meta")
#   end

#   defp tokenize_markdown(content) do
#     # Simple tokenization - split into lines and classify
#     lines = String.split(content, ~r/\r?\n/)
#     tokens = Enum.map(lines, &classify_line/1)
#     {:ok, tokens}
#   end

#   defp classify_line(line) do
#     cond do
#       String.match?(line, ~r/^#+\s/) -> {:heading, line}
#       String.match?(line, ~r/^```/) -> {:code_fence, line}
#       String.match?(line, ~r/^<!--.*-->/) -> {:html_comment, line}
#       String.match?(line, ~r/^\s*[-*+]\s+/) -> {:list_item, line}
#       String.trim(line) == "" -> {:blank, line}
#       true -> {:text, line}
#     end
#   end

#   defp build_ast(tokens) do
#     ast = %AST.Root{
#       type: :root,
#       children: [],
#       data: %{}
#     }

#     children = build_children(tokens, [])
#     {:ok, %{ast | children: children}}
#   end

#   defp build_children([], acc), do: Enum.reverse(acc)

#   defp build_children([{:heading, line} | rest], acc) do
#     level = count_hashes(line)
#     text = String.trim(String.replace(line, ~r/^\#{1,6}\s*/, ""))

#     heading = %AST.Heading{
#       type: :heading,
#       depth: level,
#       children: [%AST.Text{type: :text, value: text}]
#     }

#     build_children(rest, [heading | acc])
#   end

#   defp build_children([{:text, line} | rest], acc) do
#     paragraph = %AST.Paragraph{
#       type: :paragraph,
#       children: [%AST.Text{type: :text, value: line}]
#     }

#     build_children(rest, [paragraph | acc])
#   end

#   defp build_children([{:code_fence, line} | rest], acc) do
#     {code_content, remaining} = collect_code_block(rest, [])
#     lang = extract_language(line)

#     code = %AST.Code{
#       type: :code,
#       lang: lang,
#       value: Enum.join(code_content, "\n")
#     }

#     build_children(remaining, [code | acc])
#   end

#   defp build_children([{:html_comment, line} | rest], acc) do
#     # Process Kyozo annotations but don't add to AST
#     build_children(rest, acc)
#   end

#   defp build_children([_ | rest], acc) do
#     # Skip other tokens for now
#     build_children(rest, acc)
#   end

#   defp count_hashes(line) do
#     case Regex.run(~r/^(\#*)/, line) do
#       [_, hashes] -> min(String.length(hashes), 6)
#       _ -> 1
#     end
#   end

#   defp extract_language(line) do
#     case Regex.run(~r/^```(\w+)/, line) do
#       [_, lang] -> lang
#       _ -> nil
#     end
#   end

#   defp collect_code_block([], acc), do: {Enum.reverse(acc), []}

#   defp collect_code_block([{:code_fence, _} | rest], acc) do
#     {Enum.reverse(acc), rest}
#   end

#   defp collect_code_block([{_, line} | rest], acc) do
#     collect_code_block(rest, [line | acc])
#   end

#   defp enhance_with_kyozo(ast, content) do
#     # Extract Kyozo metadata from HTML comments
#     kyozo_data = extract_kyozo_metadata(content)

#     enhanced_ast = %{ast | data: Map.put(ast.data, :kyozo, kyozo_data)}
#     {:ok, enhanced_ast}
#   end

#   defp extract_kyozo_metadata(content) do
#     ~r/<!-- kyozo:(.*?) -->/s
#     |> Regex.scan(content, capture: :all_but_first)
#     |> Enum.map(fn [json] -> Jason.decode(json) end)
#     |> Enum.filter(&match?({:ok, _}, &1))
#     |> Enum.map(fn {:ok, data} -> data end)
#     |> Enum.reduce(%{}, &Map.merge/2)
#   end
# end
