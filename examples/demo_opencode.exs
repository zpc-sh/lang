#!/usr/bin/env elixir

# Demo script for OpenCode Agents - Self-hosted AI provider for testing
# This script demonstrates the OpenCode provider without requiring full application setup

defmodule Lang.Providers.Provider do
  @callback capabilities() :: map()
  @callback pricing() :: map()
  @callback available?() :: boolean()
  @callback handle_request(method :: String.t(), params :: map(), opts :: keyword()) ::
              {:ok, result :: map()} | {:error, reason :: any()}
  @callback estimate_cost(method :: String.t(), params :: map()) ::
              {:ok, %{estimated_tokens: integer(), estimated_cost_usd: float()}} | {:error, any()}
  @callback health_check() :: {:ok, String.t()} | {:error, any()}
end

defmodule Lang.Providers.OpenCode do
  @moduledoc """
  OpenCode Agents - Self-hosted provider for testing without API costs.
  """

  @behaviour Lang.Providers.Provider

  @default_model "opencode-dev"
  @base_delay_ms 100
  @max_delay_ms 500

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
        "lang.generate.code"
      ],
      strengths: [:cost_effective, :fast_response, :consistent, :testing],
      weaknesses: [:simulated_responses, :limited_reasoning],
      cost_tier: :cheap,
      speed_tier: :fast,
      quality_tier: :basic,
      specializations: [:testing, :development, :cost_optimization]
    }
  end

  @impl Lang.Providers.Provider
  def pricing do
    %{
      input_tokens_per_dollar: 1_000_000,
      output_tokens_per_dollar: 1_000_000,
      base_cost_per_request: 0.0,
      bulk_discount_threshold: 0
    }
  end

  @impl Lang.Providers.Provider
  def available?, do: true

  @impl Lang.Providers.Provider
  def handle_request(method, params, _opts \\ []) do
    simulate_processing_delay()

    case method do
      "completion" -> handle_completion(params)
      "hover" -> handle_hover(params)
      "explain" -> handle_explain(params)
      "refactor" -> handle_refactor(params)
      "generate_tests" -> handle_generate_tests(params)
      "lang.query.simple" -> handle_simple_query(params)
      "lang.think.explain_intent" -> handle_explain_intent(params)
      "lang.think.security_analysis" -> handle_security_analysis(params)
      "lang.generate.code" -> handle_generate_code(params)
      _ -> {:error, "Method #{method} not supported by OpenCode provider"}
    end
  end

  @impl Lang.Providers.Provider
  def estimate_cost(_method, params) do
    estimated_tokens = estimate_tokens(params)
    {:ok, %{estimated_tokens: estimated_tokens, estimated_cost_usd: 0.0}}
  end

  @impl Lang.Providers.Provider
  def health_check do
    {:ok, "OpenCode Agents running locally - #{DateTime.utc_now() |> DateTime.to_string()}"}
  end

  # Private implementations
  defp handle_completion(params) do
    prefix = Map.get(params, :prefix, "")
    language = Map.get(params, :language, "text")
    completion = generate_completion(prefix, language)

    {:ok,
     %{
       completion: completion,
       confidence: 0.75,
       provider: "opencode",
       model: @default_model,
       metadata: %{language: language, completion_length: String.length(completion)}
     }}
  end

  defp handle_hover(params) do
    symbol = Map.get(params, :symbol, "unknown")
    language = Map.get(params, :language, "text")

    hover_info = """
    **#{symbol}** (#{language})

    Simulated hover information for `#{symbol}`.
    **Type:** #{random_type(language)}
    **Description:** This is a simulated hover response.
    """

    {:ok,
     %{
       hover_content: hover_info,
       confidence: 0.70,
       provider: "opencode",
       metadata: %{symbol: symbol, language: language}
     }}
  end

  defp handle_explain(params) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")

    explanation = """
    ## Code Explanation (#{language})

    This #{language} code appears to:
    1. **Structure:** Contains typical #{language} patterns
    2. **Purpose:** Handles #{random_purpose()} functionality
    3. **Complexity:** #{assess_complexity(String.length(code))}

    *Note: This is a simulated explanation for testing purposes.*
    """

    {:ok,
     %{
       explanation: explanation,
       confidence: 0.68,
       provider: "opencode",
       metadata: %{language: language, code_length: String.length(code)}
     }}
  end

  defp handle_refactor(params) do
    code = Map.get(params, :code, "")
    goal = Map.get(params, :goal, "improve readability")

    refactored = "// Refactored for #{goal}\n#{code}\n// End refactored code"

    {:ok,
     %{
       refactored_code: refactored,
       changes_summary: "Simulated refactoring for #{goal}",
       confidence: 0.65,
       provider: "opencode"
     }}
  end

  defp handle_generate_tests(params) do
    code = Map.get(params, :code, "")
    language = Map.get(params, :language, "text")

    tests =
      case language do
        "elixir" ->
          """
          defmodule TestModule do
            use ExUnit.Case

            test "generated test case" do
              # Test for: #{String.slice(code, 0, 50)}...
              assert true
            end
          end
          """

        _ ->
          """
          // Generated test for #{language}
          function testGeneratedCode() {
            // Test implementation
            assert(true);
          }
          """
      end

    {:ok,
     %{
       test_code: tests,
       test_count: 1,
       confidence: 0.72,
       provider: "opencode"
     }}
  end

  defp handle_simple_query(params) do
    query = Map.get(params, :query, "")
    answer = "Based on the query '#{query}', the simulated answer involves #{random_concept()}."

    {:ok,
     %{
       answer: answer,
       confidence: 0.70,
       provider: "opencode",
       query_type: "simple"
     }}
  end

  defp handle_explain_intent(params) do
    _code = Map.get(params, :code, "")

    intent = """
    Based on analysis, the intent appears to be:
    **Primary Purpose:** #{random_intent()}
    **Implementation:** Uses #{random_pattern()} pattern
    *Confidence: 75% (simulated analysis)*
    """

    {:ok,
     %{
       intent: intent,
       confidence: 0.75,
       reasoning_steps: ["Analyzed structure", "Identified patterns", "Inferred purpose"],
       provider: "opencode"
     }}
  end

  defp handle_security_analysis(params) do
    _code = Map.get(params, :code, "")

    issues = [
      %{type: "input_validation", severity: "medium", line: 1},
      %{type: "potential_injection", severity: "high", line: 5}
    ]

    {:ok,
     %{
       security_issues: issues,
       severity_scores: [%{issue: "input_validation", severity: "medium"}],
       recommendations: ["Validate inputs", "Use parameterized queries"],
       confidence: 0.65,
       provider: "opencode"
     }}
  end

  defp handle_generate_code(params) do
    description = Map.get(params, :description, "")
    language = Map.get(params, :language, "elixir")

    generated =
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

        _ ->
          "// Generated code for: #{description}"
      end

    {:ok,
     %{
       generated_code: generated,
       language: language,
       confidence: 0.72,
       provider: "opencode"
     }}
  end

  # Helper functions
  defp simulate_processing_delay do
    delay = @base_delay_ms + :rand.uniform(@max_delay_ms - @base_delay_ms)
    :timer.sleep(delay)
  end

  defp generate_completion(prefix, language) do
    trimmed_prefix = String.trim(prefix)

    case language do
      "elixir" ->
        if String.ends_with?(trimmed_prefix, "def ") do
          "#{random_function_name()}(#{random_params()}) do\n  #{random_elixir_body()}\nend"
        else
          random_elixir_value()
        end

      "javascript" ->
        if String.ends_with?(trimmed_prefix, "function ") do
          "#{random_function_name()}() { return #{random_js_value()}; }"
        else
          "// Completed for #{language}: #{String.slice(prefix, -20, 20)}..."
        end

      _ ->
        "// Completed for #{language}: #{String.slice(prefix, -20, 20)}..."
    end
  end

  defp estimate_tokens(params) do
    content_size =
      params
      |> Map.values()
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")
      |> String.length()

    max(50, div(content_size, 4))
  end

  # Random generators for realistic responses
  defp random_function_name do
    Enum.random(["process_data", "handle_request", "calculate_result", "validate_input"])
  end

  defp random_params, do: Enum.random(["data", "opts", "params, opts", "input"])
  defp random_elixir_body, do: Enum.random(["IO.puts(\"Processing...\")", "{:ok, result}", ":ok"])
  defp random_elixir_value, do: Enum.random([":ok", "%{}", "[]", "42"])
  defp random_js_value, do: Enum.random(["true", "null", "42", "'result'"])

  defp random_type(language) do
    case language do
      "elixir" -> Enum.random(["atom()", "string()", "list()", "map()"])
      "javascript" -> Enum.random(["string", "number", "object", "function"])
      _ -> "unknown"
    end
  end

  defp random_purpose,
    do: Enum.random(["data processing", "user interaction", "API communication"])

  defp assess_complexity(length) when length < 100, do: "Low complexity"
  defp assess_complexity(length) when length < 500, do: "Medium complexity"
  defp assess_complexity(_), do: "High complexity"

  defp random_concept,
    do: Enum.random(["modular architecture", "data flow patterns", "error handling"])

  defp random_intent, do: Enum.random(["data transformation", "user validation", "API handling"])
  defp random_pattern, do: Enum.random(["observer", "strategy", "factory", "pipeline"])
end

defmodule OpenCodeDemo do
  @moduledoc """
  Demonstration of OpenCode Agents - Self-hosted AI provider for cost-free testing.
  """

  def run_demo do
    IO.puts("""
    🚀 OpenCode Agents Demo - Self-Hosted AI Provider
    ================================================
    Cost-free AI responses for development and testing!
    """)

    # Test provider capabilities
    IO.puts("\n📋 Provider Capabilities:")
    capabilities = Lang.Providers.OpenCode.capabilities()
    IO.puts("   Methods: #{length(capabilities.methods)}")
    IO.puts("   Cost Tier: #{capabilities.cost_tier}")
    IO.puts("   Speed Tier: #{capabilities.speed_tier}")
    IO.puts("   Available: #{Lang.Providers.OpenCode.available?()}")

    # Test health check
    case Lang.Providers.OpenCode.health_check() do
      {:ok, message} -> IO.puts("\n✅ Health Check: #{message}")
      {:error, reason} -> IO.puts("\n❌ Health Check Failed: #{reason}")
    end

    # Demo different methods
    demo_methods = [
      {"Code Completion", "completion", %{prefix: "def calculate_", language: "elixir"}},
      {"Hover Info", "hover", %{symbol: "user_data", language: "elixir"}},
      {"Code Explanation", "explain", %{code: "Enum.map(items, &process/1)", language: "elixir"}},
      {"Security Analysis", "lang.think.security_analysis",
       %{code: "def query(input), do: \"SELECT * WHERE id = \#{input}\"", language: "elixir"}},
      {"Test Generation", "generate_tests",
       %{code: "def add(a, b), do: a + b", language: "elixir"}},
      {"Simple Query", "lang.query.simple", %{query: "What is Elixir programming language?"}}
    ]

    IO.puts("\n🧪 Method Demonstrations:")

    Enum.each(demo_methods, fn {name, method, params} ->
      IO.puts("\n#{name}:")

      start_time = System.monotonic_time(:millisecond)

      case Lang.Providers.OpenCode.handle_request(method, params) do
        {:ok, result} ->
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time

          # Show key result
          key_field = find_main_content_key(result)
          content = Map.get(result, key_field, "No content")
          preview = String.slice(to_string(content), 0, 100)

          IO.puts("   ✅ Response (#{duration}ms): #{preview}...")
          IO.puts("   📊 Confidence: #{Map.get(result, :confidence, "N/A")}")
          IO.puts("   🏷️  Provider: #{Map.get(result, :provider, "N/A")}")

        {:error, reason} ->
          IO.puts("   ❌ Error: #{reason}")
      end
    end)

    # Cost analysis demo
    IO.puts("\n💰 Cost Analysis:")
    small_params = %{code: "def hello", language: "elixir"}

    large_params = %{
      code: String.duplicate("def function_test, do: :ok\n", 20),
      language: "elixir"
    }

    {:ok, small_estimate} = Lang.Providers.OpenCode.estimate_cost("completion", small_params)
    {:ok, large_estimate} = Lang.Providers.OpenCode.estimate_cost("completion", large_params)

    IO.puts(
      "   Small request: #{small_estimate.estimated_tokens} tokens, $#{small_estimate.estimated_cost_usd}"
    )

    IO.puts(
      "   Large request: #{large_estimate.estimated_tokens} tokens, $#{large_estimate.estimated_cost_usd}"
    )

    # Performance test
    IO.puts("\n⚡ Performance Test (10 concurrent requests):")
    start_time = System.monotonic_time(:millisecond)

    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          Lang.Providers.OpenCode.handle_request("completion", %{
            prefix: "def test_#{i}",
            language: "elixir"
          })
        end)
      end

    results = Task.await_many(tasks, 5000)
    end_time = System.monotonic_time(:millisecond)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    total_time = end_time - start_time

    IO.puts("   ✅ #{successful}/10 requests completed in #{total_time}ms")
    IO.puts("   📈 Average: #{div(total_time, 10)}ms per request")

    IO.puts("""

    🎯 Summary:
    ===========
    ✅ OpenCode Agents is working perfectly!
    ✅ Zero API costs - completely self-hosted
    ✅ Fast responses (#{@base_delay_ms}-#{@max_delay_ms}ms simulated processing)
    ✅ Supports all major LSP and AI methods
    ✅ Perfect for testing, CI/CD, and development

    💡 Next Steps:
    - Use OpenCode in your test suites
    - Configure as default provider for development
    - Set up CI/CD with cost-free AI testing
    - Compare performance with real AI providers

    🚀 Happy coding without the API bills!
    """)
  end

  defp find_main_content_key(result) do
    content_keys = [
      :completion,
      :hover_content,
      :explanation,
      :answer,
      :intent,
      :generated_code,
      :refactored_code,
      :test_code
    ]

    Enum.find(content_keys, fn key -> Map.has_key?(result, key) end) || :result
  end
end

# Run the demo
OpenCodeDemo.run_demo()
