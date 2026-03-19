#!/usr/bin/env elixir

Mix.install([
  {:lang, path: "../../"}
])

defmodule ThinkAIDemo do
  @moduledoc """
  Interactive demo showcasing LANG's AI-powered Think operations.

  This script demonstrates the real AI capabilities we've built:
  - Code explanation with multiple AI providers
  - Bug prediction and security analysis
  - Error diagnosis from stacktraces
  - Semantic code search
  - Test generation and code review
  - Timeline operations for code evolution

  Run with: elixir priv/demos/think_ai_demo.exs
  """

  alias Lang.Think.Facade
  alias Lang.Timeline.Core, as: Timeline
  require Logger

  @sample_code """
  defmodule OrderProcessor do
    def process_order(order) do
      with {:ok, validated} <- validate_order(order),
           {:ok, calculated} <- calculate_total(validated),
           {:ok, charged} <- charge_payment(calculated) do
        send_confirmation(charged)
        {:ok, charged}
      else
        {:error, reason} -> {:error, reason}
      end
    end

    defp validate_order(%{items: items} = order) when length(items) > 0 do
      if Enum.all?(items, &valid_item?/1) do
        {:ok, order}
      else
        {:error, :invalid_items}
      end
    end
    defp validate_order(_), do: {:error, :no_items}

    defp calculate_total(%{items: items} = order) do
      total = Enum.reduce(items, 0, &(&1.price * &1.quantity + &2))
      {:ok, Map.put(order, :total, total)}
    end

    defp charge_payment(%{total: total} = order) when total > 0 do
      # Simulate payment processing
      Process.sleep(100)
      {:ok, Map.put(order, :payment_status, :charged)}
    end
    defp charge_payment(_), do: {:error, :invalid_total}

    defp send_confirmation(order) do
      Logger.info("Order confirmed: #{order.id}")
    end

    defp valid_item?(%{price: price, quantity: qty})
      when is_number(price) and price > 0 and is_integer(qty) and qty > 0, do: true
    defp valid_item?(_), do: false
  end
  """

  @sample_stacktrace """
  ** (FunctionClauseError) no function clause matching in OrderProcessor.validate_order/1
      (demo 0.1.0) lib/order_processor.ex:15: OrderProcessor.validate_order(%{})
      (demo 0.1.0) lib/order_processor.ex:3: OrderProcessor.process_order/1
      (demo 0.1.0) lib/demo.ex:20: Demo.run/0
      (elixir 1.15.0) lib/enum.ex:1693: Enum."-map/2-lists^map/1-0-"/2
  """

  def run do
    IO.puts("""

    🧠 LANG AI-Powered Think Operations Demo
    ========================================

    This demo showcases LANG's AI-powered cognitive analysis capabilities.
    We'll analyze Elixir code using real AI providers for intelligent insights.

    """)

    demo_menu()
  end

  defp demo_menu do
    IO.puts("""
    Choose a demo:

    1. 🎯 Code Explanation (Intent, Why, How)
    2. 🔍 Code Analysis (Review, Bugs, Performance)
    3. 🚨 Error Diagnosis
    4. 🔎 Semantic Search
    5. 🧪 Test Generation
    6. ⏰ Timeline Operations
    7. 🚀 Comprehensive Analysis
    8. Exit

    """)

    case get_user_choice() do
      "1" ->
        demo_code_explanation()

      "2" ->
        demo_code_analysis()

      "3" ->
        demo_error_diagnosis()

      "4" ->
        demo_semantic_search()

      "5" ->
        demo_test_generation()

      "6" ->
        demo_timeline_operations()

      "7" ->
        demo_comprehensive_analysis()

      "8" ->
        exit_demo()

      _ ->
        IO.puts("Invalid choice. Please try again.\n")
        demo_menu()
    end
  end

  defp demo_code_explanation do
    IO.puts("""

    🎯 AI-Powered Code Explanation Demo
    ===================================

    We'll analyze the OrderProcessor code with three different explanation styles:

    """)

    # Explain Intent
    IO.puts("🔹 Explaining HIGH-LEVEL INTENT...\n")

    case Facade.explain_intent(@sample_code, language: "elixir", provider: "openai") do
      {:ok, result} ->
        print_result("Intent Analysis", result)

      {:error, reason} ->
        print_fallback("Intent Analysis", reason)
    end

    # Explain Why
    IO.puts("\n🔹 Explaining WHY this approach was chosen...\n")

    case Facade.explain_why(@sample_code, language: "elixir") do
      {:ok, result} ->
        print_result("Why Analysis", result)

      {:error, reason} ->
        print_fallback("Why Analysis", reason)
    end

    # Explain How
    IO.puts("\n🔹 Explaining HOW the code works step-by-step...\n")

    case Facade.explain_how(@sample_code, language: "elixir") do
      {:ok, result} ->
        print_result("How Analysis", result)

      {:error, reason} ->
        print_fallback("How Analysis", reason)
    end

    continue_demo()
  end

  defp demo_code_analysis do
    IO.puts("""

    🔍 AI-Powered Code Analysis Demo
    ================================

    Running comprehensive code analysis...

    """)

    # Bug Prediction
    IO.puts("🔹 Predicting potential bugs...\n")

    case Facade.predict_bugs(@sample_code, language: "elixir") do
      {:ok, result} ->
        print_result("Bug Prediction", result)

      {:error, reason} ->
        print_fallback("Bug Prediction", reason)
    end

    # Security Scan
    IO.puts("\n🔹 Running security analysis...\n")

    case Facade.security_scan(@sample_code, language: "elixir") do
      {:ok, result} ->
        print_result("Security Analysis", result)

      {:error, reason} ->
        print_fallback("Security Analysis", reason)
    end

    # Performance Analysis
    IO.puts("\n🔹 Analyzing performance characteristics...\n")

    case Facade.predict_performance(@sample_code, language: "elixir") do
      {:ok, result} ->
        print_result("Performance Analysis", result)

      {:error, reason} ->
        print_fallback("Performance Analysis", reason)
    end

    continue_demo()
  end

  defp demo_error_diagnosis do
    IO.puts("""

    🚨 AI-Powered Error Diagnosis Demo
    ==================================

    Analyzing a real FunctionClauseError with AI...

    """)

    case Facade.diagnose_error(@sample_stacktrace,
           error_type: "FunctionClauseError",
           context: %{
             recent_changes: "Added validation for empty orders",
             environment: "development"
           }
         ) do
      {:ok, result} ->
        print_result("Error Diagnosis", result)

        IO.puts("\n🔧 Root Cause:")
        IO.puts(result.details.root_cause || "Analysis provided in summary")

        IO.puts("\n💡 Suggested Solutions:")
        solutions = result.details.solutions || ["See analysis above for solutions"]

        Enum.each(solutions, fn solution ->
          IO.puts("  • #{solution}")
        end)

      {:error, reason} ->
        print_fallback("Error Diagnosis", reason)
    end

    continue_demo()
  end

  defp demo_semantic_search do
    IO.puts("""

    🔎 AI-Powered Semantic Search Demo
    ==================================

    Searching for validation-related code...

    """)

    case Facade.find_semantic(
           "functions that validate data or check business rules",
           @sample_code,
           max_results: 5,
           scope: "current_file"
         ) do
      {:ok, result} ->
        print_result("Semantic Search", result)

        matches = result.details.matches || []

        if length(matches) > 0 do
          IO.puts("\n🎯 Found matches:")

          Enum.each(matches, fn match ->
            IO.puts("  • #{inspect(match)}")
          end)
        else
          IO.puts("\n🎯 Search completed - see analysis above for semantic matches")
        end

      {:error, reason} ->
        print_fallback("Semantic Search", reason)
    end

    continue_demo()
  end

  defp demo_test_generation do
    IO.puts("""

    🧪 AI-Powered Test Generation Demo
    ==================================

    Generating comprehensive tests for OrderProcessor...

    """)

    case Facade.generate_tests(@sample_code,
           language: "elixir",
           test_types: ["unit", "integration", "edge_cases"],
           framework: "ExUnit"
         ) do
      {:ok, result} ->
        print_result("Test Generation", result)

        test_cases = result.details.test_cases || []

        if length(test_cases) > 0 do
          IO.puts("\n🧪 Generated Test Cases:")

          Enum.each(test_cases, fn test_case ->
            IO.puts("  • #{inspect(test_case)}")
          end)
        else
          IO.puts("\n🧪 Test generation completed - see analysis for test recommendations")
        end

      {:error, reason} ->
        print_fallback("Test Generation", reason)
    end

    continue_demo()
  end

  defp demo_timeline_operations do
    IO.puts("""

    ⏰ Timeline Operations Demo
    ===========================

    Demonstrating code evolution tracking with Timeline...

    """)

    # Create timeline
    IO.puts("🔹 Creating timeline for OrderProcessor...")

    case Timeline.create_timeline(
           "order_processor_v1",
           %{
             version: "1.0",
             content: @sample_code,
             description: "Initial OrderProcessor implementation"
           },
           %{author: "demo", created_at: DateTime.utc_now()}
         ) do
      {:ok, timeline_id} ->
        IO.puts("✅ Timeline created: #{timeline_id}")

        # Add evolution state
        IO.puts("\n🔹 Adding evolved version...")

        evolved_code =
          String.replace(@sample_code, "Process.sleep(100)", "# Fast payment processing")

        case Timeline.add_state(
               timeline_id,
               %{
                 version: "1.1",
                 content: evolved_code,
                 description: "Optimized payment processing"
               },
               %{author: "demo", optimization: true}
             ) do
          {:ok, state_id} ->
            IO.puts("✅ Evolution state added: #{state_id}")

            # Analyze timeline
            IO.puts("\n🔹 Analyzing timeline evolution...")

            case Timeline.analyze_timeline(timeline_id) do
              {:ok, analysis} ->
                IO.puts("\n📊 Timeline Analysis:")
                IO.puts("  • Total states: #{analysis.total_states}")
                IO.puts("  • Total branches: #{analysis.total_branches}")
                IO.puts("  • Created: #{analysis.creation_date}")
                IO.puts("  • Evolution velocity: #{inspect(analysis.evolution_velocity)}")

              {:error, reason} ->
                IO.puts("❌ Analysis failed: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("❌ Failed to add state: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("❌ Timeline creation failed: #{inspect(reason)}")
    end

    continue_demo()
  end

  defp demo_comprehensive_analysis do
    IO.puts("""

    🚀 Comprehensive AI Analysis Demo
    =================================

    Running multiple AI operations simultaneously...

    """)

    operations = [
      :explain_intent,
      :review_code,
      :predict_bugs,
      :estimate_complexity
    ]

    case Facade.analyze_comprehensive(@sample_code, operations,
           language: "elixir",
           provider: "openai"
         ) do
      {:ok, results} ->
        IO.puts("✅ Comprehensive analysis completed!\n")

        Enum.each(operations, fn operation ->
          case Map.get(results, operation) do
            {:error, reason} ->
              IO.puts("❌ #{operation}: #{inspect(reason)}")

            result ->
              IO.puts("🔹 #{String.upcase(to_string(operation))}:")
              IO.puts("   #{result.summary}")
              IO.puts("   Confidence: #{result.confidence_score}")
              IO.puts("   Provider: #{result.provider_used}\n")
          end
        end)

      {:error, reason} ->
        IO.puts("❌ Comprehensive analysis failed: #{inspect(reason)}")
    end

    continue_demo()
  end

  defp print_result(title, result) do
    IO.puts("✅ #{title} Results:")
    IO.puts("   Summary: #{result.summary}")
    IO.puts("   Confidence: #{result.confidence_score}")
    IO.puts("   Provider: #{result.provider_used}")

    if map_size(result.metrics) > 0 do
      IO.puts("   Metrics: #{inspect(result.metrics)}")
    end
  end

  defp print_fallback(title, reason) do
    IO.puts("⚠️  #{title} using fallback (AI provider unavailable):")
    IO.puts("   Reason: #{inspect(reason)}")
    IO.puts("   Note: In production, this would use local analysis with basic insights.")
  end

  defp continue_demo do
    IO.puts("\nPress Enter to return to menu...")
    IO.gets("")
    demo_menu()
  end

  defp exit_demo do
    IO.puts("""

    🎉 LANG AI Think Operations Demo Complete!
    ==========================================

    You've seen LANG's AI-powered cognitive capabilities:

    ✅ Real AI-powered code explanation and analysis
    ✅ Intelligent error diagnosis from stacktraces
    ✅ Semantic code search and similarity matching
    ✅ AI-generated test cases and code review
    ✅ Timeline operations for code evolution tracking
    ✅ Fallback handling when AI providers are unavailable

    Key Features Demonstrated:
    • Multi-provider AI integration (OpenAI, Anthropic, xAI)
    • Sophisticated prompt engineering for code analysis
    • Confidence scoring and quality assessment
    • Async and sync operation modes
    • Comprehensive error handling and fallbacks
    • Real-time timeline operations for code evolution

    Next Steps:
    • Try integrating with your editor via LSP
    • Explore the REST API endpoints
    • Configure your preferred AI providers
    • Set up async processing for large codebases

    Happy coding with LANG! 🚀

    """)
  end

  defp get_user_choice do
    IO.gets("Choose option (1-8): ")
    |> String.trim()
  end
end

# Start the demo
ThinkAIDemo.run()
