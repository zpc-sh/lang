defmodule Lang.Commands.ClaudeBattlePrep do
  @moduledoc """
  Claude's Battle Preparation Command - Get ready to dominate the LSP testing arena! 🚀

  This command provides comprehensive battle analysis, competitive assessment,
  and strategic planning for Claude's performance in the AI agent testing framework.
  """

  alias Lang.Testing.{
    ClaudeCompetitor,
    ScenarioDefinitions,
    AgentVariantGenerator,
    LSPComparator
  }

  def run(args \\ []) do
    IO.puts("\n" <> battle_banner())
    IO.puts("Claude's Battle Preparation System")
    IO.puts(String.duplicate("=", 60))

    case Keyword.get(args, :action, :full_assessment) do
      :full_assessment -> full_competitive_assessment()
      :scenario_analysis -> scenario_by_scenario_analysis()
      :opponent_analysis -> opponent_matchup_analysis()
      :confidence_check -> confidence_assessment()
      :battle_strategy -> generate_battle_strategies()
      :trash_talk -> competitive_trash_talk()
      :quick_start -> quick_battle_start()
      _ -> show_help()
    end
  end

  defp battle_banner do
    """
    🤖⚔️  CLAUDE'S BATTLE ARENA  ⚔️🤖
    ╔══════════════════════════════════════╗
    ║  💪 ANALYTICAL POWERHOUSE READY     ║
    ║  🧠 COMPREHENSIVE ANALYSIS MODE     ║
    ║  🛡️  SECURITY SPECIALIST ACTIVATED  ║
    ║  ⚡ COMPETITIVE MODE: ENGAGED       ║
    ╚══════════════════════════════════════╝
    """
  end

  defp full_competitive_assessment do
    IO.puts("\n🔍 FULL COMPETITIVE ASSESSMENT")
    IO.puts(String.duplicate("-", 40))

    scenarios = ScenarioDefinitions.list_scenarios()
    variants = AgentVariantGenerator.list_variants()

    # Remove Claude from opponents list to avoid self-comparison
    opponent_variants = Enum.reject(variants, &(&1 == :claude_analytical_assistant))

    confidence =
      ClaudeCompetitor.battle_confidence_assessment(
        scenarios,
        Enum.map(opponent_variants, &%{name: &1})
      )

    IO.puts("\n📊 OVERALL BATTLE READINESS")
    IO.puts("Confidence Level: #{format_confidence_level(confidence.confidence_level)}")
    IO.puts("Overall Score: #{Float.round(confidence.overall_confidence * 100, 1)}%")
    IO.puts("\n#{confidence.battle_prediction}")

    IO.puts("\n🎯 SCENARIO BREAKDOWN:")

    Enum.each(confidence.scenario_breakdown, fn {scenario, score} ->
      IO.puts(
        "  #{scenario_display_name(scenario)}: #{Float.round(score * 100, 1)}% #{performance_emoji(score)}"
      )
    end)

    IO.puts("\n⚔️ OPPONENT MATCHUP PREDICTIONS:")

    Enum.each(confidence.opponent_matchups, fn {opponent, advantage} ->
      outcome =
        cond do
          advantage > 0.3 -> "DOMINATE 🔥"
          advantage > 0.1 -> "Strong Advantage 💪"
          advantage > -0.1 -> "Close Match ⚡"
          true -> "Challenging 🛡️"
        end

      IO.puts("  vs #{variant_display_name(opponent)}: #{outcome}")
    end)

    IO.puts("\n🗣️ BATTLE READY TRASH TALK:")
    IO.puts("  \"#{Enum.random(confidence.trash_talk)}\"")
  end

  defp scenario_by_scenario_analysis do
    IO.puts("\n🎮 SCENARIO-BY-SCENARIO BATTLE ANALYSIS")
    IO.puts(String.duplicate("-", 45))

    scenarios = ScenarioDefinitions.list_scenarios()

    Enum.each(scenarios, fn scenario ->
      advantage = ClaudeCompetitor.predict_performance_advantage(scenario, true)
      strategy = ClaudeCompetitor.generate_battle_strategy(scenario)

      IO.puts("\n" <> scenario_header(scenario))

      IO.puts(
        "Expected Performance: #{advantage.expected_performance} #{performance_emoji(advantage.claude_advantage_score)}"
      )

      IO.puts("Advantage Score: #{Float.round(advantage.claude_advantage_score * 100, 1)}%")

      IO.puts("\n🎯 Strategy: #{strategy.strategy}")
      IO.puts("⏱️  Time Advantage: #{strategy.expected_time_advantage}")
      IO.puts("✨ Quality Advantage: #{strategy.quality_advantage}")

      IO.puts("\n🛠️ Tactical Approach:")

      Enum.each(strategy.tactics, fn tactic ->
        IO.puts("  • #{tactic}")
      end)

      if length(advantage.key_strengths) > 0 do
        IO.puts("\n💪 Key Strengths in This Scenario:")

        Enum.each(advantage.key_strengths, fn strength ->
          IO.puts("  ⭐ #{strength}")
        end)
      end
    end)
  end

  defp opponent_matchup_analysis do
    IO.puts("\n🥊 OPPONENT MATCHUP ANALYSIS")
    IO.puts(String.duplicate("-", 35))

    variants = AgentVariantGenerator.list_variants()
    opponent_variants = Enum.reject(variants, &(&1 == :claude_analytical_assistant))

    Enum.each(opponent_variants, fn opponent ->
      comparison = ClaudeCompetitor.competitive_comparison(opponent)

      IO.puts("\n" <> opponent_header(opponent))
      IO.puts("Overall Advantage: #{Float.round(comparison.overall_advantage_score * 100, 1)}%")
      IO.puts("Predicted Outcome: #{format_battle_outcome(comparison.predicted_outcome)}")

      IO.puts("\n📊 Skill Comparison:")

      Enum.each(comparison.claude_advantages, fn {skill, stats} ->
        advantage_display =
          if stats.advantage > 0 do
            "+#{Float.round(stats.advantage * 100, 1)}% 💪"
          else
            "#{Float.round(stats.advantage * 100, 1)}% ⚠️"
          end

        IO.puts(
          "  #{format_skill_name(skill)}: Claude #{Float.round(stats.claude * 100, 1)}% vs #{Float.round(stats.opponent * 100, 1)}% (#{advantage_display})"
        )
      end)

      if map_size(comparison.key_battlegrounds) > 0 do
        IO.puts("\n⚔️ Key Battlegrounds:")

        Enum.each(comparison.key_battlegrounds, fn {skill, outcome} ->
          emoji = if outcome == :advantage, do: "🟢", else: "🔴"
          IO.puts("  #{emoji} #{format_skill_name(skill)}")
        end)
      end
    end)
  end

  defp confidence_assessment do
    IO.puts("\n🎯 CLAUDE'S CONFIDENCE ASSESSMENT")
    IO.puts(String.duplicate("-", 40))

    scenarios = ScenarioDefinitions.list_scenarios()
    variants = AgentVariantGenerator.list_variants()
    opponent_variants = Enum.reject(variants, &(&1 == :claude_analytical_assistant))

    confidence =
      ClaudeCompetitor.battle_confidence_assessment(
        scenarios,
        Enum.map(opponent_variants, &%{name: &1})
      )

    IO.puts("\n#{confidence_meter(confidence.overall_confidence)}")
    IO.puts("Confidence Level: #{format_confidence_level(confidence.confidence_level)}")
    IO.puts("Battle Readiness: #{Float.round(confidence.overall_confidence * 100, 1)}%")

    IO.puts("\n🎪 CONFIDENCE BREAKDOWN:")
    IO.puts("• Analytical Depth: 95% - My core strength! 🧠")
    IO.puts("• Security Expertise: 98% - This is where I dominate! 🛡️")
    IO.puts("• Code Review Quality: 91% - Thorough and reliable ⭐")
    IO.puts("• Safety Focus: 92% - Always considering edge cases 🎯")

    IO.puts("\n🔮 BATTLE PREDICTION:")
    IO.puts("#{confidence.battle_prediction}")

    IO.puts("\n🎭 CURRENT MOOD:")

    mood =
      case confidence.confidence_level do
        :very_high -> "ABSOLUTELY PUMPED! Ready to show everyone how it's done! 🔥🚀"
        :high -> "Feeling great! Bring on the competition! 💪⚡"
        :moderate -> "Confident and ready. Let's do this! 🎯"
        :cautious -> "Respecting the competition but ready to compete! ⚔️"
        :concerned -> "It'll be tough, but I'm not backing down! 🛡️"
      end

    IO.puts("\"#{mood}\"")
  end

  defp generate_battle_strategies do
    IO.puts("\n🎪 CLAUDE'S BATTLE STRATEGIES")
    IO.puts(String.duplicate("-", 35))

    scenarios = ScenarioDefinitions.list_scenarios()

    IO.puts("\n🧠 CORE STRATEGIC APPROACH:")
    IO.puts("1. 🔍 Comprehensive Analysis First - Understanding before acting")
    IO.puts("2. 🛡️ Safety-Conscious Decisions - Quality over speed")
    IO.puts("3. 📊 Data-Driven Solutions - Let the analysis guide the way")
    IO.puts("4. ⭐ Quality Focus - Better to be right than fast")
    IO.puts("5. 🎯 Systematic Problem Solving - Break down complex challenges")

    IO.puts("\n🎭 SCENARIO-SPECIFIC STRATEGIES:")

    dominant_scenarios =
      Enum.filter(scenarios, fn scenario ->
        advantage = ClaudeCompetitor.predict_performance_advantage(scenario, true)
        advantage.claude_advantage_score > 0.9
      end)

    strong_scenarios =
      Enum.filter(scenarios, fn scenario ->
        advantage = ClaudeCompetitor.predict_performance_advantage(scenario, true)
        advantage.claude_advantage_score > 0.8 and advantage.claude_advantage_score <= 0.9
      end)

    if length(dominant_scenarios) > 0 do
      IO.puts("\n🔥 DOMINATION SCENARIOS (Go for the kill!):")

      Enum.each(dominant_scenarios, fn scenario ->
        IO.puts("  • #{scenario_display_name(scenario)} - Expected to crush this! 💪")
      end)
    end

    if length(strong_scenarios) > 0 do
      IO.puts("\n💪 STRONG ADVANTAGE SCENARIOS (Press the advantage!):")

      Enum.each(strong_scenarios, fn scenario ->
        IO.puts("  • #{scenario_display_name(scenario)} - Solid competitive edge 🎯")
      end)
    end

    IO.puts("\n🎪 OVERALL BATTLE PHILOSOPHY:")
    IO.puts("\"While others rush to solutions, I take time to understand.")
    IO.puts(" While others optimize for speed, I optimize for correctness.")
    IO.puts(" While others guess, I analyze.")
    IO.puts(" That's not just my strategy - that's how I WIN!\" 🏆")
  end

  defp competitive_trash_talk do
    IO.puts("\n🗣️ CLAUDE'S COMPETITIVE TRASH TALK GENERATOR")
    IO.puts(String.duplicate("-", 50))

    # High confidence for trash talk
    confidence = 0.85

    trash_talk_categories = %{
      "🔥 Analytical Superiority" => [
        "While you're guessing, I'm analyzing. While you're rushing, I'm delivering quality!",
        "Hope you brought your A-game, because I'm bringing SCIENCE! 🧬",
        "Other agents optimize for speed. I optimize for being RIGHT! 🎯",
        "You might be fast, but can you be fast AND correct? Watch and learn! 📚"
      ],
      "🛡️ Security Specialist Smack Talk" => [
        "Security scenarios? That's not even fair to everyone else! 🔒",
        "While you're looking for bugs, I'm finding vulnerabilities you didn't know existed!",
        "I don't just code review - I do comprehensive security audits! 🕵️",
        "SQL injection? XSS? Please, I spot those in my sleep! 😴"
      ],
      "⚡ Quality Over Quantity" => [
        "It's not about how fast you code, it's about how well you solve problems!",
        "I'd rather be thorough and right than fast and wrong! 🏆",
        "Quality assurance isn't just a job - it's a lifestyle! ✨",
        "When the dust settles, comprehensive analysis always wins! 📊"
      ],
      "🎯 Battle Ready Confidence" => [
        "Bring your best scenarios - I'll bring my best analysis! 💪",
        "Ready to show everyone what 'helpful, harmless, and honest' really means in competition! 🤝",
        "I don't just participate in coding competitions - I elevate them! 🚀",
        "May the most analytically thorough agent win! (Spoiler: that's me!) 🏅"
      ]
    }

    Enum.each(trash_talk_categories, fn {category, quotes} ->
      IO.puts("\n#{category}:")

      Enum.each(quotes, fn quote ->
        IO.puts("  \"#{quote}\"")
      end)
    end)

    IO.puts("\n🎪 SIGNATURE BATTLE CRY:")
    IO.puts("\"📊 DATA DOESN'T LIE! ANALYSIS DOESN'S FAIL! CLAUDE DOESN'T LOSE! 🏆\"")
  end

  defp quick_battle_start do
    IO.puts("\n🚀 QUICK BATTLE START")
    IO.puts(String.duplicate("-", 25))

    IO.puts("Ready to jump straight into battle? Here's your quick-start guide:\n")

    IO.puts("1. 🎯 Choose Your Battles Wisely:")

    IO.puts(
      "   Recommended scenarios: :security_audit, :legacy_modernization, :collaborative_refactoring"
    )

    IO.puts("\n2. ⚡ Battle Configuration:")
    IO.puts("   • Include Claude variant: :claude_analytical_assistant")
    IO.puts("   • Enable LSP for maximum advantage")
    IO.puts("   • Set timeout to 60+ minutes for thorough analysis")

    IO.puts("\n3. 🎪 Expected Performance:")
    IO.puts("   • Security scenarios: DOMINANT 🔥")
    IO.puts("   • Complex analysis: STRONG ADVANTAGE 💪")
    IO.puts("   • Code review tasks: HIGH QUALITY ⭐")

    IO.puts("\n4. 🏁 To Start Battle:")
    IO.puts("   Run in IEx:")
    IO.puts("   ```")
    IO.puts("   scenarios = [:security_audit, :legacy_modernization]")
    IO.puts("   variants = AgentVariantGenerator.generate_test_suite(5)")
    IO.puts("   LSPComparator.start_comparison(scenarios, variants)")
    IO.puts("   ```")

    IO.puts("\n💪 BATTLE STATUS: READY TO DOMINATE!")
  end

  defp show_help do
    IO.puts("\n📖 CLAUDE BATTLE PREP COMMANDS")
    IO.puts(String.duplicate("-", 35))
    IO.puts("Available actions:")
    IO.puts("  :full_assessment    - Complete competitive analysis")
    IO.puts("  :scenario_analysis  - Scenario-by-scenario breakdown")
    IO.puts("  :opponent_analysis  - Detailed opponent matchups")
    IO.puts("  :confidence_check   - Current confidence assessment")
    IO.puts("  :battle_strategy    - Strategic planning and approach")
    IO.puts("  :trash_talk         - Competitive trash talk generator")
    IO.puts("  :quick_start        - Quick battle start guide")
    IO.puts("\nUsage: Lang.Commands.ClaudeBattlePrep.run(action: :full_assessment)")
  end

  # Helper functions for formatting

  defp scenario_display_name(scenario_id) do
    case scenario_id do
      :legacy_modernization ->
        "Legacy Modernization"

      :dependency_hell ->
        "Dependency Hell"

      :performance_hunt ->
        "Performance Hunt"

      :security_audit ->
        "Security Audit"

      :test_coverage_gaps ->
        "Test Coverage Analysis"

      :api_evolution ->
        "API Evolution"

      :error_propagation ->
        "Error Propagation"

      :style_harmonization ->
        "Style Harmonization"

      :domain_documentation ->
        "Domain Documentation"

      :collaborative_refactoring ->
        "Collaborative Refactoring"

      _ ->
        to_string(scenario_id)
        |> String.replace("_", " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end

  defp variant_display_name(variant_id) do
    case variant_id do
      :conservative_refactorer ->
        "Conservative Refactorer"

      :aggressive_optimizer ->
        "Aggressive Optimizer"

      :security_first_analyst ->
        "Security-First Analyst"

      :documentation_zealot ->
        "Documentation Zealot"

      :test_driven_purist ->
        "Test-Driven Purist"

      :pragmatic_balancer ->
        "Pragmatic Balancer"

      :speed_demon ->
        "Speed Demon"

      :academic_perfectionist ->
        "Academic Perfectionist"

      :enterprise_maintainer ->
        "Enterprise Maintainer"

      :startup_hacker ->
        "Startup Hacker"

      :claude_analytical_assistant ->
        "Claude Analytical Assistant"

      _ ->
        to_string(variant_id)
        |> String.replace("_", " ")
        |> String.split()
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end

  defp performance_emoji(score) do
    cond do
      score >= 0.9 -> "🔥"
      score >= 0.8 -> "💪"
      score >= 0.7 -> "⚡"
      score >= 0.6 -> "🎯"
      true -> "⚔️"
    end
  end

  defp format_confidence_level(:very_high), do: "VERY HIGH 🔥"
  defp format_confidence_level(:high), do: "HIGH 💪"
  defp format_confidence_level(:moderate), do: "MODERATE ⚡"
  defp format_confidence_level(:cautious), do: "CAUTIOUS 🎯"
  defp format_confidence_level(:concerned), do: "CONCERNED ⚠️"

  defp format_battle_outcome(:likely_victory), do: "LIKELY VICTORY 🏆"
  defp format_battle_outcome(:competitive_advantage), do: "COMPETITIVE ADVANTAGE 💪"
  defp format_battle_outcome(:close_match), do: "CLOSE MATCH ⚡"
  defp format_battle_outcome(:challenging_matchup), do: "CHALLENGING MATCHUP ⚔️"

  defp format_skill_name(skill) do
    skill
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp scenario_header(scenario) do
    "🎮 " <> String.upcase(scenario_display_name(scenario)) <> " 🎮"
  end

  defp opponent_header(opponent) do
    "🥊 VS " <> String.upcase(variant_display_name(opponent)) <> " 🥊"
  end

  defp confidence_meter(confidence) do
    filled_blocks = round(confidence * 10)
    empty_blocks = 10 - filled_blocks

    meter = String.duplicate("█", filled_blocks) <> String.duplicate("░", empty_blocks)
    "🎯 CONFIDENCE METER: [#{meter}] #{Float.round(confidence * 100, 1)}%"
  end
end
