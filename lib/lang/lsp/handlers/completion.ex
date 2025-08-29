defmodule Lang.LSP.Handlers.Completion do
  @moduledoc """
  Handles textDocument/completion requests with AI-powered suggestions.

  Provides intelligent code completions by:
  - Analyzing context around the cursor
  - Routing to appropriate AI providers
  - Formatting results as LSP CompletionItems
  - Caching frequent completions
  """

  require Logger
  alias Lang.Providers.Router
  alias Lang.TextIntelligence.{ContextAnalyzer, ParserRegistry}

  @type position :: %{String.t() => integer()}
  @type completion_context :: %{
          trigger_kind: integer(),
          trigger_character: String.t() | nil
        }

  @doc """
  Handle completion request from LSP client.
  """
  @spec handle(String.t(), String.t(), position(), completion_context(), map()) ::
          {:ok, list(map())} | {:error, term()}
  def handle(uri, text, position, context, opts \\ %{}) do
    with {:ok, analysis_context} <- analyze_context(text, position),
         {:ok, completions} <- get_completions(analysis_context, opts),
         {:ok, formatted} <- format_completions(completions, analysis_context) do
      {:ok, formatted}
    else
      {:error, reason} = error ->
        Logger.error("Completion failed: #{inspect(reason)}")
        error
    end
  end

  # Analyze the context around the cursor position
  defp analyze_context(text, %{"line" => line, "character" => character}) do
    lines = String.split(text, "\n")
    current_line = Enum.at(lines, line, "")

    # Get text before and after cursor
    prefix = String.slice(current_line, 0, character)
    suffix = String.slice(current_line, character..-1)

    # Extract relevant context
    context = %{
      # Current line info
      line: current_line,
      line_number: line,
      character: character,
      prefix: prefix,
      suffix: suffix,

      # Surrounding context
      previous_lines: get_previous_lines(lines, line, 5),
      next_lines: get_next_lines(lines, line, 2),

      # Token analysis
      last_token: extract_last_token(prefix),
      in_string?: in_string?(prefix),
      in_comment?: in_comment?(prefix),

      # Language detection
      language: detect_language_from_content(lines),

      # Completion type detection
      completion_type: detect_completion_type(prefix, suffix)
    }

    {:ok, context}
  rescue
    e ->
      {:error, {:context_analysis_failed, e}}
  end

  # Get completions from AI providers
  defp get_completions(context, opts) do
    # Build prompt for AI
    prompt = build_completion_prompt(context)

    # Determine which provider to use
    provider = opts[:provider] || select_provider(context)

    # Request completions
    case Router.route_request(provider, :completion, %{
           prompt: prompt,
           max_tokens: opts[:max_tokens] || 150,
           temperature: opts[:temperature] || 0.3,
           stop_sequences: get_stop_sequences(context),
           n: opts[:num_completions] || 5
         }) do
      {:ok, %{completions: completions}} when is_list(completions) and completions != [] ->
        {:ok, completions}

      {:ok, %{choices: choices}} when is_list(choices) and choices != [] ->
        completions = Enum.map(choices, &(&1["text"] || &1["content"]))
        {:ok, completions}

      other ->
        # Fallback to local, AST-driven identifiers if provider empty/error
        Logger.debug("AI completion fallback: #{inspect(other)}")
        {:ok, local_completions(context)}
    end
  end

  # Local, fast fallback completions based on parsed identifiers and context
  defp local_completions(%{language: lang, last_token: last, completion_type: ctype} = ctx) do
    content = Enum.join(ctx.previous_lines, "\n") <> "\n" <> ctx.line <> "\n" <> Enum.join(ctx.next_lines, "\n")

    ids =
      case ParserRegistry.parse(content, lang) do
        {:ok, %{"functions" => funs}} when is_list(funs) ->
          Enum.map(funs, fn
            %{"name" => n} -> n
            %{name: n} -> n
            n when is_binary(n) -> n
            _ -> nil
          end)
        {:ok, %{:functions => funs}} when is_list(funs) -> Enum.map(funs, &to_string/1)
        {:ok, parsed} when is_map(parsed) -> Map.values(parsed) |> List.flatten() |> Enum.map(&to_string/1)
        _ -> []
      end
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    base =
      case ctype do
        :function_name -> ids
        :member_access -> ids
        :import -> ids
        _ -> ids
      end

    # Filter by current token prefix if present
    prefix = last || ""
    filtered =
      if prefix == "" do
        base
      else
        Enum.filter(base, &String.starts_with?(&1, prefix))
      end

    # Return as short strings; formatter will shape into LSP items
    Enum.take(filtered, 20)
  end

  # Format completions as LSP CompletionItems
  defp format_completions(completions, context) do
    items =
      completions
      |> Enum.with_index()
      |> Enum.map(fn {completion, index} ->
        format_completion_item(completion, index, context)
      end)
      |> Enum.filter(&(&1 != nil))

    {:ok, items}
  end

  defp format_completion_item(completion, index, context) do
    # Clean up the completion text
    text = clean_completion_text(completion, context)

    # Skip if empty or duplicate
    if text == "" or text == context.prefix do
      nil
    else
      %{
        "label" => create_label(text, context),
        "kind" => determine_completion_kind(text, context),
        "detail" => create_detail(text, context),
        "documentation" => create_documentation(text, context),
        "sortText" => String.pad_leading(to_string(index), 3, "0"),
        "filterText" => extract_filter_text(text, context),
        "insertText" => text,
        # PlainText
        "insertTextFormat" => 1,
        "additionalTextEdits" => []
      }
    end
  end

  # Build a prompt for the AI model
  defp build_completion_prompt(context) do
    """
    Complete the following #{context.language} code at the cursor position (|):

    ```#{context.language}
    #{Enum.join(context.previous_lines, "\n")}
    #{context.prefix}|#{context.suffix}
    #{Enum.join(context.next_lines, "\n")}
    ```

    Context:
    - Completion type: #{context.completion_type}
    - Last token: #{context.last_token}

    Provide concise, contextually appropriate completions that:
    1. Follow the existing code style
    2. Are syntactically correct
    3. Make semantic sense in the context
    4. Complete the current expression or statement

    Return only the text to insert at the cursor position.
    """
  end

  # Utility functions

  defp get_previous_lines(lines, current_index, count) do
    start_index = max(0, current_index - count)

    lines
    |> Enum.slice(start_index, current_index - start_index)
    |> Enum.take(-count)
  end

  defp get_next_lines(lines, current_index, count) do
    lines
    |> Enum.slice((current_index + 1)..-1)
    |> Enum.take(count)
  end

  defp extract_last_token(prefix) do
    case Regex.run(~r/[\w\.\:]+$/, prefix) do
      [token] -> token
      _ -> ""
    end
  end

  defp in_string?(text) do
    # Simplified string detection
    quotes =
      Regex.scan(~r/(?<!\\)["']/, text)
      |> List.flatten()
      |> length()

    rem(quotes, 2) == 1
  end

  defp in_comment?(text) do
    # Check for common comment patterns
    String.contains?(text, ["//", "#", "--"]) or
      Regex.match?(~r/\/\*(?!.*\*\/)/, text)
  end

  defp detect_language_from_content(lines) do
    cond do
      Enum.any?(lines, &String.contains?(&1, "defmodule")) -> "elixir"
      Enum.any?(lines, &String.contains?(&1, "function")) -> "javascript"
      Enum.any?(lines, &String.contains?(&1, "def ")) -> "python"
      Enum.any?(lines, &String.contains?(&1, "fn ")) -> "rust"
      true -> "text"
    end
  end

  defp detect_completion_type(prefix, _suffix) do
    cond do
      Regex.match?(~r/\.$/, prefix) -> :member_access
      Regex.match?(~r/\($/, prefix) -> :function_argument
      Regex.match?(~r/def\s+\w*$/, prefix) -> :function_name
      Regex.match?(~r/class\s+\w*$/, prefix) -> :class_name
      Regex.match?(~r/import\s+/, prefix) -> :import
      Regex.match?(~r/@\w*$/, prefix) -> :decorator
      true -> :general
    end
  end

  defp select_provider(context) do
    case context.completion_type do
      # Good for package names
      :import -> :openai
      # Good for API knowledge
      :member_access -> :anthropic
      # Default to Grok
      _ -> :xai
    end
  end

  defp get_stop_sequences(context) do
    base_stops = ["\n\n", "```"]

    case context.language do
      "elixir" -> base_stops ++ ["\nend", "\ndefmodule", "\ndef ", "\ndefp "]
      "python" -> base_stops ++ ["\ndef ", "\nclass ", "\n\n"]
      "javascript" -> base_stops ++ ["\nfunction", "\nclass", "\nconst ", "\nlet "]
      _ -> base_stops
    end
  end

  defp clean_completion_text(text, context) do
    text
    |> String.trim()
    |> remove_prefix_overlap(context.prefix)
    |> remove_markdown_artifacts()
    |> limit_to_single_statement(context)
  end

  defp remove_prefix_overlap(text, prefix) do
    # Remove any overlap with existing prefix
    prefix_words =
      String.split(prefix, ~r/\s+/)
      |> List.last()

    if prefix_words && String.starts_with?(text, prefix_words) do
      String.slice(text, String.length(prefix_words)..-1)
    else
      text
    end
  end

  defp remove_markdown_artifacts(text) do
    text
    |> String.replace(~r/```\w*\n?/, "")
    |> String.replace(~r/^```/, "")
  end

  defp limit_to_single_statement(text, context) do
    # Limit completion to single statement/expression
    case context.language do
      "elixir" ->
        text |> String.split("\n") |> List.first() |> String.trim_trailing(",")

      _ ->
        text |> String.split(~r/[;\n]/) |> List.first() |> String.trim()
    end
  end

  defp create_label(text, _context) do
    # Truncate long completions for the label
    if String.length(text) > 50 do
      String.slice(text, 0..47) <> "..."
    else
      text
    end
  end

  defp determine_completion_kind(text, context) do
    # LSP CompletionItemKind values
    cond do
      # Function
      context.completion_type == :function_name -> 3
      # Class
      context.completion_type == :class_name -> 7
      # Function
      String.contains?(text, "(") -> 3
      # Variable
      String.contains?(text, "=") -> 6
      # Module
      context.completion_type == :import -> 9
      # Text
      true -> 1
    end
  end

  defp create_detail(text, context) do
    "AI suggestion (#{context.completion_type})"
  end

  defp create_documentation(_text, context) do
    %{
      "kind" => "markdown",
      "value" => """
      **AI-generated completion**

      Type: `#{context.completion_type}`
      Language: `#{context.language}`

      This completion was generated based on the surrounding context.
      """
    }
  end

  defp extract_filter_text(text, _context) do
    # Extract the main identifier for filtering
    case Regex.run(~r/^\w+/, text) do
      [filter] -> filter
      _ -> text
    end
  end
end
