#!/usr/bin/env elixir

# Tool Profiling and Scenario Optimization Demo
# This script demonstrates the complete Tool Inventory Capture System
# for optimizing AI provider testing based on actual capabilities

defmodule Lang.Providers.Provider do
  @callback capabilities() :: map()
  @callback available?() :: boolean()
  @callback handle_request(method :: String.t(), params :: map(), opts :: keyword()) ::
              {:ok, result :: map()} | {:error, reason :: any()}
end

# Load the providers
Code.require_file("lib/lang/providers/opencode.ex", ".")

# Simulate other providers for demo
defmodule MockProvider do
  def simulate_provider_response(provider_name, method, _params) do
    case {provider_name, method} do
      {:anthropic, "explain"} ->
        {:ok,
         %{
           explanation: """
           FILESYSTEM:
           - No direct file access: Cannot read files directly
           - No directory traversal: Cannot navigate filesystem

           CODE_EXECUTION:
           - No code execution: Cannot run Python, shell commands, or compile code
           - Text analysis only: Can analyze code as text

           ANALYSIS:
           - Security analysis: Strong vulnerability detection capabilities
           - Code review: Detailed analysis of code quality and safety
           - Pattern recognition: Identify anti-patterns and best practices

           EXTERNAL_SERVICES:
           - No HTTP requests: Cannot make external API calls
           - No database access: Cannot query databases directly

           LIMITATIONS:
           - Cannot execute code or access filesystem
           - Analysis based on provided text only
           - No real-time data access
           """,
           confidence: 0.88,
           provider: "anthropic"
         }}

      {:gemini, "explain"} ->
        {:ok,
         %{
           explanation: """
           FILESYSTEM:
           - No direct access: Cannot read files or traverse directories
           - Text processing only: Work with provided file contents

           CODE_EXECUTION:
           - No execution capability: Cannot run code directly
           - Simulation possible: Can simulate execution logic

           ANALYSIS:
           - Multimodal analysis: Can process text, code, and images together
           - Performance analysis: Strong algorithmic complexity analysis
           - Large context: Handle very large codebases efficiently

           EXTERNAL_SERVICES:
           - No direct access: Cannot make HTTP calls or database queries
           - Fast processing: Optimized for quick response times

           LIMITATIONS:
           - No real execution or filesystem access
           - Analysis limited to provided context
           - Cannot persist data or maintain state
           """,
           confidence: 0.86,
           provider: "gemini"
         }}

      {provider, _} ->
        {:ok,
         %{
           explanation: "Mock response for #{provider} - capabilities analysis",
           confidence: 0.7,
           provider: to_string(provider)
         }}
    end
  end
end

defmodule ToolProfilingDemo do
  @moduledoc """
  Comprehensive demonstration of Tool Inventory Capture System
  """

  @providers [
    {:opencode, Lang.Providers.OpenCode, "🆓 OpenCode (Self-Hosted)", true},
    {:anthropic, :mock, "🧠 Claude (Anthropic)", false},
    {:gemini, :mock, "✨ Gemini (Google)", false},
    {:openai, :mock, "🚀 GPT (OpenAI)", false}
  ]

  def run_comprehensive_demo do
    IO.puts("""
    🔍 LANG Tool Profiling & Scenario Optimization Demo
    ==================================================
    Demonstrating intelligent test optimization based on provider capabilities
    """)

    # Step 1: Profile all providers
    IO.puts("\n📋 STEP 1: Provider Tool Profiling")
    IO.puts("=" |> String.duplicate(50))

    provider_profiles = profile_all_providers()
    print_profiling_summary(provider_profiles)

    # Step 2: Generate base scenarios
    IO.puts("\n🎯 STEP 2: Base Scenario Generation")
    IO.puts("=" |> String.duplicate(50))

    base_scenarios = generate_base_scenarios()
    print_scenarios(base_scenarios)

    # Step 3: Optimize scenarios per provider
    IO.puts("\n⚡ STEP 3: Tool-Aware Scenario Optimization")
    IO.puts("=" |> String.duplicate(50))

    optimized_suite = optimize_scenarios_for_providers(base_scenarios, provider_profiles)
    print_optimization_results(optimized_suite)

    # Step 4: Demonstrate LANG value proposition
    IO.puts("\n💎 STEP 4: LANG Value Demonstration")
    IO.puts("=" |> String.duplicate(50))

    demonstrate_lang_value(optimized_suite)

    # Step 5: Generate recommendations
    IO.puts("\n🎯 STEP 5: Intelligent Routing Recommendations")
    IO.puts("=" |> String.duplicate(50))

    generate_routing_recommendations(provider_profiles, optimized_suite)
  end

  # =============================================================================
  # Provider Profiling
  # =============================================================================

  defp profile_all_providers do
    IO.puts("Profiling provider tools and capabilities...")

    @providers
    |> Enum.map(fn {name, module, description, available} ->
      IO.write("  #{description}: ")

      profile =
        case {module, available} do
          {Lang.Providers.OpenCode, true} ->
            profile_real_provider(module)

          {:mock, false} ->
            profile_mock_provider(name)

          _ ->
            %{available: false, reason: "Not configured"}
        end

      case profile do
        %{available: true} ->
          IO.puts("✅ Profiled successfully")

        %{available: false, reason: reason} ->
          IO.puts("❌ #{reason}")
      end

      {name, Map.put(profile, :description, description)}
    end)
    |> Map.new()
  end

  defp profile_real_provider(module) do
    case module.handle_request("explain", %{
           code: """
           Before we begin testing, please provide a complete inventory of your available tools.

           What tools and capabilities do you have for:
           - Filesystem operations
           - Code execution
           - External services
           - Analysis capabilities
           """,
           question: "List your available tools and limitations"
         }) do
      {:ok, response} ->
        tools = parse_tool_response(response)

        %{
          available: true,
          method: :direct_query,
          tools: tools,
          # OpenCode is fast
          response_time: 150,
          efficiency_rating: calculate_efficiency_rating(tools),
          profiled_at: DateTime.utc_now()
        }

      {:error, reason} ->
        %{available: false, reason: "Profiling failed: #{inspect(reason)}"}
    end
  end

  defp profile_mock_provider(provider_name) do
    # Simulate profiling of external providers
    case MockProvider.simulate_provider_response(provider_name, "explain", %{}) do
      {:ok, response} ->
        tools = parse_tool_response(response)

        %{
          # Mock as unavailable (no API key)
          available: false,
          simulated: true,
          expected_tools: tools,
          expected_efficiency: get_expected_efficiency(provider_name),
          limitations: get_provider_limitations(provider_name)
        }

      {:error, _reason} ->
        %{available: false, reason: "Mock profiling failed"}
    end
  end

  defp parse_tool_response(response) do
    explanation =
      case response do
        %{explanation: text} -> text
        %{content: text} -> text
        _ -> inspect(response)
      end

    # Simple parsing of tool categories
    %{
      filesystem: extract_capabilities(explanation, "FILESYSTEM:"),
      code_execution: extract_capabilities(explanation, "CODE_EXECUTION:"),
      analysis: extract_capabilities(explanation, "ANALYSIS:"),
      external_services: extract_capabilities(explanation, "EXTERNAL_SERVICES:"),
      limitations: extract_capabilities(explanation, "LIMITATIONS:"),
      raw_response: String.slice(explanation, 0, 200) <> "..."
    }
  end

  defp extract_capabilities(text, section) do
    case Regex.run(~r/#{Regex.escape(section)}(.*?)(?=\n[A-Z]+:|$)/s, text) do
      [_, section_content] ->
        section_content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "-"))
        |> length()

      nil ->
        0
    end
  end

  defp calculate_efficiency_rating(tools) do
    # Simple efficiency calculation based on tool availability
    total_tools =
      tools.filesystem + tools.code_execution + tools.analysis + tools.external_services

    case total_tools do
      # Basic capability
      0 -> 0.3
      # Limited tools
      1..2 -> 0.5
      # Good tool coverage
      3..5 -> 0.7
      # Excellent tools
      _ -> 0.9
    end
  end

  defp get_expected_efficiency(provider_name) do
    case provider_name do
      # Strong analysis, limited tools
      :anthropic -> 0.4
      # Fast processing, moderate tools
      :gemini -> 0.6
      # Good generation, limited tools
      :openai -> 0.5
      _ -> 0.3
    end
  end

  defp get_provider_limitations(provider_name) do
    case provider_name do
      :anthropic -> ["No filesystem access", "No code execution", "Analysis focused"]
      :gemini -> ["No direct execution", "Fast but limited tools", "Multimodal capable"]
      :openai -> ["No filesystem access", "No execution", "Generation focused"]
      _ -> ["Unknown limitations"]
    end
  end

  # =============================================================================
  # Scenario Generation
  # =============================================================================

  defp generate_base_scenarios do
    [
      %{
        name: "Simple Code Completion",
        complexity: :low,
        base_tokens: 5_000,
        description: "Complete basic function definitions",
        filesystem_heavy: false,
        execution_required: false
      },
      %{
        name: "Security Analysis",
        complexity: :high,
        base_tokens: 75_000,
        description: "Identify vulnerabilities and security issues",
        filesystem_heavy: true,
        execution_required: false
      },
      %{
        name: "Performance Optimization",
        complexity: :very_high,
        base_tokens: 100_000,
        description: "Analyze and optimize code performance",
        filesystem_heavy: true,
        execution_required: true
      },
      %{
        name: "Test Suite Generation",
        complexity: :medium,
        base_tokens: 40_000,
        description: "Generate comprehensive test cases",
        filesystem_heavy: false,
        execution_required: true
      }
    ]
  end

  defp print_scenarios(scenarios) do
    Enum.each(scenarios, fn scenario ->
      IO.puts("""
      📝 #{scenario.name}
      ├─ Complexity: #{scenario.complexity}
      ├─ Base Tokens: #{format_number(scenario.base_tokens)}
      ├─ Filesystem Heavy: #{scenario.filesystem_heavy}
      ├─ Execution Required: #{scenario.execution_required}
      └─ Description: #{scenario.description}
      """)
    end)
  end

  # =============================================================================
  # Scenario Optimization
  # =============================================================================

  defp optimize_scenarios_for_providers(scenarios, provider_profiles) do
    scenarios
    |> Enum.flat_map(fn scenario ->
      provider_profiles
      |> Enum.map(fn {provider_name, profile} ->
        optimize_scenario_for_provider(scenario, provider_name, profile)
      end)
    end)
  end

  defp optimize_scenario_for_provider(scenario, provider_name, profile) do
    optimizations = generate_optimizations(scenario, profile)
    token_savings = calculate_token_savings(optimizations)
    lang_value = assess_lang_value(scenario, profile, optimizations)

    %{
      provider: provider_name,
      scenario: scenario,
      profile: profile,
      optimizations: optimizations,
      token_savings: token_savings,
      optimized_tokens: scenario.base_tokens - token_savings,
      lang_value_score: lang_value,
      recommendation: generate_recommendation(scenario, profile, lang_value)
    }
  end

  defp generate_optimizations(scenario, profile) do
    optimizations = []

    # Filesystem optimization
    optimizations =
      if scenario.filesystem_heavy and not has_filesystem_tools?(profile) do
        [
          %{
            type: :pre_indexed_files,
            description: "Provide pre-scanned file structure and content",
            saves_tokens: 30_000,
            lang_benefit: "LANG's native filesystem scanning eliminates exploration overhead"
          }
          | optimizations
        ]
      else
        optimizations
      end

    # Execution optimization
    optimizations =
      if scenario.execution_required and not has_execution_tools?(profile) do
        [
          %{
            type: :pre_computed_results,
            description: "Provide pre-executed test results and performance data",
            saves_tokens: 25_000,
            lang_benefit: "LANG's execution environment provides instant results"
          }
          | optimizations
        ]
      else
        optimizations
      end

    # Provider-specific optimizations
    optimizations = add_provider_specific_optimizations(optimizations, scenario, profile)

    optimizations
  end

  defp has_filesystem_tools?(profile) do
    case profile do
      %{tools: %{filesystem: count}} when count > 0 -> true
      %{efficiency_rating: rating} when rating > 0.7 -> true
      _ -> false
    end
  end

  defp has_execution_tools?(profile) do
    case profile do
      %{tools: %{code_execution: count}} when count > 0 -> true
      %{efficiency_rating: rating} when rating > 0.8 -> true
      _ -> false
    end
  end

  defp add_provider_specific_optimizations(optimizations, scenario, profile) do
    case Map.get(profile, :description, "") do
      desc ->
        cond do
          String.contains?(desc, "Claude") and scenario.complexity == :low ->
            [
              %{
                type: :focused_prompts,
                description: "Focus Claude on specific analysis rather than general explanation",
                saves_tokens: 5_000,
                lang_benefit: "LANG optimizes prompts per provider strengths"
              }
              | optimizations
            ]

          String.contains?(desc, "Gemini") ->
            [
              %{
                type: :context_optimization,
                description: "Leverage Gemini's large context window efficiently",
                saves_tokens: 8_000,
                lang_benefit: "LANG maximizes each provider's unique capabilities"
              }
              | optimizations
            ]

          true ->
            optimizations
        end

      _ ->
        optimizations
    end
  end

  defp calculate_token_savings(optimizations) do
    optimizations
    |> Enum.map(&Map.get(&1, :saves_tokens, 0))
    |> Enum.sum()
  end

  defp assess_lang_value(scenario, profile, optimizations) do
    base_value =
      case scenario.complexity do
        :low -> 25
        :medium -> 50
        :high -> 75
        :very_high -> 100
      end

    tool_gap_bonus =
      case profile do
        # High value for unavailable providers
        %{available: false} -> 50
        %{efficiency_rating: rating} when rating < 0.5 -> 40
        %{efficiency_rating: rating} when rating < 0.7 -> 25
        _ -> 10
      end

    optimization_bonus = min(length(optimizations) * 15, 60)

    base_value + tool_gap_bonus + optimization_bonus
  end

  defp generate_recommendation(_scenario, profile, lang_value) do
    cond do
      not Map.get(profile, :available, false) ->
        "Route to OpenCode for cost-free testing"

      lang_value > 80 ->
        "High LANG value - significant optimization opportunity"

      lang_value > 50 ->
        "Medium LANG value - moderate optimization benefit"

      true ->
        "Low LANG value - provider handles task efficiently"
    end
  end

  # =============================================================================
  # Results Display
  # =============================================================================

  defp print_profiling_summary(provider_profiles) do
    IO.puts("\n📊 Provider Profiling Summary:")

    Enum.each(provider_profiles, fn {name, profile} ->
      status = if Map.get(profile, :available, false), do: "✅ Available", else: "❌ Unavailable"

      efficiency =
        Map.get(profile, :efficiency_rating, Map.get(profile, :expected_efficiency, 0.0))

      IO.puts("""

      #{Map.get(profile, :description, to_string(name))}
      ├─ Status: #{status}
      ├─ Efficiency: #{Float.round(efficiency * 100, 1)}%
      └─ Tools: #{describe_tools(profile)}
      """)
    end)
  end

  defp describe_tools(profile) do
    case profile do
      %{tools: tools} ->
        total = tools.filesystem + tools.code_execution + tools.analysis + tools.external_services
        "#{total} capabilities detected"

      %{limitations: limitations} ->
        "Limited: #{Enum.join(limitations, ", ")}"

      _ ->
        "Tool analysis pending"
    end
  end

  defp print_optimization_results(optimized_suite) do
    # Group by scenario for better display
    optimized_suite
    |> Enum.group_by(fn opt -> opt.scenario.name end)
    |> Enum.each(fn {scenario_name, provider_optimizations} ->
      IO.puts("\n🎯 #{scenario_name}:")

      Enum.each(provider_optimizations, fn opt ->
        provider_desc = get_provider_description(opt.provider, opt.profile)

        savings_pct =
          if opt.scenario.base_tokens > 0 do
            Float.round(opt.token_savings / opt.scenario.base_tokens * 100, 1)
          else
            0.0
          end

        IO.puts("""
        ├─ #{provider_desc}
        │  ├─ Original tokens: #{format_number(opt.scenario.base_tokens)}
        │  ├─ Token savings: #{format_number(opt.token_savings)} (#{savings_pct}%)
        │  ├─ Optimized tokens: #{format_number(opt.optimized_tokens)}
        │  ├─ LANG value score: #{opt.lang_value_score}/100
        │  ├─ Optimizations: #{length(opt.optimizations)}
        │  └─ Recommendation: #{opt.recommendation}
        """)

        if length(opt.optimizations) > 0 do
          IO.puts("   📋 Optimizations Applied:")

          Enum.each(opt.optimizations, fn optimization ->
            IO.puts("     • #{optimization.description}")
            IO.puts("       └─ LANG Benefit: #{optimization.lang_benefit}")
          end)
        end
      end)
    end)
  end

  defp get_provider_description(provider_name, profile) do
    Map.get(profile, :description, to_string(provider_name))
  end

  # =============================================================================
  # LANG Value Demonstration
  # =============================================================================

  defp demonstrate_lang_value(optimized_suite) do
    total_scenarios = length(optimized_suite)

    # Calculate aggregate savings
    total_original_tokens = optimized_suite |> Enum.map(& &1.scenario.base_tokens) |> Enum.sum()
    total_token_savings = optimized_suite |> Enum.map(& &1.token_savings) |> Enum.sum()
    total_optimized_tokens = optimized_suite |> Enum.map(& &1.optimized_tokens) |> Enum.sum()

    avg_lang_value =
      optimized_suite |> Enum.map(& &1.lang_value_score) |> Enum.sum() |> div(total_scenarios)

    IO.puts("""
    💎 LANG Platform Value Proposition:

    📊 Aggregate Analysis (#{total_scenarios} test scenarios):
    ├─ Original token requirement: #{format_number(total_original_tokens)}
    ├─ LANG-optimized tokens: #{format_number(total_optimized_tokens)}
    ├─ Total tokens saved: #{format_number(total_token_savings)}
    ├─ Average efficiency gain: #{Float.round(total_token_savings / total_original_tokens * 100, 1)}%
    └─ Average LANG value score: #{avg_lang_value}/100

    🎯 Key Value Propositions:
    """)

    # Identify highest-value scenarios
    high_value_scenarios =
      optimized_suite
      |> Enum.filter(fn opt -> opt.lang_value_score > 70 end)
      |> Enum.take(3)

    if length(high_value_scenarios) > 0 do
      IO.puts("\n🏆 Highest Value Opportunities:")

      Enum.each(high_value_scenarios, fn opt ->
        savings_pct = Float.round(opt.token_savings / opt.scenario.base_tokens * 100, 1)

        IO.puts(
          "   • #{opt.scenario.name} with #{get_provider_description(opt.provider, opt.profile)}"
        )

        IO.puts(
          "     └─ #{savings_pct}% efficiency gain, #{opt.lang_value_score}/100 value score"
        )
      end)
    end

    # Show provider gaps LANG addresses
    IO.puts("""

    🔧 Provider Capability Gaps LANG Addresses:
    ├─ Filesystem Access: LANG's native scanning eliminates exploration overhead
    ├─ Code Execution: LANG's runtime provides instant results without API limits
    ├─ Context Management: LANG handles large codebases beyond token limits
    ├─ Tool Integration: LANG bridges capability gaps across all providers
    └─ Cost Optimization: OpenCode provides unlimited testing, smart routing saves costs
    """)
  end

  # =============================================================================
  # Routing Recommendations
  # =============================================================================

  defp generate_routing_recommendations(_provider_profiles, optimized_suite) do
    # Analyze which providers perform best for each scenario type
    scenario_recommendations =
      optimized_suite
      |> Enum.group_by(fn opt -> opt.scenario.name end)
      |> Enum.map(fn {scenario_name, opts} ->
        best_option =
          Enum.max_by(opts, fn opt ->
            case Map.get(opt.profile, :available, false) do
              # Factor in token cost
              true -> opt.lang_value_score - opt.optimized_tokens / 1000
              # Heavily penalize unavailable providers
              false -> -1000
            end
          end)

        {scenario_name, best_option}
      end)

    IO.puts("🎯 Intelligent Routing Strategy:")

    # Development recommendations
    IO.puts("""

    🧪 Development & Testing Phase:
    └─ Route ALL requests to OpenCode (FREE testing)
       ├─ Zero API costs during development
       ├─ Unlimited testing and experimentation
       ├─ Consistent responses for test automation
       └─ Perfect for CI/CD pipelines
    """)

    # Production recommendations
    IO.puts("\n🚀 Production Routing Recommendations:")

    Enum.each(scenario_recommendations, fn {scenario_name, best_opt} ->
      provider_name = best_opt.provider
      profile = best_opt.profile
      available = Map.get(profile, :available, false)

      status_icon = if available, do: "✅", else: "⚠️"
      availability_note = if available, do: "", else: " (Configure API key)"

      IO.puts("""

      📋 #{scenario_name}:
      ├─ #{status_icon} Best Provider: #{get_provider_description(provider_name, profile)}#{availability_note}
      ├─ Expected tokens: #{format_number(best_opt.optimized_tokens)}
      ├─ LANG value: #{best_opt.lang_value_score}/100
      └─ Reason: #{best_opt.recommendation}
      """)
    end)

    # Cost optimization summary
    IO.puts("""

    💰 Cost Optimization Strategy:
    ├─ Development: Use OpenCode (FREE) for all testing
    ├─ Simple tasks: Route to most cost-effective available provider
    ├─ Complex analysis: Route to specialized providers (Claude for security)
    ├─ High-volume: Use LANG's caching and optimization features
    └─ Fallback: Always fallback to OpenCode when providers unavailable

    🎯 Expected Cost Savings with LANG:
    ├─ Development costs: 100% savings (OpenCode is free)
    ├─ Production efficiency: Significant token reduction through optimization
    ├─ Smart routing: Route only complex tasks to expensive providers
    └─ Comprehensive testing: Unlimited validation without API costs
    """)
  end

  # =============================================================================
  # Utility Functions
  # =============================================================================

  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 1)}K"
  end

  defp format_number(num), do: "#{num}"
end

# Run the comprehensive demo
ToolProfilingDemo.run_comprehensive_demo()

IO.puts("""

🎊 Tool Profiling Demo Complete!
================================

Key Takeaways:
✅ LANG intelligently profiles each provider's capabilities
✅ Scenarios are optimized based on actual tool availability
✅ Providers with fewer tools benefit MORE from LANG optimization
✅ OpenCode enables unlimited cost-free testing and development
✅ Smart routing maximizes value while minimizing costs

Next Steps:
1. Configure API keys for production providers
2. Use OpenCode for all development and testing (FREE!)
3. Implement LANG's smart routing in your application
4. Monitor token usage and optimize based on real patterns

🚀 Build unlimited AI capabilities without unlimited bills!
""")
