defmodule Lang.Commands.TalkToGrok do
  @moduledoc """
  Direct command-line interface to talk to Grok.

  Provides a simple way to send commands and questions directly to Grok
  for testing and debugging the xAI integration.
  """

  require Logger
  alias Lang.Providers.{XAI, Router}

  @doc """
  Send a direct message to Grok and get response
  """
  def ask(question, opts \\ []) when is_binary(question) do
    Logger.info("Sending question to Grok", question: question)

    case XAI.analyze_situation("", question, opts) do
      {:ok, %{analysis: response}} ->
        IO.puts("\n" <> String.duplicate("=", 60))
        IO.puts("🤖 GROK RESPONDS:")
        IO.puts(String.duplicate("=", 60))
        IO.puts(response)
        IO.puts(String.duplicate("=", 60) <> "\n")
        {:ok, response}

      {:error, error} ->
        IO.puts("❌ Grok failed to respond: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Send a mission command to Grok commander
  """
  def command_mission(mission_description, opts \\ []) when is_binary(mission_description) do
    Logger.info("Sending mission to Grok commander", mission: mission_description)

    case Router.command_mission(mission_description, opts) do
      {:ok, %{mission_plan: %{tasks: tasks}, raw_response: response}} ->
        IO.puts("\n" <> String.duplicate("=", 60))
        IO.puts("🎯 GROK MISSION COMMAND:")
        IO.puts(String.duplicate("=", 60))
        IO.puts(response)
        IO.puts("\n📋 PARSED TASKS:")

        tasks
        |> Enum.with_index(1)
        |> Enum.each(fn {task, index} ->
          IO.puts("  #{index}. [#{task.provider}] #{task.description} (#{task.priority})")
        end)

        IO.puts(String.duplicate("=", 60) <> "\n")
        {:ok, {response, tasks}}

      {:ok, %{raw_response: response}} ->
        # Fallback when task parsing fails
        IO.puts("\n" <> String.duplicate("=", 60))
        IO.puts("🎯 GROK MISSION RESPONSE:")
        IO.puts(String.duplicate("=", 60))
        IO.puts(response)
        IO.puts("⚠️  (Task parsing failed - showing raw response)")
        IO.puts(String.duplicate("=", 60) <> "\n")
        {:ok, response}

      {:error, error} ->
        IO.puts("❌ Mission command failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Interactive conversation with Grok
  """
  def chat do
    IO.puts("""

    🚀 LANG LSP - Direct Chat with Grok Commander
    ===============================================

    Type your questions or commands. Type 'quit' to exit.

    Commands:
    - ask <question>        : Ask Grok a direct question
    - mission <description> : Send a mission command
    - health               : Check Grok's health
    - quit                 : Exit chat

    """)

    chat_loop()
  end

  defp chat_loop do
    input =
      IO.gets("🤖 You: ")
      |> String.trim()

    case input do
      "quit" ->
        IO.puts("👋 Goodbye!")

      "health" ->
        case XAI.health_check() do
          {:ok, message} -> IO.puts("✅ #{message}")
          {:error, error} -> IO.puts("❌ Health check failed: #{inspect(error)}")
        end

        chat_loop()

      "ask " <> question ->
        ask(question)
        chat_loop()

      "mission " <> mission ->
        command_mission(mission)
        chat_loop()

      "" ->
        chat_loop()

      question ->
        # Default to asking Grok
        ask(question)
        chat_loop()
    end
  end

  @doc """
  Test all provider connections
  """
  def test_all_providers do
    IO.puts("\n🧪 Testing All AI Providers")
    IO.puts(String.duplicate("=", 40))

    providers = [:xai, :openai, :anthropic]

    results =
      Enum.map(providers, fn provider ->
        IO.write("Testing #{provider}... ")

        result =
          case provider do
            :xai -> XAI.health_check()
            :openai -> Lang.Providers.OpenAI.health_check()
            :anthropic -> Lang.Providers.Anthropic.health_check()
          end

        case result do
          {:ok, message} ->
            IO.puts("✅ #{message}")
            {provider, :healthy}

          {:error, error} ->
            IO.puts("❌ #{inspect(error)}")
            {provider, :unhealthy}
        end
      end)

    healthy_count = Enum.count(results, fn {_, status} -> status == :healthy end)

    IO.puts("\n📊 Summary: #{healthy_count}/#{length(providers)} providers healthy")
    results
  end

  @doc """
  Quick demonstration of provider capabilities
  """
  def demo do
    IO.puts("""

    🎯 LANG LSP Provider Demo
    =========================

    This will demonstrate each AI provider's specialty:
    """)

    # Test Grok (Command & Coordination)
    IO.puts("\n1️⃣  Testing Grok (Mission Commander)")

    case ask(
           "You are the mission commander. Analyze this task: 'Review authentication system for security issues'. Break it into subtasks for different AI specialists."
         ) do
      {:ok, _} -> IO.puts("✅ Grok coordination test passed")
      {:error, _} -> IO.puts("❌ Grok test failed")
    end

    # Test OpenAI (Code Generation)
    IO.puts("\n2️⃣  Testing OpenAI (Code Generation)")

    case Lang.Providers.OpenAI.handle_request("lang.generate.from_spec", %{
           specification: "Create a simple function that validates email addresses",
           language: "elixir"
         }) do
      {:ok, _} -> IO.puts("✅ OpenAI generation test passed")
      {:error, _} -> IO.puts("❌ OpenAI test failed")
    end

    # Test Anthropic (Security Analysis)
    IO.puts("\n3️⃣  Testing Anthropic (Security Analysis)")

    case Lang.Providers.Anthropic.handle_request("lang.think.security_scan", %{
           content: "def login(email, password), do: User.authenticate(email, password)"
         }) do
      {:ok, _} -> IO.puts("✅ Anthropic security test passed")
      {:error, _} -> IO.puts("❌ Anthropic test failed")
    end

    IO.puts("\n🎉 Demo complete! All providers tested.")
  end

  @doc """
  Show provider capabilities matrix
  """
  def show_capabilities do
    IO.puts("""

    🧠 AI Provider Capabilities Matrix
    ==================================
    """)

    Lang.Providers.Provider.capability_matrix()
    |> Enum.each(fn {provider, info} ->
      IO.puts("\n#{String.upcase(to_string(provider))}:")
      IO.puts("  Best for: #{Enum.join(info.best_for, ", ")}")
      IO.puts("  Avoid for: #{Enum.join(info.avoid_for, ", ")}")
      IO.puts("  Specializes in: #{Enum.join(info.specializes_in, ", ")}")
    end)

    IO.puts("\n💰 Cost Comparison:")

    Lang.Providers.Provider.all_pricing()
    |> Enum.each(fn {provider, pricing} ->
      IO.puts("  #{provider}: #{pricing.cost_tier} (${pricing.base_cost_per_request} base)")
    end)
  end
end
