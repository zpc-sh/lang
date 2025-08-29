defmodule Lang.Providers.OpenAI do
  @moduledoc """
  OpenAI GPT provider for LANG LSP system.

  Specializes in:
  - Code generation and explanation
  - Complex reasoning tasks
  - General-purpose analysis
  - Flow tracing and detailed breakdowns
  """

  @behaviour Lang.Providers.Provider
  require Logger

  @base_url "https://api.openai.com/v1"
  @default_model "gpt-4-turbo-preview"
  @generation_model "gpt-4-turbo-preview"

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
        "lang.think.explain_intent",
        "lang.think.explain_why",
        "lang.think.explain_how",
        "lang.think.trace_flow",
        "lang.generate.from_spec",
        "lang.generate.from_tests",
        "lang.generate.complete_partial",
        "lang.generate.dockerfile",
        "lang.query.natural"
      ],
      strengths: [:generation, :explanation, :complex_reasoning, :general_purpose],
      weaknesses: [:cost_optimization, :simple_tasks],
      cost_tier: :expensive,
      speed_tier: :medium,
      quality_tier: :excellent,
      specializations: [:generation, :explanation, :complex_analysis, :reasoning]
    }
  end

  @impl Lang.Providers.Provider
  def pricing do
    %{
      # GPT-4 is expensive
      input_tokens_per_dollar: 500,
      # Even more expensive for output
      output_tokens_per_dollar: 250,
      # Higher base cost
      base_cost_per_request: 0.01,
      bulk_discount_threshold: 50_000
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

      <<"lang.think.explain", _::binary>> ->
        handle_explanation(method, params, opts)

      "lang.think.trace_flow" ->
        handle_flow_tracing(params, opts)

      <<"lang.generate", _::binary>> ->
        handle_generation(method, params, opts)

      "lang.query.natural" ->
        handle_natural_query(params, opts)

      _ ->
        {:error, "Method #{method} not supported by OpenAI provider"}
    end
  end

  @impl Lang.Providers.Provider
  def estimate_cost(method, params) do
    estimated_tokens = estimate_tokens(method, params)
    # GPT-4 pricing: ~$0.03 per 1K input tokens, $0.06 per 1K output tokens
    # 80% input
    estimated_input_cost = estimated_tokens * 0.8 * 0.00003
    # 20% output
    estimated_output_cost = estimated_tokens * 0.2 * 0.00006
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
    case simple_completion("Respond with 'OPENAI_HEALTHY' if you can process this request.") do
      {:ok, response} ->
        if String.contains?(response, "OPENAI_HEALTHY") do
          {:ok, "OpenAI GPT connection healthy"}
        else
          {:warning, "OpenAI responding but unexpected format: #{response}"}
        end

      {:error, error} ->
        {:error, "OpenAI health check failed: #{inspect(error)}"}
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
    Complete this #{language} code. Provide only the completion, no explanations.

    Code to complete:
    ```#{language}
    #{prefix}
    ```

    #{if String.length(context) > 0, do: "Context: #{context}", else: ""}

    Complete the code naturally and idiomatically.
    """

    case completion_request(prompt, Keyword.put(opts, :max_tokens, 200)) do
      {:ok, response} ->
        {:ok,
         %{
           completion: String.trim(response.content),
           confidence: 0.85,
           provider: "openai",
           model: response.model,
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
    Provide hover information for this #{language} symbol: `#{symbol}`

    #{if String.length(context) > 0, do: "Context:\n```#{language}\n#{context}\n```", else: ""}

    Provide:
    - Type information
    - Brief description
    - Usage example if helpful

    Format as markdown for display.
    """

    case completion_request(prompt, Keyword.put(opts, :max_tokens, 250)) do
      {:ok, response} ->
        {:ok,
         %{
           hover_content: response.content,
           confidence: 0.82,
           provider: "openai",
           model: response.model,
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
    #{question}

    #{language} code:
    ```#{language}
    #{code}
    ```

    Provide a clear, educational explanation covering:
    1. What this code does
    2. How it works
    3. Key concepts used
    4. Any notable patterns or techniques
    """

    case completion_request(prompt, Keyword.put(opts, :max_tokens, 800)) do
      {:ok, response} ->
        {:ok,
         %{
           explanation: response.content,
           confidence: 0.88,
           provider: "openai",
           model: response.model,
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
    2. Summary of changes made
    3. Benefits of the refactoring

    Focus on clean, maintainable, and efficient code.
    """

    case completion_request(prompt, Keyword.put(opts, :max_tokens, 1000)) do
      {:ok, response} ->
        # Extract code and summary from response
        refactored_code = extract_code_from_response(response.content)
        changes_summary = extract_changes_summary(response.content)

        {:ok,
         %{
           refactored_code: refactored_code,
           changes_summary: changes_summary,
           confidence: 0.86,
           provider: "openai",
           model: response.model,
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
    Generate comprehensive tests for this #{language} code.

    Code to test:
    ```#{language}
    #{code}
    ```

    #{if framework != "auto", do: "Use #{framework} testing framework.", else: "Use the standard testing framework for #{language}."}

    Generate:
    1. Unit tests for main functionality
    2. Edge case tests
    3. Error handling tests
    4. Clear test descriptions

    Provide complete, runnable test code.
    """

    case completion_request(prompt, Keyword.put(opts, :max_tokens, 1200)) do
      {:ok, response} ->
        test_code = extract_code_from_response(response.content)
        test_count = count_test_functions(test_code)

        {:ok,
         %{
           test_code: test_code,
           test_count: test_count,
           confidence: 0.84,
           provider: "openai",
           model: response.model,
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

  defp handle_explanation("lang.think.explain_intent", params, opts) do
    prompt = """
    Analyze this code and explain what it's trying to accomplish. Focus on the main intent and purpose.

    Code:
    ```
    #{params.content}
    ```

    Provide a clear, concise explanation of:
    1. The primary purpose of this code
    2. What problem it's solving
    3. Key functional aspects
    """

    completion_request(prompt, opts)
  end

  defp handle_explanation("lang.think.explain_why", params, opts) do
    prompt = """
    Analyze this code and explain WHY it exists from a business/architectural perspective.

    Code:
    ```
    #{params.content}
    ```

    Explain:
    1. What business need this addresses
    2. Why this approach was chosen
    3. How it fits into the larger system
    """

    completion_request(prompt, opts)
  end

  defp handle_explanation("lang.think.explain_how", params, opts) do
    prompt = """
    Provide a step-by-step explanation of HOW this code works.

    Code:
    ```
    #{params.content}
    ```

    Break down:
    1. Execution flow step by step
    2. Key data transformations
    3. Decision points and branches
    4. Expected inputs and outputs
    """

    completion_request(prompt, opts)
  end

  defp handle_flow_tracing(params, opts) do
    prompt = """
    Trace the data and control flow starting from: #{params.starting_point}

    Context: #{inspect(params.context)}

    Provide:
    1. Step-by-step flow analysis
    2. Key data transformations at each step
    3. Decision points and branches
    4. Potential failure points
    5. Dependencies and side effects

    Format as a clear flow diagram with explanations.
    """

    completion_request(prompt, opts)
  end

  defp handle_generation("lang.generate.from_spec", params, opts) do
    prompt = """
    Generate working code from this specification:

    #{params.specification}

    Requirements:
    - Generate complete, functional code
    - Include error handling where appropriate
    - Add clear comments explaining key sections
    - Follow best practices for the target language
    - Ensure code is production-ready

    #{if params.language, do: "Target language: #{params.language}", else: ""}
    #{if params.framework, do: "Framework: #{params.framework}", else: ""}
    """

    completion_request(prompt, Keyword.put(opts, :model, @generation_model))
  end

  defp handle_generation("lang.generate.from_tests", params, opts) do
    prompt = """
    Generate implementation code that passes these tests:

    Tests:
    ```
    #{params.tests}
    ```

    Generate:
    1. Complete implementation that satisfies all tests
    2. Appropriate error handling
    3. Clear documentation
    4. Efficient, clean code

    #{if params.language, do: "Language: #{params.language}", else: ""}
    """

    completion_request(prompt, Keyword.put(opts, :model, @generation_model))
  end

  defp handle_generation("lang.generate.dockerfile", params, opts) do
    prompt = """
    Generate an optimized Dockerfile for this project:

    Project context: #{params.project_context || "General application"}
    #{if params.language, do: "Primary language: #{params.language}", else: ""}
    #{if params.dependencies, do: "Dependencies: #{inspect(params.dependencies)}", else: ""}

    Generate:
    1. Multi-stage Dockerfile for optimization
    2. Proper caching layers
    3. Security best practices
    4. Minimal final image size
    5. Clear comments explaining each section
    """

    completion_request(prompt, opts)
  end

  defp handle_natural_query(params, opts) do
    prompt = """
    Answer this natural language query about the codebase:

    Query: #{params.query}

    #{if params.context, do: "Context: #{params.context}", else: ""}
    #{if params.scope, do: "Scope: #{params.scope}", else: ""}

    Provide:
    1. Direct answer to the question
    2. Relevant code locations if applicable
    3. Explanation of findings
    4. Confidence level in the answer
    """

    completion_request(prompt, opts)
  end

  # =============================================================================
  # OpenAI API Integration
  # =============================================================================

  defp completion_request(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 2000)

    payload = %{
      model: model,
      messages: [
        %{role: "user", content: prompt}
      ],
      temperature: temperature,
      max_tokens: max_tokens
    }

    case make_request("/chat/completions", payload) do
      {:ok, response} ->
        parse_completion_response(response)

      {:error, error} ->
        {:error, "OpenAI completion failed: #{inspect(error)}"}
    end
  end

  defp simple_completion(prompt, opts \\ []) do
    case completion_request(prompt, opts) do
      {:ok, %{content: content}} -> {:ok, content}
      {:error, error} -> {:error, error}
    end
  end

  defp make_request(endpoint, payload) do
    url = @base_url <> endpoint
    headers = request_headers()
    body = Jason.encode!(payload)

    Logger.debug("OpenAI request to #{endpoint}", payload: sanitize_payload(payload))

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response_body}} ->
        Logger.debug("OpenAI response success")
        {:ok, response_body}

      {:ok, %{status: status, body: error_body}} ->
        Logger.warning("OpenAI API error", status: status, error: error_body)
        {:error, %{status: status, body: error_body}}

      {:error, reason} ->
        Logger.error("OpenAI request failed", reason: reason)
        {:error, reason}
    end
  end

  defp request_headers do
    api_key = get_api_key()

    [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"User-Agent", "LANG-LSP/1.0"}
    ]
  end

  defp get_api_key do
    case Application.get_env(:lang, :ai_providers)[:openai_api_key] do
      nil ->
        raise "OPENAI_API_KEY not configured in :lang, :ai_providers"

      key ->
        key
    end
  end

  # =============================================================================
  # Response Parsing
  # =============================================================================

  defp parse_completion_response(response) do
    case get_in(response, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        {:error, "Invalid response format from OpenAI"}

      content ->
        {:ok,
         %{
           content: String.trim(content),
           model: response["model"],
           usage: response["usage"],
           finish_reason: get_in(response, ["choices", Access.at(0), "finish_reason"])
         }}
    end
  end

  # =============================================================================
  # Utilities
  # =============================================================================

  defp estimate_tokens(method, params) do
    content_length =
      case params do
        %{content: content} when is_binary(content) -> String.length(content)
        # Generation needs more context
        %{specification: spec} when is_binary(spec) -> String.length(spec) * 2
        %{tests: tests} when is_binary(tests) -> String.length(tests) * 2
        # Queries need more processing
        %{query: query} when is_binary(query) -> String.length(query) * 3
        _ -> 1000
      end

    base_overhead =
      case method do
        <<"lang.generate", _::binary>> -> 800
        _ -> 400
      end

    # GPT tokens: roughly 4 chars per token
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
      temperature: 0.3,
      messages: [
        %{
          role: "system",
          content:
            "You are a code completion assistant. Provide only the code to complete, without explanations."
        },
        %{
          role: "user",
          content: prompt
        }
      ],
      max_tokens: Keyword.get(opts, :max_tokens, 150),
      n: Keyword.get(opts, :n, 3),
      stop: Keyword.get(opts, :stop_sequences, ["\n\n", "```"])
    }

    case make_request("/chat/completions", payload) do
      {:ok, %{"choices" => choices}} ->
        completions =
          Enum.map(choices, fn choice ->
            %{
              text: get_in(choice, ["message", "content"]) || "",
              label: String.slice(get_in(choice, ["message", "content"]) || "", 0..50),
              kind: 1
            }
          end)

        {:ok, completions}

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
      temperature: 0.2,
      messages: [
        %{
          role: "system",
          content: "You are a helpful code documentation assistant. Be concise and informative."
        },
        %{
          role: "user",
          content: prompt
        }
      ],
      max_tokens: Keyword.get(opts, :max_tokens, 200)
    }

    case make_request("/chat/completions", payload) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}

      {:error, error} ->
        {:error, "Query failed: #{inspect(error)}"}
    end
  end

  @doc """
  Handle code analysis requests
  """
  def analyze(prompt, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @generation_model),
      temperature: 0.4,
      messages: [
        %{
          role: "system",
          content: "You are an expert code analyst. Provide detailed, educational explanations."
        },
        %{
          role: "user",
          content: prompt
        }
      ],
      max_tokens: Keyword.get(opts, :max_tokens, 1000)
    }

    case make_request("/chat/completions", payload) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}

      {:error, error} ->
        {:error, "Analysis failed: #{inspect(error)}"}
    end
  end

  @doc """
  Handle code generation requests
  """
  def generate(prompt, opts \\ []) do
    payload = %{
      model: Keyword.get(opts, :model, @generation_model),
      temperature: 0.5,
      messages: [
        %{
          role: "system",
          content:
            "You are an expert code generator. Generate clean, idiomatic code that follows best practices."
        },
        %{
          role: "user",
          content: prompt
        }
      ],
      max_tokens: Keyword.get(opts, :max_tokens, 2000)
    }

    case make_request("/chat/completions", payload) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}

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
          if String.length(content) > 200 do
            String.slice(content, 0, 200) <> "... (truncated)"
          else
            content
          end
        end)
      end)
    end)
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp extract_code_from_response(content) do
    case Regex.run(~r/```[a-zA-Z]*\n(.*?)\n```/s, content) do
      [_, code] -> String.trim(code)
      nil -> content
    end
  end

  defp extract_changes_summary(content) do
    lines = String.split(content, "\n")

    summary_lines =
      lines
      |> Enum.filter(fn line ->
        String.contains?(String.downcase(line), ["change", "improvement", "refactor", "benefit"])
      end)
      |> Enum.take(3)

    case summary_lines do
      [] -> "Code refactored with improvements"
      lines -> Enum.join(lines, " ")
    end
  end

  defp count_test_functions(test_code) do
    test_patterns = [
      ~r/test\s+["\w]/,
      ~r/it\s*\(/,
      ~r/describe\s*\(/,
      ~r/def test_/,
      ~r/func Test/,
      ~r/@Test/
    ]

    count =
      Enum.reduce(test_patterns, 0, fn pattern, acc ->
        matches = Regex.scan(pattern, test_code)
        acc + length(matches)
      end)

    max(1, count)
  end
end
