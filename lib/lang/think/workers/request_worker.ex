defmodule Lang.Think.Workers.RequestWorker do
  @moduledoc """
  Executes cognitive requests (explain, find, trace) and stores results.
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3
  require Logger

  alias Lang.Think.{Request, Result, AIEngine}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id}}) do
    with {:ok, req} <- Request.by_id(request_id),
         {:ok, _} <- Request.update_status(req, %{}, %{status: :running}) do
      result =
        :telemetry.span([:lang, :think, :execute], %{kind: req.kind, request_id: req.id}, fn ->
          case execute(req) do
            {:ok, output} = ok -> {ok, Map.merge(%{status: :ok}, safe_metrics(output))}
            {:error, reason} = err -> {err, %{status: :error, reason: inspect(reason)}}
          end
        end)

      case result do
        {:ok, output} ->
          {:ok, _} =
            Result.create(%{
              request_id: req.id,
              summary: output[:summary],
              details: output[:details] || %{},
              artifacts: output[:artifacts] || [],
              confidence_score: output[:confidence_score],
              metrics: output[:metrics] || %{},
              completed_at: DateTime.utc_now()
            })

          {:ok, _} = Request.complete(req, %{metadata: %{}})
          :ok

        {:error, reason} ->
          Logger.error("Think request failed", request_id: req.id, reason: inspect(reason))
          {:ok, _} = Request.fail(req, %{error_message: to_string(reason), metadata: %{}})
          :ok
      end
    else
      _ -> :ok
    end
  end

  defp execute(%Request{kind: kind, input: input} = req) do
    # Build options from request metadata and user preferences
    opts = build_execution_opts(req)

    # Use AI Engine for all think operations
    case AIEngine.execute(kind, input, opts) do
      {:ok, ai_result} ->
        {:ok, ai_result}

      {:error, :no_content} ->
        {:ok, fallback_result(kind, input, "No content provided for analysis")}

      {:error, :no_stacktrace} ->
        {:ok, fallback_result(kind, input, "No stacktrace provided for diagnosis")}

      {:error, :no_query} ->
        {:ok, fallback_result(kind, input, "No search query provided")}

      {:error, :no_trace_target} ->
        {:ok, fallback_result(kind, input, "No trace target specified")}

      {:error, {:ai_provider_failed, reason}} ->
        Logger.warning("AI provider failed, using fallback",
          kind: kind,
          reason: reason,
          request_id: req.id
        )

        {:ok, fallback_result(kind, input, "AI provider unavailable - using basic analysis")}

      {:error, reason} ->
        Logger.error("Think operation failed", kind: kind, reason: reason, request_id: req.id)
        {:error, reason}
    end
  end

  defp build_execution_opts(req) do
    # Extract provider preference and other options from request metadata
    metadata = req.metadata || %{}

    [
      provider_preference: get_in(metadata, ["provider"]) || get_in(metadata, [:provider]),
      model: get_in(metadata, ["model"]) || get_in(metadata, [:model]),
      temperature: get_in(metadata, ["temperature"]) || get_in(metadata, [:temperature]) || 0.3,
      max_tokens: get_in(metadata, ["max_tokens"]) || get_in(metadata, [:max_tokens]) || 2000,
      user_id: req.user_id,
      project_id: req.project_id
    ]
  end

  defp fallback_result(kind, input, error_msg) do
    %{
      summary: generate_fallback_summary(kind, input),
      details: %{
        fallback_reason: error_msg,
        basic_analysis: perform_basic_analysis(kind, input),
        input_summary: summarize_input(input)
      },
      confidence_score: Decimal.new("0.2"),
      metrics: %{
        fallback_used: true,
        input_size: calculate_input_size(input)
      },
      provider_used: "fallback",
      tokens_used: %{}
    }
  end

  defp generate_fallback_summary(kind, input) do
    case kind do
      :explain_intent -> "Basic intent analysis: #{get_content_preview(input)}"
      :explain_why -> "Basic reasoning analysis: #{get_content_preview(input)}"
      :explain_how -> "Basic execution analysis: #{get_content_preview(input)}"
      :diagnose -> "Basic error diagnosis: #{get_stacktrace_preview(input)}"
      :predict_bugs -> "Basic bug prediction completed"
      :predict_performance -> "Basic performance analysis completed"
      :security_scan -> "Basic security scan completed"
      :find_semantic -> "Basic semantic search: #{get_query_preview(input)}"
      :find_similar -> "Basic similarity search: #{get_query_preview(input)}"
      :trace_flow -> "Basic flow trace completed"
      :generate_tests -> "Basic test generation analysis completed"
      :review_code -> "Basic code review completed"
      :estimate_complexity -> "Basic complexity estimation completed"
      _ -> "Basic analysis completed for #{kind}"
    end
  end

  defp perform_basic_analysis(kind, input) do
    case kind do
      k when k in [:explain_intent, :explain_why, :explain_how] ->
        content = get_content(input)

        %{
          content_length: String.length(content),
          line_count: length(String.split(content, "\n")),
          has_functions: String.contains?(content, "def"),
          language_hints: detect_language_hints(content)
        }

      :diagnose ->
        stack = get_stacktrace(input)
        lines = String.split(stack, "\n")

        %{
          stack_depth: length(lines),
          error_hints: extract_error_hints(lines),
          top_frames: Enum.take(lines, 5)
        }

      _ ->
        %{analysis_type: kind, basic_metrics: true}
    end
  end

  defp analyze_text_fast(content, opts) when is_binary(content) do
    case Lang.Analyses.Adapters.TextIntelligence.analyze(content, opts) do
      {:ok, analysis} -> analysis
      {:error, _} -> %{summary: String.slice(content, 0, 120)}
    end
  end

  # Helper functions for fallback analysis
  defp get_content(input) do
    get_in(input, ["code"]) || get_in(input, [:code]) ||
      get_in(input, ["content"]) || get_in(input, [:content]) || ""
  end

  defp get_stacktrace(input) do
    get_in(input, ["stacktrace"]) || get_in(input, [:stacktrace]) ||
      get_in(input, ["error"]) || get_in(input, [:error]) || ""
  end

  defp get_content_preview(input) do
    content = get_content(input)

    if String.length(content) > 50 do
      String.slice(content, 0, 47) <> "..."
    else
      content
    end
  end

  defp get_stacktrace_preview(input) do
    stack = get_stacktrace(input)
    lines = String.split(stack, "\n")

    if length(lines) > 0 do
      "#{length(lines)} stack frames"
    else
      "no stacktrace"
    end
  end

  defp get_query_preview(input) do
    query = get_in(input, ["query"]) || get_in(input, [:query]) || ""

    if String.length(query) > 30 do
      String.slice(query, 0, 27) <> "..."
    else
      query
    end
  end

  defp summarize_input(input) do
    %{
      keys: Map.keys(input),
      has_code: not is_nil(get_in(input, ["code"]) || get_in(input, [:code])),
      has_content: not is_nil(get_in(input, ["content"]) || get_in(input, [:content])),
      has_query: not is_nil(get_in(input, ["query"]) || get_in(input, [:query]))
    }
  end

  defp calculate_input_size(input) do
    content = get_content(input)
    stack = get_stacktrace(input)
    String.length(content) + String.length(stack)
  end

  defp detect_language_hints(content) do
    hints = []
    hints = if String.contains?(content, "defmodule"), do: ["elixir" | hints], else: hints
    hints = if String.contains?(content, "function"), do: ["javascript" | hints], else: hints
    hints = if String.contains?(content, "def "), do: ["python_or_ruby" | hints], else: hints
    hints = if String.contains?(content, "class "), do: ["oop_language" | hints], else: hints
    hints
  end

  defp extract_error_hints(stack_lines) do
    hints = []

    hints =
      if Enum.any?(stack_lines, &String.contains?(&1, "FunctionClauseError")),
        do: ["pattern_match_error" | hints],
        else: hints

    hints =
      if Enum.any?(stack_lines, &String.contains?(&1, "Ecto")),
        do: ["database_error" | hints],
        else: hints

    hints =
      if Enum.any?(stack_lines, &String.contains?(&1, "Phoenix")),
        do: ["web_framework_error" | hints],
        else: hints

    hints
  end

  defp engine_metrics do
    if Code.ensure_loaded?(Lang.Native.PerfEngine) and
         function_exported?(Lang.Native.PerfEngine, :memory_stats, 0) do
      case Lang.Native.PerfEngine.memory_stats() do
        {:ok, stats} -> Map.new(stats)
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp hint_from_stack(lines) do
    cond do
      Enum.any?(lines, &String.contains?(&1, "FunctionClauseError")) ->
        "Pattern mismatch in function call"

      Enum.any?(lines, &String.contains?(&1, "Ecto")) ->
        "Ecto query or schema issue"

      Enum.any?(lines, &String.contains?(&1, "DBConnection")) ->
        "Database connectivity/pool issue"

      true ->
        "Review top frames for failing function and arguments"
    end
  end

  defp safe_metrics(%{metrics: m}) when is_map(m), do: m
  defp safe_metrics(_), do: %{}
end
