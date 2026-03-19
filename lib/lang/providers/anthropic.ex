defmodule Lang.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude provider for LANG LSP system.

  Specializes in:
  - Security analysis and vulnerability detection
  - Code review and diagnostics
  - Bug prediction and safety analysis
  - Detailed analytical tasks
  """

  @behaviour Lang.Providers.Provider
  require Logger

  @base_url "https://api.anthropic.com/v1"
  @default_model "claude-3-5-sonnet-20241022"
  @analysis_model "claude-3-5-sonnet-20241022"

  # =============================================================================
  # Provider Behavior Implementation
  # =============================================================================

  @impl Lang.Providers.Provider
  def capabilities do
    %{
      methods: [
        "completion",
        "hover",
        "explain",
        "refactor",
        "generate_tests",
        "lang.think.diagnose",
        "lang.think.predict_bugs",
        "lang.think.security_scan",
        "lang.think.review_code",
        "lang.think.find_semantic",
        "lang.query.impact",
        "lang.analyze.document"
      ],
      strengths: [:security, :analysis, :diagnostics, :safety, :detailed_review],
      weaknesses: [:cost_optimization, :simple_generation],
      cost_tier: :expensive,
      speed_tier: :medium,
      quality_tier: :excellent,
      specializations: [:security, :diagnostics, :analysis, :safety_critical_tasks, :code_review]
    }
  end

  @impl Lang.Providers.Provider
  def pricing do
    %{
      # Claude is expensive but worth it for analysis
      input_tokens_per_dollar: 600,
      output_tokens_per_dollar: 200,
      base_cost_per_request: 0.008,
      bulk_discount_threshold: 75_000
    }
  end

  @impl Lang.Providers.Provider
  def handle_request(method, params, opts \\ []) do
    case method do
      "completion" ->
        handle_completion(params, opts)

      "hover" ->
        handle_hover(params, opts)

      "explain" ->
        handle_explain(params, opts)

      "refactor" ->
        handle_refactor(params, opts)

      "generate_tests" ->
        handle_generate_tests(params, opts)

      "lang.think.diagnose" ->
        handle_diagnostics(params, opts)

      "lang.think.predict_bugs" ->
        handle_bug_prediction(params, opts)

      "lang.think.security_scan" ->
        handle_security_scan(params, opts)

      "lang.think.review_code" ->
        handle_code_review(params, opts)

      "lang.think.find_semantic" ->
        handle_semantic_search(params, opts)

      "lang.query.impact" ->
        handle_impact_analysis(params, opts)

      "lang.analyze.document" ->
        handle_document_analysis(params, opts)

      _ ->
        {:error, "Method #{method} not supported by Anthropic provider"}
    end
  end

  @impl Lang.Providers.Provider
  def estimate_cost(method, params) do
    estimated_tokens = estimate_tokens(method, params)
    # Claude pricing: ~$0.015 per 1K input tokens, $0.075 per 1K output tokens
    estimated_input_cost = estimated_tokens * 0.8 * 0.000015
    estimated_output_cost = estimated_tokens * 0.2 * 0.000075
    total_cost = estimated_input_cost + estimated_output_cost

    {:ok,
     %{
       estimated_tokens: estimated_tokens,
       estimated_cost_usd: total_cost
     }}
  end

  @impl Lang.Providers.Provider
  def available? do
    case get_api_key() do
      nil -> false
      _key -> true
    end
  rescue
    _ -> false
  end

  @impl Lang.Providers.Provider
  def health_check do
    case simple_message("Respond with 'CLAUDE_HEALTHY' if you can process this request.") do
      {:ok, response} ->
        if String.contains?(response, "CLAUDE_HEALTHY") do
          {:ok, "Anthropic Claude connection healthy"}
        else
          {:warning, "Claude responding but unexpected format: #{response}"}
        end

      {:error, error} ->
        {:error, "Anthropic health check failed: #{inspect(error)}"}
    end
  end

  # =============================================================================
  # LSP Method Handlers
  # =============================================================================

  defp handle_completion(params, opts) do
    prefix = Map.get(params, :prefix, "")
    language = Map.get(params, :language, "text")
    context = Map.get(params, :context, "")

    prompt = """
    Complete this #{language} code:

    ```#{language}
    #{prefix}
    ```

    #{if String.length(context) > 0, do: "Context:\n#{context}\n", else: ""}

    Provide only the code to complete, without explanations.
    """

    case message_request(prompt, Keyword.put(opts, :max_tokens, 150)) do
      {:ok, response} ->
        {:ok,
         %{
           completion: String.trim(response.content),
           confidence: 0.88,
           provider: "anthropic",
           model: @default_model,
           metadata: %{
             language: language,
             completion_length: String.length(response.content),
             context_used: String.length(context) > 0
           }
         }}

      {:error, error} ->
        {:error, "Completion failed: #{inspect(error)}"}
    end
  end

  defp handle_hover(params, opts) do
    symbol = Map.get(params, :symbol, "unknown")
    language = Map.get(params, :language, "text")
    context = Map.get(params, :context, "")

    prompt = """
    Provide information about this #{language} symbol: `#{symbol}`

    #{if String.length(context) > 0, do: "Context:\n```#{language}\n#{context}\n```\n", else: ""}

    Provide:
    1. Type/signature information
    2. Brief description
    3. Usage notes if relevant

    Format as markdown for hover display.
    """

    case message_request(prompt, Keyword.put(opts, :max_tokens, 300)) do
      {:ok, response} ->
        {:ok,
         %{
           hover_content: response.content,
           confidence: 0.85,
           provider: "anthropic",
           model: @default_model,
           metadata: %{
             symbol: symbol,
             language: language,
             info_length: String.length(response.content)
           }
         }}

      {:error, error} ->
        {:error, "Hover failed: #{inspect(error)}"}
    end
  end

  defp handle_explain(params, opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    question = Map.get(params, :question, "What does this code do?")

    prompt = """
    Explain this #{language} code in detail.

    Question: #{question}

    Code:
    ```#{language}
    #{code}
    ```

    Provide a comprehensive explanation covering:
    1. What the code does (purpose)
    2. How it works (implementation details)
    3. Key concepts or patterns used
    4. Potential issues or improvements
    """

    case message_request(prompt, Keyword.put(opts, :max_tokens, 1000)) do
      {:ok, response} ->
        {:ok,
         %{
           explanation: response.content,
           confidence: 0.92,
           provider: "anthropic",
           model: @default_model,
           metadata: %{
             language: language,
             code_length: String.length(code),
             question: question
           }
         }}

      {:error, error} ->
        {:error, "Explanation failed: #{inspect(error)}"}
    end
  end

  defp handle_refactor(params, opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    goal = Map.get(params, :goal, "improve code quality")

    prompt = """
    Refactor this #{language} code to #{goal}.

    Original code:
    ```#{language}
    #{code}
    ```

    Provide:
    1. The refactored code
    2. A summary of changes made
    3. Explanation of improvements

    Focus on: readability, maintainability, performance, and best practices.
    """

    case message_request(prompt, Keyword.put(opts, :max_tokens, 1200)) do
      {:ok, response} ->
        # Extract refactored code and summary from response
        parts = String.split(response.content, "```", trim: true)
        refactored_code = if length(parts) >= 2, do: Enum.at(parts, 1), else: response.content

        {:ok,
         %{
           refactored_code: String.trim(refactored_code),
           changes_summary: extract_summary_from_response(response.content),
           confidence: 0.89,
           provider: "anthropic",
           model: @default_model,
           metadata: %{
             language: language,
             original_length: String.length(code),
             refactored_length: String.length(refactored_code),
             goal: goal
           }
         }}

      {:error, error} ->
        {:error, "Refactoring failed: #{inspect(error)}"}
    end
  end

  defp handle_generate_tests(params, opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    framework = Map.get(params, :framework, "auto")

    prompt = """
    Generate comprehensive test cases for this #{language} code.

    Code to test:
    ```#{language}
    #{code}
    ```

    #{if framework != "auto", do: "Use testing framework: #{framework}", else: "Use appropriate testing framework for #{language}"}

    Generate:
    1. Unit tests covering main functionality
    2. Edge case tests
    3. Error condition tests
    4. Clear test descriptions

    Provide complete, runnable test code.
    """

    case message_request(prompt, Keyword.put(opts, :max_tokens, 1500)) do
      {:ok, response} ->
        test_code = extract_code_from_response(response.content)
        test_count = count_tests_in_code(test_code)

        {:ok,
         %{
           test_code: test_code,
           test_count: test_count,
           confidence: 0.87,
           provider: "anthropic",
           model: @default_model,
           metadata: %{
             language: language,
             framework: framework,
             original_code_length: String.length(code)
           }
         }}

      {:error, error} ->
        {:error, "Test generation failed: #{inspect(error)}"}
    end
  end

  # =============================================================================
  # Analysis Method Handlers
  # =============================================================================

  defp handle_diagnostics(params, opts) do
    prompt = """
    You are an expert debugger. Analyze this error and provide a clear diagnosis:

    Error/Stack Trace:
    #{params.error_data}

    #{if params.context != %{}, do: "Additional Context:\n#{inspect(params.context)}", else: ""}

    Provide:
    1. **Root Cause**: What exactly went wrong
    2. **Plain English**: Explain the error in simple terms
    3. **Fix Strategy**: Step-by-step solution
    4. **Prevention**: How to avoid this in the future
    5. **Confidence Level**: How certain are you about this diagnosis (0-100%)

    Be direct and actionable.
    """

    message_request(prompt, opts)
  end

  defp handle_bug_prediction(params, opts) do
    prompt = """
    Analyze this code for potential runtime failures and bugs:

    Code:
    ```
    #{params.content}
    ```

    Context: #{params.context}

    Look for:
    1. **Runtime Errors**: Null pointer exceptions, array bounds, etc.
    2. **Logic Bugs**: Edge cases, race conditions, incorrect assumptions
    3. **Performance Issues**: N+1 queries, memory leaks, inefficient algorithms
    4. **Production Risks**: What breaks under load, edge cases, external dependencies
    5. **Security Vulnerabilities**: Input validation, injection risks, auth bypasses

    For each issue found:
    - **Severity**: CRITICAL/HIGH/MEDIUM/LOW
    - **Location**: Specific line/section
    - **Scenario**: When/how it fails
    - **Fix**: Concrete solution
    - **Confidence**: How likely this bug is (0-100%)
    """

    message_request(prompt, opts)
  end

  defp handle_security_scan(params, opts) do
    scan_type = params.scan_type || "comprehensive"

    prompt = """
    Perform a #{scan_type} security analysis of this code:

    Code:
    ```
    #{params.content}
    ```

    Security Focus Areas:
    1. **Input Validation**: SQL injection, XSS, command injection
    2. **Authentication & Authorization**: Bypass vulnerabilities, privilege escalation
    3. **Data Security**: Sensitive data exposure, encryption issues
    4. **Business Logic**: Race conditions, state manipulation
    5. **Infrastructure**: Configuration vulnerabilities, dependency risks

    For each vulnerability:
    - **CWE ID** (if applicable)
    - **Severity**: CRITICAL/HIGH/MEDIUM/LOW/INFO
    - **Attack Vector**: How it can be exploited
    - **Impact**: What damage can occur
    - **Fix**: Specific remediation steps
    - **Code Example**: Show the secure version

    Prioritize by exploitability and business impact.
    """

    message_request(prompt, Keyword.put(opts, :model, @analysis_model))
  end

  defp handle_code_review(params, opts) do
    prompt = """
    Perform a thorough code review of this code:

    Code:
    ```
    #{params.content}
    ```

    Review Areas:
    1. **Code Quality**: Readability, maintainability, best practices
    2. **Architecture**: Design patterns, separation of concerns
    3. **Performance**: Efficiency, scalability concerns
    4. **Testing**: Test coverage gaps, edge cases
    5. **Security**: Security best practices
    6. **Documentation**: Code comments, API documentation

    Provide:
    - **Strengths**: What's done well
    - **Issues**: Problems found with severity levels
    - **Suggestions**: Specific improvements
    - **Priority**: What to fix first
    - **Overall Score**: 1-10 rating with justification
    """

    message_request(prompt, opts)
  end

  defp handle_semantic_search(params, opts) do
    prompt = """
    Perform semantic search to find code matching this intent:

    Search Query: #{params.query}
    Search Scope: #{params.scope}
    Context: #{params.context}

    Search for code that:
    1. **Functionally matches** the query intent
    2. **Semantically similar** patterns
    3. **Related concepts** and implementations

    Return:
    - **Primary Matches**: Direct functional matches
    - **Secondary Matches**: Related/similar code
    - **Relevance Scores**: 0-100% confidence
    - **Explanation**: Why each match is relevant
    - **Suggestions**: Better search terms if needed
    """

    message_request(prompt, opts)
  end

  defp handle_impact_analysis(params, opts) do
    prompt = """
    Analyze the impact of changing this code:

    Target Change: #{params.change_description}
    #{if params.code, do: "Current Code:\n```\n#{params.code}\n```", else: ""}

    Analyze:
    1. **Breaking Changes**: What will definitely break
    2. **Affected Systems**: Dependencies, consumers, integrations
    3. **Risk Assessment**: Probability and severity of issues
    4. **Test Requirements**: What needs testing
    5. **Rollback Strategy**: How to safely revert
    6. **Deployment Considerations**: Staging, feature flags, etc.

    Provide:
    - **Risk Level**: LOW/MEDIUM/HIGH/CRITICAL
    - **Blast Radius**: How many systems affected
    - **Migration Path**: Step-by-step safe approach
    - **Monitoring**: Key metrics to watch post-deployment
    """

    message_request(prompt, opts)
  end

  defp handle_document_analysis(params, opts) do
    prompt = """
    Analyze this document for key insights:

    Document:
    ```
    #{params.content}
    ```

    Analysis Type: #{params.analysis_type || "comprehensive"}

    Provide:
    1. **Summary**: Key points and themes
    2. **Structure**: Organization and flow
    3. **Quality Assessment**: Clarity, completeness, accuracy
    4. **Action Items**: What needs to be done
    5. **Recommendations**: Improvements and next steps
    6. **Confidence Level**: How reliable is this analysis
    """

    message_request(prompt, opts)
  end

  # =============================================================================
  # Anthropic API Integration
  # =============================================================================

  defp message_request(content, opts) do
    model = Keyword.get(opts, :model, @default_model)
    max_tokens = Keyword.get(opts, :max_tokens, 4000)

    payload = %{
      model: model,
      max_tokens: max_tokens,
      messages: [
        %{
          role: "user",
          content: content
        }
      ]
    }

    case make_request("/messages", payload, opts) do
      {:ok, response} ->
        parse_message_response(response)

      {:error, error} ->
        {:error, "Anthropic message failed: #{inspect(error)}"}
    end
  end

  defp simple_message(content, opts \\ []) do
    case message_request(content, opts) do
      {:ok, %{content: content}} -> {:ok, content}
      {:error, error} -> {:error, error}
    end
  end

  defp make_request(endpoint, payload, opts \\ []) do
    url = @base_url <> endpoint
    headers = request_headers(opts)
    body = Jason.encode!(payload)

    Logger.debug("Anthropic request to #{endpoint}", payload: sanitize_payload(payload))

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response_body}} ->
        Logger.debug("Anthropic response success")
        {:ok, response_body}

      {:ok, %{status: status, body: error_body}} ->
        Logger.warning("Anthropic API error", status: status, error: error_body)
        {:error, %{status: status, body: error_body}}

      {:error, reason} ->
        Logger.error("Anthropic request failed", reason: reason)
        {:error, reason}
    end
  end

  defp request_headers(opts \\ []) do
    api_key = get_api_key(opts)

    [
      {"x-api-key", api_key},
      {"Content-Type", "application/json"},
      {"anthropic-version", "2023-06-01"},
      {"User-Agent", "LANG-LSP/1.0"}
    ]
  end

  defp get_api_key(opts \\ []) do
    case Lang.Providers.Credentials.resolve_api_key(:anthropic, opts) do
      {:ok, key} -> key
      {:error, _} -> raise "ANTHROPIC_API_KEY not configured for this request"
    end
  end

  # =============================================================================
  # Response Parsing
  # =============================================================================

  defp parse_message_response(response) do
    case response["content"] do
      [%{"text" => text} | _] ->
        {:ok,
         %{
           content: String.trim(text),
           model: response["model"],
           usage: response["usage"],
           stop_reason: response["stop_reason"]
         }}

      _ ->
        {:error, "Invalid response format from Anthropic"}
    end
  end

  # =============================================================================
  # Utilities
  # =============================================================================

  defp estimate_tokens(method, params) do
    content_length =
      case params do
        %{content: content} when is_binary(content) -> String.length(content)
        %{error_data: error} when is_binary(error) -> String.length(error)
        %{query: query} when is_binary(query) -> String.length(query) * 2
        _ -> 1000
      end

    base_overhead =
      case method do
        # Security scans need detailed prompts
        "lang.think.security_scan" -> 1200
        "lang.think.review_code" -> 1000
        "lang.think.predict_bugs" -> 1000
        _ -> 600
      end

    # Claude tokens: roughly 3.5 chars per token
    div(content_length, 4) + base_overhead
  end

  # =============================================================================
  # LSP Methods (for router compatibility)
  # =============================================================================

  @doc """
  Handle code completion requests
  """
  def complete(prompt, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @default_model),
      max_tokens: Keyword.get(opts, :max_tokens, 150),
      messages: [
        %{
          role: "user",
          content: """
          You are a code completion assistant. Provide only the code to complete, without explanations.

          #{prompt}
          """
        }
      ]
    }

    case make_request("/messages", payload, opts) do
      {:ok, response} ->
        case response["content"] do
          [%{"text" => text} | _] ->
            # Parse multiple completion options from response
            completions = [
              %{
                text: String.trim(text),
                label: String.slice(String.trim(text), 0..50),
                kind: 1
              }
            ]

            {:ok, completions}

          _ ->
            {:error, "Invalid completion response format"}
        end

      {:error, error} ->
        {:error, "Completion failed: #{inspect(error)}"}
    end
  end

  @doc """
  Handle quick info/hover requests
  """
  def query(prompt, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @default_model),
      max_tokens: Keyword.get(opts, :max_tokens, 200),
      messages: [
        %{
          role: "user",
          content: """
          You are a helpful code documentation assistant. Be concise and informative.

          #{prompt}
          """
        }
      ]
    }

    case make_request("/messages", payload, opts) do
      {:ok, response} ->
        case response["content"] do
          [%{"text" => text} | _] ->
            {:ok, String.trim(text)}

          _ ->
            {:error, "Invalid query response format"}
        end

      {:error, error} ->
        {:error, "Query failed: #{inspect(error)}"}
    end
  end

  @doc """
  Handle code analysis requests
  """
  def analyze(prompt, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @analysis_model),
      max_tokens: Keyword.get(opts, :max_tokens, 1000),
      messages: [
        %{
          role: "user",
          content: """
          You are an expert code analyst. Provide detailed, educational explanations.

          #{prompt}
          """
        }
      ]
    }

    case make_request("/messages", payload, opts) do
      {:ok, response} ->
        case response["content"] do
          [%{"text" => text} | _] ->
            {:ok, String.trim(text)}

          _ ->
            {:error, "Invalid analysis response format"}
        end

      {:error, error} ->
        {:error, "Analysis failed: #{inspect(error)}"}
    end
  end

  @doc """
  Handle code generation requests
  """
  def generate(prompt, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @default_model),
      max_tokens: Keyword.get(opts, :max_tokens, 2000),
      messages: [
        %{
          role: "user",
          content: """
          You are an expert code generator. Generate clean, idiomatic code that follows best practices.

          #{prompt}
          """
        }
      ]
    }

    case make_request("/messages", payload, opts) do
      {:ok, response} ->
        case response["content"] do
          [%{"text" => text} | _] ->
            {:ok, String.trim(text)}

          _ ->
            {:error, "Invalid generation response format"}
        end

      {:error, error} ->
        {:error, "Generation failed: #{inspect(error)}"}
    end
  end

  defp sanitize_payload(payload) do
    # Remove sensitive data and truncate long content for logging
    payload
    |> Map.update("messages", [], fn messages ->
      Enum.map(messages, fn message ->
        Map.update(message, "content", "", fn content ->
          if String.length(content) > 300 do
            String.slice(content, 0, 300) <> "... (truncated)"
          else
            content
          end
        end)
      end)
    end)
  end

  # =============================================================================
  # Task Helper (for compatibility)
  # =============================================================================

  def handle_task(task, opts) do
    # Convert generic task to method call
    method = infer_method_from_task(task)
    params = %{content: task.description}

    handle_request(method, params, opts)
  end

  defp infer_method_from_task(task) do
    description = String.downcase(task.description)

    cond do
      String.contains?(description, ["security", "vulnerability", "exploit"]) ->
        "lang.think.security_scan"

      String.contains?(description, ["bug", "error", "fail"]) ->
        "lang.think.predict_bugs"

      String.contains?(description, ["review", "analyze", "audit"]) ->
        "lang.think.review_code"

      String.contains?(description, ["diagnose", "debug", "trace"]) ->
        "lang.think.diagnose"

      true ->
        "lang.analyze.document"
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp extract_summary_from_response(content) do
    # Extract summary from response content
    lines = String.split(content, "\n")

    summary_lines =
      lines
      |> Enum.filter(fn line ->
        String.contains?(String.downcase(line), ["change", "improvement", "refactor", "summary"])
      end)
      |> Enum.take(3)

    case summary_lines do
      [] -> "Code refactored successfully"
      lines -> Enum.join(lines, " ")
    end
  end

  defp extract_code_from_response(content) do
    # Extract code blocks from markdown response
    case Regex.run(~r/```[a-zA-Z]*\n(.*?)\n```/s, content) do
      [_, code] -> String.trim(code)
      nil -> content
    end
  end

  defp count_tests_in_code(test_code) do
    # Count test functions/cases in the generated test code
    test_patterns = [
      ~r/test\s+"/,
      ~r/it\s*\(/,
      ~r/describe\s*\(/,
      ~r/def test_/,
      ~r/function test/
    ]

    count =
      Enum.reduce(test_patterns, 0, fn pattern, acc ->
        matches = Regex.scan(pattern, test_code)
        acc + length(matches)
      end)

    max(1, count)
  end
end
