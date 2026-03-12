#!/usr/bin/env elixir

# Demo script for LANG Token Cost Calculation System
# This demonstrates the cost calculation features we've implemented
# Run with: mix run demo_cost_calculation.exs

defmodule CostCalculationDemo do
  @moduledoc """
  Demonstration of the LANG cost calculation system.
  
  Shows how to:
  - Calculate costs for different providers and models
  - Compare costs across providers
  - Track session costs
  - Format costs for display
  - Generate cost alerts and recommendations
  """

  require Logger

  def run do
    IO.puts("🚀 LANG Cost Calculation System Demo")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("")

    # Demo 1: Basic cost calculation
    demo_basic_cost_calculation()

    # Demo 2: Provider comparison
    demo_provider_comparison()

    # Demo 3: Session cost tracking (simulated)
    demo_session_tracking()

    # Demo 4: Real-time streaming costs
    demo_streaming_costs()

    # Demo 5: Cost optimization recommendations
    demo_cost_optimization()

    # Demo 6: LSP integration format
    demo_lsp_formatting()

    IO.puts("\n✅ Demo completed! The cost calculation system is ready for LSP integration.")
  end

  defp demo_basic_cost_calculation do
    IO.puts("💰 Demo 1: Basic Cost Calculation")
    IO.puts("-" |> String.duplicate(30))

    # Simulate different token usages
    scenarios = [
      %{
        name: "Quick Query",
        usage: %{input_tokens: 50, output_tokens: 100},
        provider: :openai,
        model: "gpt-4o-mini"
      },
      %{
        name: "Code Generation",
        usage: %{input_tokens: 500, output_tokens: 800},
        provider: :openai,
        model: "gpt-4o"
      },
      %{
        name: "Analysis Task",
        usage: %{input_tokens: 1200, output_tokens: 600},
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      },
      %{
        name: "Local Development",
        usage: %{input_tokens: 800, output_tokens: 400},
        provider: :ollama,
        model: "llama3.1:8b"
      }
    ]

    Enum.each(scenarios, fn scenario ->
      cost = calculate_cost_safe(scenario.provider, scenario.model, scenario.usage)
      
      IO.puts("  #{scenario.name}:")
      IO.puts("    Provider: #{scenario.provider} (#{scenario.model})")
      IO.puts("    Tokens: #{scenario.usage.input_tokens} in, #{scenario.usage.output_tokens} out")
      
      case cost do
        {:ok, result} ->
          IO.puts("    Cost: #{format_cost_safe(result.total_cost)}")
          IO.puts("    Breakdown: Input #{format_cost_safe(result.input_cost)}, Output #{format_cost_safe(result.output_cost)}")
        {:error, reason} ->
          IO.puts("    Cost: N/A (#{reason[:error] || reason})")
      end
      
      IO.puts("")
    end)
  end

  defp demo_provider_comparison do
    IO.puts("🔄 Demo 2: Provider Cost Comparison")
    IO.puts("-" |> String.duplicate(30))

    # Test usage pattern
    usage = %{input_tokens: 1000, output_tokens: 500}
    
    # Available provider/model combinations
    providers = [
      {:openai, "gpt-4o-mini"},
      {:openai, "gpt-4o"},
      {:anthropic, "claude-3-5-haiku-20241022"},
      {:anthropic, "claude-3-5-sonnet-20241022"},
      {:gemini, "gemini-1.5-flash"},
      {:gemini, "gemini-1.5-pro"},
      {:ollama, "llama3.1:8b"}
    ]

    IO.puts("Comparing costs for #{usage.input_tokens} input + #{usage.output_tokens} output tokens:\n")

    results = Enum.map(providers, fn {provider, model} ->
      case calculate_cost_safe(provider, model, usage) do
        {:ok, cost} ->
          %{
            provider: provider,
            model: model,
            cost: cost.total_cost,
            formatted_cost: format_cost_safe(cost.total_cost),
            available: true
          }
        {:error, _} ->
          %{
            provider: provider,
            model: model,
            cost: :infinity,
            formatted_cost: "N/A",
            available: false
          }
      end
    end)

    # Sort by cost (available first, then by cost)
    sorted_results = 
      results
      |> Enum.sort_by(fn r -> {!r.available, r.cost} end)

    Enum.with_index(sorted_results, 1) |> Enum.each(fn {result, rank} ->
      status = if result.available, do: "✅", else: "❌"
      IO.puts("  #{rank}. #{status} #{result.provider}/#{result.model} - #{result.formatted_cost}")
    end)

    # Show savings
    if length(Enum.filter(results, & &1.available)) >= 2 do
      available_results = Enum.filter(results, & &1.available)
      cheapest = Enum.min_by(available_results, & &1.cost)
      most_expensive = Enum.max_by(available_results, & &1.cost)
      
      if cheapest.cost != most_expensive.cost do
        savings = most_expensive.cost - cheapest.cost
        savings_pct = (savings / most_expensive.cost * 100) |> Float.round(1)
        IO.puts("\n  💡 Potential savings: #{format_cost_safe(savings)} (#{savings_pct}%) by choosing #{cheapest.provider}/#{cheapest.model}")
      end
    end

    IO.puts("")
  end

  defp demo_session_tracking do
    IO.puts("📊 Demo 3: Session Cost Tracking")
    IO.puts("-" |> String.duplicate(30))

    # Simulate a chat session with multiple messages
    session_id = "demo_chat_#{:rand.uniform(1000)}"
    IO.puts("Starting session: #{session_id}")
    IO.puts("Budget limit: $2.00")

    session = create_session(session_id, %{budget_limit: 2.00})

    # Simulate various messages
    messages = [
      {%{input_tokens: 100, output_tokens: 200}, :openai, "gpt-4o-mini", "Quick question"},
      {%{input_tokens: 500, output_tokens: 800}, :anthropic, "claude-3-5-sonnet-20241022", "Code review"},
      {%{input_tokens: 300, output_tokens: 400}, :openai, "gpt-4o", "Complex analysis"},
      {%{input_tokens: 150, output_tokens: 300}, :gemini, "gemini-1.5-flash", "Follow-up"},
      {%{input_tokens: 800, output_tokens: 600}, :anthropic, "claude-3-5-sonnet-20241022", "Final summary"}
    ]

    Enum.with_index(messages, 1) |> Enum.each(fn {{usage, provider, model, msg_type}, idx} ->
      case calculate_cost_safe(provider, model, usage) do
        {:ok, cost_data} ->
          session = add_message_to_session(session, cost_data, msg_type)
          
          IO.puts("  Message #{idx} (#{msg_type}): #{format_cost_safe(cost_data.total_cost)} - Running total: #{format_cost_safe(session.total_cost)}")
          
          # Check for budget alerts
          if session.budget_limit && session.total_cost > session.budget_limit * 0.8 do
            utilization = (session.total_cost / session.budget_limit * 100) |> Float.round(1)
            if session.total_cost >= session.budget_limit do
              IO.puts("    🚨 Budget exceeded! #{utilization}% used")
            else
              IO.puts("    ⚠️  Approaching budget: #{utilization}% used")
            end
          end

        {:error, _} ->
          IO.puts("  Message #{idx} (#{msg_type}): Cost calculation failed")
      end
    end)

    # Show session summary
    IO.puts("\n  📈 Session Summary:")
    IO.puts("    Total cost: #{format_cost_safe(session.total_cost)}")
    IO.puts("    Messages: #{session.message_count}")
    IO.puts("    Average cost/message: #{format_cost_safe(session.total_cost / max(session.message_count, 1))}")
    
    total_tokens = session.total_input_tokens + session.total_output_tokens
    IO.puts("    Total tokens: #{format_number(total_tokens)}")
    
    if session.budget_limit do
      utilization = (session.total_cost / session.budget_limit * 100) |> Float.round(1)
      IO.puts("    Budget utilization: #{utilization}%")
    end

    IO.puts("")
  end

  defp demo_streaming_costs do
    IO.puts("📡 Demo 4: Streaming Cost Estimation")
    IO.puts("-" |> String.duplicate(30))

    # Simulate streaming response progression
    provider = :openai
    model = "gpt-4o"
    
    # Simulate progressive token counts during streaming
    stages = [
      {%{input_tokens: 100, output_tokens: 50}, "25% complete"},
      {%{input_tokens: 100, output_tokens: 100}, "50% complete"},
      {%{input_tokens: 100, output_tokens: 150}, "75% complete"},
      {%{input_tokens: 100, output_tokens: 200}, "100% complete"}
    ]
    
    estimated_final = %{input_tokens: 100, output_tokens: 200}

    IO.puts("Streaming response cost tracking (#{provider}/#{model}):")
    IO.puts("")

    Enum.each(stages, fn {current_tokens, stage} ->
      case calculate_cost_safe(provider, model, current_tokens) do
        {:ok, current_cost} ->
          case calculate_cost_safe(provider, model, estimated_final) do
            {:ok, final_cost} ->
              progress = (current_tokens.output_tokens / estimated_final.output_tokens * 100) |> Float.round(1)
              remaining = final_cost.total_cost - current_cost.total_cost
              
              IO.puts("  #{stage}:")
              IO.puts("    💰 Current: #{format_cost_safe(current_cost.total_cost)}")
              IO.puts("    🎯 Estimated final: #{format_cost_safe(final_cost.total_cost)}")
              IO.puts("    📊 Progress: #{progress}%")
              IO.puts("    ⏳ Remaining: #{format_cost_safe(remaining)}")
              IO.puts("")

            {:error, _} ->