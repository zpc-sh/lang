defmodule Lang.LSP.Handlers.Rename do
  @moduledoc """
  Handles textDocument/rename requests.

  Minimal implementation: performs in-document rename by locating occurrences
  of the symbol under the given position and returning a WorkspaceEdit with
  text edits for the same URI. Workspace-wide rename is a future enhancement.
  """

  require Logger

  @type lsp_pos :: %{line: non_neg_integer(), character: non_neg_integer()}

  def handle(id, %{"textDocument" => %{"uri" => uri}, "position" => pos, "newName" => new_name}, state) do
    with true <- valid_new_name?(new_name) do
      case Map.get(state.documents, uri) do
        nil -> error_response(id, :document_not_found)
        %{text: text} ->
          case get_word_at_position(text, pos) do
            nil -> error_response(id, :symbol_not_found)
            "" -> error_response(id, :symbol_not_found)
            ^new_name -> %{"jsonrpc" => "2.0", "id" => id, "result" => %{"changes" => %{uri => []}}}
            old ->
              # Build edits across all open documents in memory
              changes =
                state.documents
                |> Enum.reduce(%{}, fn {u, %{text: t}}, acc ->
                  es = find_occurrence_edits(t, old, new_name)
                  if es == [], do: acc, else: Map.put(acc, u, es)
                end)

              %{"jsonrpc" => "2.0", "id" => id, "result" => %{"changes" => changes}}
          end
      end
    else
      _ -> error_response(id, :invalid_new_name)
    end
  end

  defp valid_new_name?(name) when is_binary(name) do
    byte_size(name) > 0 and byte_size(name) <= 128 and String.match?(name, ~r/^[A-Za-z_][A-Za-z0-9_!?]*$/)
  end
  defp valid_new_name?(_), do: false

  defp get_word_at_position(text, %{"line" => line, "character" => character}) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    before = String.slice(current_line, 0, character) |> String.reverse()
    after_cursor = String.slice(current_line, character..-1)

    word_before = Regex.run(~r/^[A-Za-z0-9_!?]+/, before) |> List.first("") |> String.reverse()
    word_after = Regex.run(~r/^[A-Za-z0-9_!?]+/, after_cursor) |> List.first("")
    case word_before <> word_after do
      "" -> nil
      w -> w
    end
  end

  defp find_occurrence_edits(text, old, new_name) do
    re = ~r/(^|[^A-Za-z0-9_!?])(#{Regex.escape(old)})(?![A-Za-z0-9_!?])/u

    text
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, ln} ->
      # scan returns list of capture indexes; default to :index
      case Regex.scan(re, line, return: :index) do
        [] -> []
        matches ->
          Enum.map(matches, fn
            [{_pre_pos, _pre_len}, {name_pos, name_len}] ->
              %{
                "range" => %{
                  "start" => %{"line" => ln, "character" => name_pos},
                  "end" => %{"line" => ln, "character" => name_pos + name_len}
                },
                "newText" => new_name
              }
            # safety fallback, shouldn't occur with the regex above
            [{name_pos, name_len}] ->
              %{
                "range" => %{
                  "start" => %{"line" => ln, "character" => name_pos},
                  "end" => %{"line" => ln, "character" => name_pos + name_len}
                },
                "newText" => new_name
              }
          end)
      end
    end)
  end

  defp error_response(id, message, code \\ -32603) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => to_string(message)}
    }
  end
end
