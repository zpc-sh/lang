defmodule Lang.Think.Facade do
  @moduledoc """
  High-level facade for AI-powered Think operations.

  This module provides a clean, simple interface for performing cognitive
  analysis operations. It handles the complexity of AI provider integration,
  request management, and result processing.

  ## Examples

      # Explain what code does
      {:ok, explanation} = Lang.Think.Facade.explain_intent("def hello, do: :world")

      # Get AI-powered code review
      {:ok, review} = Lang.Think.Facade.review_code(code, language: "elixir")

      # Diagnose an error from stacktrace
      {:ok, diagnosis} = Lang.Think.Facade.diagnose_error(stacktrace)

  """

  alias Lang.Think.{Request, AIEngine}
  require Logger

  @type think_opts :: [
          provider: String.t(),
          model: String.t(),
          temperature: float(),
          max_tokens: integer(),
          user_id: String.t(),
          project_id: String.t(),
          async: boolean()
        ]

  @type sync_result :: %{
          summary: String.t(),
          details: map(),
          confidence_score: Decimal.t(),
          provider_used: String.t()
        }

  @type async_result :: {:ok, String.t()} | {:error, any()}

  # =============================================================================
  # Code Explanation Operations
  # =============================================================================

  @doc """
  Explain the high-level intent and purpose of code.

  ## Parameters
  - `code` - The code to analyze
  - `opts` - Options including language, provider preference, etc.

  ## Examples

      {:ok, result} = Lang.Think.Facade.explain_intent(\"\"\"
      def calculate_total(items) do
        Enum.reduce(items, 0, &(&1.price + &2))
      end
      \"\"\", language: "elixir")

      IO.puts result.summary
      # => "Function calculates total price by summing item prices"

  """
  @spec explain_intent(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def explain_intent(code, opts \\ []) do
    input = build_code_input(code, opts)
    execute_think_operation(:explain_intent, input, opts)
  end

  @doc """
  Explain why code exists and the reasoning behind it.
  """
  @spec explain_why(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def explain_why(code, opts \\ []) do
    input = build_code_input(code, opts)
    execute_think_operation(:explain_why, input, opts)
  end

  @doc """
  Explain how code works step-by-step.
  """
  @spec explain_how(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def explain_how(code, opts \\ []) do
    input = build_code_input(code, opts)
    execute_think_operation(:explain_how, input, opts)
  end

  # =============================================================================
  # Code Analysis Operations
  # =============================================================================

  @doc """
  Perform comprehensive code review with AI-powered insights.

  ## Parameters
  - `code` - Code to review
  - `opts` - Options including review focus, severity threshold, etc.

  ## Examples

      {:ok, review} = Lang.Think.Facade.review_code(code,
        language: "elixir",
        focus: ["performance", "security", "maintainability"]
      )

      # Review contains quality score and improvement suggestions

  """
  @spec review_code(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def review_code(code, opts \\ []) do
    input = build_code_input(code, opts)
    execute_think_operation(:review_code, input, opts)
  end

  @doc """
  Predict potential bugs and issues in code.
  """
  @spec predict_bugs(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def predict_bugs(code, opts \\ []) do
    input = build_code_input(code, opts)
    execute_think_operation(:predict_bugs, input, opts)
  end

  @doc """
  Analyze performance characteristics and bottlenecks.
  """
  @spec predict_performance(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def predict_performance(code, opts \\ []) do
    input = build_code_input(code, opts)
    execute_think_operation(:predict_performance, input, opts)
  end

  @doc """
  Perform security analysis and vulnerability scanning.
  """
  @spec security_scan(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def security_scan(code, opts \\ []) do
    input = build_code_input(code, opts)
    execute_think_operation(:security_scan, input, opts)
  end

  @doc """
  Estimate code complexity with detailed breakdown.
  """
  @spec estimate_complexity(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def estimate_complexity(code, opts \\ []) do
    input = build_code_input(code, opts)
    execute_think_operation(:estimate_complexity, input, opts)
  end

  # =============================================================================
  # Error Analysis Operations
  # =============================================================================

  @doc """
  Diagnose errors from stacktraces with AI-powered root cause analysis.

  ## Parameters
  - `stacktrace` - Error stacktrace or error message
  - `opts` - Options including error context, environment info, etc.

  ## Examples

      {:ok, diagnosis} = Lang.Think.Facade.diagnose_error(stacktrace,
        error_type: "FunctionClauseError",
        context: %{recent_changes: "Updated user validation"}
      )

      # Diagnosis contains root cause analysis and solutions

  """
  @spec diagnose_error(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def diagnose_error(stacktrace, opts \\ []) do
    input = %{
      "stacktrace" => stacktrace,
      "error_type" => Keyword.get(opts, :error_type),
      "error_message" => Keyword.get(opts, :error_message),
      "environment" => Keyword.get(opts, :environment),
      "recent_changes" => Keyword.get(opts, :recent_changes)
    }

    execute_think_operation(:diagnose, input, opts)
  end

  # =============================================================================
  # Search Operations
  # =============================================================================

  @doc """
  Semantic search for code that matches a natural language query.

  ## Parameters
  - `query` - Natural language search query
  - `codebase` - Code content to search within
  - `opts` - Search options including scope, max results, etc.

  ## Examples

      {:ok, results} = Lang.Think.Facade.find_semantic(
        "functions that validate user input",
        codebase_content,
        max_results: 10,
        scope: "project"
      )

      # Results contain semantic matches with relevance scores

  """
  @spec find_semantic(String.t(), String.t(), think_opts()) ::
          {:ok, sync_result()} | async_result()
  def find_semantic(query, codebase, opts \\ []) do
    input = %{
      "query" => query,
      "code" => codebase,
      "scope" => Keyword.get(opts, :scope, "project"),
      "max_results" => Keyword.get(opts, :max_results, 20),
      "file_types" => Keyword.get(opts, :file_types, [])
    }

    execute_think_operation(:find_semantic, input, opts)
  end

  @doc """
  Find code similar to a given example or pattern.
  """
  @spec find_similar(String.t(), String.t(), think_opts()) ::
          {:ok, sync_result()} | async_result()
  def find_similar(pattern, codebase, opts \\ []) do
    input = %{
      "query" => pattern,
      "code" => codebase,
      "scope" => Keyword.get(opts, :scope, "project"),
      "max_results" => Keyword.get(opts, :max_results, 20)
    }

    execute_think_operation(:find_similar, input, opts)
  end

  # =============================================================================
  # Flow Analysis Operations
  # =============================================================================

  @doc """
  Trace execution flow through code for a specific function or operation.

  ## Parameters
  - `target` - Function name or operation to trace
  - `code` - Code containing the target
  - `opts` - Tracing options including depth, focus areas, etc.

  ## Examples

      {:ok, trace} = Lang.Think.Facade.trace_flow("process_order", code,
        language: "elixir",
        depth: 5
      )

      # Trace contains execution path and flow analysis

  """
  @spec trace_flow(String.t(), String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def trace_flow(target, code, opts \\ []) do
    input = build_code_input(code, opts) |> Map.put("target", target)
    execute_think_operation(:trace_flow, input, opts)
  end

  # =============================================================================
  # Test Generation Operations
  # =============================================================================

  @doc """
  Generate comprehensive tests for code using AI analysis.

  ## Parameters
  - `code` - Code to generate tests for
  - `opts` - Test generation options including test types, coverage targets, etc.

  ## Examples

      {:ok, tests} = Lang.Think.Facade.generate_tests(code,
        language: "elixir",
        test_types: ["unit", "integration", "edge_cases"],
        framework: "ExUnit"
      )

      # Tests contain generated test code with comprehensive coverage

  """
  @spec generate_tests(String.t(), think_opts()) :: {:ok, sync_result()} | async_result()
  def generate_tests(code, opts \\ []) do
    input =
      build_code_input(code, opts)
      |> Map.put("test_types", Keyword.get(opts, :test_types, ["unit", "edge_cases"]))
      |> Map.put("framework", Keyword.get(opts, :framework))

    execute_think_operation(:generate_tests, input, opts)
  end

  # =============================================================================
  # Batch Operations
  # =============================================================================

  @doc """
  Perform multiple think operations on the same code efficiently.

  ## Parameters
  - `code` - Code to analyze
  - `operations` - List of operations to perform
  - `opts` - Shared options for all operations

  ## Examples

      {:ok, results} = Lang.Think.Facade.analyze_comprehensive(code, [
        :explain_intent,
        :review_code,
        :predict_bugs,
        :estimate_complexity
      ], language: "elixir")

      # Returns map with results for each operation
      # Access results: results.explain_intent.summary, etc.

  """
  @spec analyze_comprehensive(String.t(), [atom()], think_opts()) ::
          {:ok, map()} | {:error, any()}
  def analyze_comprehensive(code, operations, opts \\ []) do
    input = build_code_input(code, opts)

    results =
      operations
      |> Enum.map(fn operation ->
        case execute_think_operation(operation, input, opts) do
          {:ok, result} -> {operation, result}
          {:error, reason} -> {operation, {:error, reason}}
        end
      end)
      |> Enum.into(%{})

    {:ok, results}
  end

  # =============================================================================
  # Private Implementation
  # =============================================================================

  defp execute_think_operation(operation, input, opts) do
    if Keyword.get(opts, :async, false) do
      execute_async(operation, input, opts)
    else
      execute_sync(operation, input, opts)
    end
  end

  defp execute_sync(operation, input, opts) do
    case AIEngine.execute(operation, input, opts) do
      {:ok, result} ->
        {:ok, format_sync_result(result)}

      {:error, reason} ->
        Logger.warning("Think operation failed", operation: operation, reason: reason)
        {:error, reason}
    end
  end

  defp execute_async(operation, input, opts) do
    case Request.create_enqueued(%{
           kind: operation,
           input: input,
           user_id: Keyword.get(opts, :user_id),
           project_id: Keyword.get(opts, :project_id),
           run_id: Keyword.get(opts, :run_id),
           metadata: %{
             provider: Keyword.get(opts, :provider),
             model: Keyword.get(opts, :model),
             temperature: Keyword.get(opts, :temperature),
             max_tokens: Keyword.get(opts, :max_tokens)
           }
         }) do
      {:ok, request} ->
        {:ok, request.id}

      {:error, reason} ->
        Logger.error("Failed to queue think operation", operation: operation, reason: reason)
        {:error, reason}
    end
  end

  defp build_code_input(code, opts) do
    %{
      "code" => code,
      "language" => Keyword.get(opts, :language),
      "file_path" => Keyword.get(opts, :file_path),
      "line_number" => Keyword.get(opts, :line_number),
      "function_name" => Keyword.get(opts, :function_name),
      "surrounding_code" => Keyword.get(opts, :surrounding_code),
      "project_type" => Keyword.get(opts, :project_type),
      "dependencies" => Keyword.get(opts, :dependencies),
      "framework" => Keyword.get(opts, :framework)
    }
  end

  defp format_sync_result(ai_result) do
    %{
      summary: ai_result.summary,
      details: ai_result.details,
      confidence_score: ai_result.confidence_score,
      provider_used: ai_result.provider_used,
      metrics: ai_result.metrics
    }
  end

  # =============================================================================
  # Utility Functions
  # =============================================================================

  @doc """
  Get the status of an async operation.

  Returns the current status and results if completed.
  """
  @spec get_operation_status(String.t()) ::
          {:ok, :pending | :running | :completed | :failed, map()} | {:error, :not_found}
  def get_operation_status(request_id) do
    case Request.by_id(request_id) do
      {:ok, request} ->
        case request.status do
          :completed ->
            case Lang.Think.Result.by_request_id(request_id) do
              {:ok, result} ->
                {:ok, :completed,
                 %{
                   summary: result.summary,
                   details: result.details,
                   confidence_score: result.confidence_score,
                   completed_at: result.completed_at
                 }}

              {:error, _} ->
                {:ok, :completed, %{}}
            end

          :failed ->
            {:ok, :failed, %{error_message: request.error_message}}

          status ->
            {:ok, status, %{started_at: request.started_at}}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @doc """
  Cancel a pending or running async operation.
  """
  @spec cancel_operation(String.t()) :: :ok | {:error, :not_found | :already_completed}
  def cancel_operation(request_id) do
    case Request.by_id(request_id) do
      {:ok, request} ->
        if request.status in [:pending, :running] do
          case Request.cancel(request, %{}) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, :already_completed}
        end

      {:error, _} ->
        {:error, :not_found}
    end
  end

  @doc """
  Get usage statistics for think operations.
  """
  @spec get_usage_stats(String.t() | nil) :: %{
          total_operations: integer(),
          operations_by_type: map(),
          success_rate: float(),
          average_confidence: float(),
          top_providers: [String.t()]
        }
  def get_usage_stats(user_id \\ nil) do
    # This would query the Request and Result tables for statistics
    # Implementation depends on your specific analytics needs
    %{
      total_operations: 0,
      operations_by_type: %{},
      success_rate: 0.0,
      average_confidence: 0.0,
      top_providers: []
    }
  end

  @doc """
  List available AI providers and their capabilities.
  """
  @spec list_providers() :: %{String.t() => map()}
  def list_providers do
    # This would integrate with the Provider system to list capabilities
    %{
      "openai" => %{
        strengths: [:generation, :explanation, :complex_reasoning],
        cost_tier: :expensive,
        speed_tier: :medium,
        quality_tier: :excellent
      },
      "anthropic" => %{
        strengths: [:analysis, :safety, :reasoning],
        cost_tier: :expensive,
        speed_tier: :fast,
        quality_tier: :excellent
      },
      "xai" => %{
        strengths: [:speed, :code_understanding],
        cost_tier: :medium,
        speed_tier: :fast,
        quality_tier: :good
      }
    }
  end
end
