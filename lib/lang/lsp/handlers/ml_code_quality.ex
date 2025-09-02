defmodule Lang.LSP.Handlers.MLCodeQuality do
  @moduledoc """
  LSP handler for ML-powered code quality prediction.

  Provides the lang.ml.code_quality_predict method that analyzes
  code documents and returns quality metrics and improvement suggestions.
  """

  alias Lang.ML.CodeQualityPredictor
  alias Lang.LSP.Server

  @doc """
  Handle lang.ml.code_quality_predict requests.

  Analyzes the specified document and returns quality predictions.
  """
  def handle(%{"params" => %{"textDocument" => %{"uri" => uri}} = params}, state) do
    case Server.get_document(uri) do
      {:ok, document} ->
        # Extract code content
        code_content = document.content || ""

        # Get optional range
        range = Map.get(params, "range")

        # If range is specified, extract that portion
        content_to_analyze =
          if range do
            extract_range_content(code_content, range)
          else
            code_content
          end

        # Run quality prediction
        result = CodeQualityPredictor.predict_quality(content_to_analyze)

        # Convert result to LSP format
        lsp_result = %{
          "overall_score" => result.overall_score,
          "metrics" => %{
            "maintainability" => result.metrics.maintainability,
            "complexity" => result.metrics.complexity,
            "readability" => result.metrics.readability,
            "testability" => result.metrics.testability
          },
          "issues" => Enum.map(result.issues, &format_issue/1)
        }

        {:ok, lsp_result}

      :not_found ->
        {:error, %{
          "code" => -32000,
          "message" => "Document not found: #{uri}"
        }}
    end
  end

  def handle(_params, _state) do
    {:error, %{
      "code" => -32602,
      "message" => "Invalid parameters for lang.ml.code_quality_predict"
    }}
  end

  # Extract content from a specific range
  defp extract_range_content(code_content, range) do
    lines = String.split(code_content, "\n")

    start_line = get_in(range, ["start", "line"]) || 0
    end_line = get_in(range, ["end", "line"]) || (length(lines) - 1)

    # Ensure bounds are valid
    start_line = max(0, min(start_line, length(lines) - 1))
    end_line = max(start_line, min(end_line, length(lines) - 1))

    # Extract the specified lines
    selected_lines = Enum.slice(lines, start_line..end_line)
    Enum.join(selected_lines, "\n")
  end

  # Format an issue for LSP response
  defp format_issue(issue) do
    %{
      "type" => Atom.to_string(issue.type),
      "message" => issue.message,
      "range" => issue.range,
      "confidence" => issue.confidence
    }
  end
end