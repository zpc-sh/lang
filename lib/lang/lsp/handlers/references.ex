defmodule Lang.LSP.Handlers.References do
  @moduledoc """
  Handles textDocument/references requests.
  """

  require Logger
  alias Lang.TextIntelligence.SymbolAnalyzer

  def handle(id, %{"textDocument" => %{"uri" => uri}, "position" => position}, state) do
    case Map.get(state.documents, uri) do
      nil ->
        error_response(id, :document_not_found)

      document ->
        word = get_word_at_position(document.text, position)

        references = 
          case SymbolAnalyzer.find_references(word, state.root_uri) do
            {:ok, refs} ->
              Enum.map(refs, &format_location/1)

            {:error, _reason} ->
              []
          end

        %{ 
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => references
        }
    end
  end

  defp get_word_at_position(text, %{"line" => line, "character" => character}) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    before = String.slice(current_line, 0, character) |> String.reverse()
    after_cursor = String.slice(current_line, character..-1)

    word_before = Regex.run(~r/^[\w_]+/, before) |> List.first("") |> String.reverse()
    word_after = Regex.run(~r/^[\w_]+/, after_cursor) |> List.first("")

    word_before <> word_after
  end

  defp format_location(%{location: %{uri: uri, range: range}}) do
    %{ 
      "uri" => uri,
      "range" => range
    }
  end

  defp error_response(id, message, code \\ -32603) do
    %{ 
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => to_string(message)
      }
    }
  end
end
