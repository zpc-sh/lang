defmodule Lang.ML.CodeQualityPredictor do
  @moduledoc """
  ML-powered code quality prediction using trained models.

  This module provides intelligent assessment of code quality through:
  - Static analysis features extraction
  - Machine learning model prediction
  - Quality metrics calculation
  - Issue detection and suggestions

  Uses CPU-only ML implementations (scikit-learn compatible) for:
  - Maintainability prediction
  - Complexity assessment
  - Readability scoring
  - Testability evaluation
  """

  @type quality_metrics :: %{
    maintainability: float(),
    complexity: float(),
    readability: float(),
    testability: float()
  }

  @type quality_issue :: %{
    type: :warning | :suggestion | :info,
    message: String.t(),
    range: map(),
    confidence: float()
  }

  @type prediction_result :: %{
    overall_score: float(),
    metrics: quality_metrics(),
    issues: [quality_issue()]
  }

  @doc """
  Predict code quality for a given document.

  This is a stub implementation that provides basic heuristics.
  In production, this would use trained ML models.
  """
  @spec predict_quality(String.t(), map()) :: prediction_result()
  def predict_quality(code_content, _opts \\ %{}) do
    # Extract basic features from code
    features = extract_features(code_content)

    # Calculate quality metrics using simple heuristics (stub)
    metrics = %{
      maintainability: calculate_maintainability(features),
      complexity: calculate_complexity(features),
      readability: calculate_readability(features),
      testability: calculate_testability(features)
    }

    # Calculate overall score
    overall_score = calculate_overall_score(metrics)

    # Generate issues based on analysis
    issues = detect_issues(code_content, features, metrics)

    %{
      overall_score: overall_score,
      metrics: metrics,
      issues: issues
    }
  end

  @doc """
  Extract features from code content for ML model input.
  """
  @spec extract_features(String.t()) :: map()
  def extract_features(code_content) do
    lines = String.split(code_content, "\n")
    total_lines = length(lines)

    %{
      total_lines: total_lines,
      avg_line_length: avg_line_length(lines),
      function_count: count_functions(code_content),
      comment_ratio: comment_ratio(code_content),
      nesting_depth: max_nesting_depth(code_content),
      variable_count: count_variables(code_content),
      cyclomatic_complexity: estimate_cyclomatic_complexity(code_content)
    }
  end

  # Stub implementations for quality calculations

  defp calculate_maintainability(features) do
    # Simple heuristic: lower is better for most metrics
    base_score = 100

    # Penalize for high complexity
    complexity_penalty = features.cyclomatic_complexity * 2

    # Penalize for long functions
    length_penalty = max(0, features.total_lines - 50) * 0.5

    # Reward for comments
    comment_bonus = features.comment_ratio * 20

    # Reward for reasonable line lengths
    line_length_penalty = if features.avg_line_length > 120, do: 10, else: 0

    score = base_score - complexity_penalty - length_penalty - line_length_penalty + comment_bonus
    max(0, min(100, score)) / 100
  end

  defp calculate_complexity(features) do
    # Normalize cyclomatic complexity to 0-1 scale
    complexity = features.cyclomatic_complexity
    1.0 - min(1.0, complexity / 20.0)
  end

  defp calculate_readability(features) do
    # Simple readability score based on line length and comments
    line_score = if features.avg_line_length < 100, do: 1.0, else: 0.7
    comment_score = min(1.0, features.comment_ratio * 3)
    (line_score + comment_score) / 2
  end

  defp calculate_testability(features) do
    # Higher function count generally improves testability
    # Lower complexity improves testability
    function_bonus = min(1.0, features.function_count / 10.0)
    complexity_penalty = features.cyclomatic_complexity / 30.0
    max(0, function_bonus - complexity_penalty)
  end

  defp calculate_overall_score(metrics) do
    # Weighted average of all metrics
    weights = %{maintainability: 0.4, complexity: 0.3, readability: 0.2, testability: 0.1}

    weighted_sum =
      metrics.maintainability * weights.maintainability +
      metrics.complexity * weights.complexity +
      metrics.readability * weights.readability +
      metrics.testability * weights.testability

    weighted_sum
  end

  defp detect_issues(code_content, features, metrics) do
    issues = []

    # Check for long functions
    if features.total_lines > 50 do
      issues = [%{
        type: :warning,
        message: "Function is quite long (#{features.total_lines} lines). Consider breaking it into smaller functions.",
        range: %{start: %{line: 0, character: 0}, end: %{line: features.total_lines - 1, character: 0}},
        confidence: 0.8
      } | issues]
    end

    # Check for high complexity
    if features.cyclomatic_complexity > 10 do
      issues = [%{
        type: :warning,
        message: "High cyclomatic complexity (#{features.cyclomatic_complexity}). Consider simplifying the logic.",
        range: %{start: %{line: 0, character: 0}, end: %{line: features.total_lines - 1, character: 0}},
        confidence: 0.9
      } | issues]
    end

    # Check for low comment ratio
    if features.comment_ratio < 0.1 do
      issues = [%{
        type: :suggestion,
        message: "Low comment ratio (#{Float.round(features.comment_ratio * 100, 1)}%). Consider adding more documentation.",
        range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 0}},
        confidence: 0.6
      } | issues]
    end

    # Check for long lines
    if features.avg_line_length > 120 do
      issues = [%{
        type: :suggestion,
        message: "Average line length is high (#{Float.round(features.avg_line_length, 1)} characters). Consider breaking long lines.",
        range: %{start: %{line: 0, character: 0}, end: %{line: 0, character: 0}},
        confidence: 0.7
      } | issues]
    end

    issues
  end

  # Helper functions for feature extraction

  defp avg_line_length(lines) do
    if lines == [] do
      0
    else
      total_length = lines |> Enum.reduce(0, fn x, acc -> acc + String.length(x) end)
      total_length / length(lines)
    end
  end

  defp count_functions(code_content) do
    # Simple regex-based function counting
    ~r/def\s+\w+/ |> Regex.scan(code_content) |> length()
  end

  defp comment_ratio(code_content) do
    lines = String.split(code_content, "\n")
    comment_lines = Enum.count(lines, &String.contains?(&1, "#"))
    if lines == [], do: 0, else: comment_lines / length(lines)
  end

  defp max_nesting_depth(_code_content) do
    # Stub: would need proper AST analysis
    3
  end

  defp count_variables(_code_content) do
    # Stub: would need proper AST analysis
    10
  end

  defp estimate_cyclomatic_complexity(code_content) do
    # Simple estimation based on keywords
    complexity_keywords = ~w(if case cond unless while for)
    complexity = 1 # base complexity

    Enum.each(complexity_keywords, fn keyword ->
      complexity = complexity + (String.split(code_content, keyword) |> length()) - 1
    end)

    complexity
  end
end