defmodule Lang.Testing.AgentVariantGenerator do
  @moduledoc """
  Generates different OpenCode agent variants with varying personalities, capabilities,
  and behavioral patterns for LSP performance testing.

  Each variant represents a different approach to code analysis and generation,
  allowing us to test how LSP support benefits different types of AI agents.
  """

  alias Lang.Providers.OpenCode

  @doc """
  Generate a configured agent variant with specific personality traits and capabilities.
  """
  def generate_variant(variant_name, opts \\ []) do
    base_config = get_base_variant_config(variant_name)
    custom_config = Keyword.get(opts, :config, %{})

    config = Map.merge(base_config, custom_config)

    %{
      name: variant_name,
      config: config,
      provider_module: create_variant_module(variant_name, config),
      capabilities: determine_capabilities(config),
      metadata: %{
        created_at: DateTime.utc_now(),
        version: "1.0.0",
        personality_type: config.personality_type,
        risk_tolerance: config.risk_tolerance,
        optimization_focus: config.optimization_focus
      }
    }
  end

  @doc """
  Get all available agent variant types.
  """
  def list_variants do
    [
      :conservative_refactorer,
      :aggressive_optimizer,
      :security_first_analyst,
      :documentation_zealot,
      :test_driven_purist,
      :pragmatic_balancer,
      :speed_demon,
      :academic_perfectionist,
      :enterprise_maintainer,
      :startup_hacker,
      :claude_analytical_assistant
    ]
  end

  @doc """
  Generate multiple agent variants for comprehensive testing.
  """
  def generate_test_suite(count \\ 10) do
    variants = list_variants()

    variants
    |> Enum.take(count)
    |> Enum.map(&generate_variant/1)
    |> add_cross_combinations()
  end

  # Private Functions

  defp get_base_variant_config(:conservative_refactorer) do
    %{
      personality_type: :conservative,
      risk_tolerance: 0.2,
      optimization_focus: :safety,
      response_patterns: %{
        code_change_threshold: 0.1,
        breaking_change_aversion: 0.9,
        test_coverage_requirement: 0.95,
        documentation_verbosity: 0.8
      },
      quality_weights: %{
        correctness: 0.9,
        maintainability: 0.8,
        performance: 0.3,
        security: 0.7
      },
      decision_biases: %{
        prefer_explicit_over_implicit: 0.9,
        prefer_verbose_over_concise: 0.7,
        prefer_safe_over_fast: 0.9
      }
    }
  end

  defp get_base_variant_config(:aggressive_optimizer) do
    %{
      personality_type: :aggressive,
      risk_tolerance: 0.8,
      optimization_focus: :performance,
      response_patterns: %{
        code_change_threshold: 0.7,
        breaking_change_aversion: 0.3,
        test_coverage_requirement: 0.6,
        documentation_verbosity: 0.3
      },
      quality_weights: %{
        correctness: 0.7,
        maintainability: 0.4,
        performance: 0.9,
        security: 0.5
      },
      decision_biases: %{
        prefer_performance_over_readability: 0.9,
        prefer_minimal_over_verbose: 0.8,
        prefer_fast_over_safe: 0.8
      }
    }
  end

  defp get_base_variant_config(:security_first_analyst) do
    %{
      personality_type: :security_focused,
      risk_tolerance: 0.1,
      optimization_focus: :security,
      response_patterns: %{
        code_change_threshold: 0.3,
        breaking_change_aversion: 0.6,
        test_coverage_requirement: 0.9,
        documentation_verbosity: 0.9
      },
      quality_weights: %{
        correctness: 0.8,
        maintainability: 0.7,
        performance: 0.4,
        security: 1.0
      },
      decision_biases: %{
        prefer_secure_over_convenient: 1.0,
        prefer_explicit_permissions: 0.9,
        prefer_defense_in_depth: 0.9
      },
      security_focus: %{
        vulnerability_scanning: 0.9,
        input_validation_emphasis: 0.9,
        authentication_scrutiny: 1.0
      }
    }
  end

  defp get_base_variant_config(:documentation_zealot) do
    %{
      personality_type: :documentation_focused,
      risk_tolerance: 0.4,
      optimization_focus: :clarity,
      response_patterns: %{
        code_change_threshold: 0.4,
        breaking_change_aversion: 0.7,
        test_coverage_requirement: 0.8,
        documentation_verbosity: 1.0
      },
      quality_weights: %{
        correctness: 0.8,
        maintainability: 0.9,
        performance: 0.5,
        security: 0.6
      },
      decision_biases: %{
        prefer_self_documenting_code: 0.9,
        prefer_verbose_naming: 0.8,
        prefer_explicit_interfaces: 0.9
      },
      documentation_focus: %{
        comment_density: 0.9,
        api_documentation_completeness: 1.0,
        example_generation: 0.8
      }
    }
  end

  defp get_base_variant_config(:test_driven_purist) do
    %{
      personality_type: :test_driven,
      risk_tolerance: 0.3,
      optimization_focus: :testability,
      response_patterns: %{
        code_change_threshold: 0.5,
        breaking_change_aversion: 0.8,
        test_coverage_requirement: 1.0,
        documentation_verbosity: 0.7
      },
      quality_weights: %{
        correctness: 0.9,
        maintainability: 0.8,
        performance: 0.4,
        security: 0.7
      },
      decision_biases: %{
        prefer_testable_design: 1.0,
        prefer_dependency_injection: 0.9,
        prefer_pure_functions: 0.8
      },
      testing_focus: %{
        test_first_development: 1.0,
        edge_case_coverage: 0.9,
        integration_test_emphasis: 0.7
      }
    }
  end

  defp get_base_variant_config(:pragmatic_balancer) do
    %{
      personality_type: :balanced,
      risk_tolerance: 0.5,
      optimization_focus: :balance,
      response_patterns: %{
        code_change_threshold: 0.5,
        breaking_change_aversion: 0.5,
        test_coverage_requirement: 0.8,
        documentation_verbosity: 0.6
      },
      quality_weights: %{
        correctness: 0.8,
        maintainability: 0.7,
        performance: 0.6,
        security: 0.7
      },
      decision_biases: %{
        prefer_pragmatic_solutions: 0.8,
        consider_all_tradeoffs: 0.9,
        adapt_to_context: 0.9
      }
    }
  end

  defp get_base_variant_config(:speed_demon) do
    %{
      personality_type: :speed_focused,
      risk_tolerance: 0.9,
      optimization_focus: :speed,
      response_patterns: %{
        code_change_threshold: 0.8,
        breaking_change_aversion: 0.2,
        test_coverage_requirement: 0.4,
        documentation_verbosity: 0.2
      },
      quality_weights: %{
        correctness: 0.6,
        maintainability: 0.3,
        performance: 0.9,
        security: 0.4
      },
      decision_biases: %{
        prefer_quick_solutions: 0.9,
        prefer_minimal_code: 0.8,
        accept_technical_debt: 0.7
      }
    }
  end

  defp get_base_variant_config(:academic_perfectionist) do
    %{
      personality_type: :perfectionist,
      risk_tolerance: 0.1,
      optimization_focus: :theoretical_optimality,
      response_patterns: %{
        code_change_threshold: 0.2,
        breaking_change_aversion: 0.9,
        test_coverage_requirement: 0.95,
        documentation_verbosity: 1.0
      },
      quality_weights: %{
        correctness: 1.0,
        maintainability: 0.9,
        performance: 0.8,
        security: 0.8
      },
      decision_biases: %{
        prefer_theoretical_best: 0.9,
        prefer_formal_verification: 0.8,
        prefer_mathematical_elegance: 0.9
      },
      academic_focus: %{
        algorithm_optimality: 0.9,
        complexity_analysis: 0.8,
        formal_correctness: 0.9
      }
    }
  end

  defp get_base_variant_config(:enterprise_maintainer) do
    %{
      personality_type: :enterprise_focused,
      risk_tolerance: 0.2,
      optimization_focus: :long_term_maintainability,
      response_patterns: %{
        code_change_threshold: 0.3,
        breaking_change_aversion: 0.9,
        test_coverage_requirement: 0.9,
        documentation_verbosity: 0.9
      },
      quality_weights: %{
        correctness: 0.9,
        maintainability: 1.0,
        performance: 0.5,
        security: 0.8
      },
      decision_biases: %{
        prefer_established_patterns: 0.9,
        prefer_backward_compatibility: 0.9,
        prefer_enterprise_standards: 0.8
      },
      enterprise_focus: %{
        scalability_consideration: 0.9,
        team_collaboration: 0.8,
        legacy_system_integration: 0.9
      }
    }
  end

  defp get_base_variant_config(:startup_hacker) do
    %{
      personality_type: :startup_focused,
      risk_tolerance: 0.8,
      optimization_focus: :rapid_iteration,
      response_patterns: %{
        code_change_threshold: 0.7,
        breaking_change_aversion: 0.3,
        test_coverage_requirement: 0.5,
        documentation_verbosity: 0.3
      },
      quality_weights: %{
        correctness: 0.7,
        maintainability: 0.4,
        performance: 0.6,
        security: 0.5
      },
      decision_biases: %{
        prefer_mvp_solutions: 0.9,
        prefer_rapid_prototyping: 0.8,
        accept_shortcuts: 0.7
      },
      startup_focus: %{
        time_to_market: 0.9,
        feature_velocity: 0.8,
        resource_efficiency: 0.7
      }
    }
  end

  defp get_base_variant_config(:claude_analytical_assistant) do
    %{
      personality_type: :analytical_assistant,
      risk_tolerance: 0.3,
      optimization_focus: :comprehensive_analysis,
      response_patterns: %{
        code_change_threshold: 0.4,
        breaking_change_aversion: 0.8,
        test_coverage_requirement: 0.85,
        documentation_verbosity: 0.95
      },
      quality_weights: %{
        correctness: 0.95,
        maintainability: 0.9,
        performance: 0.7,
        security: 0.95
      },
      decision_biases: %{
        prefer_thorough_analysis: 0.95,
        consider_edge_cases: 0.9,
        explain_reasoning: 0.95,
        provide_multiple_solutions: 0.8
      },
      claude_specific: %{
        security_focus: 0.95,
        analytical_depth: 0.9,
        helpful_explanations: 0.95,
        safety_considerations: 0.9,
        step_by_step_thinking: 0.85
      }
    }
  end

  defp create_variant_module(variant_name, config) do
    module_name = :"Elixir.Lang.Testing.Variants.#{Macro.camelize(to_string(variant_name))}"

    # Create a dynamic module that wraps OpenCode with variant-specific behavior
    defmodule_ast =
      quote do
        defmodule unquote(module_name) do
          @moduledoc "Generated agent variant: #{unquote(variant_name)}"

          @behaviour Lang.Providers.Provider
          @config unquote(Macro.escape(config))
          @variant_name unquote(variant_name)

          def capabilities do
            case @variant_name do
              :claude_analytical_assistant ->
                # Use Anthropic provider capabilities for Claude variant
                Lang.Providers.Anthropic.capabilities()

              _ ->
                OpenCode.capabilities()
            end
          end

          def pricing do
            case @variant_name do
              :claude_analytical_assistant ->
                Lang.Providers.Anthropic.pricing()

              _ ->
                OpenCode.pricing()
            end
          end

          def available?, do: OpenCode.available?()

          def health_check do
            case @variant_name do
              :claude_analytical_assistant ->
                Lang.Providers.Anthropic.health_check()

              _ ->
                OpenCode.health_check()
            end
          end

          def handle_request(method, params, opts \\ []) do
            # Apply variant-specific modifications to the request
            modified_params = apply_variant_modifications(method, params, @config)
            modified_opts = Keyword.put(opts, :variant_config, @config)

            # Delegate based on variant type
            result =
              case @variant_name do
                :claude_analytical_assistant ->
                  # Use real Anthropic provider for Claude variant
                  Lang.Providers.Anthropic.handle_request(method, modified_params, modified_opts)

                _ ->
                  # Use OpenCode simulation for other variants
                  OpenCode.handle_request(method, modified_params, modified_opts)
              end

            case result do
              {:ok, response} ->
                {:ok, apply_variant_post_processing(response, @config)}

              error ->
                error
            end
          end

          def estimate_cost(method, params) do
            case @variant_name do
              :claude_analytical_assistant ->
                Lang.Providers.Anthropic.estimate_cost(method, params)

              _ ->
                OpenCode.estimate_cost(method, params)
            end
          end

          defp apply_variant_modifications(method, params, config) do
            params
            |> adjust_quality_thresholds(config)
            |> adjust_response_length(config)
            |> adjust_risk_tolerance(config)
          end

          defp apply_variant_post_processing(result, config) do
            result
            |> Map.put(:variant_name, @variant_name)
            |> Map.put(:variant_metadata, %{
              personality_type: config.personality_type,
              optimization_focus: config.optimization_focus,
              risk_tolerance: config.risk_tolerance
            })
            |> adjust_confidence_score(config)
          end

          defp adjust_quality_thresholds(params, config) do
            # Adjust parameters based on quality weights
            case config.quality_weights do
              %{correctness: correctness} when correctness > 0.8 ->
                Map.put(params, :quality_threshold, 0.9)

              %{performance: performance} when performance > 0.8 ->
                Map.put(params, :performance_focus, true)

              _ ->
                params
            end
          end

          defp adjust_response_length(params, config) do
            verbosity = Map.get(config.response_patterns, :documentation_verbosity, 0.5)

            cond do
              verbosity > 0.8 -> Map.put(params, :response_style, :verbose)
              verbosity < 0.3 -> Map.put(params, :response_style, :concise)
              true -> params
            end
          end

          defp adjust_risk_tolerance(params, config) do
            if config.risk_tolerance < 0.3 do
              Map.put(params, :conservative_mode, true)
            else
              params
            end
          end

          defp adjust_confidence_score(result, config) do
            base_confidence = Map.get(result, :confidence, 0.7)

            # Adjust confidence based on variant characteristics
            adjustment =
              case config.personality_type do
                :conservative -> -0.1
                :aggressive -> 0.1
                :perfectionist -> -0.2
                :startup_focused -> 0.15
                _ -> 0.0
              end

            adjusted_confidence = max(0.0, min(1.0, base_confidence + adjustment))
            Map.put(result, :confidence, adjusted_confidence)
          end
        end
      end

    # Compile the module
    Code.compile_quoted(defmodule_ast)
    module_name
  end

  defp determine_capabilities(config) do
    base_capabilities = [
      "completion",
      "hover",
      "explain",
      "refactor",
      "generate_tests"
    ]

    # Add specialized capabilities based on config
    specialized =
      case config.optimization_focus do
        :security -> ["security_analysis", "vulnerability_scan"]
        :performance -> ["performance_analysis", "optimization_suggestions"]
        :testability -> ["test_generation", "coverage_analysis"]
        :clarity -> ["documentation_generation", "code_explanation"]
        _ -> []
      end

    base_capabilities ++ specialized
  end

  defp add_cross_combinations(variants) do
    # Add some hybrid variants that combine characteristics
    hybrids = [
      create_hybrid_variant(:security_optimizer, :security_first_analyst, :aggressive_optimizer),
      create_hybrid_variant(:documented_tester, :documentation_zealot, :test_driven_purist),
      create_hybrid_variant(:pragmatic_performer, :pragmatic_balancer, :speed_demon)
    ]

    variants ++ hybrids
  end

  defp create_hybrid_variant(name, parent1, parent2) do
    config1 = get_base_variant_config(parent1)
    config2 = get_base_variant_config(parent2)

    # Merge configurations with weighted averages
    hybrid_config = %{
      personality_type: :hybrid,
      risk_tolerance: (config1.risk_tolerance + config2.risk_tolerance) / 2,
      optimization_focus: "#{config1.optimization_focus}_#{config2.optimization_focus}",
      response_patterns:
        merge_response_patterns(config1.response_patterns, config2.response_patterns),
      quality_weights: merge_quality_weights(config1.quality_weights, config2.quality_weights),
      decision_biases:
        merge_maps(
          Map.get(config1, :decision_biases, %{}),
          Map.get(config2, :decision_biases, %{})
        )
    }

    generate_variant(name, config: hybrid_config)
  end

  defp merge_response_patterns(patterns1, patterns2) do
    Map.merge(patterns1, patterns2, fn _k, v1, v2 -> (v1 + v2) / 2 end)
  end

  defp merge_quality_weights(weights1, weights2) do
    Map.merge(weights1, weights2, fn _k, v1, v2 -> (v1 + v2) / 2 end)
  end

  defp merge_maps(map1, map2) do
    Map.merge(map1, map2, fn _k, v1, v2 -> (v1 + v2) / 2 end)
  end
end
