#!/usr/bin/env elixir

# Simple test script to communicate with Grok
# Run with: elixir test_grok.exs

Mix.install([
  {:req, "~> 0.4.0"},
  {:jason, "~> 1.4"}
])

defmodule TestGrok do
  require Logger

  @base_url "https://api.x.ai/v1"

  def run do
    Logger.info("Testing xAI Grok connection...")

    case get_api_key() do
      nil ->
        IO.puts("❌ XAI_API_KEY environment variable not set")
        System.exit(1)

      api_key ->
        IO.puts("✅ API key found")
        test_connection(api_key)
    end
  end

  defp test_connection(api_key) do
    IO.puts("\n🚀 Attempting to connect to Grok...")

    payload = %{
      model: "grok-beta",
      messages: [
        %{
          role: "system",
          content:
            "You are Grok, the mission commander for a multi-AI development team. Be direct and tactical."
        },
        %{
          role: "user",
          content: """
          Hello Grok! I'm testing the connection from the LANG LSP system.

          Please respond with:
          1. Confirmation you can receive this message
          2. A brief tactical assessment of this codebase integration task
          3. Your readiness to coordinate with other AI providers (OpenAI, Anthropic)
          """
        }
      ],
      temperature: 0.3,
      max_tokens: 500
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"User-Agent", "LANG-LSP-Test/1.0"}
    ]

    case Req.post(@base_url <> "/chat/completions", headers: headers, json: payload) do
      {:ok, %{status: 200, body: response}} ->
        handle_success(response)

      {:ok, %{status: status, body: error_body}} ->
        handle_error(status, error_body)

      {:error, reason} ->
        IO.puts("❌ Request failed: #{inspect(reason)}")
        System.exit(1)
    end
  end

  defp handle_success(response) do
    case get_in(response, ["choices", Access.at(0), "message", "content"]) do
      nil ->
        IO.puts("❌ Unexpected response format")
        IO.inspect(response, label: "Full Response")

      content ->
        IO.puts("✅ SUCCESS! Grok responded:")
        IO.puts("\n" <> String.duplicate("=", 60))
        IO.puts(content)
        IO.puts(String.duplicate("=", 60))

        # Show usage stats if available
        if usage = response["usage"] do
          IO.puts("\n📊 Usage Stats:")
          IO.puts("  Input tokens: #{usage["prompt_tokens"] || "unknown"}")
          IO.puts("  Output tokens: #{usage["completion_tokens"] || "unknown"}")
          IO.puts("  Total tokens: #{usage["total_tokens"] || "unknown"}")
        end

        IO.puts("\n🎉 Grok is ready for mission command!")
    end
  end

  defp handle_error(status, error_body) do
    IO.puts("❌ API Error (#{status})")

    case error_body do
      %{"error" => %{"message" => message}} ->
        IO.puts("Error: #{message}")

      %{"error" => error} when is_binary(error) ->
        IO.puts("Error: #{error}")

      _ ->
        IO.puts("Error body: #{inspect(error_body)}")
    end

    System.exit(1)
  end

  defp get_api_key do
    System.get_env("XAI_API_KEY")
  end
end

# Run the test
TestGrok.run()
