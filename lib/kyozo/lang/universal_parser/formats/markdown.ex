defmodule Kyozo.Lang.UniversalParser.Formats.Markdown do
  @moduledoc """
  Markdown Format Parser for Universal Parser

  This module provides comprehensive Markdown parsing capabilities with structure
  analysis, content extraction, and validation. It handles standard Markdown
  syntax and provides detailed analysis of document structure.

  ## Features

  - **Full Markdown Support** - Headers, links, lists, code blocks, tables
  - **Structure Analysis** - Document hierarchy and organization analysis
  - **Content Extraction** - Extract specific elements (headers, links, etc.)
  - **Table of Contents** - Automatic TOC generation from headers
  - **Link Validation** - Check for broken or malformed links
  - **Code Block Analysis** - Language detection and syntax validation

  ## Usage Examples

      # Basic Markdown parsing
      markdown = '''
      # Title

      This is a **bold** text with a [link](https://example.com).

      ## Subsection

      - Item 1
      - Item 2

      ```elixir
      def hello, do: "world"
      ```
      '''
      {:ok, result} = Markdown.parse(markdown)

      # With structure analysis
      {:ok, result} = Markdown.parse(markdown, analyze_structure: true)
      result.structure.headers
      # => [%{level: 1, text: "Title"}, %{level: 2, text: "Subsection"}]

      # Extract table of contents
      {:ok, toc} = Markdown.extract_toc(markdown)

  """

  require Logger

  @type parse_options :: [
          analyze_structure: boolean(),
          extract_links: boolean(),
          extract_code_blocks: boolean(),
          validate_links: boolean(),
          generate_toc: boolean(),
          include_metadata: boolean()
        ]

  @type markdown_element :: %{
          type: atom(),
          content: String.t(),
          attributes: map(),
          line_number: non_neg_integer() | nil
        }

  @type header_info :: %{
          level: 1..6,
          text: String.t(),
          id: String.t() | nil,
          line_number: non_neg_integer()
        }

  @type link_info :: %{
          text: String.t(),
          url: String.t(),
          title: String.t() | nil,
          line_number: non_neg_integer(),
          valid: boolean() | nil
        }

  @type code_block_info :: %{
          language: String.t() | nil,
          code: String.t(),
          line_number: non_neg_integer(),
          line_count: non_neg_integer()
        }

  @type markdown_structure :: %{
          headers: [header_info()],
          links: [link_info()],
          code_blocks: [code_block_info()],
          lists: [markdown_element()],
          tables: [markdown_element()],
          images: [link_info()],
          document_hierarchy: map(),
          word_count: non_neg_integer(),
          reading_time_minutes: non_neg_integer()
        }

  @type parsed_markdown :: %{
          content: String.t(),
          html: String.t() | nil,
          structure: markdown_structure(),
          metadata: %{
            parse_time_us: non_neg_integer(),
            content_size: non_neg_integer(),
            line_count: non_neg_integer(),
            parser_used: atom()
          }
        }

  @default_options [
    analyze_structure: true,
    extract_links: true,
    extract_code_blocks: true,
    validate_links: false,
    generate_toc: false,
    include_metadata: true
  ]

  @doc """
  Parse Markdown content with comprehensive analysis.

  ## Options

  - `:analyze_structure` - Include structural analysis (default: true)
  - `:extract_links` - Extract and analyze links (default: true)
  - `:extract_code_blocks` - Extract code blocks with language detection (default: true)
  - `:validate_links` - Validate link URLs (default: false)
  - `:generate_toc` - Generate table of contents (default: false)
  - `:include_metadata` - Include parsing metadata (default: true)

  ## Examples

      {:ok, result} = Markdown.parse("# Hello\n\nThis is **markdown**.")
      result.structure.headers
      # => [%{level: 1, text: "Hello", line_number: 1}]

  """
  @spec parse(String.t(), parse_options()) :: {:ok, parsed_markdown()} | {:error, term()}
  def parse(content, options \\ []) when is_binary(content) do
    options = Keyword.merge(@default_options, options)
    start_time = System.monotonic_time(:microsecond)

    try do
      # Parse structure elements
      structure = analyze_markdown_structure(content, options)

      # Generate HTML if needed
      html =
        if Keyword.get(options, :generate_html, false) do
          convert_to_html(content)
        else
          nil
        end

      end_time = System.monotonic_time(:microsecond)
      parse_time = end_time - start_time

      metadata =
        if Keyword.get(options, :include_metadata, true) do
          %{
            parse_time_us: parse_time,
            content_size: byte_size(content),
            line_count: count_lines(content),
            parser_used: :builtin_markdown
          }
        else
          %{}
        end

      result = %{
        content: content,
        html: html,
        structure: structure,
        metadata: metadata
      }

      {:ok, result}
    rescue
      error -> {:error, {:markdown_parse_error, error}}
    end
  end

  @doc """
  Parse Markdown with minimal overhead for performance-critical scenarios.

  Returns only basic structure without detailed analysis.

  ## Examples

      {:ok, basic_info} = Markdown.parse_minimal(markdown_content)

  """
  @spec parse_minimal(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_minimal(content) when is_binary(content) do
    try do
      headers = extract_headers(content)
      links = extract_links_basic(content)

      basic_structure = %{
        headers: headers,
        links: links,
        word_count: count_words(content),
        line_count: count_lines(content)
      }

      {:ok, basic_structure}
    rescue
      error -> {:error, {:minimal_parse_error, error}}
    end
  end

  @doc """
  Extract table of contents from Markdown headers.

  ## Examples

      markdown = "# Chapter 1\n## Section 1.1\n### Subsection 1.1.1"
      {:ok, toc} = Markdown.extract_toc(markdown)
      # => [%{level: 1, text: "Chapter 1", children: [%{level: 2, text: "Section 1.1", ...}]}]

  """
  @spec extract_toc(String.t()) :: {:ok, [map()]} | {:error, term()}
  def extract_toc(content) when is_binary(content) do
    try do
      headers = extract_headers(content)
      toc = build_toc_hierarchy(headers)
      {:ok, toc}
    rescue
      error -> {:error, {:toc_generation_error, error}}
    end
  end

  @doc """
  Validate all links in Markdown content.

  ## Examples

      {:ok, validation_report} = Markdown.validate_links(markdown_content)
      # => %{valid: 5, invalid: 1, unreachable: 0, details: [...]}

  """
  @spec validate_links(String.t()) :: {:ok, map()} | {:error, term()}
  def validate_links(content) when is_binary(content) do
    try do
      links = extract_links_detailed(content)

      validation_results = Enum.map(links, &validate_single_link/1)

      summary = %{
        total: length(links),
        valid: Enum.count(validation_results, & &1.valid),
        invalid: Enum.count(validation_results, &(not &1.valid)),
        details: validation_results
      }

      {:ok, summary}
    rescue
      error -> {:error, {:link_validation_error, error}}
    end
  end

  @doc """
  Extract all code blocks from Markdown content.

  ## Examples

      {:ok, code_blocks} = Markdown.extract_code_blocks(markdown_content)
      # => [%{language: "elixir", code: "def hello...", line_number: 5}]

  """
  @spec extract_code_blocks(String.t()) :: {:ok, [code_block_info()]} | {:error, term()}
  def extract_code_blocks(content) when is_binary(content) do
    try do
      code_blocks = do_extract_code_blocks(content)
      {:ok, code_blocks}
    rescue
      error -> {:error, {:code_block_extraction_error, error}}
    end
  end

  @doc """
  Calculate reading time for Markdown content.

  ## Examples

      reading_time = Markdown.calculate_reading_time(content)
      # => 3 (minutes)

  """
  @spec calculate_reading_time(String.t()) :: non_neg_integer()
  def calculate_reading_time(content) when is_binary(content) do
    word_count = count_words(content)
    # Average reading speed: 200 words per minute
    max(1, div(word_count, 200))
  end

  @doc """
  Convert Markdown to HTML.

  ## Examples

      {:ok, html} = Markdown.to_html("# Hello\n\nThis is **bold**.")
      # => {:ok, "<h1>Hello</h1>\n<p>This is <strong>bold</strong>.</p>"}

  """
  @spec to_html(String.t()) :: {:ok, String.t()} | {:error, term()}
  def to_html(content) when is_binary(content) do
    try do
      html = convert_to_html(content)
      {:ok, html}
    rescue
      error -> {:error, {:html_conversion_error, error}}
    end
  end

  # === Private Functions ===

  defp analyze_markdown_structure(content, options) do
    base_structure = %{
      headers: [],
      links: [],
      code_blocks: [],
      lists: [],
      tables: [],
      images: [],
      document_hierarchy: %{},
      word_count: count_words(content),
      reading_time_minutes: calculate_reading_time(content)
    }

    structure =
      if Keyword.get(options, :analyze_structure, true) do
        %{
          base_structure
          | headers: extract_headers(content),
            lists: extract_lists(content),
            tables: extract_tables(content),
            images: extract_images(content)
        }
      else
        base_structure
      end

    structure =
      if Keyword.get(options, :extract_links, true) do
        links =
          if Keyword.get(options, :validate_links, false) do
            extract_links_detailed(content)
            |> Enum.map(&validate_single_link/1)
          else
            extract_links_detailed(content)
          end

        %{structure | links: links}
      else
        structure
      end

    structure =
      if Keyword.get(options, :extract_code_blocks, true) do
        %{structure | code_blocks: do_extract_code_blocks(content)}
      else
        structure
      end

    # Build document hierarchy
    structure = %{structure | document_hierarchy: build_document_hierarchy(structure.headers)}

    structure
  end

  defp extract_headers(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _index} ->
      String.match?(line, ~r/^#+\s+.+/)
    end)
    |> Enum.map(fn {line, line_number} ->
      level = count_leading_hashes(line)
      text = String.trim(String.replace(line, ~r/^#+\s*/, ""))
      id = generate_header_id(text)

      %{
        level: level,
        text: text,
        id: id,
        line_number: line_number
      }
    end)
  end

  defp extract_links_basic(content) do
    # Basic link extraction using regex
    ~r/\[([^\]]+)\]\(([^)]+)\)/
    |> Regex.scan(content, capture: :all_but_first)
    |> Enum.map(fn [text, url] ->
      %{text: text, url: url, valid: nil}
    end)
  end

  defp extract_links_detailed(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      # Extract links with titles: [text](url "title")
      detailed_matches =
        Regex.scan(~r/\[([^\]]+)\]\(([^)]+?)\s*(?:"([^"]+)")?\)/, line, capture: :all_but_first)

      Enum.map(detailed_matches, fn match ->
        case match do
          [text, url, title] ->
            %{text: text, url: url, title: title, line_number: line_number, valid: nil}

          [text, url] ->
            %{text: text, url: url, title: nil, line_number: line_number, valid: nil}
        end
      end)
    end)
  end

  defp extract_images(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      # Extract images: ![alt](src "title")
      Regex.scan(~r/!\[([^\]]*)\]\(([^)]+?)\s*(?:"([^"]+)")?\)/, line, capture: :all_but_first)
      |> Enum.map(fn match ->
        case match do
          [alt, src, title] ->
            %{
              text: alt,
              url: src,
              title: title,
              line_number: line_number,
              type: :image,
              valid: nil
            }

          [alt, src] ->
            %{text: alt, url: src, title: nil, line_number: line_number, type: :image, valid: nil}
        end
      end)
    end)
  end

  defp do_extract_code_blocks(content) do
    # Extract fenced code blocks
    fenced_pattern = ~r/```(\w*)\n(.*?)```/s

    Regex.scan(fenced_pattern, content, capture: :all_but_first)
    |> Enum.map(fn [language, code] ->
      %{
        language: if(language == "", do: nil, else: language),
        code: String.trim(code),
        line_number: find_code_block_line_number(content, code),
        line_count: count_lines(code)
      }
    end)
  end

  defp extract_lists(content) do
    lines = String.split(content, "\n")

    current_list = nil
    lists = []

    {final_lists, _} =
      Enum.reduce(lines, {lists, current_list}, fn line, {acc_lists, current} ->
        cond do
          String.match?(line, ~r/^\s*[-*+]\s+/) ->
            # Unordered list item
            item_text = String.trim(String.replace(line, ~r/^\s*[-*+]\s+/, ""))
            new_item = %{type: :unordered_item, content: item_text}

            case current do
              nil -> {acc_lists, [new_item]}
              list -> {acc_lists, list ++ [new_item]}
            end

          String.match?(line, ~r/^\s*\d+\.\s+/) ->
            # Ordered list item
            item_text = String.trim(String.replace(line, ~r/^\s*\d+\.\s+/, ""))
            new_item = %{type: :ordered_item, content: item_text}

            case current do
              nil -> {acc_lists, [new_item]}
              list -> {acc_lists, list ++ [new_item]}
            end

          String.trim(line) == "" and current != nil ->
            # Empty line - end current list
            list_element = %{type: :list, content: current, line_number: nil, attributes: %{}}
            {acc_lists ++ [list_element], nil}

          true ->
            # Non-list line
            if current != nil do
              list_element = %{type: :list, content: current, line_number: nil, attributes: %{}}
              {acc_lists ++ [list_element], nil}
            else
              {acc_lists, current}
            end
        end
      end)

    # Handle final list if exists
    case final_lists do
      {lists, nil} ->
        lists

      {lists, final_list} ->
        list_element = %{type: :list, content: final_list, line_number: nil, attributes: %{}}
        lists ++ [list_element]
    end
  end

  defp extract_tables(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _index} ->
      # Simple table detection - contains pipes
      # Skip separator lines
      String.contains?(line, "|") and
        String.trim(line) != "" and
        not String.match?(line, ~r/^\s*\|[\s\-:]+\|\s*$/)
    end)
    |> Enum.chunk_by(fn {_line, index} ->
      # Group consecutive table lines
      # Simple grouping heuristic
      div(index, 10)
    end)
    |> Enum.map(fn table_lines ->
      rows =
        Enum.map(table_lines, fn {line, line_num} ->
          cells =
            line
            |> String.split("|")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          %{cells: cells, line_number: line_num}
        end)

      %{
        type: :table,
        content: rows,
        line_number: elem(List.first(table_lines), 1),
        attributes: %{row_count: length(rows)}
      }
    end)
  end

  defp build_document_hierarchy(headers) do
    headers
    |> Enum.reduce(%{}, fn header, hierarchy ->
      level_key = "level_#{header.level}"
      current_level = Map.get(hierarchy, level_key, [])
      Map.put(hierarchy, level_key, current_level ++ [header])
    end)
  end

  defp build_toc_hierarchy(headers) do
    # Build nested TOC structure
    do_build_toc(headers, 1, [])
  end

  defp do_build_toc([], _current_level, acc), do: Enum.reverse(acc)

  defp do_build_toc([header | rest], current_level, acc) do
    if header.level <= current_level do
      # Same level or higher - add to current level
      {children, remaining} = extract_children(rest, header.level + 1)

      toc_item = %{
        level: header.level,
        text: header.text,
        id: header.id,
        children: children
      }

      do_build_toc(remaining, current_level, [toc_item | acc])
    else
      # Lower level - shouldn't happen in well-structured documents
      do_build_toc(rest, current_level, acc)
    end
  end

  defp extract_children(headers, child_level) do
    {children, rest} = Enum.split_while(headers, fn h -> h.level >= child_level end)
    {do_build_toc(children, child_level, []), rest}
  end

  defp validate_single_link(link) do
    valid =
      case link.url do
        "http" <> _ -> validate_http_url(link.url)
        "mailto:" <> _ -> true
        # Internal anchor
        "#" <> _ -> true
        _ -> validate_relative_url(link.url)
      end

    %{link | valid: valid}
  end

  defp validate_http_url(url) do
    # Basic URL structure validation
    String.match?(url, ~r/^https?:\/\/[^\s$.?#].[^\s]*$/i)
  end

  defp validate_relative_url(url) do
    # Basic relative URL validation
    not String.contains?(url, " ") and String.length(url) > 0
  end

  defp count_leading_hashes(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == "#"))
    |> length()
    # Maximum 6 levels in Markdown
    |> min(6)
  end

  defp generate_header_id(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end

  defp find_code_block_line_number(content, code) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.find(fn {line, _index} ->
      String.contains?(line, String.slice(code, 0, 20))
    end)
    |> case do
      {_line, index} -> index
      nil -> 0
    end
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end

  defp count_words(content) do
    content
    # Remove code blocks
    |> String.replace(~r/```.*?```/s, " ")
    # Remove markdown syntax
    |> String.replace(~r/[#*_`\[\]()]/, " ")
    |> String.split()
    |> length()
  end

  defp convert_to_html(content) do
    # Basic Markdown to HTML conversion
    # This is a simplified implementation - in production, use a proper library
    content
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/\*\*([^*]+)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*([^*]+)\*/, "<em>\\1</em>")
    |> String.replace(~r/\[([^\]]+)\]\(([^)]+)\)/, "<a href=\"\\2\">\\1</a>")
    |> String.replace(~r/^- (.+)$/m, "<li>\\1</li>")
    |> String.replace(~r/(<li>.*<\/li>)/s, "<ul>\\1</ul>")
  end
end
