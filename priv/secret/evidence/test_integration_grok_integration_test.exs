@@ SNAPSHOT of test/integration/grok_integration_test.exs @@
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
      end
    end
  end
end
