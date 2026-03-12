#!/usr/bin/env elixir

# Comprehensive AI Provider Demo - All Providers Showcase
# This script demonstrates OpenCode (free), Claude (Anthropic), GPT (OpenAI), and Gemini (Google)

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

# Load the providers
Code.require_file("lib/lang/providers/opencode.ex", ".")
Code.require_file("lib/lang/providers/anthropic.ex", ".")
Code.require_file("lib/lang/providers/openai.ex", ".")
Code.require_file("lib/lang/providers/gemini.ex", ".")

defmodule AllProvidersDemo do
  @moduledoc """
  Comprehensive demonstration of all AI providers in the LANG system.
  Shows capabilities, costs, and performance characteristics.
  """

  @providers [
    {:opencode, Lang.Providers.OpenCode, "🆓 Free Self-hosted"},
    {:anthropic, Lang.Providers.Anthropic, "🧠 Claude (Analysis Expert)"},
    {:openai, Lang.Providers.OpenAI, "🚀 GPT (Generation Master)"},
    {:gemini, Lang.Providers.Gemini, "✨ Gemini (Multimodal Speedster)"}
  ]

  def run_comprehensive_demo do
    IO.puts("""
    🎯 LANG AI Provider Ecosystem Demo
    ==================================
    Showcasing all four AI providers with their unique strengths!
    """)

    # Provider overview
    print_provider_overview()

    # Test each provider
    test_all_providers()

    # Cost comparison
    compare_costs()

    # Performance benchmark
    benchmark_performance()

    # Specialization showcase
    showcase_specializations()

    # Final recommendations
    print_recommendations()
  end

  defp print_provider_overview do
    IO.puts("\n🏢 Provider Portfolio:")
    IO.puts("=" |> String.duplicate(50))

    Enum.each(@providers, fn {key, module, description} ->
      caps = module.capabilities()
      pricing = if function_exported?(module, :pricing, 0), do: module.pricing(), else: %{}
      available = module.available?()

      IO.puts("""
      #{description}
      ├─ Status: #{if available, do: "✅ Available", else: "❌ Unavailable"}
      ├─ Methods: #{length(caps.methods)}
      ├─ Cost Tier: #{Map.get(caps, :cost_tier, "N/A")}
      ├─ Speed Tier: #{Map.get(caps, :speed_tier, "N/A")}
      ├─ Quality Tier: #{Map.get(caps, :quality_tier, "N/A")}
      └─ Specializations: #{inspect(Map.get(caps, :specializations, []))}
      """)
    end)
  end

  defp test_all_providers do
    IO.puts("\n🧪 Provider Testing Suite:")
    IO.puts("=" |> String.duplicate(50))

    test_cases = [
      {"Code Completion", "completion", %{prefix: "def fibonacci(", language: "elixir"}},
      {"Hover Information", "hover", %{symbol: "Enum.map", language: "elixir"}},
      {"Code Explanation", "explain", %{code: "Enum.reduce(1..10, 0, &+/2)", language: "elixir"}},
      {"Test Generation", "generate_tests",
       %{code: "def add(a, b), do: a + b", language: "elixir"}}
    ]

    Enum.each(test_cases, fn {test_name, method, params} ->
      IO.puts("\n🔬 #{test_name}:")
      test_method_across_providers(method, params)
    end)
  end

  defp test_method_across_providers(method, params) do
    Enum.each(@providers, fn {key, module, description} ->
      IO.write("  #{description}: ")

      case module.available?() do
        false ->
          IO.puts("❌ Unavailable (no API key)")

        true ->
          start_time = System.monotonic_time(:millisecond)

          case module.handle_request(method, params) do
            {:ok, result} ->
              end_time = System.monotonic_time(:millisecond)
              duration = end_time - start_time

              # Extract main content
              content_key = find_main_content_key(result)
              content = Map.get(result, content_key, "No content")
              preview = String.slice(to_string(content), 0, 60)

              confidence = Map.get(result, :confidence, 0.0)

              IO.puts("✅ #{duration}ms | Confidence: #{confidence} | #{preview}...")

            {:error, reason} ->
              error_msg = if is_binary(reason), do: reason, else: inspect(reason)
              IO.puts("❌ Error: #{String.slice(error_msg, 0, 50)}...")
          end
      end
    end)
  end

  defp compare_costs do
    IO.puts("""

    💰 Cost Analysis Comparison:
    ============================
    """)

    test_params = %{
      small: %{code: "def hello, do: :world", language: "elixir"},
      medium: %{code: String.duplicate("def func_#{&1}, do: :ok\n", 10), language: "elixir"},
      large: %{
        code: String.duplicate("def large_func_#{&1}(data) do\n  process(data)\nend\n", 50),
        language: "elixir"
      }
    }

    Enum.each(test_params, fn {size, params} ->
      IO.puts("\n📊 #{String.upcase(to_string(size))} Request Cost Analysis:")

      Enum.each(@providers, fn {key, module, description} ->
        case module.estimate_cost("completion", params) do
          {:ok, estimate} ->
            cost_str =
              if estimate.estimated_cost_usd == 0.0,
                do: "FREE",
                else: "$#{Float.round(estimate.estimated_cost_usd, 6)}"

            IO.puts("  #{description}")
            IO.puts("  ├─ Tokens: #{estimate.estimated_tokens}")
            IO.puts("  └─ Cost: #{cost_str}")

          {:error, _} ->
            IO.puts("  #{description}: Cost estimation unavailable")
        end
      end)
    end)

    # Monthly cost projection
    IO.puts("""

    📈 Monthly Cost Projections (1000 requests/day):
    """)

    monthly_requests = 30_000
    test_params_monthly = %{code: "def monthly_test(data), do: process(data)", language: "elixir"}

    Enum.each(@providers, fn {key, module, description} ->
      case module.estimate_cost("completion", test_params_monthly) do
        {:ok, estimate} ->
          monthly_cost = estimate.estimated_cost_usd * monthly_requests
          cost_str = if monthly_cost == 0.0, do: "FREE", else: "$#{Float.round(monthly_cost, 2)}"
          IO.puts("  #{description}: #{cost_str}/month")

        {:error, _} ->
          IO.puts("  #{description}: Estimation unavailable")
      end
    end)
  end

  defp benchmark_performance do
    IO.puts("""

    ⚡ Performance Benchmark:
    =========================
    Testing 5 concurrent completion requests...
    """)

    params = %{prefix: "def benchmark_test_", language: "elixir"}

    Enum.each(@providers, fn {key, module, description} ->
      IO.write("#{description}: ")

      if not module.available?() do
        IO.puts("❌ Unavailable")
      else
        # Run concurrent benchmark
        start_time = System.monotonic_time(:millisecond)

        tasks =
          for i <- 1..5 do
            Task.async(fn ->
              test_params = Map.put(params, :prefix, "#{params.prefix}#{i}")
              module.handle_request("completion", test_params)
            end)
          end

        results = Task.await_many(tasks, 10_000)
        end_time = System.monotonic_time(:millisecond)

        successful = Enum.count(results, &match?({:ok, _}, &1))
        total_time = end_time - start_time
        avg_time = if successful > 0, do: div(total_time, successful), else: 0

        IO.puts("✅ #{successful}/5 requests | #{total_time}ms total | #{avg_time}ms avg")
      end
    end)
  end

  defp showcase_specializations do
    IO.puts("""

    🎯 Provider Specialization Showcase:
    ===================================
    """)

    specializations = [
      {"🆓 OpenCode - Free Testing", :opencode, "completion",
       %{prefix: "def test_", language: "elixir"}},
      {"🧠 Claude - Security Analysis", :anthropic, "lang.think.security_scan",
       %{
         code: "def query(input), do: \"SELECT * FROM users WHERE id = \#{input}\"",
         language: "elixir"
       }},
      {"🚀 GPT - Code Generation", :openai, "lang.generate.from_spec",
       %{specification: "Create a function that calculates factorial", language: "elixir"}},
      {"✨ Gemini - Performance Analysis", :gemini, "lang.think.analyze_performance",
       %{code: "Enum.reduce(1..1000000, 0, &+/2)", language: "elixir"}}
    ]

    Enum.each(specializations, fn {title, provider_key, method, params} ->
      IO.puts("\n#{title}:")

      {_key, module, _desc} = Enum.find(@providers, fn {k, _, _} -> k == provider_key end)

      if not module.available?() do
        IO.puts("  ❌ Unavailable - configure API key to test")
      else
        start_time = System.monotonic_time(:millisecond)

        case module.handle_request(method, params) do
          {:ok, result} ->
            end_time = System.monotonic_time(:millisecond)
            duration = end_time - start_time

            # Show result preview
            content_key = find_main_content_key(result)
            content = Map.get(result, content_key, "No content")
            preview = String.slice(to_string(content), 0, 100)

            IO.puts("  ✅ Success (#{duration}ms)")
            IO.puts("  📄 Preview: #{preview}...")
            IO.puts("  🎯 Confidence: #{Map.get(result, :confidence, "N/A")}")

          {:error, reason} ->
            IO.puts("  ❌ Error: #{inspect(reason)}")
        end
      end
    end)
  end

  defp print_recommendations do
    IO.puts("""

    🎯 Provider Selection Guide:
    ============================

    💡 CHOOSE YOUR PROVIDER BASED ON NEEDS:

    🆓 OpenCode (Free Self-hosted):
    ├─ Perfect for: Testing, CI/CD, development, prototyping
    ├─ Pros: Zero cost, always available, consistent responses
    └─ Cons: Basic quality, simulated responses only

    🧠 Claude (Anthropic):
    ├─ Perfect for: Security analysis, code review, diagnostics, safety-critical
    ├─ Pros: Excellent analysis, safety-focused, detailed explanations
    └─ Cons: Higher cost, slower for simple tasks

    🚀 GPT (OpenAI):
    ├─ Perfect for: Code generation, complex reasoning, explanations
    ├─ Pros: Versatile, high quality, good at creative tasks
    └─ Cons: Expensive, rate limits

    ✨ Gemini (Google):
    ├─ Perfect for: Fast responses, multimodal analysis, large context
    ├─ Pros: Fast, cost-effective, handles large inputs well
    └─ Cons: Newer model, less proven for complex reasoning

    🎯 RECOMMENDED STRATEGY:

    Development Phase:
    1. Use OpenCode for all testing and CI/CD
    2. Use Claude for security reviews
    3. Use GPT for complex code generation
    4. Use Gemini for performance analysis

    Production Phase:
    1. Route simple tasks to Gemini (cost + speed)
    2. Route security tasks to Claude (safety)
    3. Route complex generation to GPT (quality)
    4. Use OpenCode for load testing

    🚀 Next Steps:
    - Configure API keys in config/runtime.exs
    - Set up provider routing in your application
    - Use OpenCode for unlimited testing
    - Monitor costs and adjust provider selection
    """)

    print_configuration_guide()
  end

  defp print_configuration_guide do
    IO.puts("""

    ⚙️ Configuration Guide:
    =======================

    Add to config/runtime.exs:
    ```elixir
    config :lang, :ai_providers, %{
      # Free - always available
      # No configuration needed for OpenCode

      # Claude (Anthropic) - for analysis
      anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),

      # GPT (OpenAI) - for generation
      openai_api_key: System.get_env("OPENAI_API_KEY"),

      # Gemini (Google) - for speed
      gemini_api_key: System.get_env("GEMINI_API_KEY")
    }
    ```

    Environment Variables:
    ```bash
    export ANTHROPIC_API_KEY="your-claude-key"
    export OPENAI_API_KEY="your-openai-key"
    export GEMINI_API_KEY="your-gemini-key"
    ```

    Usage in Code:
    ```elixir
    # Use specific provider
    {:ok, result} = Lang.Providers.Provider.execute("completion", params, provider: :gemini)

    # Auto-select best provider
    {:ok, result} = Lang.Providers.Router.route_request("completion", params)

    # Cost-free testing
    {:ok, result} = Lang.Providers.Provider.execute("completion", params, provider: :opencode)
    ```
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
      :test_code,
      :security_issues,
      :performance_analysis,
      :text
    ]

    Enum.find(content_keys, fn key -> Map.has_key?(result, key) end) || :result
  end
end

# Run the comprehensive demo
AllProvidersDemo.run_comprehensive_demo()
