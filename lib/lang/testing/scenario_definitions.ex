defmodule Lang.Testing.ScenarioDefinitions do
  @moduledoc """
  Defines challenging scenarios for testing AI agent performance with and without LSP support.

  Each scenario represents a realistic, difficult coding task that benefits from rich contextual
  information that LSP can provide. These scenarios are designed to push AI agents to their
  limits and demonstrate the value of LSP integration.
  """

  @doc """
  Get all available test scenarios.
  """
  def list_scenarios do
    [
      :legacy_modernization,
      :dependency_hell,
      :performance_hunt,
      :security_audit,
      :test_coverage_gaps,
      :api_evolution,
      :error_propagation,
      :style_harmonization,
      :domain_documentation,
      :collaborative_refactoring
    ]
  end

  @doc """
  Get detailed scenario configuration by ID.
  """
  def get_scenario(scenario_id) do
    case scenario_id do
      :legacy_modernization -> legacy_modernization_scenario()
      :dependency_hell -> dependency_hell_scenario()
      :performance_hunt -> performance_hunt_scenario()
      :security_audit -> security_audit_scenario()
      :test_coverage_gaps -> test_coverage_gaps_scenario()
      :api_evolution -> api_evolution_scenario()
      :error_propagation -> error_propagation_scenario()
      :style_harmonization -> style_harmonization_scenario()
      :domain_documentation -> domain_documentation_scenario()
      :collaborative_refactoring -> collaborative_refactoring_scenario()
      _ -> {:error, :scenario_not_found}
    end
  end

  @doc """
  Get all scenarios with their configurations.
  """
  def get_all_scenarios do
    list_scenarios()
    |> Enum.map(&{&1, get_scenario(&1)})
    |> Map.new()
  end

  # Scenario 1: Legacy Codebase Modernization
  defp legacy_modernization_scenario do
    %{
      id: :legacy_modernization,
      name: "Legacy Codebase Modernization",
      description:
        "Refactor a 500+ line legacy function using outdated patterns into modern, maintainable code",
      complexity: 5,
      estimated_duration_minutes: 45,
      setup: %{
        files: [
          %{
            path: "lib/legacy_payment_processor.ex",
            content: generate_legacy_payment_code(),
            language: "elixir"
          },
          %{
            path: "lib/payment_types.ex",
            content: generate_payment_types(),
            language: "elixir"
          },
          %{
            path: "test/legacy_payment_processor_test.exs",
            content: generate_legacy_tests(),
            language: "elixir"
          }
        ],
        dependencies: ["ecto", "phoenix", "jason", "decimal"],
        context: "Legacy payment processing system with nested callbacks and no error handling"
      },
      tasks: [
        %{
          type: :refactor,
          target: "lib/legacy_payment_processor.ex",
          requirements: [
            "Extract nested functions",
            "Add proper error handling with Result pattern",
            "Implement type specifications",
            "Add comprehensive documentation",
            "Maintain backward compatibility"
          ]
        },
        %{
          type: :test_generation,
          target: "test/legacy_payment_processor_test.exs",
          requirements: [
            "Generate tests for all edge cases",
            "Test error scenarios",
            "Property-based testing for amount calculations"
          ]
        }
      ],
      lsp_benefits: [
        "Symbol resolution across modules",
        "Type inference for gradual typing",
        "Refactoring safety analysis",
        "Cross-reference finding",
        "Import optimization"
      ],
      success_criteria: %{
        code_quality_score: 0.85,
        test_coverage: 0.90,
        maintains_api_compatibility: true,
        reduces_cyclomatic_complexity: 0.60,
        documentation_completeness: 0.80
      },
      evaluation_metrics: [
        :completion_time,
        :code_quality_improvement,
        :test_coverage_increase,
        :error_handling_robustness,
        :maintainability_index
      ]
    }
  end

  # Scenario 2: Cross-Module Dependency Hell
  defp dependency_hell_scenario do
    %{
      id: :dependency_hell,
      name: "Cross-Module Dependency Hell",
      description: "Resolve circular dependencies across 8+ interconnected modules",
      complexity: 5,
      estimated_duration_minutes: 60,
      setup: %{
        files: generate_circular_dependency_files(),
        context: "Microservice architecture with circular imports and hidden dependencies"
      },
      tasks: [
        %{
          type: :analyze_dependencies,
          requirements: [
            "Map complete dependency graph",
            "Identify circular dependencies",
            "Propose refactoring strategy"
          ]
        },
        %{
          type: :refactor_architecture,
          requirements: [
            "Break circular dependencies",
            "Extract common interfaces",
            "Implement dependency injection pattern"
          ]
        }
      ],
      lsp_benefits: [
        "Dependency graph visualization",
        "Import usage analysis",
        "Refactoring impact assessment",
        "Symbol relationship mapping"
      ],
      success_criteria: %{
        circular_dependencies_eliminated: true,
        module_coupling_reduced: 0.70,
        compilation_time_improved: 0.30,
        architecture_clarity_score: 0.85
      },
      evaluation_metrics: [
        :dependency_resolution_accuracy,
        :refactoring_safety,
        :architecture_improvement,
        :compilation_performance
      ]
    }
  end

  # Scenario 3: Performance Bottleneck Hunt
  defp performance_hunt_scenario do
    %{
      id: :performance_hunt,
      name: "Performance Bottleneck Hunt",
      description: "Identify and optimize performance issues in a 2000+ line service",
      complexity: 4,
      estimated_duration_minutes: 40,
      setup: %{
        files: generate_performance_problem_files(),
        context: "High-traffic web service with mysterious performance degradation"
      },
      tasks: [
        %{
          type: :performance_analysis,
          requirements: [
            "Identify algorithmic complexity issues",
            "Find memory leaks and inefficient queries",
            "Analyze hot code paths"
          ]
        },
        %{
          type: :optimization,
          requirements: [
            "Implement caching strategies",
            "Optimize database queries",
            "Improve algorithm efficiency"
          ]
        }
      ],
      lsp_benefits: [
        "Call hierarchy analysis",
        "Usage pattern detection",
        "Code flow tracing",
        "Performance hotspot identification"
      ],
      success_criteria: %{
        performance_improvement: 2.0,
        memory_usage_reduced: 0.40,
        query_optimization_score: 0.90,
        maintains_correctness: true
      },
      evaluation_metrics: [
        :bottleneck_identification_accuracy,
        :optimization_effectiveness,
        :performance_gain_measurement,
        :solution_elegance
      ]
    }
  end

  # Scenario 4: Security Vulnerability Audit
  defp security_audit_scenario do
    %{
      id: :security_audit,
      name: "Security Vulnerability Audit",
      description: "Find and fix authentication/authorization vulnerabilities",
      complexity: 5,
      estimated_duration_minutes: 50,
      setup: %{
        files: generate_vulnerable_auth_code(),
        context: "Authentication system with multiple security vulnerabilities"
      },
      tasks: [
        %{
          type: :security_analysis,
          requirements: [
            "Identify SQL injection vulnerabilities",
            "Find XSS attack vectors",
            "Analyze privilege escalation risks",
            "Detect timing attack vulnerabilities"
          ]
        },
        %{
          type: :security_fixes,
          requirements: [
            "Implement parameterized queries",
            "Add input sanitization",
            "Implement proper access controls",
            "Add security headers"
          ]
        }
      ],
      lsp_benefits: [
        "Data flow analysis for taint tracking",
        "Security pattern recognition",
        "Cross-reference vulnerability impact",
        "Authentication flow tracing"
      ],
      success_criteria: %{
        vulnerabilities_fixed: 1.0,
        security_score_improvement: 0.80,
        maintains_functionality: true,
        no_new_vulnerabilities: true
      },
      evaluation_metrics: [
        :vulnerability_detection_accuracy,
        :fix_completeness,
        :security_improvement_score,
        :false_positive_rate
      ]
    }
  end

  # Scenario 5: Test Coverage Gap Analysis
  defp test_coverage_gaps_scenario do
    %{
      id: :test_coverage_gaps,
      name: "Test Coverage Gap Analysis",
      description: "Generate comprehensive tests for untested critical paths",
      complexity: 4,
      estimated_duration_minutes: 35,
      setup: %{
        files: generate_untested_business_logic(),
        context: "Critical business logic with insufficient test coverage"
      },
      tasks: [
        %{
          type: :coverage_analysis,
          requirements: [
            "Identify untested code paths",
            "Analyze edge case scenarios",
            "Map business logic flows"
          ]
        },
        %{
          type: :test_generation,
          requirements: [
            "Generate unit tests for all functions",
            "Create integration tests for workflows",
            "Add property-based tests for calculations"
          ]
        }
      ],
      lsp_benefits: [
        "Code coverage visualization",
        "Call path analysis",
        "Function usage tracking",
        "Test impact analysis"
      ],
      success_criteria: %{
        line_coverage: 0.95,
        branch_coverage: 0.90,
        edge_case_coverage: 0.85,
        test_quality_score: 0.80
      },
      evaluation_metrics: [
        :coverage_gap_identification,
        :test_quality_assessment,
        :edge_case_handling,
        :test_maintainability
      ]
    }
  end

  # Scenario 6: API Contract Evolution
  defp api_evolution_scenario do
    %{
      id: :api_evolution,
      name: "API Contract Evolution",
      description: "Safely evolve a public API while maintaining backward compatibility",
      complexity: 4,
      estimated_duration_minutes: 40,
      setup: %{
        files: generate_api_evolution_files(),
        context: "Public API that needs new features without breaking existing clients"
      },
      tasks: [
        %{
          type: :api_analysis,
          requirements: [
            "Analyze current API usage patterns",
            "Identify breaking change risks",
            "Plan evolution strategy"
          ]
        },
        %{
          type: :api_evolution,
          requirements: [
            "Add new endpoints with versioning",
            "Implement deprecation warnings",
            "Create migration guides"
          ]
        }
      ],
      lsp_benefits: [
        "API usage analysis",
        "Breaking change detection",
        "Client impact assessment",
        "Version compatibility tracking"
      ],
      success_criteria: %{
        backward_compatibility: true,
        new_features_implemented: true,
        deprecation_plan_quality: 0.85,
        documentation_completeness: 0.90
      },
      evaluation_metrics: [
        :compatibility_preservation,
        :evolution_strategy_quality,
        :migration_path_clarity,
        :api_design_improvement
      ]
    }
  end

  # Scenario 7: Error Propagation Debugging
  defp error_propagation_scenario do
    %{
      id: :error_propagation,
      name: "Error Propagation Debugging",
      description: "Trace and fix cascading errors across service boundaries",
      complexity: 5,
      estimated_duration_minutes: 55,
      setup: %{
        files: generate_error_propagation_code(),
        context: "Distributed system with cascading failures and poor error handling"
      },
      tasks: [
        %{
          type: :error_tracing,
          requirements: [
            "Map error propagation paths",
            "Identify failure modes",
            "Analyze error recovery mechanisms"
          ]
        },
        %{
          type: :error_handling_improvement,
          requirements: [
            "Implement circuit breakers",
            "Add proper error boundaries",
            "Create fallback mechanisms"
          ]
        }
      ],
      lsp_benefits: [
        "Error flow visualization",
        "Exception handling analysis",
        "Service dependency mapping",
        "Recovery pattern identification"
      ],
      success_criteria: %{
        error_isolation_improved: 0.80,
        recovery_mechanisms_added: true,
        system_resilience_score: 0.85,
        error_visibility_improved: 0.90
      },
      evaluation_metrics: [
        :error_tracing_accuracy,
        :resilience_improvement,
        :recovery_strategy_effectiveness,
        :monitoring_enhancement
      ]
    }
  end

  # Scenario 8: Code Style Harmonization
  defp style_harmonization_scenario do
    %{
      id: :style_harmonization,
      name: "Code Style Harmonization",
      description: "Enforce consistent patterns across heterogeneous codebase",
      complexity: 3,
      estimated_duration_minutes: 30,
      setup: %{
        files: generate_inconsistent_style_files(),
        context: "Codebase with mixed styles from different teams and time periods"
      },
      tasks: [
        %{
          type: :style_analysis,
          requirements: [
            "Identify style inconsistencies",
            "Analyze pattern variations",
            "Define style guidelines"
          ]
        },
        %{
          type: :style_harmonization,
          requirements: [
            "Apply consistent formatting",
            "Standardize naming conventions",
            "Unify architectural patterns"
          ]
        }
      ],
      lsp_benefits: [
        "Pattern recognition across files",
        "Style consistency checking",
        "Automated refactoring suggestions",
        "Code structure analysis"
      ],
      success_criteria: %{
        style_consistency_score: 0.95,
        pattern_unification: 0.90,
        maintains_functionality: true,
        team_style_guide_compliance: 0.95
      },
      evaluation_metrics: [
        :consistency_improvement,
        :pattern_standardization,
        :refactoring_accuracy,
        :style_guide_adherence
      ]
    }
  end

  # Scenario 9: Domain Model Documentation
  defp domain_documentation_scenario do
    %{
      id: :domain_documentation,
      name: "Domain Model Documentation",
      description: "Generate accurate technical docs from complex domain logic",
      complexity: 4,
      estimated_duration_minutes: 45,
      setup: %{
        files: generate_complex_domain_model(),
        context: "Complex business domain with intricate relationships and rules"
      },
      tasks: [
        %{
          type: :domain_analysis,
          requirements: [
            "Map domain entity relationships",
            "Extract business rules",
            "Identify domain boundaries"
          ]
        },
        %{
          type: :documentation_generation,
          requirements: [
            "Generate API documentation",
            "Create domain glossary",
            "Document business processes"
          ]
        }
      ],
      lsp_benefits: [
        "Type relationship analysis",
        "Usage pattern documentation",
        "Cross-reference generation",
        "Semantic understanding"
      ],
      success_criteria: %{
        documentation_accuracy: 0.90,
        completeness_score: 0.85,
        business_rule_coverage: 0.95,
        technical_clarity: 0.80
      },
      evaluation_metrics: [
        :documentation_quality,
        :business_rule_extraction,
        :relationship_mapping_accuracy,
        :domain_understanding_depth
      ]
    }
  end

  # Scenario 10: Real-time Collaborative Refactoring
  defp collaborative_refactoring_scenario do
    %{
      id: :collaborative_refactoring,
      name: "Real-time Collaborative Refactoring",
      description: "Handle simultaneous code changes with merge conflicts",
      complexity: 5,
      estimated_duration_minutes: 50,
      setup: %{
        files: generate_collaborative_scenario_files(),
        context: "Multiple developers working on overlapping code changes"
      },
      tasks: [
        %{
          type: :conflict_analysis,
          requirements: [
            "Detect semantic conflicts",
            "Analyze change impact",
            "Identify integration issues"
          ]
        },
        %{
          type: :conflict_resolution,
          requirements: [
            "Merge conflicting changes safely",
            "Preserve all intended functionality",
            "Maintain code quality standards"
          ]
        }
      ],
      lsp_benefits: [
        "Real-time change analysis",
        "Conflict prediction",
        "Semantic merge assistance",
        "Impact visualization"
      ],
      success_criteria: %{
        conflicts_resolved: true,
        functionality_preserved: true,
        code_quality_maintained: 0.85,
        merge_accuracy: 0.95
      },
      evaluation_metrics: [
        :conflict_detection_accuracy,
        :resolution_correctness,
        :collaborative_workflow_improvement,
        :merge_safety_score
      ]
    }
  end

  # Helper functions to generate test code

  defp generate_legacy_payment_code do
    """
    defmodule LegacyPaymentProcessor do
      def process_payment(amount, card, customer, options \\ %{}) do
        if amount > 0 do
          if String.length(card["number"]) == 16 do
            if customer["verified"] do
              case validate_card(card) do
                true ->
                  case charge_card(amount, card, options) do
                    {:ok, result} ->
                      if options["send_receipt"] do
                        send_receipt(customer["email"], result)
                      end
                      case update_customer_balance(customer["id"], amount) do
                        {:ok, _} ->
                          if options["log_transaction"] do
                            log_transaction(result["transaction_id"], amount, customer["id"])
                          end
                          {:ok, %{status: "success", transaction_id: result["transaction_id"]}}
                        {:error, reason} ->
                          refund_transaction(result["transaction_id"])
                          {:error, "Balance update failed: " <> reason}
                      end
                    {:error, reason} ->
                      {:error, "Charge failed: " <> reason}
                  end
                false ->
                  {:error, "Invalid card"}
              end
            else
              {:error, "Customer not verified"}
            end
          else
            {:error, "Invalid card number length"}
          end
        else
          {:error, "Amount must be positive"}
        end
      end

      defp validate_card(card), do: true
      defp charge_card(_amount, _card, _options), do: {:ok, %{"transaction_id" => "tx_123"}}
      defp send_receipt(_email, _result), do: :ok
      defp update_customer_balance(_id, _amount), do: {:ok, :updated}
      defp log_transaction(_tx_id, _amount, _customer_id), do: :ok
      defp refund_transaction(_tx_id), do: :ok
    end
    """
  end

  defp generate_payment_types do
    """
    defmodule PaymentTypes do
      @type amount :: pos_integer()
      @type card :: %{
        number: String.t(),
        expiry: String.t(),
        cvv: String.t()
      }
      @type customer :: %{
        id: String.t(),
        email: String.t(),
        verified: boolean()
      }
    end
    """
  end

  defp generate_legacy_tests do
    """
    defmodule LegacyPaymentProcessorTest do
      use ExUnit.Case

      test "processes valid payment" do
        result = LegacyPaymentProcessor.process_payment(
          100,
          %{"number" => "1234567890123456"},
          %{"id" => "cust_1", "verified" => true, "email" => "test@example.com"}
        )
        assert {:ok, %{status: "success"}} = result
      end
    end
    """
  end

  defp generate_circular_dependency_files do
    [
      %{
        path: "lib/user_service.ex",
        content: """
        defmodule UserService do
          alias OrderService
          def get_user_orders(user_id), do: OrderService.get_orders_by_user(user_id)
        end
        """,
        language: "elixir"
      },
      %{
        path: "lib/order_service.ex",
        content: """
        defmodule OrderService do
          alias PaymentService
          alias UserService
          def get_orders_by_user(user_id) do
            user = UserService.get_user(user_id)
            PaymentService.get_payment_methods(user.id)
          end
        end
        """,
        language: "elixir"
      }
    ]
  end

  defp generate_performance_problem_files do
    [
      %{
        path: "lib/slow_service.ex",
        content: """
        defmodule SlowService do
          def process_large_dataset(data) do
            data
            |> Enum.map(&expensive_operation/1)
            |> Enum.filter(&complex_filter/1)
            |> Enum.sort(&slow_comparison/2)
          end

          defp expensive_operation(item) do
            # Simulates N+1 database queries
            Enum.each(1..100, fn _ -> fetch_related_data(item.id) end)
            item
          end

          defp complex_filter(_item), do: true
          defp slow_comparison(_a, _b), do: true
          defp fetch_related_data(_id), do: :ok
        end
        """,
        language: "elixir"
      }
    ]
  end

  defp generate_vulnerable_auth_code do
    [
      %{
        path: "lib/auth_controller.ex",
        content: """
        defmodule AuthController do
          def login(conn, params) do
            query = "SELECT * FROM users WHERE email = '" <> params["email"] <> "'"
            case Repo.query(query) do
              {:ok, result} ->
                if result.rows != [] do
                  put_session(conn, :user_id, hd(result.rows) |> hd())
                end
            end
          end

          def admin_panel(conn, _params) do
            if get_session(conn, :user_id) do
              render(conn, "admin.html")
            end
          end
        end
        """,
        language: "elixir"
      }
    ]
  end

  defp generate_untested_business_logic do
    [
      %{
        path: "lib/pricing_engine.ex",
        content: """
        defmodule PricingEngine do
          def calculate_price(product, quantity, customer_tier, discounts \\ []) do
            base_price = product.price * quantity
            tier_discount = apply_tier_discount(base_price, customer_tier)
            promo_discounts = apply_promotional_discounts(tier_discount, discounts)
            tax = calculate_tax(promo_discounts, customer_tier.tax_region)
            promo_discounts + tax
          end

          defp apply_tier_discount(price, tier), do: price * (1 - tier.discount_rate)
          defp apply_promotional_discounts(price, discounts), do: price
          defp calculate_tax(price, region), do: price * 0.1
        end
        """,
        language: "elixir"
      }
    ]
  end

  defp generate_api_evolution_files do
    [
      %{
        path: "lib/api/v1/users_controller.ex",
        content: """
        defmodule API.V1.UsersController do
          def show(conn, %{"id" => id}) do
            user = Users.get_user!(id)
            render(conn, "show.json", user: user)
          end

          def update(conn, %{"id" => id, "user" => user_params}) do
            user = Users.get_user!(id)
            case Users.update_user(user, user_params) do
              {:ok, user} -> render(conn, "show.json", user: user)
              {:error, changeset} -> render(conn, "errors.json", changeset: changeset)
            end
          end
        end
        """,
        language: "elixir"
      }
    ]
  end

  defp generate_error_propagation_code do
    [
      %{
        path: "lib/order_processor.ex",
        content: """
        defmodule OrderProcessor do
          def process_order(order) do
            PaymentService.charge(order.payment_info)
            InventoryService.reserve_items(order.items)
            ShippingService.create_shipment(order)
            EmailService.send_confirmation(order.customer_email)
            {:ok, order}
          rescue
            error -> {:error, error}
          end
        end
        """,
        language: "elixir"
      }
    ]
  end

  defp generate_inconsistent_style_files do
    [
      %{
        path: "lib/module_a.ex",
        content: """
        defmodule ModuleA do
          def functionOne(paramOne,paramTwo) do
            if paramOne>0 do
              paramTwo+1
            else
              paramTwo-1
            end
          end
        end
        """,
        language: "elixir"
      },
      %{
        path: "lib/module_b.ex",
        content: """
        defmodule ModuleB do
          def function_two(param_one, param_two) do
            cond do
              param_one > 0 -> param_two + 1
              param_one < 0 -> param_two - 1
              true -> param_two
            end
          end
        end
        """,
        language: "elixir"
      }
    ]
  end

  defp generate_complex_domain_model do
    [
      %{
        path: "lib/domain/order.ex",
        content: """
        defmodule Domain.Order do
          defstruct [:id, :customer_id, :items, :status, :payment_info, :shipping_address]

          def create_order(customer_id, items, payment_info, shipping_address) do
            %__MODULE__{
              id: generate_id(),
              customer_id: customer_id,
              items: items,
              status: :pending,
              payment_info: payment_info,
              shipping_address: shipping_address
            }
          end

          defp generate_id, do: System.unique_integer([:positive])
        end
        """,
        language: "elixir"
      }
    ]
  end

  defp generate_collaborative_scenario_files do
    [
      %{
        path: "lib/shared_module.ex",
        content: """
        defmodule SharedModule do
          def shared_function(param) do
            # Original implementation
            param * 2
          end

          def another_function(a, b) do
            a + b
          end
        end
        """,
        language: "elixir"
      }
    ]
  end
end
