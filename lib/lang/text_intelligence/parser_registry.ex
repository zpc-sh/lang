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
end
