defmodule Lang.TextIntelligence.ParserRegistry do
  @moduledoc """
  Central registry for all supported text formats and their parsers
  """

  use GenServer
  require Logger

  @parsers %{
    # Programming languages
    "javascript" => %{parser: :builtin_javascript, domain: "code"},
    "python" => %{parser: :builtin_python, domain: "code"},
    "elixir" => %{parser: :builtin_elixir, domain: "code"},
    "typescript" => %{parser: :builtin_typescript, domain: "code"},
    "rust" => %{parser: :builtin_rust, domain: "code"},
    "go" => %{parser: :builtin_go, domain: "code"},

    # Documentation formats
    "markdown" => %{parser: :builtin_markdown, domain: "documentation"},
    "text" => %{parser: :builtin_text, domain: "documentation"},
    "rst" => %{parser: :builtin_rst, domain: "documentation"},
    "asciidoc" => %{parser: :builtin_asciidoc, domain: "documentation"},

    # Data formats
    "json" => %{parser: :builtin_json, domain: "data"},
    "yaml" => %{parser: :builtin_yaml, domain: "config"},
    "toml" => %{parser: :builtin_toml, domain: "config"},
    "xml" => %{parser: :builtin_xml, domain: "data"},
    "csv" => %{parser: :builtin_csv, domain: "data"},

    # Communication formats
    "conversation" => %{
      parser: :composite,
      components: [:conversation_parser, :sentiment_analyzer, :intent_classifier],
      domain: "communication"
    },
    "email" => %{parser: :builtin_email, domain: "communication"},
    "chat" => %{parser: :builtin_chat, domain: "communication"},

    # Specialized formats
    "log" => %{parser: :builtin_log, domain: "monitoring"},
    "sql" => %{parser: :builtin_sql, domain: "query"},
    "regex" => %{parser: :builtin_regex, domain: "pattern"}
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Parser Registry with #{map_size(@parsers)} parsers")
    {:ok, %{parsers: @parsers, cache: %{}, stats: %{}}}
  end

  def get_parser(format) when is_binary(format) do
    GenServer.call(__MODULE__, {:get_parser, format})
  end

  def list_supported_formats do
    GenServer.call(__MODULE__, :list_formats)
  end

  def get_parser_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  def register_custom_parser(format, parser_config) do
    GenServer.call(__MODULE__, {:register_parser, format, parser_config})
  end

  @impl true
  def handle_call({:get_parser, format}, _from, state) do
    normalized_format = String.downcase(format)

    case Map.get(state.parsers, normalized_format) do
      nil ->
        {:reply, {:error, :unsupported_format}, state}

      parser_config ->
        # Update stats
        stats = Map.update(state.stats, normalized_format, 1, &(&1 + 1))
        {:reply, {:ok, parser_config}, %{state | stats: stats}}
    end
  end

  @impl true
  def handle_call(:list_formats, _from, state) do
    formats =
      state.parsers
      |> Enum.map(fn {format, config} ->
        %{
          format: format,
          domain: config.domain,
          parser_type: get_parser_type(config.parser),
          usage_count: Map.get(state.stats, format, 0)
        }
      end)
      |> Enum.sort_by(& &1.format)

    {:reply, formats, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    total_requests = state.stats |> Map.values() |> Enum.sum()

    stats = %{
      total_parsers: map_size(state.parsers),
      total_requests: total_requests,
      format_usage: state.stats,
      domains: get_domain_stats(state.parsers)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:register_parser, format, parser_config}, _from, state) do
    normalized_format = String.downcase(format)

    # Validate parser config
    case validate_parser_config(parser_config) do
      :ok ->
        updated_parsers = Map.put(state.parsers, normalized_format, parser_config)
        Logger.info("Registered custom parser for format: #{normalized_format}")
        {:reply, :ok, %{state | parsers: updated_parsers}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp get_parser_type(:composite), do: "composite"

  defp get_parser_type(parser) when is_atom(parser) do
    parser
    |> Atom.to_string()
    |> String.replace("builtin_", "")
  end

  defp get_domain_stats(parsers) do
    parsers
    |> Enum.group_by(fn {_format, config} -> config.domain end)
    |> Enum.map(fn {domain, formats} -> {domain, length(formats)} end)
    |> Enum.into(%{})
  end

  defp validate_parser_config(%{parser: parser, domain: domain})
       when is_atom(parser) and is_binary(domain) do
    :ok
  end

  defp validate_parser_config(%{parser: :composite, components: components, domain: domain})
       when is_list(components) and is_binary(domain) do
    if Enum.all?(components, &is_atom/1) do
      :ok
    else
      {:error, :invalid_components}
    end
  end

  defp validate_parser_config(_), do: {:error, :invalid_config}

  # =============================================================================
  # Public API Methods
  # =============================================================================

  @doc """
  Parse content using the appropriate parser for the format.
  """
  def parse(content, format) when is_binary(content) and is_binary(format) do
    case get_parser(format) do
      {:ok, parser_config} ->
        parse_with_config(content, format, parser_config)

      {:error, :unsupported_format} ->
        # Fallback to basic text parsing
        {:ok, parse_as_text(content)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_with_config(content, format, %{parser: :composite, components: components}) do
    # For composite parsers, run all components and merge results
    results =
      components
      |> Enum.map(fn component ->
        parse_with_parser(content, format, component)
      end)
      |> Enum.reduce(%{}, fn result, acc ->
        Map.merge(acc, result, fn _key, v1, v2 ->
          case {v1, v2} do
            {list1, list2} when is_list(list1) and is_list(list2) -> list1 ++ list2
            {map1, map2} when is_map(map1) and is_map(map2) -> Map.merge(map1, map2)
            {_, v2} -> v2
          end
        end)
      end)

    {:ok, results}
  end

  defp parse_with_config(content, format, %{parser: parser}) do
    result = parse_with_parser(content, format, parser)
    {:ok, result}
  end

  defp parse_with_parser(content, format, parser) do
    case parser do
      :builtin_javascript -> parse_javascript(content)
      :builtin_python -> parse_python(content)
      :builtin_elixir -> parse_elixir(content)
      :builtin_markdown -> parse_markdown(content)
      :builtin_json -> parse_json(content)
      :builtin_yaml -> parse_yaml(content)
      :builtin_xml -> parse_xml(content)
      :builtin_text -> parse_as_text(content)
      _ -> parse_as_text(content)
    end
  end

  # =============================================================================
  # Format-specific parsers
  # =============================================================================

  defp parse_javascript(content) do
    %{
      type: "javascript",
      functions: extract_js_functions(content),
      variables: extract_js_variables(content),
      imports: extract_js_imports(content),
      exports: extract_js_exports(content)
    }
  end

  defp parse_python(content) do
    %{
      type: "python",
      classes: extract_python_classes(content),
      functions: extract_python_functions(content),
      imports: extract_python_imports(content)
    }
  end

  defp parse_elixir(content) do
    %{
      type: "elixir",
      modules: extract_elixir_modules(content),
      functions: extract_elixir_functions(content),
      macros: extract_elixir_macros(content),
      attributes: extract_elixir_attributes(content)
    }
  end

  defp parse_markdown(content) do
    %{
      type: "markdown",
      headers: extract_markdown_headers(content),
      links: extract_markdown_links(content),
      code_blocks: extract_markdown_code_blocks(content)
    }
  end

  defp parse_json(content) do
    case Jason.decode(content) do
      {:ok, parsed} -> %{type: "json", data: parsed}
      {:error, _} -> %{type: "json", error: "Invalid JSON", raw: content}
    end
  end

  defp parse_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, parsed} -> %{type: "yaml", data: parsed}
      {:error, _} -> %{type: "yaml", error: "Invalid YAML", raw: content}
    end
  rescue
    _ -> %{type: "yaml", error: "YAML parser not available", raw: content}
  end

  defp parse_xml(content) do
    %{type: "xml", raw: content}
  end

  defp parse_as_text(content) do
    %{
      type: "text",
      lines: String.split(content, "\n"),
      word_count: content |> String.split(~r/\s+/) |> length(),
      char_count: String.length(content)
    }
  end

  # =============================================================================
  # Extraction helpers
  # =============================================================================

  defp extract_js_functions(content) do
    Regex.scan(~r/function\s+(\w+)\s*\(([^)]*)\)/, content, capture: :all_but_first)
    |> Enum.map(fn [name, params] -> %{name: name, params: params} end)
  end

  defp extract_js_variables(content) do
    Regex.scan(~r/(?:let|const|var)\s+(\w+)/, content, capture: :all_but_first)
    |> Enum.map(fn [name] -> name end)
  end

  defp extract_js_imports(content) do
    Regex.scan(~r/import\s+.*\s+from\s+['"]([^'"]+)['"]/, content, capture: :all_but_first)
    |> Enum.map(fn [module] -> module end)
  end

  defp extract_js_exports(content) do
    Regex.scan(~r/export\s+(?:default\s+)?(?:function\s+)?(\w+)/, content,
      capture: :all_but_first
    )
    |> Enum.map(fn [name] -> name end)
  end

  defp extract_python_classes(content) do
    Regex.scan(~r/class\s+(\w+)(?:\([^)]*\))?:/, content, capture: :all_but_first)
    |> Enum.map(fn [name] -> name end)
  end

  defp extract_python_functions(content) do
    Regex.scan(~r/def\s+(\w+)\s*\(([^)]*)\):/, content, capture: :all_but_first)
    |> Enum.map(fn [name, params] -> %{name: name, params: params} end)
  end

  defp extract_python_imports(content) do
    imports = Regex.scan(~r/import\s+([\w\.]+)/, content, capture: :all_but_first)
    from_imports = Regex.scan(~r/from\s+([\w\.]+)\s+import/, content, capture: :all_but_first)
    (imports ++ from_imports) |> Enum.map(fn [module] -> module end)
  end

  defp extract_elixir_modules(content) do
    Regex.scan(~r/defmodule\s+([\w\.]+)/, content, capture: :all_but_first)
    |> Enum.map(fn [name] -> name end)
  end

  defp extract_elixir_functions(content) do
    Regex.scan(~r/def\s+(\w+)(?:\([^)]*\))?/, content, capture: :all_but_first)
    |> Enum.map(fn [name] -> name end)
  end

  defp extract_elixir_macros(content) do
    Regex.scan(~r/defmacro\s+(\w+)(?:\([^)]*\))?/, content, capture: :all_but_first)
    |> Enum.map(fn [name] -> name end)
  end

  defp extract_elixir_attributes(content) do
    Regex.scan(~r/@(\w+)/, content, capture: :all_but_first)
    |> Enum.map(fn [name] -> name end)
  end

  defp extract_markdown_headers(content) do
    Regex.scan(~r/^(#+)\s+(.+)$/m, content, capture: :all_but_first)
    |> Enum.map(fn [hashes, title] -> %{level: String.length(hashes), title: title} end)
  end

  defp extract_markdown_links(content) do
    Regex.scan(~r/\[([^\]]+)\]\(([^)]+)\)/, content, capture: :all_but_first)
    |> Enum.map(fn [text, url] -> %{text: text, url: url} end)
  end

  defp extract_markdown_code_blocks(content) do
    Regex.scan(~r/```(\w*)\n(.*?)```/s, content, capture: :all_but_first)
    |> Enum.map(fn [lang, code] -> %{language: lang, code: String.trim(code)} end)
  end
end
