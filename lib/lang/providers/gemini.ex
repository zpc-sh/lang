defmodule Lang.Providers.Gemini do
  @moduledoc """
  Google Gemini provider for LANG LSP system.

  Specializes in:
  - Multimodal analysis (text, code, images)
  - Fast reasoning and generation
  - Code understanding and optimization
  - Large context window processing
  """

  @behaviour Lang.Providers.Provider
  require Logger

  @base_url "https://generativelanguage.googleapis.com/v1beta"
  @default_model "gemini-1.5-pro"
  @flash_model "gemini-1.5-flash"
  @pro_model "gemini-1.5-pro"

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
        "lang.think.analyze_performance",
        "lang.think.explain_architecture",
        "lang.think.find_patterns",
        "lang.generate.optimize",
        "lang.generate.documentation",
        "lang.query.multimodal",
        "lang.analyze.large_context"
      ],
      strengths: [
        :multimodal,
        :fast_reasoning,
        :large_context,
        :code_optimization,
        :pattern_recognition
      ],
      weaknesses: [:newer_model, :api_stability],
      cost_tier: :medium,
      speed_tier: :fast,
      quality_tier: :excellent,
      specializations: [
        :multimodal,
        :optimization,
        :large_context,
        :pattern_analysis,
        :fast_generation
      ]
    }
  end

  @impl Lang.Providers.Provider
  def pricing do
    %{
      # Gemini is competitively priced
      input_tokens_per_dollar: 1000,
      output_tokens_per_dollar: 800,
      base_cost_per_request: 0.002,
      bulk_discount_threshold: 100_000
    }
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

      "lang.think.analyze_performance" ->
        handle_performance_analysis(params, opts)

      "lang.think.explain_architecture" ->
        handle_architecture_explanation(params, opts)

      "lang.think.find_patterns" ->
        handle_pattern_finding(params, opts)

      "lang.generate.optimize" ->
        handle_optimization(params, opts)

      "lang.generate.documentation" ->
        handle_documentation_generation(params, opts)

      "lang.query.multimodal" ->
        handle_multimodal_query(params, opts)

      "lang.analyze.large_context" ->
        handle_large_context_analysis(params, opts)

      _ ->
        {:error, "Method #{method} not supported by Gemini provider"}
    end
  end

  @impl Lang.Providers.Provider
  def estimate_cost(method, params) do
    estimated_tokens = estimate_tokens(method, params)

    # Gemini pricing varies by model
    model = get_model_for_method(method)
    {input_cost, output_cost} = get_model_pricing(model)

    # Assume 70% input, 30% output
    estimated_input_cost = estimated_tokens * 0.7 * input_cost
    estimated_output_cost = estimated_tokens * 0.3 * output_cost
    total_cost = estimated_input_cost + estimated_output_cost

    {:ok,
     %{
       estimated_tokens: estimated_tokens,
       estimated_cost_usd: total_cost,
       model: model
     }}
  end

  @impl Lang.Providers.Provider
  def health_check do
    case simple_generation("Respond with 'GEMINI_HEALTHY' if you can process this.") do
      {:ok, response} ->
        if String.contains?(response, "GEMINI_HEALTHY") do
          {:ok, "Google Gemini connection healthy"}
        else
          {:warning, "Gemini responding but unexpected format: #{response}"}
        end

      {:error, error} ->
        {:error, "Gemini health check failed: #{inspect(error)}"}
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
    Complete this #{language} code efficiently and idiomatically:

    ```#{language}
    #{prefix}
    ```

    #{if String.length(context) > 0, do: "Context: #{context}", else: ""}

    Provide only the completion, no explanations.
    """

    case generate_content(prompt, Keyword.put(opts, :model, @flash_model)) do
      {:ok, response} ->
        completion = extract_text_from_response(response)

        {:ok,
         %{
           completion: String.trim(completion),
           confidence: 0.87,
           provider: "gemini",
           model: @flash_model,
           metadata: %{
             language: language,
             completion_length: String.length(completion),
             context_used: String.length(context) > 0,
             response_time_ms: Map.get(response, :response_time, 0)
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
    Provide concise hover information for `#{symbol}` in #{language}:

    #{if String.length(context) > 0, do: "Context:\n```#{language}\n#{context}\n```\n", else: ""}

    Include:
    - Type/signature
    - Brief purpose
    - Usage notes

    Format as markdown.
    """

    case generate_content(prompt, Keyword.put(opts, :model, @flash_model)) do
      {:ok, response} ->
        hover_content = extract_text_from_response(response)

        {:ok,
         %{
           hover_content: hover_content,
           confidence: 0.84,
           provider: "gemini",
           model: @flash_model,
           metadata: %{
             symbol: symbol,
             language: language,
             info_length: String.length(hover_content)
           }
         }}

      {:error, error} ->
        {:error, "Hover failed: #{inspect(error)}"}
    end
  end

  defp handle_explain(params, opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    question = Map.get(params, :question, "Explain this code")

    prompt = """
    #{question}

    #{language} code:
    ```#{language}
    #{code}
    ```

    Provide a clear explanation covering:
    1. Purpose and functionality
    2. Implementation approach
    3. Key concepts and patterns
    4. Performance considerations
    5. Potential improvements
    """

    case generate_content(prompt, opts) do
      {:ok, response} ->
        explanation = extract_text_from_response(response)

        {:ok,
         %{
           explanation: explanation,
           confidence: 0.89,
           provider: "gemini",
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
    Refactor this #{language} code to #{goal}:

    ```#{language}
    #{code}
    ```

    Provide:
    1. Refactored code with improvements
    2. List of specific changes made
    3. Benefits achieved

    Focus on: performance, readability, maintainability, and best practices.
    """

    case generate_content(prompt, opts) do
      {:ok, response} ->
        response_text = extract_text_from_response(response)
        refactored_code = extract_code_block(response_text)
        changes_summary = extract_changes_from_response(response_text)

        {:ok,
         %{
           refactored_code: refactored_code,
           changes_summary: changes_summary,
           confidence: 0.86,
           provider: "gemini",
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
    Generate comprehensive tests for this #{language} code:

    ```#{language}
    #{code}
    ```

    #{if framework != "auto", do: "Use #{framework} framework.", else: "Use standard #{language} testing framework."}

    Include:
    1. Unit tests for core functionality
    2. Edge case testing
    3. Error condition handling
    4. Integration tests if applicable
    5. Clear test descriptions

    Generate complete, executable test code.
    """

    case generate_content(prompt, opts) do
      {:ok, response} ->
        response_text = extract_text_from_response(response)
        test_code = extract_code_block(response_text)
        test_count = count_test_cases(test_code)

        {:ok,
         %{
           test_code: test_code,
           test_count: test_count,
           confidence: 0.85,
           provider: "gemini",
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
  # Specialized Method Handlers
  # =============================================================================

  defp handle_performance_analysis(params, opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")

    prompt = """
    Analyze the performance characteristics of this #{language} code:

    ```#{language}
    #{code}
    ```

    Provide detailed analysis:
    1. **Time Complexity**: Big O analysis for main operations
    2. **Space Complexity**: Memory usage patterns
    3. **Bottlenecks**: Identify performance bottlenecks
    4. **Optimizations**: Specific improvement suggestions
    5. **Scalability**: How it performs under load
    6. **Resource Usage**: CPU, memory, I/O patterns

    Include concrete optimization recommendations.
    """

    case generate_content(prompt, Keyword.put(opts, :model, @pro_model)) do
      {:ok, response} ->
        analysis = extract_text_from_response(response)

        {:ok,
         %{
           performance_analysis: analysis,
           confidence: 0.91,
           provider: "gemini",
           model: @pro_model,
           metadata: %{
             language: language,
             code_length: String.length(code),
             analysis_type: "performance"
           }
         }}

      {:error, error} ->
        {:error, "Performance analysis failed: #{inspect(error)}"}
    end
  end

  defp handle_architecture_explanation(params, opts) do
    codebase_info = Map.get(params, :codebase_info, "")
    focus_area = Map.get(params, :focus_area, "overall architecture")

    prompt = """
    Explain the software architecture focusing on #{focus_area}:

    Codebase Information:
    #{codebase_info}

    Provide comprehensive analysis:
    1. **Architecture Overview**: High-level design patterns
    2. **Component Relationships**: How modules interact
    3. **Data Flow**: Information movement through system
    4. **Design Patterns**: Identified architectural patterns
    5. **Strengths**: Well-designed aspects
    6. **Improvement Areas**: Architectural improvements
    7. **Scalability**: Architecture's growth potential

    Focus on clarity and actionable insights.
    """

    case generate_content(prompt, Keyword.put(opts, :model, @pro_model)) do
      {:ok, response} ->
        explanation = extract_text_from_response(response)

        {:ok,
         %{
           architecture_explanation: explanation,
           confidence: 0.88,
           provider: "gemini",
           model: @pro_model,
           metadata: %{
             focus_area: focus_area,
             info_length: String.length(codebase_info)
           }
         }}

      {:error, error} ->
        {:error, "Architecture explanation failed: #{inspect(error)}"}
    end
  end

  defp handle_pattern_finding(params, opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    pattern_type = Map.get(params, :pattern_type, "all")

    prompt = """
    Identify #{pattern_type} patterns in this #{language} code:

    ```#{language}
    #{code}
    ```

    Look for:
    1. **Design Patterns**: GoF patterns, architectural patterns
    2. **Code Patterns**: Common coding idioms and practices
    3. **Anti-patterns**: Problematic patterns to avoid
    4. **Performance Patterns**: Optimization techniques used
    5. **Security Patterns**: Security-related implementations

    For each pattern found:
    - Name and type
    - Location in code
    - Purpose and benefits
    - Quality assessment
    - Improvement suggestions
    """

    case generate_content(prompt, opts) do
      {:ok, response} ->
        analysis = extract_text_from_response(response)
        patterns = extract_patterns_from_analysis(analysis)

        {:ok,
         %{
           patterns_found: patterns,
           detailed_analysis: analysis,
           confidence: 0.83,
           provider: "gemini",
           model: @default_model,
           metadata: %{
             language: language,
             pattern_type: pattern_type,
             code_length: String.length(code)
           }
         }}

      {:error, error} ->
        {:error, "Pattern finding failed: #{inspect(error)}"}
    end
  end

  defp handle_optimization(params, opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    optimization_target = Map.get(params, :target, "performance")

    prompt = """
    Optimize this #{language} code for #{optimization_target}:

    ```#{language}
    #{code}
    ```

    Provide:
    1. **Optimized Code**: Improved version
    2. **Optimization Techniques**: Methods used
    3. **Performance Impact**: Expected improvements
    4. **Trade-offs**: Any compromises made
    5. **Benchmarking**: How to measure improvements

    Focus on practical, measurable optimizations.
    """

    case generate_content(prompt, opts) do
      {:ok, response} ->
        response_text = extract_text_from_response(response)
        optimized_code = extract_code_block(response_text)
        optimization_notes = extract_optimization_details(response_text)

        {:ok,
         %{
           optimized_code: optimized_code,
           optimization_details: optimization_notes,
           confidence: 0.87,
           provider: "gemini",
           model: @default_model,
           metadata: %{
             language: language,
             optimization_target: optimization_target,
             original_length: String.length(code),
             optimized_length: String.length(optimized_code)
           }
         }}

      {:error, error} ->
        {:error, "Optimization failed: #{inspect(error)}"}
    end
  end

  defp handle_documentation_generation(params, opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    doc_type = Map.get(params, :type, "api")

    prompt = """
    Generate #{doc_type} documentation for this #{language} code:

    ```#{language}
    #{code}
    ```

    Create comprehensive documentation including:
    1. **Overview**: Purpose and functionality
    2. **API Documentation**: Functions, parameters, return values
    3. **Usage Examples**: Practical code examples
    4. **Configuration**: Setup and configuration options
    5. **Error Handling**: Exception scenarios
    6. **Performance Notes**: Usage considerations

    Format as clear, professional documentation.
    """

    case generate_content(prompt, opts) do
      {:ok, response} ->
        documentation = extract_text_from_response(response)

        {:ok,
         %{
           documentation: documentation,
           doc_type: doc_type,
           confidence: 0.88,
           provider: "gemini",
           model: @default_model,
           metadata: %{
             language: language,
             code_length: String.length(code),
             doc_length: String.length(documentation)
           }
         }}

      {:error, error} ->
        {:error, "Documentation generation failed: #{inspect(error)}"}
    end
  end

  defp handle_multimodal_query(params, opts) do
    query = Map.get(params, :query, "")
    images = Map.get(params, :images, [])
    code = Map.get(params, :code, "")

    prompt = """
    #{query}

    #{if String.length(code) > 0, do: "Code context:\n```\n#{code}\n```\n", else: ""}

    #{if length(images) > 0, do: "Analyze the provided images in context of the query.", else: ""}

    Provide a comprehensive response considering all provided context.
    """

    # Include images in the request if provided
    opts_with_images = if length(images) > 0, do: Keyword.put(opts, :images, images), else: opts

    case generate_content(prompt, opts_with_images) do
      {:ok, response} ->
        answer = extract_text_from_response(response)

        {:ok,
         %{
           answer: answer,
           confidence: 0.85,
           provider: "gemini",
           model: @pro_model,
           metadata: %{
             query_length: String.length(query),
             has_images: length(images) > 0,
             has_code: String.length(code) > 0,
             multimodal: true
           }
         }}

      {:error, error} ->
        {:error, "Multimodal query failed: #{inspect(error)}"}
    end
  end

  defp handle_large_context_analysis(params, opts) do
    content = Map.get(params, :content, "")
    analysis_type = Map.get(params, :analysis_type, "comprehensive")

    prompt = """
    Perform #{analysis_type} analysis of this large content:

    #{content}

    Provide detailed analysis including:
    1. **Summary**: Key points and themes
    2. **Structure**: Organization and flow
    3. **Patterns**: Recurring elements or themes
    4. **Insights**: Notable observations
    5. **Recommendations**: Actionable improvements

    Leverage the large context window to provide comprehensive analysis.
    """

    case generate_content(prompt, Keyword.put(opts, :model, @pro_model)) do
      {:ok, response} ->
        analysis = extract_text_from_response(response)

        {:ok,
         %{
           large_context_analysis: analysis,
           confidence: 0.89,
           provider: "gemini",
           model: @pro_model,
           metadata: %{
             content_length: String.length(content),
             analysis_type: analysis_type,
             tokens_processed: estimate_token_count(content)
           }
         }}

      {:error, error} ->
        {:error, "Large context analysis failed: #{inspect(error)}"}
    end
  end

  # =============================================================================
  # Gemini API Integration
  # =============================================================================

  defp generate_content(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_output_tokens = Keyword.get(opts, :max_tokens, 2048)
    images = Keyword.get(opts, :images, [])

    parts = build_content_parts(prompt, images)

    payload = %{
      contents: [
        %{
          parts: parts
        }
      ],
      generationConfig: %{
        temperature: temperature,
        maxOutputTokens: max_output_tokens,
        topP: 0.95,
        topK: 40
      }
    }

    case make_request("/models/#{model}:generateContent", payload, opts) do
      {:ok, response} ->
        parse_generation_response(response)

      {:error, error} ->
        {:error, "Generation failed: #{inspect(error)}"}
    end
  end

  defp simple_generation(prompt, opts \\ []) do
    case generate_content(prompt, opts) do
      {:ok, %{text: text}} -> {:ok, text}
      {:error, error} -> {:error, error}
    end
  end

  defp make_request(endpoint, payload, opts \\ []) do
    url = @base_url <> endpoint
    headers = request_headers(opts)
    body = Jason.encode!(payload)

    Logger.debug("Gemini request to #{endpoint}")

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response_body}} ->
        Logger.debug("Gemini response success")
        {:ok, response_body}

      {:ok, %{status: status, body: error_body}} ->
        Logger.warning("Gemini API error", status: status, error: error_body)
        {:error, %{status: status, body: error_body}}

      {:error, reason} ->
        Logger.error("Gemini request failed", reason: reason)
        {:error, reason}
    end
  end

  defp request_headers(opts \\ []) do
    api_key = get_api_key(opts)

    [
      {"Content-Type", "application/json"},
      {"x-goog-api-key", api_key},
      {"User-Agent", "LANG-LSP/1.0"}
    ]
  end

  defp get_api_key(opts \\ []) do
    case Lang.Providers.Credentials.resolve_api_key(:gemini, opts) do
      {:ok, key} -> key
      {:error, _} -> raise "GEMINI_API_KEY not configured for this request"
    end
  end

  # =============================================================================
  # Response Parsing
  # =============================================================================

  defp parse_generation_response(response) do
    case get_in(response, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"]) do
      nil ->
        {:error, "Invalid response format from Gemini"}

      text ->
        {:ok,
         %{
           text: String.trim(text),
           model: response["modelVersion"] || @default_model,
           usage: response["usageMetadata"],
           finish_reason: get_in(response, ["candidates", Access.at(0), "finishReason"])
         }}
    end
  end

  defp extract_text_from_response(response) do
    Map.get(response, :text, "")
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp build_content_parts(prompt, images) do
    text_part = %{text: prompt}

    if length(images) > 0 do
      image_parts =
        Enum.map(images, fn image_data ->
          %{
            inlineData: %{
              mimeType: "image/jpeg",
              data: image_data
            }
          }
        end)

      [text_part | image_parts]
    else
      [text_part]
    end
  end

  defp extract_code_block(content) do
    case Regex.run(~r/```[a-zA-Z]*\n(.*?)\n```/s, content) do
      [_, code] -> String.trim(code)
      nil -> content
    end
  end

  defp extract_changes_from_response(content) do
    lines = String.split(content, "\n")

    change_lines =
      lines
      |> Enum.filter(fn line ->
        String.contains?(String.downcase(line), [
          "change",
          "improvement",
          "benefit",
          "optimization"
        ])
      end)
      |> Enum.take(3)

    case change_lines do
      [] -> "Code optimized with improvements"
      lines -> Enum.join(lines, " ")
    end
  end

  defp extract_patterns_from_analysis(analysis) do
    # Extract pattern names from the analysis text
    patterns =
      analysis
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, "Pattern"))
      |> Enum.map(&String.trim/1)
      |> Enum.take(10)

    case patterns do
      [] -> ["Analysis completed - see detailed analysis"]
      patterns -> patterns
    end
  end

  defp extract_optimization_details(content) do
    lines = String.split(content, "\n")

    detail_lines =
      lines
      |> Enum.filter(fn line ->
        String.contains?(String.downcase(line), [
          "optimization",
          "improvement",
          "performance",
          "technique"
        ])
      end)
      |> Enum.take(5)

    case detail_lines do
      [] -> "Optimizations applied - see optimized code"
      lines -> Enum.join(lines, " ")
    end
  end

  defp count_test_cases(test_code) do
    test_patterns = [
      ~r/test\s+["\w]/,
      ~r/it\s*\(/,
      ~r/describe\s*\(/,
      ~r/def test_/,
      ~r/func Test/,
      ~r/@Test/,
      ~r/TEST\(/
    ]

    count =
      Enum.reduce(test_patterns, 0, fn pattern, acc ->
        matches = Regex.scan(pattern, test_code)
        acc + length(matches)
      end)

    max(1, count)
  end

  defp estimate_tokens(method, params) do
    base_content =
      params
      |> Map.values()
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")
      |> String.length()

    method_overhead =
      case method do
        "lang.analyze.large_context" -> 1000
        "lang.think.analyze_performance" -> 600
        "lang.generate.optimize" -> 500
        _ -> 200
      end

    # Gemini uses approximately 4 chars per token
    div(base_content, 4) + method_overhead
  end

  defp estimate_token_count(content) do
    div(String.length(content), 4)
  end

  defp get_model_for_method(method) do
    case method do
      "completion" -> @flash_model
      "hover" -> @flash_model
      "lang.think.analyze_performance" -> @pro_model
      "lang.think.explain_architecture" -> @pro_model
      "lang.query.multimodal" -> @pro_model
      "lang.analyze.large_context" -> @pro_model
      _ -> @default_model
    end
  end

  defp get_model_pricing(model) do
    case model do
      # Flash is cheaper
      @flash_model -> {0.000001, 0.000002}
      # Pro is more expensive
      @pro_model -> {0.000002, 0.000004}
      # Default pricing
      _ -> {0.0000015, 0.000003}
    end
  end
end
