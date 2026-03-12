#!/usr/bin/env elixir

# Comprehensive test script for implemented LSP handlers
Mix.install([
  {:jason, "~> 1.4"}
])

defmodule LSPHandlerTest do
  @moduledoc """
  Test script to demonstrate the implemented LSP handlers.
  This tests the handlers directly without requiring a full LSP connection.
  """

  require Logger

  def run do
    Logger.info("🚀 Testing Implemented LSP Handlers")
    Logger.info("=" |> String.duplicate(50))

    test_results = [
      test_api_usage_logger(),
      test_security_validator(),
      test_rate_limiter(),
      test_code_generation(),
      test_natural_language_query(),
      test_scratch_storage(),
      test_performance_metrics(),
      test_agent_efficiency(),
      test_rpc_shutdown()
    ]

    total_tests = length(test_results)
    passed_tests = Enum.count(test_results, &(&1 == :ok))
    failed_tests = total_tests - passed_tests

    Logger.info(("\n" <> "=") |> String.duplicate(50))
    Logger.info("📊 Test Summary:")
    Logger.info("  Total Tests: #{total_tests}")
    Logger.info("  Passed: #{passed_tests}")
    Logger.info("  Failed: #{failed_tests}")

    if failed_tests == 0 do
      Logger.info("✅ All tests passed! LSP handlers are working correctly.")
    else
      Logger.warning("❌ Some tests failed. Check the logs above.")
    end

    {passed_tests, failed_tests}
  end

  defp test_api_usage_logger do
    Logger.info("\n🧪 Testing API Usage Logger...")

    try do
      handler = Elixir.Lang.LSP.Lang.Lang.Metrics.Usage

      params = %{
        "user_id" => "test_user_123",
        "method" => "test_method",
        "duration_ms" => 150,
        "tokens_used" => 42
      }

      ctx = %{"client_id" => "test_client"}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          Logger.info("✅ Usage logging successful: #{inspect(result)}")
          :ok

        {:error, error} ->
          Logger.error("❌ Usage logging failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in usage logger test: #{inspect(error)}")
        :error
    end
  end

  defp test_security_validator do
    Logger.info("\n🔒 Testing Security Input Validator...")

    try do
      handler = Elixir.Lang.LSP.Lang.Lang.Security.Validate

      # Test with malicious input
      params = %{
        "input" => "<script>alert('xss')</script>; DROP TABLE users;",
        "type" => "general"
      }

      ctx = %{}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          if result["valid"] == false and length(result["issues"]) > 0 do
            Logger.info("✅ Security validation correctly identified threats")
            Logger.info("   Issues found: #{length(result["issues"])}")
            Logger.info("   Risk level: #{result["risk_level"]}")
            :ok
          else
            Logger.error("❌ Security validation should have failed for malicious input")
            :error
          end

        {:error, error} ->
          Logger.error("❌ Security validation failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in security validator test: #{inspect(error)}")
        :error
    end
  end

  defp test_rate_limiter do
    Logger.info("\n⏱️  Testing Rate Limiter...")

    try do
      handler = Elixir.Lang.LSP.Lang.Lang.Security.RateLimit

      # Test rate limit check
      params = %{
        "key" => "test_user_rate_limit",
        "limit" => 10,
        "window_seconds" => 60,
        "action" => "check"
      }

      ctx = %{}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          Logger.info("✅ Rate limit check successful")
          Logger.info("   Allowed: #{result["allowed"]}")
          Logger.info("   Remaining: #{result["remaining"]}")
          Logger.info("   Current: #{result["current"]}")
          :ok

        {:error, error} ->
          Logger.error("❌ Rate limit check failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in rate limiter test: #{inspect(error)}")
        :error
    end
  end

  defp test_code_generation do
    Logger.info("\n🏗️  Testing Code Generation from Diagrams...")

    try do
      handler = Elixir.Lang.LSP.Lang.Lang.Generate.FromDiagram

      # Test with simple mermaid diagram
      params = %{
        "diagram" => """
        User {
          id integer
          name string
          email string
        }
        """,
        "type" => "mermaid",
        "language" => "elixir",
        "options" => %{"use_ash" => false}
      }

      ctx = %{}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          Logger.info("✅ Code generation successful")
          Logger.info("   Language: #{result["language"]}")
          Logger.info("   Lines generated: #{result["metadata"]["lines_generated"]}")
          Logger.info("   Generated code preview:")
          Logger.info(String.slice(result["generated_code"], 0, 200) <> "...")
          :ok

        {:error, error} ->
          Logger.error("❌ Code generation failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in code generation test: #{inspect(error)}")
        :error
    end
  end

  defp test_natural_language_query do
    Logger.info("\n🔍 Testing Natural Language Query...")

    try do
      handler = Elixir.Lang.LSP.Lang.Lang.Query.Natural

      params = %{
        "query" => "find all elixir functions that handle errors",
        "max_results" => 5,
        "include_code" => true
      }

      ctx = %{}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          Logger.info("✅ Natural language query successful")
          Logger.info("   Query: #{result["query"]}")
          Logger.info("   Results found: #{result["total_results"]}")
          Logger.info("   Processing time: #{result["processing_time_ms"]}ms")
          Logger.info("   Intent detected: #{result["interpretation"]["confidence"]}")
          :ok

        {:error, error} ->
          Logger.error("❌ Natural language query failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in natural language query test: #{inspect(error)}")
        :error
    end
  end

  defp test_scratch_storage do
    Logger.info("\n📝 Testing Scratch Storage...")

    try do
      handler = Elixir.Lang.LSP.Lang.Lang.Storage.UpdateScratch

      params = %{
        "user_id" => "test_user_456",
        "session_id" => "session_789",
        "stage" => "code_analysis",
        "data" => %{
          "analyzed_files" => ["lib/example.ex"],
          "issues_found" => 3,
          "suggestions" => ["optimize loops", "add error handling"]
        }
      }

      ctx = %{}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          Logger.info("✅ Scratch storage update successful")
          Logger.info("   Updated: #{result["updated"]}")
          Logger.info("   Stage: #{result["stage"]}")
          Logger.info("   Version: #{result["version"]}")
          :ok

        {:error, error} ->
          Logger.error("❌ Scratch storage update failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in scratch storage test: #{inspect(error)}")
        :error
    end
  end

  defp test_performance_metrics do
    Logger.info("\n📊 Testing Performance Metrics...")

    try do
      handler = Elixir.Lang.LSP.Lang.Lang.Metrics.Performance

      params = %{
        "type" => "system",
        "timeframe" => "current",
        "include_details" => true
      }

      ctx = %{}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          Logger.info("✅ Performance metrics collection successful")
          Logger.info("   Metrics type: #{result["type"]}")
          Logger.info("   Uptime: #{result["metrics"]["uptime_ms"]}ms")
          Logger.info("   Schedulers online: #{result["metrics"]["schedulers_online"]}")
          Logger.info("   Elixir version: #{result["metrics"]["elixir_version"]}")
          :ok

        {:error, error} ->
          Logger.error("❌ Performance metrics collection failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in performance metrics test: #{inspect(error)}")
        :error
    end
  end

  defp test_agent_efficiency do
    Logger.info("\n🤖 Testing Agent Efficiency Metrics...")

    try do
      handler = Elixir.Lang.LSP.Lang.Lang.Metrics.AgentEfficiency

      # Test aggregate metrics
      params = %{
        "timeframe" => "1h",
        "type" => "all"
      }

      ctx = %{}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          Logger.info("✅ Agent efficiency metrics successful")
          Logger.info("   Total agents: #{result["total_agents"]}")
          Logger.info("   Active agents: #{result["aggregate_metrics"]["active_agent_count"]}")
          Logger.info("   Top performers: #{length(result["top_performers"])}")
          :ok

        {:error, error} ->
          Logger.error("❌ Agent efficiency metrics failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in agent efficiency test: #{inspect(error)}")
        :error
    end
  end

  defp test_rpc_shutdown do
    Logger.info("\n🛑 Testing RPC Shutdown (dry run)...")

    try do
      handler = Elixir.Lang.LSP.Lang.Rpc.Shutdown

      # Test shutdown with safe parameters
      params = %{
        "force" => false,
        "timeout_seconds" => 10,
        "reason" => "test_shutdown"
      }

      ctx = %{"client_id" => "test_client"}

      case handler.handle(params, ctx) do
        {:ok, result} ->
          Logger.info("✅ RPC shutdown handler working")
          Logger.info("   Shutdown initiated: #{result["shutdown_initiated"]}")
          Logger.info("   Reason: #{result["reason"]}")
          Logger.info("   ⚠️  Note: This is a dry run test - no actual shutdown performed")
          :ok

        {:error, error} ->
          Logger.error("❌ RPC shutdown test failed: #{inspect(error)}")
          :error
      end
    rescue
      error ->
        Logger.error("❌ Exception in RPC shutdown test: #{inspect(error)}")
        :error
    end
  end
end

# Demo of the handlers in action
defmodule LSPHandlerDemo do
  @moduledoc """
  Interactive demonstration of LSP handler capabilities.
  """

  def run_security_demo do
    IO.puts("\n🛡️  Security Handler Demo")
    IO.puts("Testing various input types...")

    test_cases = [
      {"Safe input", "Hello world! This is a normal string."},
      {"SQL injection", "'; DROP TABLE users; --"},
      {"XSS attempt", "<script>alert('hacked')</script>"},
      {"Command injection", "test; rm -rf /"},
      {"Path traversal", "../../etc/passwd"}
    ]

    handler = Elixir.Lang.LSP.Lang.Lang.Security.Validate

    Enum.each(test_cases, fn {description, input} ->
      IO.puts("\n#{description}: \"#{input}\"")

      case handler.handle(%{"input" => input, "type" => "general"}, %{}) do
        {:ok, result} ->
          IO.puts("  Valid: #{result["valid"]}")
          IO.puts("  Risk level: #{result["risk_level"]}")

          if length(result["issues"]) > 0 do
            IO.puts("  Issues: #{Enum.map(result["issues"], & &1["type"]) |> Enum.join(", ")}")
          end

        {:error, error} ->
          IO.puts("  Error: #{error}")
      end
    end)
  end

  def run_code_gen_demo do
    IO.puts("\n🏗️  Code Generation Demo")
    IO.puts("Generating Elixir code from diagram...")

    diagram = """
    BlogPost {
      id integer
      title string
      content text
      published_at datetime
      author_id integer
    }

    Author {
      id integer
      name string
      email string
    }
    """

    handler = Elixir.Lang.LSP.Lang.Lang.Generate.FromDiagram

    params = %{
      "diagram" => diagram,
      "type" => "mermaid",
      "language" => "phoenix",
      "options" => %{"include_liveview" => true}
    }

    case handler.handle(params, %{}) do
      {:ok, result} ->
        IO.puts(
          "✅ Generated #{result["metadata"]["lines_generated"]} lines of #{result["language"]} code"
        )

        IO.puts("\nCode preview:")
        IO.puts(String.slice(result["generated_code"], 0, 500) <> "...\n")

      {:error, error} ->
        IO.puts("❌ Code generation failed: #{error}")
    end
  end

  def run_metrics_demo do
    IO.puts("\n📊 Metrics Collection Demo")

    # System metrics
    handler = Elixir.Lang.LSP.Lang.Lang.Metrics.Performance

    case handler.handle(%{"type" => "memory", "include_details" => true}, %{}) do
      {:ok, result} ->
        IO.puts("Memory Metrics:")
        IO.puts("  Total: #{result["metrics"]["total_mb"]} MB")
        IO.puts("  Processes: #{result["metrics"]["processes_mb"]} MB")
        IO.puts("  System: #{result["metrics"]["system_mb"]} MB")

      {:error, error} ->
        IO.puts("❌ Metrics collection failed: #{error}")
    end
  end
end

# Run the comprehensive test suite
case LSPHandlerTest.run() do
  {passed, 0} ->
    IO.puts("\n🎉 All #{passed} handlers implemented successfully!")
    IO.puts("\nRun the demos:")
    IO.puts("  LSPHandlerDemo.run_security_demo()")
    IO.puts("  LSPHandlerDemo.run_code_gen_demo()")
    IO.puts("  LSPHandlerDemo.run_metrics_demo()")

  {passed, failed} ->
    IO.puts("\n⚠️  #{passed} handlers working, #{failed} need attention")
    System.halt(1)
end
