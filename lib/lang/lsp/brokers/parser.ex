defmodule Lang.LSP.Brokers.Parser do
  @moduledoc """
  Lightweight parser broker (in-process).

  Handles `lang.parser.parse` and `lang.parser.detect_format` using
  the existing TextIntelligence utilities.
  """

  @behaviour Lang.LSP.DomainBroker
  alias Lang.LSP.Configuration

  @impl true
  def init(_cfg), do: {:ok, :ready}

  @impl true
  def handle(%{"method" => "lang.parser.parse", "params" => %{"content" => content} = params}, %Configuration{}) do
    fmt = params["format"] || Lang.TextIntelligence.FormatDetector.detect(content)
    {:ok, parse_by_format(fmt, content)}
  end

  def handle(%{"method" => "lang.parser.detect_format", "params" => params}, %Configuration{}) do
    content = params["content"]
    uri = params["uri"]
    format =
      cond do
        is_binary(content) -> Lang.TextIntelligence.FormatDetector.detect(content)
        is_binary(uri) -> Lang.TextIntelligence.FormatDetector.detect_from_uri(uri)
        true -> "unknown"
      end

    {:ok, %{format: format}}
  end

  def handle(_req, _cfg), do: {:error, -32601, "Method not found"}

  @impl true
  def terminate(_state), do: :ok

  defp parse_by_format("json", content) do
    case Jason.decode(content) do
      {:ok, data} -> %{format: "json", data: data}
      {:error, reason} -> %{format: "json", error: {:json_parse_error, reason}}
    end
  end

  defp parse_by_format("yaml", content) do
    try do
      %{format: "yaml", data: YamlElixir.read_from_string(content)}
    rescue
      e -> %{format: "yaml", error: {:yaml_parse_error, e}}
    end
  end

  defp parse_by_format("markdown", content) do
    case Kyozo.Lang.UniversalParser.Formats.Markdown.parse_minimal(content) do
      {:ok, basic} -> %{format: "markdown", structure: basic}
      {:error, reason} -> %{format: "markdown", error: reason}
    end
  end

  defp parse_by_format(fmt, content) when is_binary(fmt) do
    %{format: fmt, content: content}
  end
end

