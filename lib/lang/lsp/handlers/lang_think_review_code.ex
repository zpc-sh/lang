defmodule Lang.LSP.Handlers.LangThinkReviewCode do
  @moduledoc """
  Handles the `lang_think_review_code` LSP method.
  """
  alias Lang.LSP.Dispatcher
  alias Lang.LSP.Protocol.Types
  alias Lang.LSP.Protocol.Response
  alias Lang.LspMeasurementEvent
  require Logger

  @doc """
  Handles the LSP request to review Elixir code.
  """
  def handle_request(%Types.Request{} = request, dispatcher) do
    %Types.Request{params: params, client_id: client_id} = request
    
    # SECURITY: Validate input parameters
    case validate_and_sanitize_input(params) do
      {:ok, sanitized_code} ->
        start_time = System.monotonic_time(:millisecond)
        review_result = perform_code_review(sanitized_code)
        duration_ms = System.monotonic_time(:millisecond) - start_time

        response = %Response{
          id: request.id,
          result: %{review: review_result}
        }

        # Log the LSP event
        log_lsp_event(client_id, "lang_think_review_code", params, response, duration_ms, nil)

        {:reply, response, dispatcher}
        
      {:error, error_msg} ->
        response = %Response{
          id: request.id,
          error: %{code: -32602, message: error_msg}
        }
        {:reply, response, dispatcher}
    end
  end

  @doc """
  Performs a basic review of the provided Elixir code.
  It attempts to compile the code and provides feedback based on the compilation result.
  It also performs a simple static analysis for common patterns.
  """
  defp perform_code_review(code) when is_binary(code) and code != "" do
    # SECURITY: Never execute arbitrary code! Use safe AST parsing only
    case safe_parse_code(code) do
      {:ok, _ast} ->
        # If code parses successfully, perform static analysis
        static_analysis_feedback(code)
      {:error, errors} ->
        # If code has syntax errors, return parsing errors
        format_parsing_errors(errors)
    end
  end
  defp perform_code_review(_code), do: "No code provided for review."

  @doc """
  SECURITY: Validates and sanitizes input to prevent malicious code injection.
  Delegates to centralized SecurityValidator to avoid drift.
  """
  defp validate_and_sanitize_input(params) when is_map(params) do
    with {:ok, sanitized} <- Lang.LSP.SecurityValidator.validate_think_params("lang.think.review_code", params) do
      case Map.get(sanitized, "code") do
        nil -> {:error, "Missing 'code' parameter"}
        code when is_binary(code) and byte_size(code) > 0 -> {:ok, String.trim(code)}
        _ -> {:error, "Code parameter must be a non-empty string"}
      end
    end
  end
  defp validate_and_sanitize_input(_), do: {:error, "Invalid parameters format"}

  @doc """
  SECURITY: Safe code parsing without execution.
  Uses Code.string_to_quoted/2 which only parses syntax without executing code.
  This is much safer than Code.compile_string/2 which actually executes code.
  """
  defp safe_parse_code(code) do
    # SAFE: Only parse syntax, never execute
    try do
      case Code.string_to_quoted(code, []) do
        {:ok, ast} -> {:ok, ast}
        {:error, {_line, error_description, token}} ->
          {:error, [%{message: "Syntax error: #{error_description} near '#{token}'", type: :syntax_error}]}
      end
    rescue
      e -> {:error, [%{message: "Parsing error: #{inspect(e)}"}]}
    end
  end

  defp format_parsing_errors(errors) do
    errors
    |> Enum.map(fn error ->
      case error do
        %{message: msg, type: :syntax_error} ->
          "Syntax Error: #{msg}"
        %{message: msg} ->
          "Parse Error: #{msg}"
        _ ->
          "Unknown parsing error: #{inspect(error)}"
      end
    end)
    |> Enum.join("\n")
  end

  @doc """
  SECURITY: Enhanced static analysis with safety checks.
  Performs comprehensive analysis without code execution.
  """
  defp static_analysis_feedback(code) do
    feedback = []
    
    # Security-focused checks
    feedback = if String.contains?(code, "IO.inspect"), 
      do: ["Warning: Found `IO.inspect` call. Remove before production." | feedback], 
      else: feedback
      
    feedback = if String.contains?(code, "IO.puts"), 
      do: ["Info: Found `IO.puts` call. Consider using Logger for production." | feedback], 
      else: feedback
      
    feedback = if String.contains?(code, "Process.sleep"), 
      do: ["Warning: Found `Process.sleep` call. This may block the system." | feedback], 
      else: feedback
      
    feedback = if Regex.match?(~r/send\s*\(/, code), 
      do: ["Info: Found `send` call. Ensure proper message handling." | feedback], 
      else: feedback
      
    feedback = if String.contains?(code, "receive do"), 
      do: ["Info: Found `receive` block. Ensure timeout handling." | feedback], 
      else: feedback
      
    feedback = if Regex.match?(~r/def\s+\w+.*do\s*$/, code), 
      do: ["Warning: Found empty function definition." | feedback], 
      else: feedback
    
    # Code quality checks
    lines = String.split(code, "\n")
    long_lines = Enum.with_index(lines, 1)
                |> Enum.filter(fn {line, _} -> String.length(line) > 120 end)
                |> Enum.map(fn {_, line_num} -> "Line #{line_num}: Line too long (>120 chars)" end)
    
    feedback = feedback ++ long_lines

    case feedback do
      [] -> "✅ Code parsed successfully. No obvious issues found during static analysis."
      _ -> "📋 Static Analysis Results:\n" <> Enum.join(feedback, "\n")
    end
  end

  defp log_lsp_event(client_id, method, request, response, duration_ms, error) do
    case Lang.LspDomain.create_lsp_measurement_event(%{
           client_id: client_id,
           method: method,
           request: request,
           response: response,
           duration_ms: duration_ms,
           error: error
         }) do
      {:ok, _event} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to log LSP measurement event: #{inspect(reason)}")
    end
  end
end
