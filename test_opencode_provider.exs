#!/usr/bin/env elixir

# Test script for OpenCode provider - runs without API costs
Mix.install([
  {:req, "~> 0.4.0"}
])

defmodule OpenCodeProviderTest do
  @moduledoc """
  Test script to verify OpenCode provider functionality for cost-free testing.
  """

  require Logger

  def run_comprehensive_test do
    IO.puts("""
    🧪 OpenCode Provider Comprehensive Test Suite
    ============================================
    Testing self-hosted AI provider for cost-free development and testing.
    """)

    # Load the Lang application modules
    Code.require_file("lib/lang/providers/provider.ex", ".")
    Code.require_file("lib/lang/providers/opencode.ex", ".")

    # Test all major functionality
    tests = [
      {"Provider Capabilities", &test_provider_capabilities/0},
      {"LSP Methods", &test_lsp_methods/0},
      {"Think Methods", &test_think_methods/0},
      {"Generation Methods", &test_generation_methods/0},
      {"Performance Characteristics", &test_performance/0},
      {"Cost Analysis", &test_cost_analysis/0},
      {"Concurrent Requests", &test_concurrent_requests/0}
    ]

    results =
      Enum.map(tests, fn {name, test_fn} ->
        IO.write("Testing #{name}... ")

        case test_fn.() do
          :ok ->
            IO.puts("✅ PASS")
            {name, :pass}

          {:error, reason} ->
            IO.puts("❌ FAIL: #{reason}")
            {name, {:fail, reason}}
        end
      end)

    print_summary(results)
  end

  def test_provider_capabilities do
    capabilities = Lang.Providers.OpenCode.capabilities()

    cond do
      not is_map(capabilities) ->
        {:error, "capabilities/0 should return a map"}

      true ->
        required_fields = [:methods, :strengths, :cost_tier, :speed_tier, :quality_tier]

        missing_fields =
          Enum.reject(required_fields, fn field -> Map.has_key?(capabilities, field) end)

        cond do
          not Enum.empty?(missing_fields) ->
            {:error, "Missing required capability fields: #{inspect(missing_fields)}"}

          not Lang.Providers.OpenCode.available?() ->
            {:error, "Provider should always be available"}

          true ->
            case Lang.Providers.OpenCode.health_check() do
              {:ok, _} -> :ok
              error -> {:error, "Health check failed: #{inspect(error)}"}
            end
        end
    end
  end

  def test_lsp_methods do
    test_cases = [
      {
        "completion",
        %{prefix: "def ", language: "elixir", context: "# Test context"},
        [:completion, :confidence, :provider]
      },
      {
        "hover",
        %{symbol: "test_function", language: "elixir", context: "def test_function, do: :ok"},
        [:hover_content, :confidence, :provider]
      },
      {
        "explain",
        %{code: "def hello(name), do: \"Hello, \#{name}!\"", language: "elixir"},
        [:explanation, :confidence, :provider]
      },
      {
        "refactor",
        %{code: "def old_code, do: :bad", language: "elixir", goal: "improve readability"},
        [:refactored_code, :confidence, :provider]
      },
      {
        "generate_tests",
        %{code: "def add(a, b), do: a + b", language: "elixir", framework: "ExUnit"},
        [:test_code, :test_count, :provider]
      }
    ]

    Enum.each(test_cases, fn {method, params, expected_keys} ->
      case Lang.Providers.OpenCode.handle_request(method, params) do
        {:ok, result} ->
          missing_keys = Enum.reject(expected_keys, fn key -> Map.has_key?(result, key) end)

          unless Enum.empty?(missing_keys) do
            raise "Method #{method} missing keys: #{inspect(missing_keys)}"
          end

          unless result.provider == "opencode" do
            raise "Method #{method} should set provider to 'opencode'"
          end

        {:error, reason} ->
          raise "Method #{method} failed: #{reason}"
      end
    end)

    :ok
  rescue
    error -> {:error, Exception.message(error)}
  end

  def test_think_methods do
    test_cases = [
      {
        "lang.think.explain_intent",
        %{code: "def process(data), do: data |> validate() |> transform()", language: "elixir"},
        [:intent, :confidence, :reasoning_steps]
      },
      {
        "lang.think.find_semantic",
        %{query: "authentication", context: "web app"},
        [:matches, :confidence, :search_method]
      },
      {
        "lang.think.security_analysis",
        %{
          code: "def unsafe_query(input), do: \"SELECT * FROM users WHERE id = \#{input}\"",
          language: "elixir"
        },
        [:security_issues, :recommendations, :confidence]
      },
      {
        "lang.think.diagnose_issue",
        %{error: "undefined function", code: "def main, do: missing_func()", language: "elixir"},
        [:diagnosis, :likely_causes, :suggested_fixes]
      }
    ]

    Enum.each(test_cases, fn {method, params, expected_keys} ->
      case Lang.Providers.OpenCode.handle_request(method, params) do
        {:ok, result} ->
          missing_keys = Enum.reject(expected_keys, fn key -> Map.has_key?(result, key) end)

          unless Enum.empty?(missing_keys) do
            raise "Think method #{method} missing keys: #{inspect(missing_keys)}"
          end

        {:error, reason} ->
          raise "Think method #{method} failed: #{reason}"
      end
    end)

    :ok
  rescue
    error -> {:error, Exception.message(error)}
  end

  def test_generation_methods do
    test_cases = [
      {
        "lang.generate.code",
        %{description: "Create a factorial function", language: "elixir"},
        [:generated_code, :language, :confidence]
      },
      {
        "lang.generate.documentation",
        %{
          code: "def hello(name), do: \"Hello, \#{name}!\"",
          language: "elixir",
          format: "markdown"
        },
        [:documentation, :format, :confidence]
      }
    ]

    Enum.each(test_cases, fn {method, params, expected_keys} ->
      case Lang.Providers.OpenCode.handle_request(method, params) do
        {:ok, result} ->
          missing_keys = Enum.reject(expected_keys, fn key -> Map.has_key?(result, key) end)

          unless Enum.empty?(missing_keys) do
            raise "Generation method #{method} missing keys: #{inspect(missing_keys)}"
          end

        {:error, reason} ->
          raise "Generation method #{method} failed: #{reason}"
      end
    end)

    :ok
  rescue
    error -> {:error, Exception.message(error)}
  end

  def test_performance do
    params = %{prefix: "def ", language: "elixir"}

    # Test response time
    start_time = System.monotonic_time(:millisecond)
    {:ok, _result} = Lang.Providers.OpenCode.handle_request("completion", params)
    end_time = System.monotonic_time(:millisecond)

    duration = end_time - start_time

    cond do
      duration < 50 ->
        {:error, "Response too fast (#{duration}ms) - should simulate processing time"}

      duration > 2000 ->
        {:error, "Response too slow (#{duration}ms) - should be faster than real APIs"}

      true ->
        IO.write(" (#{duration}ms) ")
        :ok
    end
  end

  def test_cost_analysis do
    small_params = %{code: "def test", language: "elixir"}
    large_params = %{code: String.duplicate("def func_test, do: :ok\n", 50), language: "elixir"}

    case {Lang.Providers.OpenCode.estimate_cost("completion", small_params),
          Lang.Providers.OpenCode.estimate_cost("completion", large_params)} do
      {{:ok, small_est}, {:ok, large_est}} ->
        cond do
          small_est.estimated_cost_usd != 0.0 ->
            {:error, "Small request cost should be 0.0, got #{small_est.estimated_cost_usd}"}

          large_est.estimated_cost_usd != 0.0 ->
            {:error, "Large request cost should be 0.0, got #{large_est.estimated_cost_usd}"}

          large_est.estimated_tokens <= small_est.estimated_tokens ->
            {:error, "Large request should have more estimated tokens"}

          true ->
            IO.write(
              " (#{small_est.estimated_tokens}→#{large_est.estimated_tokens} tokens, $0.00) "
            )

            :ok
        end

      {error1, error2} ->
        {:error, "Cost estimation failed: #{inspect({error1, error2})}"}
    end
  end

  def test_concurrent_requests do
    params = %{prefix: "def concurrent_test_", language: "elixir"}

    tasks =
      for i <- 1..5 do
        Task.async(fn ->
          test_params = Map.put(params, :prefix, "#{params.prefix}#{i}")
          Lang.Providers.OpenCode.handle_request("completion", test_params)
        end)
      end

    start_time = System.monotonic_time(:millisecond)
    results = Task.await_many(tasks, 5000)
    end_time = System.monotonic_time(:millisecond)

    duration = end_time - start_time

    failed_results = Enum.reject(results, fn result -> match?({:ok, _}, result) end)

    cond do
      length(failed_results) > 0 ->
        {:error, "#{length(failed_results)} concurrent requests failed"}

      duration > 3000 ->
        {:error, "Concurrent requests took too long: #{duration}ms"}

      true ->
        IO.write(" (5 requests in #{duration}ms) ")
        :ok
    end
  end

  def print_summary(results) do
    passed = Enum.count(results, fn {_, status} -> status == :pass end)
    failed = Enum.count(results, fn {_, status} -> match?({:fail, _}, status) end)
    total = length(results)

    IO.puts("""

    📊 Test Results Summary
    ========================
    ✅ Passed: #{passed}/#{total}
    ❌ Failed: #{failed}/#{total}
    """)

    if failed > 0 do
      IO.puts("Failed tests:")

      Enum.each(results, fn
        {name, {:fail, reason}} ->
          IO.puts("  • #{name}: #{reason}")

        _ ->
          :ok
      end)
    end

    IO.puts("""

    🎯 OpenCode Provider Status: #{if failed == 0, do: "✅ READY", else: "❌ NEEDS FIXES"}

    💡 Usage Tips:
    - Use OpenCode for development and testing without API costs
    - Responses are simulated but realistic for testing workflows
    - Perfect for CI/CD pipelines and local development
    - Switch to real providers for production workloads

    🚀 Next steps:
    - Update your provider configuration to include :opencode
    - Use Lang.Providers.Provider.execute/3 with provider: :opencode
    - Run your existing tests against OpenCode for cost-free validation
    """)

    if failed == 0, do: System.halt(0), else: System.halt(1)
  end

  def demo_usage_patterns do
    IO.puts("""

    📚 OpenCode Usage Examples
    ==========================
    """)

    examples = [
      {
        "Basic completion",
        "completion",
        %{prefix: "def calculate_", language: "elixir"}
      },
      {
        "Code explanation",
        "explain",
        %{code: "Enum.map(items, &process/1)", language: "elixir"}
      },
      {
        "Security analysis",
        "lang.think.security_analysis",
        %{code: "def query(input), do: \"SELECT * WHERE id = \#{input}\"", language: "elixir"}
      }
    ]

    Enum.each(examples, fn {name, method, params} ->
      IO.puts("#{name}:")

      case Lang.Providers.OpenCode.handle_request(method, params) do
        {:ok, result} ->
          key = Map.keys(result) |> Enum.find(&is_binary(Map.get(result, &1)))
          content = Map.get(result, key, "No content") |> String.slice(0, 100)
          IO.puts("  Response: #{content}...")
          IO.puts("  Confidence: #{Map.get(result, :confidence, "N/A")}")

        {:error, reason} ->
          IO.puts("  Error: #{reason}")
      end

      IO.puts("")
    end)
  end
end

# Run the comprehensive test
OpenCodeProviderTest.run_comprehensive_test()

# Show usage examples
OpenCodeProviderTest.demo_usage_patterns()
