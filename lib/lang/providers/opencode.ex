defmodule Lang.Providers.OpenCode do
  @moduledoc """
  OpenCode Agents - Self-hosted provider for testing without API costs.

  This provider simulates AI responses locally for development and testing:
  - No external API calls or costs
  - Realistic response patterns and timing
  - Configurable behavior for different test scenarios
  - Full LSP method support for code analysis
  """

  require Logger

  @behaviour Lang.Providers.Provider

  @default_model "opencode-dev"
  @base_delay_ms 100
  @max_delay_ms 500

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
        "lang.query.simple",
        "lang.think.explain_intent",
        "lang.think.find_semantic",
        "lang.think.security_analysis",
        "lang.think.diagnose_issue",
        "lang.think.predict_outcome",
        "lang.generate.code",
        "lang.generate.documentation",
        "lang.fs.explain_structure"
      ],
      strengths: [:cost_effective, :fast_response, :consistent, :testing],
      weaknesses: [:simulated_responses, :limited_reasoning],
      cost_tier: :cheap,
      speed_tier: :fast,
      quality_tier: :basic,
      specializations: [:testing, :development, :cost_optimization],
      models: [@default_model],
      max_context_length: 50_000,
      supports_functions: true,
      supports_vision: false
    }
  end

  @impl Lang.Providers.Provider
  def pricing do
    %{
      # Effectively free
      input_tokens_per_dollar: 1_000_000,
      output_tokens_per_dollar: 1_000_000,
      base_cost_per_request: 0.0,
      bulk_discount_threshold: 0
    }
  end

  @impl Lang.Providers.Provider
  def available? do
    # Always available - no API key required
    true
  end

  @impl Lang.Providers.Provider
  def handle_request(method, params, opts \\ []) do
    # Simulate processing delay
    simulate_processing_delay()

    case method do
      "completion" -> handle_completion(params, opts)
      "hover" -> handle_hover(params, opts)
      "explain" -> handle_explain(params, opts)
      "refactor" -> handle_refactor(params, opts)
      "generate_tests" -> handle_generate_tests(params, opts)
      "lang.query.simple" -> handle_simple_query(params, opts)
      "lang.think." <> think_type -> handle_think_method(think_type, params, opts)
      "lang.generate." <> gen_type -> handle_generate_method(gen_type, params, opts)
      "lang.fs.explain_structure" -> handle_explain_structure(params, opts)
      _ -> {:error, "Method #{method} not supported by OpenCode provider"}
    end
  end

  @impl Lang.Providers.Provider
  def estimate_cost(_method, params) do
    estimated_tokens = estimate_tokens(params)

    {:ok,
     %{
       estimated_tokens: estimated_tokens,
       # Free for self-hosted
       estimated_cost_usd: 0.0
     }}
  end

  @impl Lang.Providers.Provider
  def health_check do
    {:ok, "OpenCode Agents running locally - #{DateTime.utc_now() |> DateTime.to_string()}"}
  end

  # =============================================================================
  # LSP Method Handlers
  # =============================================================================

  defp handle_completion(params, _opts) do
    prefix = Map.get(params, :prefix, "")
    language = Map.get(params, :language, "text")
    context = Map.get(params, :context, "")

    completion = generate_completion(prefix, language, context)
    quality_score = calculate_quality_score(:completion, language)

    {:ok,
     %{
       completion: completion,
       confidence: quality_score,
       provider: "opencode",
       model: @default_model,
       metadata: %{
         language: language,
         completion_length: String.length(completion),
         context_used: String.length(context) > 0
       }
     }}
  end

  defp handle_hover(params, _opts) do
    symbol = Map.get(params, :symbol, "unknown")
    language = Map.get(params, :language, "text")
    context = Map.get(params, :context, "")

    hover_info = generate_hover_info(symbol, language, context)
    quality_score = calculate_quality_score(:hover, language)

    {:ok,
     %{
       hover_content: hover_info,
       confidence: quality_score,
       provider: "opencode",
       model: @default_model,
       metadata: %{
         symbol: symbol,
         language: language,
         info_length: String.length(hover_info)
       }
     }}
  end

  defp handle_explain(params, _opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    question = Map.get(params, :question, "What does this code do?")

    explanation = generate_explanation(code, language, question)
    quality_score = calculate_quality_score(:explain, language)

    {:ok,
     %{
       explanation: explanation,
       confidence: quality_score,
       provider: "opencode",
       model: @default_model,
       metadata: %{
         language: language,
         code_length: String.length(code),
         question: question
       }
     }}
  end

  defp handle_refactor(params, _opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    goal = Map.get(params, :goal, "improve readability")

    refactored_code = generate_refactored_code(code, language, goal)
    quality_score = calculate_quality_score(:refactor, language)

    {:ok,
     %{
       refactored_code: refactored_code,
       changes_summary: "Simulated refactoring for #{goal}",
       confidence: quality_score,
       provider: "opencode",
       model: @default_model,
       metadata: %{
         language: language,
         original_length: String.length(code),
         refactored_length: String.length(refactored_code),
         goal: goal
       }
     }}
  end

  defp handle_generate_tests(params, _opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    test_framework = Map.get(params, :framework, "auto")

    tests = generate_test_code(code, language, test_framework)
    quality_score = calculate_quality_score(:generate_tests, language)

    {:ok,
     %{
       test_code: tests,
       test_count: count_generated_tests(tests),
       confidence: quality_score,
       provider: "opencode",
       model: @default_model,
       metadata: %{
         language: language,
         framework: test_framework,
         original_code_length: String.length(code)
       }
     }}
  end

  # =============================================================================
  # Think Method Handlers
  # =============================================================================

  defp handle_think_method("explain_intent", params, _opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")

    intent = generate_intent_explanation(code, language)

    {:ok,
     %{
       intent: intent,
       confidence: 0.75,
       reasoning_steps: ["Analyzed code structure", "Identified patterns", "Inferred purpose"],
       provider: "opencode"
     }}
  end

  defp handle_think_method("find_semantic", params, _opts) do
    query = Map.get(params, :query, "")
    context = Map.get(params, :context, "")

    matches = generate_semantic_matches(query, context)

    {:ok,
     %{
       matches: matches,
       confidence: 0.70,
       search_method: "simulated_semantic_search",
       provider: "opencode"
     }}
  end

  defp handle_think_method("security_analysis", params, _opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")

    analysis = generate_security_analysis(code, language)

    {:ok,
     %{
       security_issues: analysis.issues,
       severity_scores: analysis.severities,
       recommendations: analysis.recommendations,
       confidence: 0.65,
       provider: "opencode"
     }}
  end

  defp handle_think_method("diagnose_issue", params, _opts) do
    error_message = Map.get(params, :error, "")
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")

    diagnosis = generate_issue_diagnosis(error_message, code, language)

    {:ok,
     %{
       diagnosis: diagnosis.explanation,
       likely_causes: diagnosis.causes,
       suggested_fixes: diagnosis.fixes,
       confidence: 0.68,
       provider: "opencode"
     }}
  end

  defp handle_think_method(think_type, _params, _opts) do
    {:ok,
     %{
       result: "Simulated #{think_type} analysis",
       confidence: 0.60,
       provider: "opencode",
       note: "This is a simulated response for testing purposes"
     }}
  end

  # =============================================================================
  # Generate Method Handlers
  # =============================================================================

  defp handle_generate_method("code", params, _opts) do
    description = Map.get(params, :description, "")
    language = Map.get(params, :language, "text")

    generated_code = generate_code_from_description(description, language)

    {:ok,
     %{
       generated_code: generated_code,
       language: language,
       confidence: 0.72,
       provider: "opencode",
       metadata: %{
         description_length: String.length(description),
         generated_length: String.length(generated_code)
       }
     }}
  end

  defp handle_generate_method("documentation", params, _opts) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")
    format = Map.get(params, :format, "markdown")

    documentation = generate_documentation(code, language, format)

    {:ok,
     %{
       documentation: documentation,
       format: format,
       confidence: 0.74,
       provider: "opencode"
     }}
  end

  defp handle_generate_method(gen_type, _params, _opts) do
    {:ok,
     %{
       result: "Simulated #{gen_type} generation",
       confidence: 0.60,
       provider: "opencode",
       note: "This is a simulated response for testing purposes"
     }}
  end

  # =============================================================================
  # Other Handlers
  # =============================================================================

  defp handle_simple_query(params, _opts) do
    query = Map.get(params, :query, "")

    answer = generate_simple_answer(query)

    {:ok,
     %{
       answer: answer,
       confidence: 0.70,
       provider: "opencode",
       query_type: "simple"
     }}
  end

  defp handle_explain_structure(params, _opts) do
    file_tree = Map.get(params, :file_tree, [])
    focus = Map.get(params, :focus, "general")

    explanation = generate_structure_explanation(file_tree, focus)

    {:ok,
     %{
       explanation: explanation,
       structure_type: detect_project_type(file_tree),
       confidence: 0.76,
       provider: "opencode"
     }}
  end

  # =============================================================================
  # Response Generation Logic
  # =============================================================================

  defp generate_completion(prefix, language, _context) do
    trimmed_prefix = String.trim(prefix)

    case language do
      "elixir" ->
        cond do
          String.ends_with?(trimmed_prefix, "def ") ->
            "#{random_function_name()}(#{random_params()}) do\n  #{random_elixir_body()}\nend"

          String.contains?(trimmed_prefix, "=") ->
            random_elixir_value()

          true ->
            generate_generic_completion(prefix, language)
        end

      "javascript" ->
        if String.ends_with?(trimmed_prefix, "function ") do
          "#{random_function_name()}(#{random_js_params()}) {\n  return #{random_js_value()};\n}"
        else
          generate_generic_completion(prefix, language)
        end

      "python" ->
        if String.ends_with?(trimmed_prefix, "def ") do
          "#{random_function_name()}(#{random_params()}):\n    return #{random_python_value()}"
        else
          generate_generic_completion(prefix, language)
        end

      _ ->
        generate_generic_completion(prefix, language)
    end
  end

  defp generate_hover_info(symbol, language, _context) do
    """
    **#{symbol}** (#{language})

    Simulated hover information for `#{symbol}`.

    **Type:** #{random_type(language)}
    **Defined in:** #{random_file_location()}
    **Description:** This is a simulated hover response showing information about the symbol.
    """
  end

  defp generate_explanation(code, language, question) do
    code_length = String.length(code)

    """
    ## Code Explanation (#{language})

    **Question:** #{question}

    This #{language} code (#{code_length} characters) appears to:

    1. **Structure:** Contains #{random_code_elements()} typical of #{language} code
    2. **Purpose:** Based on the patterns, this likely handles #{random_purpose()}
    3. **Complexity:** #{assess_complexity(code_length)}

    **Key observations:**
    - Uses #{language}-specific syntax and conventions
    - Follows typical patterns for this language
    - Could be optimized for #{random_optimization_area()}

    *Note: This is a simulated explanation for testing purposes.*
    """
  end

  defp generate_refactored_code(code, language, goal) do
    # Simple simulation - add comments and clean up spacing
    lines = String.split(code, "\n")

    refactored_lines =
      lines
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn line ->
        if :rand.uniform() > 0.7 do
          "#{line}  // Refactored for #{goal}"
        else
          line
        end
      end)

    "// Refactored code (#{goal})\n" <> Enum.join(refactored_lines, "\n")
  end

  defp generate_test_code(code, language, framework) do
    function_name = extract_or_generate_function_name(code)

    case language do
      "elixir" ->
        """
        # Generated tests for #{function_name}
        defmodule #{String.capitalize(function_name)}Test do
          use ExUnit.Case

          test "#{function_name} returns expected result" do
            result = #{function_name}()
            assert result != nil
          end

          test "#{function_name} handles edge cases" do
            # Test edge case scenarios
            assert #{function_name}() == expected_value
          end
        end
        """

      "javascript" ->
        framework_name = if framework == "auto", do: "jest", else: framework

        """
        // Generated tests for #{function_name} using #{framework_name}
        describe('#{function_name}', () => {
          test('returns expected result', () => {
            const result = #{function_name}();
            expect(result).toBeDefined();
          });

          test('handles edge cases', () => {
            expect(#{function_name}()).toEqual(expectedValue);
          });
        });
        """

      _ ->
        """
        # Generated test code for #{function_name}
        # Framework: #{framework}
        # Language: #{language}

        def test_#{function_name}():
            result = #{function_name}()
            assert result is not None
        """
    end
  end

  defp generate_intent_explanation(code, language) do
    """
    Based on analysis of this #{language} code, the intent appears to be:

    **Primary Purpose:** #{random_intent_purpose()}

    **Implementation Approach:**
    - Uses #{random_pattern()} pattern
    - Handles #{random_data_type()} data
    - Implements #{random_functionality()}

    **Design Decisions:**
    - Prioritizes #{random_priority()} over #{random_alternative()}
    - Follows #{language} best practices
    - Designed for #{random_use_case()} use cases

    *Confidence: 75% (simulated analysis)*
    """
  end

  defp generate_semantic_matches(query, _context) do
    # Simulate finding related concepts
    base_matches = [
      %{match: "#{query}_handler", score: 0.92, type: "function"},
      %{match: "#{query}_config", score: 0.87, type: "variable"},
      %{match: "process_#{query}", score: 0.84, type: "function"},
      %{match: "#{query}_result", score: 0.81, type: "struct"}
    ]

    # Add some randomization
    Enum.take_random(base_matches, :rand.uniform(4))
  end

  defp generate_security_analysis(code, language) do
    issues = generate_mock_security_issues(code, language)

    %{
      issues: issues,
      severities:
        Enum.map(issues, fn issue -> %{issue: issue.type, severity: issue.severity} end),
      recommendations: [
        "Validate all user inputs",
        "Use parameterized queries",
        "Implement proper error handling",
        "Add rate limiting where appropriate"
      ]
    }
  end

  defp generate_issue_diagnosis(error_message, code, language) do
    %{
      explanation: """
      Based on the error "#{String.slice(error_message, 0, 100)}..." in #{language} code:

      This appears to be a #{random_error_category()} error commonly seen in #{language} applications.
      """,
      causes: [
        "Potential #{random_error_cause()}",
        "Missing #{random_missing_element()}",
        "Incorrect #{random_incorrect_element()}"
      ],
      fixes: [
        "Check #{random_check_suggestion()}",
        "Verify #{random_verification_step()}",
        "Update #{random_update_suggestion()}"
      ]
    }
  end

  defp generate_code_from_description(description, language) do
    case language do
      "elixir" ->
        """
        # Generated from: #{String.slice(description, 0, 50)}...
        defmodule GeneratedModule do
          def generated_function do
            # Implementation based on description
            :ok
          end
        end
        """

      "javascript" ->
        """
        // Generated from: #{String.slice(description, 0, 50)}...
        function generatedFunction() {
          // Implementation based on description
          return true;
        }
        """

      _ ->
        """
        # Generated code for: #{String.slice(description, 0, 50)}...
        # Language: #{language}
        def generated_function():
            # Implementation placeholder
            return None
        """
    end
  end

  defp generate_documentation(code, language, format) do
    case format do
      "markdown" ->
        """
        # Generated Documentation

        ## Overview
        This #{language} code provides functionality for the analyzed codebase.

        ## Usage
        ```#{language}
        #{String.slice(code, 0, 200)}#{if String.length(code) > 200, do: "...", else: ""}
        ```

        ## Parameters
        - Input parameters as required
        - Returns appropriate values

        *Generated by OpenCode Agents*
        """

      _ ->
        "Generated documentation in #{format} format for #{language} code."
    end
  end

  defp generate_simple_answer(query) do
    templates = [
      "Based on the query '#{query}', the answer involves #{random_concept()}.",
      "For '#{query}', you should consider #{random_approach()}.",
      "The solution to '#{query}' typically requires #{random_requirement()}."
    ]

    Enum.random(templates)
  end

  defp generate_structure_explanation(file_tree, focus) do
    file_count = length(file_tree)
    project_type = detect_project_type(file_tree)

    """
    ## Project Structure Analysis

    **Project Type:** #{project_type}
    **Files Analyzed:** #{file_count}
    **Focus:** #{focus}

    ### Structure Overview:
    - **Configuration:** Standard #{project_type} configuration files
    - **Source Code:** Organized following #{project_type} conventions
    - **Dependencies:** Appropriate for #{project_type} projects
    - **Documentation:** #{random_doc_status()}

    ### Recommendations:
    - Structure follows #{project_type} best practices
    - Consider #{random_improvement_suggestion()}
    - #{random_additional_advice()}

    *Analysis confidence: 76%*
    """
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp simulate_processing_delay do
    delay = @base_delay_ms + :rand.uniform(@max_delay_ms - @base_delay_ms)
    :timer.sleep(delay)
  end

  defp calculate_quality_score(method, language) do
    base_score =
      case method do
        :completion -> 0.75
        :hover -> 0.70
        :explain -> 0.68
        :refactor -> 0.65
        :generate_tests -> 0.72
        _ -> 0.60
      end

    language_bonus =
      case language do
        "elixir" -> 0.05
        "javascript" -> 0.03
        "python" -> 0.04
        _ -> 0.0
      end

    randomness = (:rand.uniform() - 0.5) * 0.1
    Float.round(base_score + language_bonus + randomness, 2)
  end

  defp estimate_tokens(params) do
    content_size =
      params
      |> Map.values()
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")
      |> String.length()

    # Rough estimation: ~4 characters per token
    max(50, div(content_size, 4))
  end

  defp count_generated_tests(test_code) do
    test_code
    |> String.split("\n")
    |> Enum.count(&(String.contains?(&1, "test") or String.contains?(&1, "it(")))
  end

  # Random data generators for realistic responses
  defp random_function_name,
    do:
      Enum.random([
        "process_data",
        "handle_request",
        "calculate_result",
        "validate_input",
        "format_response"
      ])

  defp random_params,
    do: Enum.random(["data", "opts", "params, opts", "input, config", "request"])

  defp random_js_params, do: Enum.random(["data", "options", "config", "params", "input"])

  defp random_elixir_body,
    do:
      Enum.random([
        "IO.puts(\"Processing...\")",
        "data |> process() |> format()",
        "{:ok, result}",
        "handle_case(data)"
      ])

  defp random_elixir_value,
    do: Enum.random([":ok", "%{status: :success}", "\"result\"", "42", "[]"])

  defp random_js_value, do: Enum.random(["true", "null", "[]", "{}", "42", "'result'"])
  defp random_python_value, do: Enum.random(["True", "None", "[]", "{}", "42", "'result'"])

  defp generate_generic_completion(prefix, language) do
    "// Completed for #{language}: #{String.slice(prefix, -20, 20)}..."
  end

  defp random_type(language) do
    case language do
      "elixir" -> Enum.random(["atom()", "string()", "list()", "map()", "pid()"])
      "javascript" -> Enum.random(["string", "number", "object", "function", "boolean"])
      "python" -> Enum.random(["str", "int", "list", "dict", "object"])
      _ -> "unknown"
    end
  end

  defp random_file_location,
    do:
      "#{Enum.random(["lib", "src", "app"])}/#{Enum.random(["module", "component", "service"])}.#{Enum.random(["ex", "js", "py"])}"

  defp random_code_elements,
    do:
      Enum.random([
        "functions and variables",
        "classes and methods",
        "modules and imports",
        "data structures"
      ])

  defp random_purpose,
    do:
      Enum.random([
        "data processing",
        "user interaction",
        "API communication",
        "business logic",
        "validation"
      ])

  defp assess_complexity(length) when length < 100, do: "Low complexity"
  defp assess_complexity(length) when length < 500, do: "Medium complexity"
  defp assess_complexity(_), do: "High complexity"

  defp random_optimization_area,
    do: Enum.random(["performance", "readability", "maintainability", "error handling"])

  defp extract_or_generate_function_name(code) do
    cond do
      String.contains?(code, "def ") ->
        code
        |> String.split("def ")
        |> Enum.at(1, "")
        |> String.split("(")
        |> hd()
        |> String.trim()

      String.contains?(code, "function ") ->
        code
        |> String.split("function ")
        |> Enum.at(1, "")
        |> String.split("(")
        |> hd()
        |> String.trim()

      true ->
        "test_function"
    end
  end

  defp random_intent_purpose,
    do:
      Enum.random([
        "data transformation",
        "user input validation",
        "API response handling",
        "business rule enforcement"
      ])

  defp random_pattern,
    do: Enum.random(["observer", "strategy", "factory", "pipeline", "middleware"])

  defp random_data_type,
    do: Enum.random(["structured", "unstructured", "streaming", "cached", "persisted"])

  defp random_functionality,
    do: Enum.random(["error handling", "logging", "caching", "validation", "transformation"])

  defp random_priority,
    do: Enum.random(["performance", "reliability", "maintainability", "security"])

  defp random_alternative, do: Enum.random(["simplicity", "flexibility", "speed", "memory usage"])

  defp random_use_case,
    do:
      Enum.random(["high-traffic", "batch processing", "real-time", "development", "production"])

  defp generate_mock_security_issues(code, _language) do
    potential_issues = [
      %{type: "input_validation", severity: "medium", line: :rand.uniform(20)},
      %{type: "sql_injection", severity: "high", line: :rand.uniform(20)},
      %{type: "xss_vulnerability", severity: "medium", line: :rand.uniform(20)},
      %{type: "hardcoded_secret", severity: "critical", line: :rand.uniform(20)}
    ]

    # Randomly select 1-3 issues based on code content
    issue_count = if String.length(code) > 200, do: :rand.uniform(3), else: 1
    Enum.take_random(potential_issues, issue_count)
  end

  defp random_error_category,
    do: Enum.random(["runtime", "syntax", "type", "logic", "configuration"])

  defp random_error_cause,
    do:
      Enum.random([
        "null reference",
        "type mismatch",
        "missing dependency",
        "configuration issue"
      ])

  defp random_missing_element,
    do:
      Enum.random([
        "import statement",
        "variable declaration",
        "error handling",
        "type annotation"
      ])

  defp random_incorrect_element,
    do: Enum.random(["function signature", "variable scope", "data type", "API usage"])

  defp random_check_suggestion,
    do:
      Enum.random([
        "variable initialization",
        "function parameters",
        "return types",
        "error conditions"
      ])

  defp random_verification_step,
    do:
      Enum.random([
        "dependency versions",
        "configuration values",
        "environment variables",
        "file permissions"
      ])

  defp random_update_suggestion,
    do:
      Enum.random([
        "error handling logic",
        "type definitions",
        "import statements",
        "configuration files"
      ])

  defp random_concept,
    do:
      Enum.random([
        "modular architecture",
        "data flow patterns",
        "error handling strategies",
        "performance optimization"
      ])

  defp random_approach,
    do:
      Enum.random([
        "breaking down the problem",
        "implementing step by step",
        "considering edge cases",
        "planning for scalability"
      ])

  defp random_requirement,
    do: Enum.random(["careful planning", "proper testing", "code review", "performance analysis"])

  defp detect_project_type(file_tree) do
    files = Enum.map(file_tree, &to_string/1)

    cond do
      Enum.any?(files, &String.contains?(&1, "mix.exs")) -> "Elixir/Phoenix"
      Enum.any?(files, &String.contains?(&1, "package.json")) -> "Node.js/JavaScript"
      Enum.any?(files, &String.contains?(&1, "requirements.txt")) -> "Python"
      Enum.any?(files, &String.contains?(&1, "Cargo.toml")) -> "Rust"
      true -> "Generic"
    end
  end

  defp random_doc_status,
    do: Enum.random(["Well documented", "Partially documented", "Needs more documentation"])

  defp random_improvement_suggestion,
    do:
      Enum.random([
        "adding more tests",
        "improving documentation",
        "extracting common utilities",
        "optimizing imports"
      ])

  defp random_additional_advice,
    do:
      Enum.random([
        "Monitor code complexity",
        "Consider dependency updates",
        "Review security practices",
        "Optimize build process"
      ])
end
