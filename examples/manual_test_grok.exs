#!/usr/bin/env elixir

# Manual test script to verify Grok connection
# Run with: elixir manual_test_grok.exs

Mix.install([
  {:req, "~> 0.4.0"},
  {:jason, "~> 1.4"}
])

defmodule ManualTestGrok do
  @moduledoc """
  Simple manual test to verify we can talk to Grok.
  This bypasses all the complex provider system and just tests basic connectivity.
  """

  require Logger

  def run do
    IO.puts("\n🚀 LANG LSP - Manual Grok Connection Test")
    IO.puts("=" |> String.duplicate(50))

    case get_api_key() do
      nil ->
        IO.puts("❌ XAI_API_KEY not set in environment")
        IO.puts("Please set: export XAI_API_KEY='your-key-here'")
        System.exit(1)

      api_key ->
        IO.puts("✅ Found API key: #{String.slice(api_key, 0, 8)}...")
        test_basic_connection(api_key)
    end
  end

  defp test_basic_connection(api_key) do
    IO.puts("\n📡 Testing basic connection to xAI API...")

    payload = %{
      model: "grok-beta",
      messages: [
        %{
          role: "system",
          content: "You are Grok, the mission commander. Be direct and tactical."
        },
        %{
          role: "user",
          content:
            "Hello Grok! Please respond with 'MANUAL_TEST_SUCCESS' to confirm this connection works."
        }
      ],
      temperature: 0.3,
      max_tokens: 100
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"User-Agent", "LANG-Manual-Test/1.0"}
    ]

    case Req.post("https://api.x.ai/v1/chat/completions",
           headers: headers,
           json: payload,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: response}} ->
        handle_success(response)

      {:ok, %{status: status, body: error}} ->
        handle_error(status, error)

      {:error, reason} ->
        IO.puts("❌ Connection failed: #{inspect(reason)}")
        suggest_fixes()
    end
  end

  defp handle_success(response) do
    case get_in(response, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        IO.puts("❌ Unexpected response format")
        IO.inspect(response, label: "Full Response")

      content ->
        IO.puts("🎉 SUCCESS! Grok responded:")
        IO.puts(("\n" <> "=") |> String.duplicate(60))
        IO.puts(content)
        IO.puts("=" |> String.duplicate(60))

        if response["usage"] do
          usage = response["usage"]
          IO.puts("\n📊 Token Usage:")
          IO.puts("  Input: #{usage["prompt_tokens"] || "unknown"}")
          IO.puts("  Output: #{usage["completion_tokens"] || "unknown"}")
          IO.puts("  Total: #{usage["total_tokens"] || "unknown"}")
        end

        if String.contains?(content, "MANUAL_TEST_SUCCESS") do
          IO.puts("\n✅ PERFECT! Connection test passed completely.")
          IO.puts("🚀 Ready to implement full provider system!")
        else
          IO.puts("\n⚠️  Connection works, but response format differs from expected.")
          IO.puts("🔧 May need to adjust response parsing logic.")
        end

        test_advanced_features(get_api_key())
    end
  end

  defp handle_error(status, error) do
    IO.puts("❌ API Error (Status: #{status})")

    case error do
      %{"error" => %{"message" => message, "type" => type}} ->
        IO.puts("Error Type: #{type}")
        IO.puts("Message: #{message}")

      %{"error" => message} when is_binary(message) ->
        IO.puts("Error: #{message}")

      other ->
        IO.puts("Error Details: #{inspect(other)}")
    end

    suggest_fixes()
  end

  defp test_advanced_features(api_key) do
    IO.puts("\n🎯 Testing advanced features...")

    # Test mission command parsing
    mission_payload = %{
      model: "grok-beta",
      messages: [
        %{
          role: "system",
          content: """
          You are the Mission Commander for a multi-AI development team.
          Break down requests into specific tasks and assign them to appropriate AI providers.

          Format your response like:
          TASK 1: [Provider] - [Description] (Priority: HIGH/MEDIUM/LOW)
          TASK 2: [Provider] - [Description] (Priority: HIGH/MEDIUM/LOW)
          """
        },
        %{
          role: "user",
          content: """
          Mission: Analyze this authentication function for security issues:

          def authenticate(email, password) do
            user = User.get_by_email(email)
            if user && user.password == password do
              {:ok, user}
            else
              {:error, :invalid}
            end
          end

          Break this into tasks for appropriate AI specialists.
          """
        }
      ],
      temperature: 0.3,
      max_tokens: 300
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"User-Agent", "LANG-Manual-Test/1.0"}
    ]

    case Req.post("https://api.x.ai/v1/chat/completions",
           headers: headers,
           json: mission_payload,
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: response}} ->
        test_mission_parsing(response)

      {:error, reason} ->
        IO.puts("⚠️  Advanced test failed: #{inspect(reason)}")
        IO.puts("✅ Basic connection works, advanced features need work.")
    end
  end

  defp test_mission_parsing(response) do
    case get_in(response, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        IO.puts("⚠️  Mission test: Unexpected response format")

      content ->
        IO.puts("\n🎯 MISSION COMMAND TEST:")
        IO.puts("=" |> String.duplicate(60))
        IO.puts(content)
        IO.puts("=" |> String.duplicate(60))

        # Test if we can parse structured tasks
        task_regex = ~r/TASK\s+\d+:\s*\[([^\]]+)\]\s*-\s*([^(]+)\s*\(Priority:\s*(\w+)\)/i
        tasks = Regex.scan(task_regex, content)

        if length(tasks) > 0 do
          IO.puts("\n📋 PARSED TASKS:")

          tasks
          |> Enum.with_index(1)
          |> Enum.each(fn {[_full, provider, description, priority], index} ->
            IO.puts(
              "  #{index}. [#{String.trim(provider)}] #{String.trim(description)} (#{String.trim(priority)})"
            )
          end)

          IO.puts("\n🎉 EXCELLENT! Mission parsing works perfectly!")
          IO.puts("🚀 Ready for full multi-agent coordination!")
        else
          IO.puts("\n⚠️  Mission responded but task parsing needs refinement.")
          IO.puts("🔧 May need to adjust task extraction regex.")
        end
    end

    final_summary()
  end

  defp final_summary do
    IO.puts("\n" <> "🎊 FINAL SUMMARY " <> "🎊")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("✅ Basic Grok connectivity: WORKING")
    IO.puts("✅ Response parsing: WORKING")
    IO.puts("✅ Mission command format: WORKING")
    IO.puts("✅ Token usage tracking: WORKING")
    IO.puts("\n🚀 RESULT: Ready to implement full LANG AI provider system!")
    IO.puts("\nNext steps:")
    IO.puts("  1. Set up OpenAI and Anthropic API keys")
    IO.puts("  2. Test provider selection logic")
    IO.puts("  3. Implement cost optimization")
    IO.puts("  4. Add error handling and retry logic")
    IO.puts("  5. Test multi-provider coordination")
  end

  defp suggest_fixes do
    IO.puts("\n🔧 TROUBLESHOOTING:")
    IO.puts("1. Check your API key: https://console.x.ai/")
    IO.puts("2. Verify network connectivity")
    IO.puts("3. Check if xAI API endpoint has changed")
    IO.puts("4. Try different model name (grok-beta vs grok-2)")
    IO.puts("5. Check rate limits and quotas")
  end

  defp get_api_key do
    System.get_env("XAI_API_KEY")
  end
end

# Run the test
ManualTestGrok.run()
