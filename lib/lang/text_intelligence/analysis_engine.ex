defmodule Lang.TextIntelligence.AnalysisEngine do
  @moduledoc """
  Core text analysis engine for LANG system.

  Provides intelligent text analysis capabilities including:
  - Content complexity analysis
  - Diagnostic detection (errors, warnings, hints)
  - Code quality metrics
  - Semantic understanding
  - Performance suggestions
  """

  require Logger
  alias Lang.Native.PerfEngine
  alias Lang.TextIntelligence.{FormatDetector, SymbolAnalyzer}

  @type analysis_result :: %{
          complexity: String.t(),
          diagnostics: [diagnostic()],
          suggestions: [suggestion()],
          metadata: map(),
          metrics: map()
        }

  @type diagnostic :: %{
          range: range(),
          severity: 1..4,
          message: String.t(),
          source: String.t(),
          code: String.t() | nil
        }

  @type suggestion :: %{
          type: String.t(),
          message: String.t(),
          range: range() | nil,
          priority: :low | :medium | :high
        }

  @type range :: %{
          start: position(),
          end: position()
        }

  @type position :: %{
          line: non_neg_integer(),
          character: non_neg_integer()
        }

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Analyze content with automatic format detection.
  """
  def analyze_content(content, format \\ nil) when is_binary(content) do
    detected_format = format || FormatDetector.detect(content)

    Logger.debug("Analyzing content",
      format: detected_format,
      content_length: String.length(content)
    )

    try do
      analysis = perform_analysis(content, detected_format)
      {:ok, analysis}
    rescue
      error ->
        Logger.error("Analysis failed", error: inspect(error))
        {:error, "Analysis failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Analyze multiple documents in batch.
  """
  def analyze_batch(documents, opts \\ []) when is_list(documents) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 10)
    timeout = Keyword.get(opts, :timeout, 30_000)

    documents
    |> Task.async_stream(
      fn {uri, content} ->
        format = FormatDetector.detect_from_uri(uri)
        result = analyze_content(content, format)
        {uri, result}
      end,
      max_concurrency: max_concurrency,
      timeout: timeout
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  @doc """
  Stream analysis for large documents.
  """
  def analyze_stream(content, format, callback) when is_function(callback, 1) do
    stream_id = "analysis_#{:erlang.unique_integer([:positive])}"

    Task.start_link(fn ->
      try do
        # Split into chunks for streaming analysis
        chunks = split_into_chunks(content, 1000)
        total_chunks = length(chunks)

        callback.({:started, %{stream_id: stream_id, total_chunks: total_chunks}})

        results =
          chunks
          |> Enum.with_index()
          |> Enum.map(fn {chunk, index} ->
            result = perform_analysis(chunk, format)

            callback.(
              {:progress,
               %{
                 stream_id: stream_id,
                 chunk_index: index,
                 progress: (index + 1) / total_chunks,
                 partial_result: result
               }}
            )

            result
          end)

        final_result = merge_analysis_results(results)
        callback.({:completed, %{stream_id: stream_id, result: final_result}})
      rescue
        error ->
          callback.({:error, %{stream_id: stream_id, error: Exception.message(error)}})
      end
    end)

    {:ok, stream_id}
  end

  # =============================================================================
  # Analysis Implementation
  # =============================================================================

  defp perform_analysis(content, format) do
    base_analysis = %{
      complexity: "unknown",
      diagnostics: [],
      suggestions: [],
      metadata: %{
        format: format,
        analyzed_at: DateTime.utc_now(),
        content_length: String.length(content),
        line_count: count_lines(content)
      },
      metrics: %{}
    }

    content
    |> analyze_complexity(format)
    |> analyze_diagnostics(format)
    |> analyze_quality(format)
    |> analyze_performance(format)
    |> Map.merge(base_analysis)
  end

  defp analyze_complexity(content, format) do
    complexity =
      cond do
        String.length(content) < 100 -> "simple"
        String.length(content) < 1000 -> "moderate"
        String.length(content) < 5000 -> "complex"
        true -> "very_complex"
      end

    # Use native performance engine if available
    case Lang.Native.PerfEngine.analyze_complexity(content, format) do
      {:ok, native_complexity} ->
        %{complexity: native_complexity}

      {:error, _} ->
        %{complexity: complexity}
    end
  end

  defp analyze_diagnostics(analysis, format) do
    diagnostics = []

    # Basic syntax checking
    syntax_diagnostics = check_syntax(analysis, format)

    # Style issues
    style_diagnostics = check_style(analysis, format)

    # Security issues
    security_diagnostics = check_security(analysis, format)

    all_diagnostics = syntax_diagnostics ++ style_diagnostics ++ security_diagnostics

    Map.put(analysis, :diagnostics, all_diagnostics)
  end

  defp analyze_quality(analysis, format) do
    suggestions = []

    # Code quality suggestions
    quality_suggestions = suggest_quality_improvements(analysis, format)

    # Performance suggestions
    perf_suggestions = suggest_performance_improvements(analysis, format)

    all_suggestions = quality_suggestions ++ perf_suggestions

    Map.put(analysis, :suggestions, all_suggestions)
  end

  defp analyze_performance(analysis, format) do
    metrics = %{
      cyclomatic_complexity: calculate_cyclomatic_complexity(analysis),
      maintainability_index: calculate_maintainability_index(analysis),
      technical_debt_ratio: calculate_technical_debt(analysis)
    }

    Map.put(analysis, :metrics, metrics)
  end

  # =============================================================================
  # Diagnostic Checkers
  # =============================================================================

  defp check_syntax(analysis, format) do
    content = Map.get(analysis, :content, "")

    case format do
      "elixir" -> check_elixir_syntax(content)
      "javascript" -> check_javascript_syntax(content)
      "python" -> check_python_syntax(content)
      "markdown" -> check_markdown_syntax(content)
      _ -> []
    end
  end

  defp check_elixir_syntax(content) do
    # Basic Elixir syntax checking
    issues = []

    issues =
      if String.contains?(content, "do\nend"),
        do: [
          create_diagnostic(
            0,
            0,
            :warning,
            "Consider using do: syntax for single expressions",
            "style"
          )
        ],
        else: issues

    issues =
      if Regex.match?(~r/\bIO\.puts\b/, content),
        do: [
          create_diagnostic(
            0,
            0,
            :info,
            "Consider using Logger instead of IO.puts",
            "best_practice"
          )
          | issues
        ],
        else: issues

    issues
  end

  defp check_javascript_syntax(content) do
    issues = []

    issues =
      if String.contains?(content, "var "),
        do: [
          create_diagnostic(
            0,
            0,
            :warning,
            "Consider using 'let' or 'const' instead of 'var'",
            "modern_js"
          )
        ],
        else: issues

    issues =
      if String.contains?(content, "=="),
        do: [
          create_diagnostic(0, 0, :info, "Consider using strict equality (===)", "best_practice")
          | issues
        ],
        else: issues

    issues
  end

  defp check_python_syntax(content) do
    issues = []

    issues =
      if Regex.match?(~r/^\s*print\s*\(/m, content),
        do: [
          create_diagnostic(
            0,
            0,
            :info,
            "Consider using logging instead of print statements",
            "best_practice"
          )
        ],
        else: issues

    issues
  end

  defp check_markdown_syntax(content) do
    issues = []

    # Check for missing alt text in images
    if Regex.match?(~r/!\[\]\([^)]+\)/, content) do
      issues = [
        create_diagnostic(
          0,
          0,
          :warning,
          "Image missing alt text for accessibility",
          "accessibility"
        )
        | issues
      ]
    end

    issues
  end

  defp check_style(analysis, _format) do
    # Generic style checks
    []
  end

  defp check_security(analysis, format) do
    content = Map.get(analysis, :content, "")

    security_patterns = [
      {~r/password\s*=\s*['"]/i, "Hardcoded password detected"},
      {~r/api[_-]?key\s*=\s*['"]/i, "Hardcoded API key detected"},
      {~r/secret\s*=\s*['"]/i, "Hardcoded secret detected"},
      {~r/eval\s*\(/i, "Use of eval() detected - security risk"}
    ]

    Enum.reduce(security_patterns, [], fn {pattern, message}, acc ->
      if Regex.match?(pattern, content) do
        [create_diagnostic(0, 0, :error, message, "security") | acc]
      else
        acc
      end
    end)
  end

  # =============================================================================
  # Suggestion Generators
  # =============================================================================

  defp suggest_quality_improvements(analysis, format) do
    suggestions = []

    # Add format-specific suggestions
    case format do
      "elixir" -> suggest_elixir_improvements(analysis)
      "javascript" -> suggest_javascript_improvements(analysis)
      _ -> suggestions
    end
  end

  defp suggest_elixir_improvements(_analysis) do
    [
      %{
        type: "refactor",
        message: "Consider breaking large functions into smaller ones",
        range: nil,
        priority: :medium
      }
    ]
  end

  defp suggest_javascript_improvements(_analysis) do
    [
      %{
        type: "modernize",
        message: "Consider using modern ES6+ features",
        range: nil,
        priority: :low
      }
    ]
  end

  defp suggest_performance_improvements(_analysis, _format) do
    [
      %{
        type: "performance",
        message: "Consider caching expensive operations",
        range: nil,
        priority: :medium
      }
    ]
  end

  # =============================================================================
  # Metrics Calculators
  # =============================================================================

  defp calculate_cyclomatic_complexity(analysis) do
    content = Map.get(analysis, :content, "")

    # Simple approximation - count decision points
    decision_keywords = ["if", "else", "elif", "case", "when", "while", "for", "&&", "||"]

    complexity =
      1 +
        Enum.reduce(decision_keywords, 0, fn keyword, acc ->
          acc + (content |> String.split(keyword) |> length()) - 1
        end)

    # Cap at reasonable maximum
    min(complexity, 50)
  end

  defp calculate_maintainability_index(analysis) do
    # Simplified maintainability index
    content_length = Map.get(analysis[:metadata], :content_length, 0)
    complexity = calculate_cyclomatic_complexity(analysis)

    # Higher score = more maintainable
    base_score = 100
    length_penalty = div(content_length, 100)
    complexity_penalty = complexity * 2

    max(0, base_score - length_penalty - complexity_penalty)
  end

  defp calculate_technical_debt(analysis) do
    # Simple heuristic: ratio of issues to content size
    diagnostics = Map.get(analysis, :diagnostics, [])
    content_length = Map.get(analysis[:metadata], :content_length, 1)

    issue_count = length(diagnostics)
    debt_ratio = issue_count / content_length * 1000

    Float.round(debt_ratio, 2)
  end

  # =============================================================================
  # Utilities
  # =============================================================================

  defp create_diagnostic(line, character, severity, message, source) do
    severity_code =
      case severity do
        :error -> 1
        :warning -> 2
        :info -> 3
        :hint -> 4
      end

    %{
      range: %{
        start: %{line: line, character: character},
        end: %{line: line, character: character + 10}
      },
      severity: severity_code,
      message: message,
      source: source,
      code: nil
    }
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end

  defp split_into_chunks(content, chunk_size) do
    content
    |> String.split("\n")
    |> Enum.chunk_every(chunk_size)
    |> Enum.map(&Enum.join(&1, "\n"))
  end

  defp merge_analysis_results(results) do
    # Merge multiple analysis results into one
    base_result = %{
      complexity: "unknown",
      diagnostics: [],
      suggestions: [],
      metadata: %{},
      metrics: %{}
    }

    Enum.reduce(results, base_result, fn result, acc ->
      %{
        complexity: determine_max_complexity(acc.complexity, result.complexity),
        diagnostics: acc.diagnostics ++ result.diagnostics,
        suggestions: acc.suggestions ++ result.suggestions,
        metadata: Map.merge(acc.metadata, result.metadata),
        metrics: merge_metrics(acc.metrics, result.metrics)
      }
    end)
  end

  defp determine_max_complexity("simple", other), do: other
  defp determine_max_complexity(this, "simple"), do: this

  defp determine_max_complexity("moderate", other) when other in ["complex", "very_complex"],
    do: other

  defp determine_max_complexity(this, "moderate") when this in ["complex", "very_complex"],
    do: this

  defp determine_max_complexity("complex", "very_complex"), do: "very_complex"
  defp determine_max_complexity("very_complex", _), do: "very_complex"
  defp determine_max_complexity(this, _), do: this

  defp merge_metrics(metrics1, metrics2) do
    Map.merge(metrics1, metrics2, fn _key, v1, v2 ->
      if is_number(v1) and is_number(v2) do
        (v1 + v2) / 2
      else
        v2
      end
    end)
  end
end
