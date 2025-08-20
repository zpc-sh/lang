defmodule Lang.TextIntelligence.AnalysisEngine do
  @moduledoc """
  Core engine for analyzing any structured text format
  """

  alias Lang.TextIntelligence.ParserRegistry
  require Logger

  def analyze_content(content, format, options \\ %{}) do
    Logger.info("Analyzing content", format: format, size: byte_size(content))

    with {:ok, parser_config} <- ParserRegistry.get_parser(format),
         {:ok, parsed_content} <- parse_content(content, parser_config),
         {:ok, analysis} <- perform_analysis(parsed_content, format, options) do
      {:ok,
       %{
         format: format,
         parser_used: parser_config.parser,
         content_size: byte_size(content),
         analysis: analysis,
         completions: generate_completions(analysis, options),
         diagnostics: generate_diagnostics(analysis, options),
         timestamp: DateTime.utc_now()
       }}
    end
  end

  def batch_analyze(contents, options \\ %{}) do
    Logger.info("Batch analyzing #{length(contents)} items")

    results =
      contents
      |> Task.async_stream(
        fn {content, format} ->
          analyze_content(content, format, options)
        end,
        timeout: :infinity,
        max_concurrency: System.schedulers_online() * 2
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:analysis_failed, reason}}
      end)

    {:ok, results}
  end

  defp parse_content(content, %{parser: :composite, components: components}) do
    # For composite parsers, run all components
    results =
      Enum.map(components, fn component ->
        case component do
          :conversation_parser -> parse_conversation(content)
          :sentiment_analyzer -> analyze_sentiment(content)
          :intent_classifier -> classify_intent(content)
          _ -> {:ok, %{type: component, result: "not_implemented"}}
        end
      end)

    {:ok,
     %{
       type: :composite,
       content: content,
       components: results,
       tokens: String.split(content)
     }}
  end

  defp parse_content(content, %{parser: parser}) when is_atom(parser) do
    case parser do
      :builtin_markdown -> parse_markdown(content)
      :builtin_javascript -> parse_javascript(content)
      :builtin_python -> parse_python(content)
      :builtin_elixir -> parse_elixir(content)
      :builtin_json -> parse_json(content)
      :builtin_yaml -> parse_yaml(content)
      :builtin_text -> parse_text(content)
      :builtin_sql -> parse_sql(content)
      :builtin_email -> parse_email(content)
      :builtin_log -> parse_log(content)
      _ -> {:ok, %{type: parser, content: content, tokens: String.split(content)}}
    end
  end

  defp parse_markdown(content) do
    lines = String.split(content, "\n")
    headers = Enum.filter(lines, &String.starts_with?(&1, "#"))

    # Extract links, code blocks, lists
    links = Regex.scan(~r/\[([^\]]+)\]\(([^)]+)\)/, content)
    code_blocks = Regex.scan(~r/```(\w+)?\n(.*?)```/s, content)
    lists = Enum.filter(lines, &(String.starts_with?(&1, "- ") or String.starts_with?(&1, "* ")))

    {:ok,
     %{
       type: :markdown,
       content: content,
       lines: lines,
       headers: headers,
       links: links,
       code_blocks: code_blocks,
       lists: lists,
       word_count: content |> String.split() |> length()
     }}
  end

  defp parse_javascript(content) do
    functions = Regex.scan(~r/function\s+(\w+)/, content)
    arrow_functions = Regex.scan(~r/const\s+(\w+)\s*=\s*\([^)]*\)\s*=>/, content)
    classes = Regex.scan(~r/class\s+(\w+)/, content)
    imports = Regex.scan(~r/import\s+.*\s+from\s+['"]([^'"]+)['"]/, content)

    {:ok,
     %{
       type: :javascript,
       content: content,
       lines: String.split(content, "\n"),
       functions: functions,
       arrow_functions: arrow_functions,
       classes: classes,
       imports: imports,
       estimated_complexity: calculate_js_complexity(content)
     }}
  end

  defp parse_python(content) do
    functions = Regex.scan(~r/def\s+(\w+)/, content)
    classes = Regex.scan(~r/class\s+(\w+)/, content)
    imports = Regex.scan(~r/(?:import|from)\s+(\w+(?:\.\w+)*)/, content)

    {:ok,
     %{
       type: :python,
       content: content,
       lines: String.split(content, "\n"),
       functions: functions,
       classes: classes,
       imports: imports,
       estimated_complexity: calculate_py_complexity(content)
     }}
  end

  defp parse_elixir(content) do
    modules = Regex.scan(~r/defmodule\s+([\w.]+)/, content)
    functions = Regex.scan(~r/def\s+(\w+)/, content)
    private_functions = Regex.scan(~r/defp\s+(\w+)/, content)

    {:ok,
     %{
       type: :elixir,
       content: content,
       lines: String.split(content, "\n"),
       modules: modules,
       functions: functions,
       private_functions: private_functions,
       estimated_complexity: calculate_ex_complexity(content)
     }}
  end

  defp parse_json(content) do
    case Jason.decode(content) do
      {:ok, parsed} ->
        {:ok,
         %{
           type: :json,
           content: content,
           parsed: parsed,
           depth: calculate_json_depth(parsed),
           key_count: count_json_keys(parsed)
         }}

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  defp parse_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, parsed} ->
        {:ok,
         %{
           type: :yaml,
           content: content,
           parsed: parsed,
           structure: analyze_yaml_structure(parsed)
         }}

      {:error, reason} ->
        {:error, {:invalid_yaml, reason}}
    end
  end

  defp parse_text(content) do
    lines = String.split(content, "\n")
    paragraphs = String.split(content, ~r/\n\s*\n/) |> Enum.reject(&(&1 == ""))
    sentences = String.split(content, ~r/[.!?]+/) |> Enum.reject(&(&1 == ""))
    words = String.split(content) |> length()

    {:ok,
     %{
       type: :text,
       content: content,
       lines: lines,
       paragraphs: paragraphs,
       sentences: sentences,
       word_count: words,
       character_count: String.length(content),
       readability: estimate_readability(sentences, words)
     }}
  end

  defp parse_sql(content) do
    select_statements = Regex.scan(~r/SELECT\s+.*?\s+FROM/i, content)
    tables = Regex.scan(~r/FROM\s+(\w+)/i, content)
    joins = Regex.scan(~r/(INNER|LEFT|RIGHT|FULL)\s+JOIN/i, content)

    {:ok,
     %{
       type: :sql,
       content: content,
       select_statements: select_statements,
       tables: tables,
       joins: joins,
       estimated_complexity: calculate_sql_complexity(content)
     }}
  end

  defp parse_email(content) do
    headers = Regex.scan(~r/^([A-Za-z-]+):\s*(.+)$/m, content)
    body_start = String.split(content, "\n\n", parts: 2) |> List.last()

    {:ok,
     %{
       type: :email,
       content: content,
       headers: headers,
       body: body_start,
       estimated_sentiment: analyze_email_sentiment(body_start)
     }}
  end

  defp parse_log(content) do
    lines = String.split(content, "\n")
    log_entries = Enum.map(lines, &parse_log_line/1)
    log_levels = log_entries |> Enum.map(& &1.level) |> Enum.frequencies()

    {:ok,
     %{
       type: :log,
       content: content,
       entries: log_entries,
       level_distribution: log_levels,
       total_entries: length(log_entries)
     }}
  end

  defp parse_conversation(content) do
    # Simple conversation parsing - in production this would be more sophisticated
    turns =
      String.split(content, "\n")
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.with_index()
      |> Enum.map(fn {line, index} ->
        %{turn: index + 1, content: String.trim(line)}
      end)

    {:ok, %{conversation_turns: turns, total_turns: length(turns)}}
  end

  defp analyze_sentiment(content) do
    # Simple sentiment analysis - in production use ML models
    positive_words = ~w[good great excellent amazing wonderful fantastic happy joy love]
    negative_words = ~w[bad terrible awful horrible sad angry hate disappointing]

    words = content |> String.downcase() |> String.split()
    positive_count = Enum.count(words, &(&1 in positive_words))
    negative_count = Enum.count(words, &(&1 in negative_words))

    sentiment =
      cond do
        positive_count > negative_count -> :positive
        negative_count > positive_count -> :negative
        true -> :neutral
      end

    {:ok, %{sentiment: sentiment, positive_score: positive_count, negative_score: negative_count}}
  end

  defp classify_intent(content) do
    # Simple intent classification
    content_lower = String.downcase(content)

    intent =
      cond do
        String.contains?(content_lower, ["help", "support", "assistance"]) -> :help_request
        String.contains?(content_lower, ["buy", "purchase", "order"]) -> :purchase_intent
        String.contains?(content_lower, ["complain", "problem", "issue"]) -> :complaint
        String.contains?(content_lower, ["thank", "appreciate", "grateful"]) -> :appreciation
        true -> :general
      end

    {:ok, %{intent: intent}}
  end

  defp perform_analysis(parsed_content, format, _options) do
    analysis = %{
      complexity_score: calculate_complexity(parsed_content),
      readability_score: calculate_readability(parsed_content),
      structure_quality: assess_structure(parsed_content, format),
      suggestions: generate_suggestions(parsed_content, format),
      metrics: extract_metrics(parsed_content, format)
    }

    {:ok, analysis}
  end

  defp calculate_complexity(%{word_count: word_count}) when word_count > 0 do
    # Simple complexity calculation based on word count
    min(word_count / 100, 10.0)
  end

  defp calculate_complexity(%{estimated_complexity: complexity}), do: complexity
  defp calculate_complexity(_), do: 1.0

  defp calculate_readability(%{word_count: word_count}) when word_count > 0 do
    # Simple readability score (higher is better)
    max(10.0 - word_count / 200, 1.0)
  end

  defp calculate_readability(%{readability: readability}), do: readability
  defp calculate_readability(_), do: 5.0

  defp assess_structure(%{headers: headers}, "markdown") when length(headers) > 0 do
    # Good structure with headers
    8.0
  end

  defp assess_structure(%{functions: functions, classes: classes}, format)
       when format in ["javascript", "python", "elixir"] do
    # Good structure if has both functions and classes
    if length(functions) > 0 and length(classes) > 0, do: 9.0, else: 6.0
  end

  defp assess_structure(_, _), do: 5.0

  defp generate_suggestions(%{headers: []}, "markdown") do
    ["Consider adding headers to improve document structure"]
  end

  defp generate_suggestions(%{word_count: wc}, _) when wc > 1000 do
    ["Consider breaking this into smaller sections"]
  end

  defp generate_suggestions(%{functions: functions}, format)
       when format in ["javascript", "python", "elixir"] and length(functions) > 20 do
    ["Consider refactoring - this file has many functions and might benefit from being split"]
  end

  defp generate_suggestions(_, _), do: []

  defp extract_metrics(parsed_content, format) do
    base_metrics = %{
      content_type: format,
      analysis_timestamp: DateTime.utc_now()
    }

    case parsed_content do
      %{word_count: wc} -> Map.put(base_metrics, :word_count, wc)
      %{lines: lines} -> Map.put(base_metrics, :line_count, length(lines))
      _ -> base_metrics
    end
  end

  defp generate_completions(analysis, _options) do
    base_completions = [
      %{
        label: "Improve readability",
        detail: "Based on readability analysis (score: #{analysis.readability_score})",
        insert_text: "Consider simplifying complex sentences",
        kind: :suggestion
      }
    ]

    suggestion_completions =
      Enum.map(analysis.suggestions, fn suggestion ->
        %{
          label: "Apply suggestion",
          detail: suggestion,
          insert_text: suggestion,
          kind: :suggestion
        }
      end)

    base_completions ++ suggestion_completions
  end

  defp generate_diagnostics(analysis, _options) do
    diagnostics = []

    diagnostics =
      if analysis.complexity_score > 8.0 do
        [
          %{
            severity: :warning,
            message: "Content complexity is very high (#{analysis.complexity_score})",
            range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 0}}
          }
          | diagnostics
        ]
      else
        diagnostics
      end

    diagnostics =
      if analysis.readability_score < 3.0 do
        [
          %{
            severity: :info,
            message:
              "Content readability could be improved (score: #{analysis.readability_score})",
            range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 0}}
          }
          | diagnostics
        ]
      else
        diagnostics
      end

    diagnostics
  end

  # Helper functions for complexity calculation
  defp calculate_js_complexity(content) do
    cyclomatic = 1 + (Regex.scan(~r/if|for|while|switch|catch|\?/, content) |> length())
    min(cyclomatic / 10, 10.0)
  end

  defp calculate_py_complexity(content) do
    cyclomatic = 1 + (Regex.scan(~r/if|for|while|try|except|with/, content) |> length())
    min(cyclomatic / 10, 10.0)
  end

  defp calculate_ex_complexity(content) do
    cyclomatic = 1 + (Regex.scan(~r/if|case|cond|with|try/, content) |> length())
    min(cyclomatic / 10, 10.0)
  end

  defp calculate_sql_complexity(content) do
    joins = Regex.scan(~r/JOIN/i, content) |> length()
    subqueries = Regex.scan(~r/\(SELECT/i, content) |> length()
    (joins + subqueries * 2) / 5
  end

  defp calculate_json_depth(data, current_depth \\ 0) do
    case data do
      map when is_map(map) ->
        if map_size(map) == 0 do
          current_depth
        else
          map
          |> Map.values()
          |> Enum.map(&calculate_json_depth(&1, current_depth + 1))
          |> Enum.max()
        end

      list when is_list(list) ->
        if list == [] do
          current_depth
        else
          list |> Enum.map(&calculate_json_depth(&1, current_depth + 1)) |> Enum.max()
        end

      _ ->
        current_depth
    end
  end

  defp count_json_keys(data) do
    case data do
      map when is_map(map) ->
        map_size(map) + (map |> Map.values() |> Enum.map(&count_json_keys/1) |> Enum.sum())

      list when is_list(list) ->
        list |> Enum.map(&count_json_keys/1) |> Enum.sum()

      _ ->
        0
    end
  end

  defp analyze_yaml_structure(data) do
    %{
      type: get_data_type(data),
      # Same logic works for YAML
      depth: calculate_json_depth(data),
      complexity: calculate_yaml_complexity(data)
    }
  end

  defp calculate_yaml_complexity(data) do
    case data do
      map when is_map(map) ->
        map_size(map) +
          (map |> Map.values() |> Enum.map(&calculate_yaml_complexity/1) |> Enum.sum())

      list when is_list(list) ->
        length(list) + (list |> Enum.map(&calculate_yaml_complexity/1) |> Enum.sum())

      _ ->
        1
    end
  end

  defp get_data_type(data) when is_map(data), do: :map
  defp get_data_type(data) when is_list(data), do: :list
  defp get_data_type(data) when is_binary(data), do: :string
  defp get_data_type(data) when is_number(data), do: :number
  defp get_data_type(data) when is_boolean(data), do: :boolean
  defp get_data_type(_), do: :unknown

  defp estimate_readability(sentences, word_count) do
    if word_count == 0 or length(sentences) == 0 do
      5.0
    else
      avg_words_per_sentence = word_count / length(sentences)
      # Simple readability: shorter sentences = better readability
      max(10.0 - avg_words_per_sentence / 5, 1.0)
    end
  end

  defp analyze_email_sentiment(body) when is_binary(body) do
    {:ok, result} = analyze_sentiment(body)
    result.sentiment
  end

  defp analyze_email_sentiment(_), do: :neutral

  defp parse_log_line(line) do
    # Simple log parsing - matches common formats like "TIMESTAMP LEVEL MESSAGE"
    case Regex.run(~r/(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}[.\d]*[Z]?)\s+(\w+)\s+(.+)/, line) do
      [_, timestamp, level, message] ->
        %{timestamp: timestamp, level: String.upcase(level), message: String.trim(message)}

      _ ->
        %{timestamp: nil, level: "UNKNOWN", message: line}
    end
  end
end
