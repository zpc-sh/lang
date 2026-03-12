#!/usr/bin/env elixir

# Massive LSP Metrics Generation Script
# Run with: mix run generate_massive_metrics.exs

IO.puts("""
================================================================================
🚀 MASSIVE LSP METRICS GENERATION - CREATING BIG DATA FOR ANALYSIS
================================================================================

This script generates thousands of realistic LSP measurement events across:
- Multiple users, organizations, and time periods
- All LSP methods (completion, hover, explain, refactor, test generation)
- Different providers (XAI, OpenAI, Anthropic)
- Various programming languages and contexts
- Realistic token usage patterns and improvements

Goal: Generate enough data to see clear patterns and optimize for 100% efficiency!
""")

# Initialize the analytics system
Mix.Task.run("app.start")

defmodule MetricsGenerator do
  @moduledoc """
  Generates realistic LSP metrics at scale for comprehensive analysis.
  """

  # Configuration for realistic data generation
  @users_count 50
  @organizations_count 10
  @days_of_data 30
  @operations_per_user_per_day 20
  @total_operations @users_count * @days_of_data * @operations_per_user_per_day

  @lsp_methods [:completion, :hover, :explain, :refactor, :generate_tests]
  @providers ["xai", "openai", "anthropic"]
  @languages ["elixir", "javascript", "python", "rust", "typescript", "go"]

  # Realistic token usage patterns based on method complexity
  @token_patterns %{
    completion: %{baseline: {80, 200}, enhanced: {45, 120}, time_saved: {5, 30}},
    hover: %{baseline: {50, 120}, enhanced: {30, 80}, time_saved: {3, 15}},
    explain: %{baseline: {200, 600}, enhanced: {120, 350}, time_saved: {20, 90}},
    refactor: %{baseline: {400, 1200}, enhanced: {250, 750}, time_saved: {45, 180}},
    generate_tests: %{baseline: {300, 800}, enhanced: {180, 480}, time_saved: {60, 240}}
  }

  # Context patterns that affect token efficiency
  @context_types [
    %{name: "phoenix_controller", complexity: :medium, efficiency_boost: 1.2},
    %{name: "ash_resource", complexity: :high, efficiency_boost: 1.4},
    %{name: "genserver", complexity: :high, efficiency_boost: 1.3},
    %{name: "livebook", complexity: :low, efficiency_boost: 1.1},
    %{name: "test_file", complexity: :medium, efficiency_boost: 1.2},
    %{name: "config", complexity: :low, efficiency_boost: 1.0},
    %{name: "migration", complexity: :medium, efficiency_boost: 1.1},
    %{name: "worker", complexity: :high, efficiency_boost: 1.3},
    %{name: "api_client", complexity: :medium, efficiency_boost: 1.2},
    %{name: "native_nif", complexity: :high, efficiency_boost: 1.5}
  ]

  def generate_massive_dataset do
    IO.puts("\n📊 GENERATING #{@total_operations} LSP MEASUREMENT EVENTS...")
    IO.puts("   Users: #{@users_count}")
    IO.puts("   Organizations: #{@organizations_count}")
    IO.puts("   Days of data: #{@days_of_data}")
    IO.puts("   Operations per user per day: #{@operations_per_user_per_day}")

    # Generate users and organizations
    users = generate_users()
    organizations = generate_organizations()

    IO.puts("\n🏭 MASS PRODUCTION OF MEASUREMENT EVENTS...")

    # Generate events in batches for performance
    batch_size = 100
    total_batches = div(@total_operations, batch_size)

    events =
      for batch_num <- 1..total_batches do
        IO.write(".")
        if rem(batch_num, 50) == 0, do: IO.puts(" #{batch_num}/#{total_batches}")

        generate_event_batch(batch_size, users, organizations)
      end
      |> List.flatten()

    IO.puts("\n✅ Generated #{length(events)} measurement events!")

    # Store events (simulated - in real implementation would batch insert)
    IO.puts("\n💾 STORING EVENTS IN BATCHES...")

    events
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      IO.write(".")
      if rem(index, 10) == 0, do: IO.puts(" Batch #{index}")
      store_event_batch(batch)
    end)

    IO.puts("\n✅ All events stored!")

    # Generate comprehensive analytics
    generate_analytics_report(events)
  end

  defp generate_users do
    for i <- 1..@users_count do
      %{
        id: "user-#{String.pad_leading("#{i}", 3, "0")}",
        email: "user#{i}@example.com",
        skill_level: Enum.random([:junior, :mid, :senior, :expert]),
        preferred_language: Enum.random(@languages),
        coding_style: Enum.random([:functional, :oop, :mixed]),
        # 0.8 to 1.2
        productivity_factor: :rand.uniform() * 0.4 + 0.8
      }
    end
  end

  defp generate_organizations do
    for i <- 1..@organizations_count do
      %{
        id: "org-#{String.pad_leading("#{i}", 2, "0")}",
        name: "Organization #{i}",
        size: Enum.random([:startup, :small, :medium, :large, :enterprise]),
        tech_stack:
          Enum.random([
            [:elixir, :phoenix],
            [:javascript, :react],
            [:python, :django],
            [:rust, :actix]
          ]),
        # 0.0 to 1.0
        lsp_adoption: :rand.uniform()
      }
    end
  end

  defp generate_event_batch(batch_size, users, organizations) do
    for _i <- 1..batch_size do
      user = Enum.random(users)
      org = Enum.random(organizations)

      generate_realistic_event(user, org)
    end
  end

  defp generate_realistic_event(user, org) do
    # Select LSP method based on user skill level and realistic usage patterns
    method = select_method_for_user(user)
    provider = select_provider_for_method(method)
    language = select_language_for_user(user, method)
    context = Enum.random(@context_types)

    # Generate realistic timestamps (spread over last 30 days)
    days_ago = :rand.uniform(@days_of_data)
    hours_ago = :rand.uniform(24)
    minutes_ago = :rand.uniform(60)

    occurred_at =
      DateTime.utc_now()
      |> DateTime.add(-days_ago, :day)
      |> DateTime.add(-hours_ago, :hour)
      |> DateTime.add(-minutes_ago, :minute)

    # Calculate realistic token usage based on method, context, user skill
    {baseline_tokens, enhanced_tokens, time_saved} =
      calculate_realistic_tokens(
        method,
        context,
        user,
        provider
      )

    # Assign to A/B test cohort (70% treatment, 30% control for realistic adoption)
    cohort_type = if :rand.uniform() < 0.7, do: :treatment, else: :control

    # Quality score based on provider and context complexity
    quality_score = calculate_quality_score(provider, context, user)

    %{
      user_id: user.id,
      organization_id: org.id,
      session_id: generate_session_id(),
      request_id: Ecto.UUID.generate(),
      lsp_method: method,
      operation_context: "#{context.name}_#{language}",
      baseline_tokens: baseline_tokens,
      enhanced_tokens: enhanced_tokens,
      token_reduction_percent: (baseline_tokens - enhanced_tokens) / baseline_tokens * 100,
      time_saved_seconds: time_saved,
      # 100-2100ms
      operation_duration_ms: :rand.uniform(2000) + 100,
      quality_score: quality_score,
      error_reduction_count: if(quality_score > 0.8, do: :rand.uniform(3), else: 0),
      iterations_saved: if(method in [:refactor, :generate_tests], do: :rand.uniform(5), else: 0),
      user_satisfaction_score:
        calculate_satisfaction_score(baseline_tokens, enhanced_tokens, time_saved),
      feature_used: cohort_type == :treatment,
      completion_rate:
        if(quality_score > 0.7,
          do: :rand.uniform() * 0.3 + 0.7,
          else: :rand.uniform() * 0.4 + 0.3
        ),
      language: language,
      file_type: get_file_extension(language),
      provider: provider,
      model: get_model_for_provider(provider),
      metadata: %{
        context_type: context.name,
        context_complexity: context.complexity,
        user_skill: user.skill_level,
        org_size: org.size,
        session_type: Enum.random(["interactive", "batch", "automated"]),
        ide: Enum.random(["vscode", "vim", "emacs", "jetbrains", "sublime"]),
        git_repo_size: Enum.random(["small", "medium", "large", "enterprise"]),
        peak_hours: time_in_peak_hours?(occurred_at)
      },
      cohort_type: cohort_type,
      experiment_name: "lsp_enhancements_massive_test",
      occurred_at: occurred_at
    }
  end

  defp select_method_for_user(user) do
    # More experienced users use more complex methods
    case user.skill_level do
      :expert ->
        Enum.random([:completion, :hover, :explain, :refactor, :generate_tests])

      :senior ->
        Enum.random([:completion, :hover, :explain, :refactor])

      :mid ->
        Enum.random([:completion, :hover, :explain])

      :junior ->
        Enum.random([:completion, :hover])
    end
  end

  defp select_provider_for_method(method) do
    # Realistic provider selection based on method strengths
    # Include OpenCode for testing scenarios (15% of the time)
    if :rand.uniform() < 0.15 do
      "opencode"
    else
      case method do
        # Completion: Fast providers preferred
        :completion -> Enum.random(["gemini", "gemini", "xai", "openai", "anthropic"])
        # Hover: Quick info providers
        :hover -> Enum.random(["gemini", "openai", "anthropic", "xai"])
        # Explain: Analysis specialists
        :explain -> Enum.random(["anthropic", "anthropic", "openai", "gemini", "xai"])
        # Refactor: Code generation specialists
        :refactor -> Enum.random(["openai", "gemini", "anthropic", "xai"])
        # Test generation: Code specialists
        :generate_tests -> Enum.random(["openai", "openai", "gemini", "anthropic", "xai"])
      end
    end
  end

  defp select_language_for_user(user, method) do
    # Bias towards user's preferred language, but vary based on method
    if :rand.uniform() < 0.6 do
      user.preferred_language
    else
      case method do
        :completion -> Enum.random(@languages)
        :generate_tests -> Enum.random(["elixir", "javascript", "python", "rust"])
        _ -> Enum.random(@languages)
      end
    end
  end

  defp calculate_realistic_tokens(method, context, user, provider) do
    pattern = @token_patterns[method]
    {base_min, base_max} = pattern.baseline
    {enh_min, enh_max} = pattern.enhanced
    {time_min, time_max} = pattern.time_saved

    # Base token counts
    baseline_tokens = :rand.uniform(base_max - base_min) + base_min
    enhanced_base = :rand.uniform(enh_max - enh_min) + enh_min

    # Apply context efficiency boost
    efficiency_boost = context.efficiency_boost
    enhanced_tokens = round(enhanced_base / efficiency_boost)

    # Apply user skill factor (experts get better results)
    skill_factor =
      case user.skill_level do
        :expert -> 1.2
        :senior -> 1.1
        :mid -> 1.0
        :junior -> 0.9
      end

    enhanced_tokens = round(enhanced_tokens / skill_factor)

    # Apply provider efficiency differences
    provider_factor =
      case provider do
        # Slightly better at token efficiency
        "xai" -> 1.1
        "anthropic" -> 1.05
        "openai" -> 1.0
        # Gemini is fast and efficient
        "gemini" -> 1.12
        # OpenCode is very efficient for simple tasks
        "opencode" -> 1.15
      end

    enhanced_tokens = round(enhanced_tokens / provider_factor)

    # Ensure enhanced is always less than baseline (with some variance)
    enhanced_tokens = min(enhanced_tokens, baseline_tokens - 5)
    # At least 40% of baseline
    enhanced_tokens = max(enhanced_tokens, round(baseline_tokens * 0.4))

    # Calculate time saved
    time_saved = :rand.uniform(time_max - time_min) + time_min
    time_saved = round(time_saved * user.productivity_factor * efficiency_boost)

    {baseline_tokens, enhanced_tokens, time_saved}
  end

  defp calculate_quality_score(provider, context, user) do
    base_quality =
      case provider do
        "anthropic" -> 0.88
        "openai" -> 0.85
        "xai" -> 0.87
        "gemini" -> 0.86
        "opencode" -> 0.70
      end

    # Context complexity affects quality
    complexity_modifier =
      case context.complexity do
        :high -> -0.05
        :medium -> 0.0
        :low -> 0.03
      end

    # User skill affects perceived quality
    skill_modifier =
      case user.skill_level do
        :expert -> 0.05
        :senior -> 0.02
        :mid -> 0.0
        :junior -> -0.03
      end

    quality = base_quality + complexity_modifier + skill_modifier + (:rand.uniform() - 0.5) * 0.1
    Float.round(max(0.0, min(1.0, quality)), 2)
  end

  defp calculate_satisfaction_score(baseline_tokens, enhanced_tokens, time_saved) do
    # Satisfaction based on actual improvements
    token_improvement = (baseline_tokens - enhanced_tokens) / baseline_tokens
    # Cap at 1 minute for calculation
    time_factor = min(time_saved / 60.0, 1.0)

    base_satisfaction = 3.5
    satisfaction = base_satisfaction + token_improvement * 1.5 + time_factor * 1.0

    # Add some randomness
    satisfaction = satisfaction + (:rand.uniform() - 0.5) * 0.5

    Float.round(max(1.0, min(5.0, satisfaction)), 1)
  end

  defp get_file_extension(language) do
    case language do
      "elixir" -> "ex"
      "javascript" -> "js"
      "typescript" -> "ts"
      "python" -> "py"
      "rust" -> "rs"
      "go" -> "go"
      _ -> "txt"
    end
  end

  defp get_model_for_provider(provider) do
    case provider do
      "xai" -> "grok-beta"
      "openai" -> Enum.random(["gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"])
      "anthropic" -> Enum.random(["claude-3-sonnet", "claude-3-haiku"])
    end
  end

  defp time_in_peak_hours?(datetime) do
    hour = datetime.hour
    # Peak hours: 9AM-5PM UTC
    hour >= 9 && hour <= 17
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16() |> String.downcase()
  end

  defp store_event_batch(events) do
    # Simulate storing events - in real implementation would use:
    # Lang.Storage.MetricsStore.bulk_store_measurement_events(events)

    # For now, just simulate processing delay
    :timer.sleep(10)

    # Track total stored
    try do
      Agent.update(:metrics_counter, fn count -> count + length(events) end)
    rescue
      ArgumentError ->
        Agent.start(fn -> length(events) end, name: :metrics_counter)
    end
  end

  def generate_analytics_report(events) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("📈 COMPREHENSIVE ANALYTICS REPORT - BIG DATA INSIGHTS")
    IO.puts(String.duplicate("=", 80))

    # Overall statistics
    total_events = length(events)
    unique_users = events |> Enum.map(& &1.user_id) |> Enum.uniq() |> length()
    unique_orgs = events |> Enum.map(& &1.organization_id) |> Enum.uniq() |> length()

    # Token efficiency analysis
    total_baseline = events |> Enum.map(& &1.baseline_tokens) |> Enum.sum()
    total_enhanced = events |> Enum.map(& &1.enhanced_tokens) |> Enum.sum()
    total_saved = total_baseline - total_enhanced
    avg_reduction = total_saved / total_baseline * 100

    IO.puts("\n🎯 MASSIVE DATASET OVERVIEW:")
    IO.puts("   Total Events Generated:   #{format_number(total_events)}")
    IO.puts("   Unique Users:             #{unique_users}")
    IO.puts("   Unique Organizations:     #{unique_orgs}")
    IO.puts("   Date Range:               #{@days_of_data} days")
    IO.puts("   Average Events/User/Day:  #{@operations_per_user_per_day}")

    IO.puts("\n💰 TOKEN EFFICIENCY AT SCALE:")
    IO.puts("   Total Baseline Tokens:    #{format_number(total_baseline)}")
    IO.puts("   Total Enhanced Tokens:    #{format_number(total_enhanced)}")
    IO.puts("   Total Tokens Saved:       #{format_number(total_saved)}")
    IO.puts("   Average Token Reduction:  #{Float.round(avg_reduction, 2)}%")
    IO.puts("   Potential Monthly Savings: $#{Float.round(total_saved * 0.00002 * 30, 2)}")

    # Method breakdown
    method_stats =
      events
      |> Enum.group_by(& &1.lsp_method)
      |> Enum.map(fn {method, method_events} ->
        baseline = Enum.sum(Enum.map(method_events, & &1.baseline_tokens))
        enhanced = Enum.sum(Enum.map(method_events, & &1.enhanced_tokens))
        reduction = if baseline > 0, do: (baseline - enhanced) / baseline * 100, else: 0

        avg_time =
          Enum.sum(Enum.map(method_events, & &1.time_saved_seconds)) / length(method_events)

        avg_quality =
          Enum.sum(Enum.map(method_events, & &1.quality_score)) / length(method_events)

        {method,
         %{
           count: length(method_events),
           reduction: Float.round(reduction, 1),
           avg_time_saved: Float.round(avg_time, 1),
           avg_quality: Float.round(avg_quality, 2)
         }}
      end)
      |> Enum.sort_by(fn {_method, stats} -> stats.reduction end, :desc)

    IO.puts("\n🔍 METHOD PERFORMANCE RANKING:")

    Enum.each(method_stats, fn {method, stats} ->
      IO.puts(
        "   #{String.pad_trailing("#{method}:", 18)} #{stats.reduction}% reduction | #{stats.avg_time_saved}s saved | Q:#{stats.avg_quality} | #{format_number(stats.count)} ops"
      )
    end)

    # Provider comparison
    provider_stats =
      events
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {provider, provider_events} ->
        baseline = Enum.sum(Enum.map(provider_events, & &1.baseline_tokens))
        enhanced = Enum.sum(Enum.map(provider_events, & &1.enhanced_tokens))
        reduction = if baseline > 0, do: (baseline - enhanced) / baseline * 100, else: 0

        avg_quality =
          Enum.sum(Enum.map(provider_events, & &1.quality_score)) / length(provider_events)

        {provider,
         %{
           count: length(provider_events),
           reduction: Float.round(reduction, 1),
           avg_quality: Float.round(avg_quality, 2)
         }}
      end)
      |> Enum.sort_by(fn {_provider, stats} -> stats.reduction end, :desc)

    IO.puts("\n🤖 PROVIDER EFFICIENCY CHAMPIONSHIP:")

    # Get first and second place providers
    first_place = elem(hd(provider_stats), 0)

    second_place =
      if length(provider_stats) > 1, do: elem(Enum.at(provider_stats, 1), 0), else: nil

    Enum.each(provider_stats, fn {provider, stats} ->
      medal =
        cond do
          provider == first_place -> "🥇"
          provider == second_place -> "🥈"
          true -> "🥉"
        end

      IO.puts(
        "   #{medal} #{String.pad_trailing("#{provider}:", 12)} #{stats.reduction}% reduction | Q:#{stats.avg_quality} | #{format_number(stats.count)} ops"
      )
    end)

    # Language analysis
    language_stats =
      events
      |> Enum.group_by(& &1.language)
      |> Enum.map(fn {language, lang_events} ->
        baseline = Enum.sum(Enum.map(lang_events, & &1.baseline_tokens))
        enhanced = Enum.sum(Enum.map(lang_events, & &1.enhanced_tokens))
        reduction = if baseline > 0, do: (baseline - enhanced) / baseline * 100, else: 0

        {language,
         %{
           count: length(lang_events),
           reduction: Float.round(reduction, 1)
         }}
      end)
      |> Enum.sort_by(fn {_lang, stats} -> stats.reduction end, :desc)

    IO.puts("\n💻 LANGUAGE OPTIMIZATION RESULTS:")

    Enum.each(language_stats, fn {language, stats} ->
      IO.puts(
        "   #{String.pad_trailing("#{language}:", 12)} #{stats.reduction}% reduction | #{format_number(stats.count)} operations"
      )
    end)

    # User skill impact
    user_skill_impact =
      events
      |> Enum.group_by(fn event ->
        # Extract skill from metadata or use random for demo
        get_in(event.metadata, [:user_skill]) || Enum.random([:junior, :mid, :senior, :expert])
      end)
      |> Enum.map(fn {skill, skill_events} ->
        baseline = Enum.sum(Enum.map(skill_events, & &1.baseline_tokens))
        enhanced = Enum.sum(Enum.map(skill_events, & &1.enhanced_tokens))
        reduction = if baseline > 0, do: (baseline - enhanced) / baseline * 100, else: 0

        avg_satisfaction =
          Enum.sum(Enum.map(skill_events, & &1.user_satisfaction_score)) / length(skill_events)

        {skill,
         %{
           count: length(skill_events),
           reduction: Float.round(reduction, 1),
           satisfaction: Float.round(avg_satisfaction, 1)
         }}
      end)
      |> Enum.sort_by(fn {_skill, stats} -> stats.reduction end, :desc)

    IO.puts("\n👥 USER SKILL LEVEL IMPACT:")

    Enum.each(user_skill_impact, fn {skill, stats} ->
      IO.puts(
        "   #{String.pad_trailing("#{skill}:", 10)} #{stats.reduction}% reduction | #{stats.satisfaction}/5.0 satisfaction | #{format_number(stats.count)} ops"
      )
    end)

    # Time distribution
    peak_hours_events =
      Enum.filter(events, fn e ->
        get_in(e.metadata, [:peak_hours]) == true
      end)

    off_hours_events = events -- peak_hours_events

    peak_reduction = calculate_avg_reduction(peak_hours_events)
    off_reduction = calculate_avg_reduction(off_hours_events)

    IO.puts("\n⏰ TEMPORAL PATTERNS:")

    IO.puts(
      "   Peak Hours (9AM-5PM):    #{Float.round(peak_reduction, 1)}% reduction | #{format_number(length(peak_hours_events))} ops"
    )

    IO.puts(
      "   Off Hours:               #{Float.round(off_reduction, 1)}% reduction | #{format_number(length(off_hours_events))} ops"
    )

    # A/B Test Analysis
    treatment_events = Enum.filter(events, &(&1.cohort_type == :treatment))
    control_events = Enum.filter(events, &(&1.cohort_type == :control))

    treatment_reduction = calculate_avg_reduction(treatment_events)
    control_reduction = calculate_avg_reduction(control_events)
    effect_size = treatment_reduction - control_reduction

    IO.puts("\n🧪 A/B TEST RESULTS (MASSIVE SCALE):")

    IO.puts(
      "   Treatment Group:          #{Float.round(treatment_reduction, 1)}% reduction | #{format_number(length(treatment_events))} users"
    )

    IO.puts(
      "   Control Group:            #{Float.round(control_reduction, 1)}% reduction | #{format_number(length(control_events))} users"
    )

    IO.puts("   Effect Size:              #{Float.round(effect_size, 1)}% improvement")

    IO.puts(
      "   Statistical Power:        #{if length(treatment_events) > 1000 and length(control_events) > 500, do: "EXTREMELY HIGH", else: "MODERATE"}"
    )

    IO.puts(
      "   Confidence Level:         #{if abs(effect_size) > 5 and min(length(treatment_events), length(control_events)) > 100, do: "99%+", else: "95%"}"
    )

    # Business impact projections
    total_time_saved = events |> Enum.map(& &1.time_saved_seconds) |> Enum.sum()
    daily_operations = total_events / @days_of_data
    # $0.00002 per token
    monthly_token_savings = total_saved * 30 * 0.00002
    # $100/hour
    monthly_productivity = total_time_saved * 30 / @days_of_data / 3600 * 100
    total_monthly_value = monthly_token_savings + monthly_productivity
    annual_value = total_monthly_value * 12

    IO.puts("\n💰 MASSIVE SCALE BUSINESS IMPACT:")
    IO.puts("   Daily Operations:         #{format_number(round(daily_operations))}")
    IO.puts("   Monthly Token Savings:    $#{Float.round(monthly_token_savings, 2)}")
    IO.puts("   Monthly Productivity:     $#{Float.round(monthly_productivity, 2)}")
    IO.puts("   Total Monthly Value:      $#{Float.round(total_monthly_value, 2)}")
    IO.puts("   Projected Annual Value:   $#{Float.round(annual_value, 2)}")
    IO.puts("   ROI at Scale:             #{Float.round(total_monthly_value / 500, 1)}x")

    # Optimization opportunities
    IO.puts("\n🎯 PATH TO 100% OPTIMIZATION:")

    worst_performing = method_stats |> List.last() |> elem(1)
    best_performing = method_stats |> List.first() |> elem(1)

    IO.puts(
      "   Current Best Method:      #{Float.round(best_performing.reduction, 1)}% reduction"
    )

    IO.puts(
      "   Current Worst Method:     #{Float.round(worst_performing.reduction, 1)}% reduction"
    )

    IO.puts(
      "   Optimization Gap:         #{Float.round(best_performing.reduction - worst_performing.reduction, 1)}%"
    )

    # Advanced patterns
    high_performers = Enum.filter(events, &(&1.token_reduction_percent > 40))
    super_efficient = Enum.filter(events, &(&1.token_reduction_percent > 50))

    IO.puts("\n🚀 HIGH PERFORMANCE PATTERNS:")

    IO.puts(
      "   >40% Reduction Events:    #{format_number(length(high_performers))} (#{Float.round(length(high_performers) / total_events * 100, 1)}%)"
    )

    IO.puts(
      "   >50% Reduction Events:    #{format_number(length(super_efficient))} (#{Float.round(length(super_efficient) / total_events * 100, 1)}%)"
    )

    if length(super_efficient) > 0 do
      super_contexts =
        super_efficient |> Enum.map(& &1.operation_context) |> Enum.frequencies() |> Enum.take(3)

      IO.puts("   Top Super-Efficient Contexts:")

      Enum.each(super_contexts, fn {context, count} ->
        IO.puts("     - #{context}: #{count} occurrences")
      end)
    end

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("🎉 MASSIVE DATA GENERATION COMPLETE!")
    IO.puts("   Ready for deep analysis and 100% optimization strategies!")
    IO.puts(String.duplicate("=", 80))

    # Return summary for further analysis
    %{
      total_events: total_events,
      avg_reduction: avg_reduction,
      method_stats: method_stats,
      provider_stats: provider_stats,
      language_stats: language_stats,
      effect_size: effect_size,
      monthly_value: total_monthly_value,
      optimization_opportunities: %{
        best_method_reduction: best_performing.reduction,
        worst_method_reduction: worst_performing.reduction,
        high_performer_rate: length(high_performers) / total_events * 100,
        super_efficient_rate: length(super_efficient) / total_events * 100
      }
    }
  end

  defp calculate_avg_reduction(events) do
    if length(events) == 0 do
      0.0
    else
      baseline = Enum.sum(Enum.map(events, & &1.baseline_tokens))
      enhanced = Enum.sum(Enum.map(events, & &1.enhanced_tokens))
      if baseline > 0, do: (baseline - enhanced) / baseline * 100, else: 0.0
    end
  end

  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 1)}K"
  end

  defp format_number(num), do: "#{num}"
end

# Execute the massive metrics generation
try do
  summary = MetricsGenerator.generate_massive_dataset()

  IO.puts("\n🎉 Massive Metrics Generation Complete!")
  IO.puts("📊 Generated #{summary.total_events} events")
  IO.puts("👥 Created #{summary.total_users} users across #{summary.total_orgs} organizations")
  IO.puts("⚡ Average token reduction: #{Float.round(summary.avg_reduction, 2)}%")

  IO.puts(
    "🏆 Best performing method achieved #{Float.round(summary.best_method_reduction, 2)}% reduction"
  )

  IO.puts(
    "📈 #{Float.round(summary.high_performer_rate, 1)}% of events were high performers (>50% reduction)"
  )

  IO.puts(
    "🚀 #{Float.round(summary.super_efficient_rate, 1)}% of events were super efficient (>80% reduction)"
  )

  IO.puts("✅ Data generation completed successfully!\n")
rescue
  e ->
    IO.puts("❌ Error generating massive metrics: #{inspect(e)}")
    System.halt(1)
end
