defmodule Lang.LSP.Handlers.Formatting do
  @moduledoc """
  Handles textDocument/formatting requests.
  """

  require Logger
  alias Lang.TextIntelligence.Formatter

  def handle(id, %{"textDocument" => %{"uri" => uri}}, state) do
    case Map.get(state.documents, uri) do
      nil ->
        error_response(id, :document_not_found)

      document ->
        edits = 
          case Formatter.format(document.text, document.language_id) do
            {:ok, formatted_text} ->
              if formatted_text != document.text do
                [
                  %{ 
                    "range" => %{
                      "start" => %{"line" => 0, "character" => 0},
                      "end" => get_document_end(document.text)
                    },
                    "newText" => formatted_text
                  }
                ]
              else
                []
              end

            {:error, _reason} ->
              []
          end

        %{ 
          "jsonrpc" => "2.0",
          "id" => id,
          "result" => edits
        }
    end
  end

  defp get_document_end(text) do
    lines = String.split(text, "\n")
    last_line = length(lines) - 1
    last_line_text = List.last(lines) || ""

    %{ 
      "line" => last_line,
      "character" => String.length(last_line_text)
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
