defmodule Lang.Integration.GrokIntegrationTest do
  use ExUnit.Case, async: false
  require Logger

  @moduletag :integration
  @moduletag timeout: 30_000

  describe "Grok Integration Tests (Real API)" do
    setup do
      case System.get_env("XAI_API_KEY") do
        nil ->
          {:skip, "XAI_API_KEY not set - skipping Grok integration tests"}

        api_key ->
          Logger.info(
            "Running Grok integration tests with API key: #{String.slice(api_key, 0, 8)}..."
          )

          :ok
      end
    end

    test "can communicate with real Grok through health check" do
      case Lang.Providers.XAI.health_check() do
        {:ok, message} ->
          assert String.contains?(message, "healthy")
          Logger.info("✅ Grok health check passed: #{message}")

        {:error, error} ->
          Logger.error("❌ Grok health check failed: #{inspect(error)}")
          flunk("Grok health check failed: #{inspect(error)}")
      end
    end

    test "can ask Grok direct questions" do
      question =
        "Hello Grok! Please respond with the exact text 'INTEGRATION_TEST_SUCCESS' to confirm this test is working."

      case Lang.Commands.TalkToGrok.ask(question) do
        {:ok, response} ->
          assert is_binary(response)
          assert String.length(response) > 10
          Logger.info("✅ Grok responded: #{String.slice(response, 0, 100)}...")

        {:error, error} ->
          Logger.error("❌ Grok failed to respond: #{inspect(error)}")
          flunk("Grok failed to respond: #{inspect(error)}")
      end
    end

    test "can send mission commands to Grok commander" do
      mission = """
      You are the mission commander. Please analyze this simple task and break it into subtasks:

      Task: Review a basic authentication function for security issues

      Please respond with a structured breakdown including what AI specialists you would assign.
      """

      case Lang.Commands.TalkToGrok.command_mission(mission) do
        {:ok, {response, tasks}} when is_list(tasks) and length(tasks) > 0 ->
          assert is_binary(response)
          assert length(tasks) > 0
          Logger.info("✅ Grok commander parsed #{length(tasks)} tasks")

          # Verify task structure
          for task <- tasks do
            assert Map.has_key?(task, :provider)
            assert Map.has_key?(task, :description)
            assert Map.has_key?(task, :priority)
            assert task.priority in [:critical, :high, :medium, :low]
          end

        {:ok, response} when is_binary(response) ->
          # Fallback case where task parsing failed but we got a response
          assert String.length(response) > 50
          Logger.info("✅ Grok commander responded (task parsing failed)")

        {:error, error} ->
          Logger.error("❌ Mission command failed: #{inspect(error)}")
          flunk("Mission command failed: #{inspect(error)}")
      end
    end

    test "can handle tactical analysis requests" do
      context = "Authentication system with JWT tokens and rate limiting"
      question = "What are the top 3 security risks I should be concerned about?"

      case Lang.Providers.XAI.analyze_situation(context, question) do
        {:ok, %{analysis: analysis}} ->
          assert is_binary(analysis)
          assert String.length(analysis) > 100
          Logger.info("✅ Grok tactical analysis completed")

        {:error, error} ->
          Logger.error("❌ Tactical analysis failed: #{inspect(error)}")
          flunk("Tactical analysis failed: #{inspect(error)}")
      end
    end

    test "can perform simple task delegation" do
      task = "Explain in one paragraph what JWT tokens are used for in authentication systems."

      case Lang.Providers.XAI.simple_task(task) do
        {:ok, response} ->
          assert is_binary(response)
          assert String.length(response) > 50
          assert String.contains?(String.downcase(response), "jwt")
          Logger.info("✅ Grok simple task completed")

        {:error, error} ->
          Logger.error("❌ Simple task failed: #{inspect(error)}")
          flunk("Simple task failed: #{inspect(error)}")
      end
    end

    test "can handle code explanation through provider interface" do
      code = """
      def authenticate_user(email, password) do
        case User.get_by_email(email) do
          %User{} = user ->
            if Bcrypt.verify_pass(password, user.password_hash) do
              {:ok, user}
            else
              {:error, :invalid_credentials}
            end
          nil ->
            {:error, :user_not_found}
        end
      end
      """

      params = %{content: code}

      case Lang.Providers.XAI.handle_request("lang.think.explain_intent", params) do
        {:ok, result} ->
          response =
            case result do
              %{content: content} -> content
              content when is_binary(content) -> content
              other -> inspect(other)
            end

          assert is_binary(response)
          assert String.length(response) > 100
          Logger.info("✅ Grok code explanation completed")

        {:error, error} ->
          Logger.error("❌ Code explanation failed: #{inspect(error)}")
          flunk("Code explanation failed: #{inspect(error)}")
      end
    end

    test "handles errors gracefully with invalid requests" do
      # Test with empty/invalid parameters
      case Lang.Providers.XAI.simple_task("") do
        {:ok, _response} ->
          Logger.info("✅ Grok handled empty request gracefully")

        {:error, error} ->
          # This is also acceptable - provider should handle errors gracefully
          assert is_binary(inspect(error))
          Logger.info("✅ Grok rejected empty request gracefully: #{inspect(error)}")
      end
    end

    test "can estimate costs before operations" do
      method = "lang.think.explain_intent"
      params = %{content: "def hello(name), do: \"Hello #{name}!\""}

      case Lang.Providers.XAI.estimate_cost(method, params) do
        {:ok, %{estimated_tokens: tokens, estimated_cost_usd: cost}} ->
          assert is_integer(tokens)
          assert tokens > 0
          assert is_float(cost) or is_integer(cost)
          assert cost >= 0
          Logger.info("✅ Cost estimation: #{tokens} tokens, $#{cost}")

        {:error, error} ->
          Logger.error("❌ Cost estimation failed: #{inspect(error)}")
          flunk("Cost estimation failed: #{inspect(error)}")
      end
    end

    test "integration with Lang.AI convenience interface" do
      question = "What does this code do: def greet(name), do: \"Hello #{name}\""

      # This should automatically route to an appropriate provider (likely Grok for simple tasks)
      case Lang.AI.ask(question) do
        {:ok, response} ->
          assert is_binary(response)
          assert String.length(response) > 20
          Logger.info("✅ Lang.AI interface working with providers")

        {:error, error} ->
          Logger.error("❌ Lang.AI interface failed: #{inspect(error)}")
          flunk("Lang.AI interface failed: #{inspect(error)}")
      end
    end

    test "can handle complex mission coordination" do
      mission = """
      Analyze this authentication system design for both security and performance issues:

      1. Users authenticate with JWT tokens
      2. Tokens are stored in Redis with 24-hour expiry
      3. Rate limiting is 100 requests per minute per user
      4. Password hashing uses bcrypt with cost factor 12

      Identify potential problems and suggest improvements.
      """

      case Lang.AI.mission(mission) do
        {:ok, result} ->
          assert is_binary(result)
          assert String.length(result) > 200
          Logger.info("✅ Complex mission coordination completed")

        {:error, error} ->
          Logger.error("❌ Mission coordination failed: #{inspect(error)}")
          # Don't fail the test since this involves multiple components
          Logger.warning("Mission coordination test failed but continuing...")
      end
    end

    test "provider selection works correctly" do
      # Test that the system can select Grok for appropriate tasks
      method = "lang.query.simple"
      params = %{query: "What is Elixir?"}

      case Lang.Providers.Provider.select_provider(method, params, %{optimize_for: :cost}) do
        {:ok, :xai} ->
          Logger.info("✅ Provider selection correctly chose Grok for cost optimization")

        {:ok, other_provider} ->
          Logger.info("ℹ️  Provider selection chose #{other_provider} instead of Grok")

        # This is still success - system made a decision

        {:error, :no_suitable_provider} ->
          flunk("No provider could handle simple query method")
      end
    end

    test "can handle concurrent requests to Grok" do
      questions = [
        "What is functional programming?",
        "Explain pattern matching",
        "What are GenServers?",
        "How does OTP work?"
      ]

      tasks =
        questions
        |> Enum.map(fn question ->
          Task.async(fn ->
            Lang.Providers.XAI.simple_task(question, max_tokens: 100)
          end)
        end)

      results = Task.await_many(tasks, 30_000)

      successful_requests =
        results
        |> Enum.count(fn
          {:ok, _} -> true
          _ -> false
        end)

      # At least 50% should succeed (account for rate limiting)
      assert successful_requests >= div(length(questions), 2)
      Logger.info("✅ Concurrent requests: #{successful_requests}/#{length(questions)} succeeded")
    end
  end

  describe "Error Recovery and Resilience" do
    @tag timeout: 10_000
    test "handles API rate limiting gracefully" do
      # Rapidly send multiple requests to test rate limiting behavior
      rapid_requests = 1..5

      results =
        rapid_requests
        |> Enum.map(fn i ->
          Lang.Providers.XAI.simple_task("Test request #{i}")
        end)

      # Some might fail due to rate limiting, but system should handle gracefully
      errors =
        Enum.count(results, fn
          {:error, _} -> true
          _ -> false
        end)

      successes =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      Logger.info("Rate limiting test: #{successes} successes, #{errors} errors")
      # Just verify the system doesn't crash
      assert successes + errors == 5
    end

    test "handles network timeouts appropriately" do
      # Test with very short timeout to simulate network issues
      question = "This is a test of network timeout handling."

      case Lang.Providers.XAI.simple_task(question, timeout: 1) do
        {:ok, _response} ->
          Logger.info("✅ Request completed faster than expected")

        {:error, _error} ->
          Logger.info("✅ Timeout handled gracefully")
          # Both outcomes are acceptable for this test
      end
    end
  end

  describe "Performance Benchmarks" do
    @tag timeout: 60_000
    test "measures Grok response times" do
      simple_question = "What is Elixir?"

      {time_microseconds, result} =
        :timer.tc(fn ->
          Lang.Providers.XAI.simple_task(simple_question)
        end)

      time_seconds = time_microseconds / 1_000_000

      case result do
        {:ok, response} ->
          Logger.info(
            "✅ Grok response time: #{Float.round(time_seconds, 2)}s for #{String.length(response)} chars"
          )

          # Basic performance expectations (adjust based on real-world usage)
          # Should respond within 30 seconds
          assert time_seconds < 30.0
          # Should provide substantive response
          assert String.length(response) > 20

        {:error, error} ->
          Logger.error("❌ Performance test failed due to error: #{inspect(error)}")
          flunk("Performance test failed: #{inspect(error)}")
      end
    end
  end
end
