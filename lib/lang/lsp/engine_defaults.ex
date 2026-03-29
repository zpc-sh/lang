defmodule Lang.LSP.EngineDefaults do
  @moduledoc """
  Registers default per-language backends with Lang.LSP.Engine, brokering
  standard LSP methods to existing local handlers.
  """

  alias Lang.LSP.Engine

  @default_langs [
    "elixir",
    "eelixir",
    "heex",
    "javascript",
    "typescript",
    "markdown",
    "json"
  ]

  @doc """
  Register default handlers for a set of languages.
  Safe to call multiple times.
  """
  def register_defaults(langs \\ @default_langs) do
    Enum.each(langs, fn lang -> Engine.register(lang, &handle/3) end)
    :ok
  end

  # Engine backend handler: (method, params, ctx) -> result
  defp handle("textDocument/completion", %{"textDocument" => %{"uri" => uri}, "position" => pos} = _params, ctx) do
    doc = Map.fetch!(ctx, :document)
    lang = doc[:language_id] || Map.get(ctx, :language_id)
    case Lang.LSP.Handlers.Completion.handle(uri, doc.text, pos, %{}, %{language: lang}) do
      {:ok, items} -> {:ok, items}
      {:error, reason} -> {:error, reason}
      other -> {:ok, other}
    end
  end

  defp handle("textDocument/hover", %{"textDocument" => %{"uri" => _uri}, "position" => pos}, ctx) do
    doc = Map.fetch!(ctx, :document)
    word = get_word_at_position(doc.text, pos)
    case Lang.Providers.Router.route_lsp(:hover, %{word: word, context: get_line_at_position(doc.text, pos), language: doc.language_id}) do
      {:ok, info} -> {:ok, %{ "contents" => %{ "kind" => "markdown", "value" => info } }}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle("textDocument/definition", %{"textDocument" => %{"uri" => uri}, "position" => pos}, ctx) do
    doc = Map.fetch!(ctx, :document)
    word = get_word_at_position(doc.text, pos)
    case Lang.TextIntelligence.SymbolAnalyzer.find_definition(word, uri, Map.get(ctx, :root_uri)) do
      {:ok, defs} -> {:ok, Enum.map(defs, &format_location/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle(_method, _params, _ctx), do: {:error, :no_handler}

  defp get_word_at_position(text, %{"line" => line, "character" => char}) do
    lines = String.split(text, "\n")
    current = Enum.at(lines, line, "")
    before = String.slice(current, 0, min(char, String.length(current))) |> String.reverse()
    afterc = if char <= String.length(current), do: String.slice(current, char..-1), else: ""
    wb = Regex.run(~r/^\w+/, before) |> List.first("") |> String.reverse()
    wa = Regex.run(~r/^\w+/, afterc) |> List.first("")
    wb <> wa
  end

  defp get_line_at_position(text, %{"line" => line}), do: Enum.at(String.split(text, "\n"), line, "")

  defp format_location(%{uri: u, range: r}), do: %{ "uri" => u, "range" => r }
  defp format_location(%{location: %{uri: u, range: r}}), do: %{ "uri" => u, "range" => r }
end

