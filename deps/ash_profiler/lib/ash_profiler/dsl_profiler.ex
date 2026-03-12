defmodule AshProfiler.DSLProfiler do
  @moduledoc """
  Profiles Ash DSL compilation performance to identify bottlenecks

  This module is only compiled in development and test environments.
  """

  # Only compile in non-production environments
  if Mix.env() in [:dev, :test] do
    def profile_dsl_compilation do
      IO.puts("=== Starting DSL Compilation Profiling ===")
      start_time = System.monotonic_time(:millisecond)

      # Hook into macro expansion events if available
      try do
        # Start telemetry application if not started
        Application.ensure_all_started(:telemetry)

        :telemetry.attach_many(
          "dsl-profiler",
          [
            [:ash, :dsl, :expansion],
            [:ash, :resource, :compilation],
            [:ash, :domain, :compilation]
          ],
          &handle_dsl_event/4,
          %{start_time: start_time}
        )
      rescue
        _ -> IO.puts("Telemetry events not available, using alternative profiling")
      end

      # Analyze all Ash resources
      analyze_resource_compilation_complexity()

      # Profile macro expansion patterns
      profile_macro_expansion_patterns()

      IO.puts("=== DSL Profiling Complete ===")
    end

    defp handle_dsl_event(event, measurements, metadata, _config) do
      duration = Map.get(measurements, :duration, 0)

      case event do
        [:ash, :dsl, :expansion] ->
          # Log slow DSL expansions
          if duration > 100 do
            IO.puts("SLOW DSL: #{metadata[:module]} #{metadata[:dsl_section]} took #{duration}ms")
          end

        [:ash, :resource, :compilation] ->
          if duration > 500 do
            IO.puts("SLOW RESOURCE: #{metadata[:resource]} took #{duration}ms")
          end

        [:ash, :domain, :compilation] ->
          if duration > 1000 do
            IO.puts("SLOW DOMAIN: #{metadata[:domain]} took #{duration}ms")
          end
      end
    end

    defp analyze_resource_compilation_complexity do
      IO.puts("\n=== Analyzing Resource DSL Complexity ===")

      # Get all Ash domains
      domains = get_ash_domains()

      for domain <- domains do
        IO.puts("\nDomain: #{inspect(domain)}")
        resources = get_domain_resources(domain)

        for resource <- resources do
          complexity = calculate_dsl_complexity(resource)
          IO.puts("  #{inspect(resource)}: #{complexity.total} complexity points")

          if complexity.total > 100 do
            IO.puts("    ⚠️  HIGH COMPLEXITY RESOURCE ⚠️")
            print_complexity_breakdown(complexity)
          end
        end
      end
    end

    defp calculate_dsl_complexity(resource) do
      try do
        # Analyze different DSL sections
        attributes_complexity = analyze_attributes_dsl(resource)
        relationships_complexity = analyze_relationships_dsl(resource)
        actions_complexity = analyze_actions_dsl(resource)
        policies_complexity = analyze_policies_dsl(resource)
        changes_complexity = analyze_changes_dsl(resource)

        %{
          attributes: attributes_complexity,
          relationships: relationships_complexity,
          actions: actions_complexity,
          policies: policies_complexity,
          changes: changes_complexity,
          total:
            attributes_complexity + relationships_complexity +
              actions_complexity + policies_complexity + changes_complexity
        }
      rescue
        error ->
          IO.puts("    ERROR analyzing #{inspect(resource)}: #{inspect(error)}")
          %{total: 0, attributes: 0, relationships: 0, actions: 0, policies: 0, changes: 0}
      end
    end

    defp analyze_attributes_dsl(resource) do
      try do
        attributes = resource.attributes()

        # Count complexity factors
        base_count = length(attributes)

        computed_count =
          Enum.count(attributes, fn attr ->
            case attr do
              %{generated?: true} -> true
              _ -> false
            end
          end)

        constraint_complexity = Enum.sum(Enum.map(attributes, &count_constraints/1))

        base_count + computed_count * 3 + constraint_complexity
      rescue
        _ -> 0
      end
    end

    defp analyze_relationships_dsl(resource) do
      try do
        relationships = resource.relationships()

        # Relationships are expensive to compile
        base_count = length(relationships) * 2

        # Many-to-many relationships are especially expensive
        many_to_many_bonus =
          Enum.count(relationships, fn rel ->
            case rel do
              %{type: :many_to_many} -> true
              _ -> false
            end
          end) * 5

        base_count + many_to_many_bonus
      rescue
        _ -> 0
      end
    end

    defp analyze_actions_dsl(resource) do
      try do
        actions = resource.actions()

        # Count action complexity
        base_count = length(actions)

        # Actions with many changes/validations are expensive
        change_complexity = Enum.sum(Enum.map(actions, &count_action_changes/1))

        base_count + change_complexity
      rescue
        _ -> 0
      end
    end

    defp analyze_policies_dsl(resource) do
      try do
        policies = resource.policies()

        # Policies are very expensive to compile
        base_count = length(policies) * 5

        # Complex expressions multiply cost
        expression_complexity = Enum.sum(Enum.map(policies, &analyze_policy_expression/1))

        base_count + expression_complexity
      rescue
        _ -> 0
      end
    end

    defp analyze_changes_dsl(resource) do
      try do
        changes = resource.changes()
        # Custom changes add compilation cost
        length(changes) * 2
      rescue
        _ -> 0
      end
    end

    defp profile_macro_expansion_patterns do
      IO.puts("\n=== Profiling Macro Expansion Patterns ===")

      # Look for common expensive patterns
      check_circular_dependencies()
      check_deep_nesting_patterns()
      check_compile_time_computations()
    end

    defp check_circular_dependencies do
      IO.puts("\nChecking for circular dependencies...")

      # Use mix xref to check dependency cycles
      try do
        {output, _} =
          System.cmd("mix", ["xref", "graph", "--format", "stats"],
            stderr_to_stdout: true,
            cd: File.cwd!()
          )

        if String.contains?(output, "cycle") do
          IO.puts("⚠️  CIRCULAR DEPENDENCIES DETECTED")
          IO.puts(output)
        else
          IO.puts("✅ No circular dependencies found")
        end
      rescue
        _ -> IO.puts("Could not check dependencies (mix xref not available)")
      end
    end

    defp check_deep_nesting_patterns do
      IO.puts("\nChecking for deep DSL nesting...")

      # Scan source files for deeply nested DSL blocks
      Path.wildcard("lib/**/*.ex")
      |> Enum.each(&analyze_file_nesting/1)
    end

    defp analyze_file_nesting(file_path) do
      try do
        content = File.read!(file_path)
        lines = String.split(content, "\n")

        {max_nesting, _} =
          Enum.reduce(lines, {0, 0}, fn line, {max_nest, current_nest} ->
            cond do
              String.contains?(line, " do") ->
                new_current = current_nest + 1
                {max(max_nest, new_current), new_current}

              String.contains?(line, "end") ->
                {max_nest, max(0, current_nest - 1)}

              true ->
                {max_nest, current_nest}
            end
          end)

        if max_nesting > 8 do
          IO.puts("⚠️  Deep nesting in #{file_path}: #{max_nesting} levels")
        end
      rescue
        _ -> :ok
      end
    end

    defp check_compile_time_computations do
      IO.puts("\nChecking for expensive compile-time computations...")

      # Look for patterns that cause compile-time work
      expensive_patterns = [
        ~r/Application\.get_env/,
        ~r/System\.get_env/,
        ~r/File\.read!/,
        ~r/Req\.get/,
        ~r/HTTPoison\.get/,
        ~r/Enum\.map.*Application/
      ]

      Path.wildcard("lib/**/*.ex")
      |> Enum.each(fn file ->
        try do
          content = File.read!(file)

          for pattern <- expensive_patterns do
            if Regex.match?(pattern, content) do
              matches = Regex.scan(pattern, content) |> length()

              if matches > 0 do
                IO.puts("⚠️  #{file}: #{matches} potential compile-time computations")
              end
            end
          end
        rescue
          _ -> :ok
        end
      end)
    end

    # Helper functions
    defp get_ash_domains do
      # Get domains from application config
      app_domains = Application.get_env(:ash, :domains, [])
      proc_domains = Application.get_env(get_app_name(), :ash_domains, [])

      # Also try to find Proc.Domain specifically
      manual_domains = [Proc.Domain]

      (app_domains ++ proc_domains ++ manual_domains)
      |> Enum.uniq()
      |> Enum.filter(&domain_exists?/1)
    end

    defp domain_exists?(domain) do
      try do
        Code.ensure_loaded?(domain) && function_exported?(domain, :resources, 0)
      rescue
        _ -> false
      end
    end

    defp get_domain_resources(domain) do
      try do
        domain.resources()
      rescue
        _ -> []
      end
    end

    defp get_app_name do
      try do
        Mix.Project.config()[:app]
      rescue
        _ -> :proc
      end
    end

    defp count_constraints(attribute) do
      try do
        case attribute do
          %{constraints: constraints} when is_list(constraints) -> length(constraints)
          %{constraints: constraints} when is_map(constraints) -> map_size(constraints)
          _ -> 0
        end
      rescue
        _ -> 0
      end
    end

    defp count_action_changes(action) do
      try do
        changes_count =
          case action do
            %{changes: changes} when is_list(changes) -> length(changes)
            _ -> 0
          end

        validations_count =
          case action do
            %{validations: validations} when is_list(validations) -> length(validations)
            _ -> 0
          end

        changes_count + validations_count
      rescue
        _ -> 0
      end
    end

    defp analyze_policy_expression(policy) do
      try do
        # Rough estimate of expression complexity
        expr_string = inspect(policy.condition)

        # Count operators and function calls
        operator_count = length(Regex.scan(~r/and|or|not/, expr_string))
        function_count = length(Regex.scan(~r/\w+\(/, expr_string))

        operator_count + function_count
      rescue
        _ -> 1
      end
    end

    defp print_complexity_breakdown(complexity) do
      IO.puts("      Attributes: #{complexity.attributes}")
      IO.puts("      Relationships: #{complexity.relationships}")
      IO.puts("      Actions: #{complexity.actions}")
      IO.puts("      Policies: #{complexity.policies}")
      IO.puts("      Changes: #{complexity.changes}")
    end
  else
    # Production stub - debug tools not available
    def profile_dsl_compilation do
      IO.puts("Debug tools not available in production environment")
    end
  end
end
