#!/usr/bin/env elixir

# Simple Chat Demo for LANG LSP System
# Demonstrates the AI chat capabilities without requiring full LSP server

defmodule ChatDemo do
  @moduledoc """
  Interactive demo of the LANG AI chat system.
  Shows how different AI agent personalities respond to developer questions.
  """

  def run do
    IO.puts("""
    ██╗      █████╗ ███╗   ██╗ ██████╗     ██████╗██╗  ██╗ █████╗ ████████╗
    ██║     ██╔══██╗████╗  ██║██╔════╝    ██╔════╝██║  ██║██╔══██╗╚══██╔══╝
    ██║     ███████║██╔██╗ ██║██║  ███╗   ██║     ███████║███████║   ██║
    ██║     ██╔══██║██║╚██╗██║██║   ██║   ██║     ██╔══██║██╔══██║   ██║
    ███████╗██║  ██║██║ ╚████║╚██████╔╝   ╚██████╗██║  ██║██║  ██║   ██║
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝     ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝

    🚀 LANG AI Chat System Demo
    Universal Text Intelligence Platform
    """)

    IO.puts("Welcome to the LANG AI Chat Demo!")
    IO.puts("This demonstrates our AI agent personalities for development assistance.\n")

    demo_agents = [
      %{
        name: "🛡️ Security Analyst",
        personality: :security_analyst,
        focus: "Security vulnerabilities, secure coding practices, threat analysis"
      },
      %{
        name: "⚡ Performance Expert",
        personality: :performance_expert,
        focus: "Speed optimization, memory usage, algorithm efficiency"
      },
      %{
        name: "🔧 Refactor Specialist",
        personality: :refactor_specialist,
        focus: "Code quality, clean architecture, technical debt reduction"
      },
      %{
        name: "🚀 Startup Advisor",
        personality: :startup_advisor,
        focus: "Rapid MVP development, resource efficiency, scalability planning"
      },
      %{
        name: "👨‍🏫 Code Mentor",
        personality: :code_mentor,
        focus: "Learning, education, skill development, concept explanation"
      }
    ]

    IO.puts("Available AI Agents:")

    Enum.with_index(demo_agents, 1)
    |> Enum.each(fn {agent, idx} ->
      IO.puts("  #{idx}. #{agent.name}")
      IO.puts("     Focus: #{agent.focus}")
    end)

    agent_choice = get_agent_choice(length(demo_agents))
    chosen_agent = Enum.at(demo_agents, agent_choice - 1)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("🤖 Starting conversation with #{chosen_agent.name}")
    IO.puts(String.duplicate("=", 60))

    start_conversation(chosen_agent)
  end

  defp get_agent_choice(max_choice) do
    choice = IO.gets("\nChoose an agent (1-#{max_choice}): ") |> String.trim()

    case Integer.parse(choice) do
      {num, ""} when num >= 1 and num <= max_choice ->
        num

      _ ->
        IO.puts("Please enter a number between 1 and #{max_choice}")
        get_agent_choice(max_choice)
    end
  end

  defp start_conversation(agent) do
    greeting = generate_greeting(agent.personality)
    IO.puts("#{agent.name}: #{greeting}")
    IO.puts("\nType 'quit' to exit, 'demo' for sample questions, or ask anything!")

    conversation_loop(agent)
  end

  defp conversation_loop(agent) do
    user_input = IO.gets("\nYou: ") |> String.trim()

    case user_input do
      "quit" ->
        IO.puts("\n👋 #{agent.name}: Thanks for chatting! Happy coding!")

      "demo" ->
        show_demo_responses(agent)
        conversation_loop(agent)

      "" ->
        conversation_loop(agent)

      message ->
        response = generate_response(agent.personality, message)
        IO.puts("\n🤖 #{agent.name}: #{response}")
        conversation_loop(agent)
    end
  end

  defp generate_greeting(personality) do
    case personality do
      :security_analyst ->
        "Hello! I'm your security specialist. I'll help you identify vulnerabilities, implement secure coding practices, and protect your applications from threats. What security concerns can I help you with today?"

      :performance_expert ->
        "Hey there! I'm focused on making your code lightning-fast. Whether it's optimizing algorithms, reducing memory usage, or eliminating bottlenecks, I'm here to boost your application's performance. What can we speed up?"

      :refactor_specialist ->
        "Hi! I'm passionate about clean, maintainable code. I can help you restructure messy code, implement design patterns, reduce technical debt, and improve overall code quality. What code would you like to improve?"

      :startup_advisor ->
        "What's up! I'm all about moving fast and building efficiently. I'll help you make smart technology choices, build MVPs quickly, and plan for scale without over-engineering. What are we building today?"

      :code_mentor ->
        "Hello! I'm here to help you learn and grow as a developer. Whether you need concepts explained, want to understand best practices, or need guidance on your coding journey, I'm here to support you. What would you like to learn about?"
    end
  end

  defp generate_response(personality, message) do
    # Analyze message intent
    intent = analyze_message_intent(message)

    case personality do
      :security_analyst -> security_response(message, intent)
      :performance_expert -> performance_response(message, intent)
      :refactor_specialist -> refactor_response(message, intent)
      :startup_advisor -> startup_response(message, intent)
      :code_mentor -> mentor_response(message, intent)
    end
  end

  defp analyze_message_intent(message) do
    lower_msg = String.downcase(message)

    cond do
      String.contains?(lower_msg, ["password", "auth", "login", "secure", "hack", "vulnerability"]) ->
        :security_focus

      String.contains?(lower_msg, ["slow", "fast", "performance", "optimize", "memory", "cpu"]) ->
        :performance_focus

      String.contains?(lower_msg, ["messy", "clean", "refactor", "improve", "structure"]) ->
        :refactor_focus

      String.contains?(lower_msg, ["learn", "explain", "how", "what", "why", "teach"]) ->
        :learning_focus

      String.contains?(lower_msg, ["mvp", "startup", "quick", "fast", "simple"]) ->
        :startup_focus

      true ->
        :general
    end
  end

  defp security_response(message, intent) do
    base_responses = [
      "From a security perspective, here's what I'd recommend:",
      "Looking at this through a security lens:",
      "Security-wise, we need to consider:",
      "This raises some important security considerations:"
    ]

    security_advice =
      case intent do
        :security_focus ->
          "Great question about security! Make sure to validate all inputs, use parameterized queries to prevent SQL injection, implement proper authentication and authorization, and never store passwords in plain text. Always assume user input is malicious."

        :performance_focus ->
          "When optimizing for performance, don't forget about security! Caching sensitive data can be risky, and some performance optimizations might introduce timing attacks. Always profile with security in mind."

        :learning_focus ->
          "Security is crucial to learn early! Start with the OWASP Top 10, understand input validation, learn about common vulnerabilities like XSS and SQL injection, and always think 'how could someone abuse this?'"

        _ ->
          "Every feature should be designed with security in mind. Consider: Who can access this? What data are we handling? How could this be exploited? What's our threat model?"
      end

    "#{Enum.random(base_responses)} #{security_advice}"
  end

  defp performance_response(message, intent) do
    base_responses = [
      "Performance-wise, here's my take:",
      "For optimal performance, consider this:",
      "Speed-wise, we should focus on:",
      "Performance optimization strategy:"
    ]

    perf_advice =
      case intent do
        :performance_focus ->
          "Great performance question! First, profile before optimizing - measure twice, cut once. Look for O(n²) algorithms, unnecessary database queries, memory allocations in loops, and blocking I/O. Sometimes the biggest gains come from caching or choosing better data structures."

        :security_focus ->
          "Security and performance often need balance. Encryption adds overhead, but it's necessary. Hashing passwords should be slow (bcrypt/argon2), input validation has costs, but both are worth it. Optimize after securing."

        :startup_focus ->
          "For startups, focus on performance bottlenecks that affect user experience first. Don't optimize everything - profile in production, fix what matters to users, and remember that developer time is often more expensive than server time."

        _ ->
          "Performance optimization follows the 80/20 rule - 20% of your code uses 80% of resources. Profile to find the real bottlenecks, not what you think they are. Premature optimization is the root of all evil, but no optimization is pretty bad too!"
      end

    "#{Enum.random(base_responses)} #{perf_advice}"
  end

  defp refactor_response(message, intent) do
    base_responses = [
      "From a code quality standpoint:",
      "Refactoring-wise, I'd suggest:",
      "For cleaner code, consider:",
      "Code structure improvement:"
    ]

    refactor_advice =
      case intent do
        :refactor_focus ->
          "Excellent refactoring mindset! Start small - extract functions, remove duplication, improve naming. Follow SOLID principles, keep functions small and focused, and refactor tests alongside code. Red-green-refactor: make it work, make it right, make it fast."

        :performance_focus ->
          "Performance and clean code go hand in hand! Well-structured code is easier to profile and optimize. Extract performance-critical sections into focused functions, use meaningful names, and avoid premature optimization. Clean code is debuggable code."

        :security_focus ->
          "Clean code is more secure code! Clear, simple functions are easier to audit for security issues. Complex, messy code hides bugs and vulnerabilities. Refactor security-critical code to be as simple and obvious as possible."

        _ ->
          "Good code is not just working code - it's readable, maintainable, and extensible. If you're spending more time reading code than writing it, invest in making it clearer. Future you will thank present you!"
      end

    "#{Enum.random(base_responses)} #{refactor_advice}"
  end

  defp startup_response(message, intent) do
    base_responses = [
      "Startup perspective - move fast but smart:",
      "For rapid development, here's my advice:",
      "MVP mindset - let's focus on:",
      "Startup efficiency approach:"
    ]

    startup_advice =
      case intent do
        :startup_focus ->
          "Perfect startup thinking! Build the minimum viable product first - focus on core features that solve real problems. Use proven technologies, leverage existing libraries, and don't reinvent wheels. Ship early, get feedback, iterate fast. Technical debt is okay if it gets you to market faster, just plan to pay it back."

        :performance_focus ->
          "Performance for startups: don't optimize too early, but don't ignore it completely. Focus on performance issues that affect user experience - page load times, API response times. Vertical scaling is often simpler than horizontal scaling early on."

        :security_focus ->
          "Security in startups: can't be ignored, but be pragmatic. Use established auth services (Auth0, Firebase), follow framework security defaults, validate inputs, use HTTPS everywhere. Don't build your own crypto or auth from scratch."

        _ ->
          "Startup success is about speed to market and learning fast. Choose boring technology that works, focus on customer problems not cool tech, and remember - perfect is the enemy of done. Build, measure, learn, repeat."
      end

    "#{Enum.random(base_responses)} #{startup_advice}"
  end

  defp mentor_response(message, intent) do
    base_responses = [
      "Great question! Let me explain:",
      "Learning opportunity here:",
      "This is a fundamental concept:",
      "Let's break this down step by step:"
    ]

    mentor_advice =
      case intent do
        :learning_focus ->
          "I love the curiosity! Learning to code is a journey. Start with fundamentals - understand data structures, algorithms, and design patterns. Practice regularly, build projects that interest you, and don't be afraid to make mistakes. Read other people's code, contribute to open source, and always keep learning new things."

        :security_focus ->
          "Security is a mindset as much as a skill set. Think like an attacker - how would you break this system? Learn about common vulnerabilities, understand threat modeling, and remember that security is everyone's responsibility, not just the security team's."

        :performance_focus ->
          "Performance optimization is both art and science. Learn to measure first - profiling tools are your friends. Understand Big O notation, know your data structures, and remember that the fastest code is code that doesn't run at all. Sometimes the best optimization is doing less work."

        _ ->
          "Every expert was once a beginner. Don't get discouraged by what you don't know - focus on progress, not perfection. Ask questions, experiment, break things in a safe environment, and remember that programming is problem-solving with code as the tool."
      end

    "#{Enum.random(base_responses)} #{mentor_advice}"
  end

  defp show_demo_responses(agent) do
    IO.puts("\n💡 Here are some sample questions you could ask #{agent.name}:")

    samples =
      case agent.personality do
        :security_analyst ->
          [
            "How do I prevent SQL injection in my web app?",
            "What are the most common security vulnerabilities?",
            "How should I store user passwords securely?",
            "What security headers should I add to my API?"
          ]

        :performance_expert ->
          [
            "My API is slow, how do I find bottlenecks?",
            "What's the best way to optimize database queries?",
            "How can I reduce memory usage in my application?",
            "Should I use caching for this use case?"
          ]

        :refactor_specialist ->
          [
            "This function is too long, how should I break it up?",
            "What design patterns would help here?",
            "How do I reduce code duplication?",
            "What makes code more maintainable?"
          ]

        :startup_advisor ->
          [
            "What tech stack should I choose for my MVP?",
            "How do I build fast without creating technical debt?",
            "What features should I prioritize first?",
            "When should I start thinking about scalability?"
          ]

        :code_mentor ->
          [
            "Can you explain how REST APIs work?",
            "What are the benefits of functional programming?",
            "How do I become better at debugging?",
            "What programming concepts should I learn next?"
          ]
      end

    Enum.with_index(samples, 1)
    |> Enum.each(fn {sample, idx} ->
      IO.puts("  #{idx}. #{sample}")
    end)

    IO.puts("\nTry asking one of these, or anything else you're curious about!")
  end
end

# Run the demo
ChatDemo.run()
