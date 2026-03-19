defmodule Lang.Workspace.Snippets do
  @moduledoc """
  Helper module for extracting code snippets and context from files.
  Uses the native Rust NIFs for high-performance text processing.
  """

  @doc """
  Extracts a context snippet from a file centered on a specific line.

  ## Parameters

  - `file_path` - Path to the source file
  - `line` - The line number to center the context around (1-based)
  - `context_lines` - Number of lines before and after to include

  ## Returns

  - `{:ok, snippet}` - The extracted snippet with line numbers
  - `{:error, reason}` - Error information

  ## Example

      iex> Lang.Workspace.Snippets.extract_context("lib/my_app/user.ex", 42, 3)
      {:ok, "39: def validate_email(email) do\\n40:   # Validation logic\\n41:   if String.contains?(email, \"@\") do\\n42:     :ok\\n43:   else\\n44:     {:error, :invalid_email}\\n45:   end\\nend"}
  """
  def extract_context(file_path, line, context_lines \\ 3) do
    start_line = max(1, line - context_lines)
    end_line = line + context_lines

    case Lang.Native.FSScanner.read_lines(file_path, start_line, end_line) do
      {:ok, lines} ->
        formatted_lines =
          lines
          |> Enum.with_index(start_line)
          |> Enum.map(fn {content, line_num} ->
            highlight = if line_num == line, do: "→ ", else: "  "
            "#{highlight}#{line_num}: #{content}"
          end)
          |> Enum.join("\n")

        {:ok, formatted_lines}

      {:error, _error} ->
        # Fallback to Elixir implementation if NIF fails
        extract_context_elixir(file_path, line, context_lines)
    end
  end

  @doc """
  Extracts a semantic context snippet with additional metadata.

  ## Parameters

  - `file_path` - Path to the source file
  - `line` - The line number to center the context around (1-based)
  - `options` - Options for the semantic extraction
    - `:include_ast` - Whether to include AST (default: false)
    - `:include_symbols` - Whether to include symbols (default: true)
    - `:context_lines` - Number of lines before and after (default: 5)

  ## Returns

  - `{:ok, %{snippet: string, symbols: list, ast: map}}` - The extracted context
  - `{:error, reason}` - Error information
  """
  def extract_semantic_context(file_path, line, options \\ []) do
    include_ast = Keyword.get(options, :include_ast, false)
    include_symbols = Keyword.get(options, :include_symbols, true)
    context_lines = Keyword.get(options, :context_lines, 5)

    with {:ok, snippet} <- extract_context(file_path, line, context_lines),
         {:ok, symbols} <- extract_symbols(file_path, line, include_symbols),
         {:ok, ast} <- extract_ast(file_path, line, include_ast) do
      {:ok,
       %{
         snippet: snippet,
         symbols: symbols,
         ast: ast,
         file_path: file_path,
         line: line
       }}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Creates a snippet from a string with line numbers.

  ## Parameters

  - `content` - The string content
  - `start_line` - The starting line number (default: 1)
  - `highlight_line` - Optional line to highlight

  ## Returns

  - A formatted string with line numbers

  ## Example

      iex> content = "def hello\\n  IO.puts(\\"world\\")\\nend"
      iex> Lang.Workspace.Snippets.format_with_line_numbers(content, 10, 11)
      "10: def hello\\n→ 11:   IO.puts(\\"world\\")\\n12: end"
  """
  def format_with_line_numbers(content, start_line \\ 1, highlight_line \\ nil) do
    content
    |> String.split("\n")
    |> Enum.with_index(start_line)
    |> Enum.map(fn {line, num} ->
      prefix = if num == highlight_line, do: "→ ", else: "  "
      "#{prefix}#{num}: #{line}"
    end)
    |> Enum.join("\n")
  end

  # Private helpers

  defp extract_context_elixir(file_path, line, context_lines) do
    # Fallback implementation using Elixir's File module
    try do
      lines =
        File.stream!(file_path)
        |> Stream.with_index(1)
        |> Stream.filter(fn {_, line_num} ->
          line_num >= line - context_lines && line_num <= line + context_lines
        end)
        |> Enum.map(fn {content, line_num} ->
          highlight = if line_num == line, do: "→ ", else: "  "
          "#{highlight}#{line_num}: #{String.trim_trailing(content)}"
        end)
        |> Enum.join("\n")

      {:ok, lines}
    rescue
      e -> {:error, "Failed to read file: #{Exception.message(e)}"}
    end
  end

  defp extract_symbols(file_path, line, include_symbols) do
    if include_symbols do
      case Lang.Native.TreeParser.extract_symbols_near_line(file_path, line) do
        {:ok, symbols} -> {:ok, symbols}
        # Return empty list on error instead of failing
        {:error, _} -> {:ok, []}
      end
    else
      {:ok, []}
    end
  end

  defp extract_ast(file_path, line, include_ast) do
    if include_ast do
      case Lang.Native.TreeParser.extract_ast_at_line(file_path, line) do
        {:ok, ast} -> {:ok, ast}
        # Return nil on error instead of failing
        {:error, _} -> {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end
end
