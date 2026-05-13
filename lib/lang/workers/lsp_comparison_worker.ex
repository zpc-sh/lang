defmodule Lang.Workers.LSPComparisonWorker do
  @moduledoc """
  Oban worker for executing individual LSP comparison tests.

  This worker handles the actual execution of AI agent tasks with and without
  LSP support, measuring performance metrics and returning results for analysis.
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3, priority: 2

  require Logger
  alias Lang.Testing.{ScenarioDefinitions, AgentVariantGenerator}
  alias Lang.LSP.Dispatch
  alias Lang.Analytics.LSPMeasurementEvent
  alias Phoenix.PubSub

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "test_id" => test_id,
          "scenario_id" => scenario_id,
          "agent_variant" => agent_variant,
          "lsp_enabled" => lsp_enabled,
          "session_id" => session_id,
          "timeout_minutes" => timeout_minutes,
          "user_id" => user_id,
          "organization_id" => organization_id
        }
      }) do
    Logger.info("Starting LSP comparison test",
      test_id: test_id,
      scenario_id: scenario_id,
      lsp_enabled: lsp_enabled
    )

    start_time = System.monotonic_time(:millisecond)

    try do
      # Get scenario configuration
      scenario = ScenarioDefinitions.get_scenario(String.to_atom(scenario_id))

      # Reconstruct agent variant
      variant = reconstruct_agent_variant(agent_variant)

      # Execute the test
      result = execute_test(scenario, variant, lsp_enabled, timeout_minutes)

      # Calculate metrics
      completion_time = System.monotonic_time(:millisecond) - start_time

      # Compile final result
      final_result = %{
        test_id: test_id,
        scenario_id: scenario_id,
        agent_variant_name: Map.get(agent_variant, "name"),
        lsp_enabled: lsp_enabled,
        status: :completed,
        completion_time_ms: completion_time,
        quality_score: calculate_quality_score(result, scenario),
        context_utilization: calculate_context_utilization(result, lsp_enabled),
        error_count: count_errors(result),
        task_completion_rate: calculate_completion_rate(result, scenario),
        results: result,
        completed_at: DateTime.utc_now()
      }

      # Track in analytics
      track_test_metrics(session_id, test_id, final_result, user_id, organization_id)

      # Notify session manager
      notify_test_completion(session_id, test_id, final_result)

      Logger.info("LSP comparison test completed",
        test_id: test_id,
        completion_time: completion_time,
        quality_score: final_result.quality_score
      )

      :ok
    rescue
      error ->
        completion_time = System.monotonic_time(:millisecond) - start_time

        error_result = %{
          test_id: test_id,
          status: :failed,
          error: Exception.message(error),
          error_type: error.__struct__,
          completion_time_ms: completion_time,
          completed_at: DateTime.utc_now()
        }

        # Notify session manager of failure
        notify_test_failure(session_id, test_id, error_result)

        Logger.error("LSP comparison test failed",
          test_id: test_id,
          error: Exception.message(error),
          completion_time: completion_time
        )

        {:error, error}
    end
  end

  # Private Functions

  defp execute_test(scenario, agent_variant, lsp_enabled, timeout_minutes) do
    timeout_ms = timeout_minutes * 60 * 1000

    # Setup test environment
    test_env = setup_test_environment(scenario, lsp_enabled)

    # Execute all tasks in the scenario
    results =
      scenario.tasks
      |> Enum.with_index()
      |> Enum.map(fn {task, index} ->
        execute_task(task, agent_variant, test_env, lsp_enabled, timeout_ms, index)
      end)

    # Compile results
    %{
      scenario_results: results,
      environment: test_env,
      lsp_enabled: lsp_enabled,
      total_tasks: length(scenario.tasks),
      completed_tasks: count_completed_tasks(results)
    }
  end

  defp setup_test_environment(scenario, lsp_enabled) do
    # Create temporary workspace for test
    workspace_id = "test_#{System.unique_integer([:positive])}"
    workspace_path = Path.join([System.tmp_dir(), "lsp_comparison", workspace_id])

    File.mkdir_p!(workspace_path)

    # Setup files from scenario
    Enum.each(scenario.setup.files, fn file_config ->
      file_path = Path.join([workspace_path, file_config.path])
      file_dir = Path.dirname(file_path)
      File.mkdir_p!(file_dir)
      File.write!(file_path, file_config.content)
    end)

    # Initialize LSP if enabled
    lsp_context =
      if lsp_enabled do
        initialize_lsp_context(workspace_path, scenario)
      else
        nil
      end

    %{
      workspace_id: workspace_id,
      workspace_path: workspace_path,
      lsp_context: lsp_context,
      lsp_enabled: lsp_enabled,
      files: scenario.setup.files
    }
  end

  defp initialize_lsp_context(workspace_path, scenario) do
    # Simulate LSP initialization and context building
    # In a real implementation, this would start actual LSP servers

    # Scan workspace for symbols, dependencies, etc.
    symbols = extract_symbols_from_workspace(workspace_path)
    dependencies = analyze_dependencies(workspace_path, scenario.setup.dependencies || [])
    type_info = infer_type_information(workspace_path)

    %{
      workspace_path: workspace_path,
      symbols: symbols,
      dependencies: dependencies,
      type_info: type_info,
      cross_references: build_cross_references(symbols),
      initialized_at: DateTime.utc_now()
    }
  end

  defp execute_task(task, agent_variant, test_env, lsp_enabled, timeout_ms, task_index) do
    task_start = System.monotonic_time(:millisecond)

    try do
      # Prepare task context
      context = prepare_task_context(task, test_env, lsp_enabled)

      # Execute task with agent variant
      result =
        Task.async(fn ->
          execute_agent_task(agent_variant, task, context, lsp_enabled)
        end)
        |> Task.await(timeout_ms)

      completion_time = System.monotonic_time(:millisecond) - task_start

      %{
        task_index: task_index,
        task_type: task.type,
        status: :completed,
        result: result,
        completion_time_ms: completion_time,
        context_used: Map.get(context, :context_size, 0),
        lsp_features_used: extract_lsp_features_used(result, lsp_enabled)
      }
    rescue
      error ->
        completion_time = System.monotonic_time(:millisecond) - task_start

        %{
          task_index: task_index,
          task_type: task.type,
          status: :failed,
          error: Exception.message(error),
          completion_time_ms: completion_time
        }
    catch
      :exit, {:timeout, _} ->
        %{
          task_index: task_index,
          task_type: task.type,
          status: :timeout,
          completion_time_ms: timeout_ms
        }
    end
  end

  defp prepare_task_context(task, test_env, lsp_enabled) do
    base_context = %{
      task_type: task.type,
      requirements: task.requirements,
      workspace_path: test_env.workspace_path,
      files: test_env.files
    }

    if lsp_enabled && test_env.lsp_context do
      # Add rich LSP context
      target_file = Map.get(task, :target)
      relevant_symbols = find_relevant_symbols(target_file, test_env.lsp_context)

      Map.merge(base_context, %{
        lsp_context: test_env.lsp_context,
        symbols: relevant_symbols,
        type_info: get_relevant_type_info(target_file, test_env.lsp_context),
        dependencies: test_env.lsp_context.dependencies,
        cross_references: get_relevant_references(target_file, test_env.lsp_context),
        context_size: calculate_context_size(test_env.lsp_context)
      })
    else
      # Minimal context without LSP
      Map.put(base_context, :context_size, 0)
    end
  end

  defp safe_string_to_module(module_string) when is_binary(module_string) do
    if String.starts_with?(module_string, "Elixir.Lang.Testing.Variants.") do
      try do
        {:ok, String.to_existing_atom(module_string)}
      rescue
        ArgumentError -> {:error, "Module does not exist"}
      end
    else
      {:error, "Unauthorized module prefix"}
    end
  end

  defp safe_string_to_module(_), do: {:error, "Invalid module format"}

  defp execute_agent_task(agent_variant, task, context, lsp_enabled) do
    # Reconstruct the agent module
    agent_module = agent_variant["provider_module"]

    # Convert task to provider request format
    {method, params} = convert_task_to_provider_request(task, context, lsp_enabled)

    # Execute via the agent variant safely
    with {:ok, module_atom} <- safe_string_to_module(agent_module),
         {:ok, result} <- apply(module_atom, :handle_request, [method, params, []]) do
      %{
        status: :success,
        output: result,
        method: method,
        lsp_context_used: lsp_enabled,
        confidence: Map.get(result, :confidence, 0.0),
        provider_metadata: Map.get(result, :metadata, %{})
      }
    else
      {:error, reason} ->
        %{
          status: :error,
          error: reason,
          method: method,
          lsp_context_used: lsp_enabled
        }
    end
  end

  defp convert_task_to_provider_request(task, context, lsp_enabled) do
    case task.type do
      :refactor ->
        method = "refactor"

        params = %{
          code: get_target_file_content(task.target, context),
          language: detect_language(task.target),
          goal: Enum.join(task.requirements, "; "),
          context: if(lsp_enabled, do: format_lsp_context(context), else: "")
        }

        {method, params}

      :analyze_dependencies ->
        method = "lang.analyze.dependencies"

        params = %{
          workspace_path: context.workspace_path,
          context: if(lsp_enabled, do: format_lsp_context(context), else: "")
        }

        {method, params}

      :performance_analysis ->
        method = "lang.analyze.performance"

        params = %{
          code: get_workspace_content(context),
          language: "elixir",
          context: if(lsp_enabled, do: format_lsp_context(context), else: "")
        }

        {method, params}

      :security_analysis ->
        method = "lang.analyze.security"

        params = %{
          code: get_workspace_content(context),
          language: "elixir",
          context: if(lsp_enabled, do: format_lsp_context(context), else: "")
        }

        {method, params}

      :test_generation ->
        method = "generate_tests"

        params = %{
          code: get_target_file_content(task.target, context),
          language: detect_language(task.target),
          framework: "ExUnit",
          context: if(lsp_enabled, do: format_lsp_context(context), else: "")
        }

        {method, params}

      :optimization ->
        method = "refactor"

        params = %{
          code: get_target_file_content(task.target, context),
          language: detect_language(task.target),
          goal: "optimize performance",
          context: if(lsp_enabled, do: format_lsp_context(context), else: "")
        }

        {method, params}

      _ ->
        # Default to explanation
        method = "explain"

        params = %{
          code: get_workspace_content(context),
          question: Enum.join(task.requirements, "; "),
          context: if(lsp_enabled, do: format_lsp_context(context), else: "")
        }

        {method, params}
    end
  end

  defp reconstruct_agent_variant(agent_data) do
    # Reconstruct agent variant from serialized data
    # This is a simplified version - in practice might need more complex reconstruction
    agent_data
  end

  defp calculate_quality_score(result, scenario) do
    # Calculate quality based on scenario success criteria
    base_score =
      case result.scenario_results do
        results when is_list(results) ->
          successful_tasks = Enum.count(results, &(&1.status == :completed))
          total_tasks = length(results)
          if total_tasks > 0, do: successful_tasks / total_tasks, else: 0.0

        _ ->
          0.0
      end

    # Apply scenario-specific quality adjustments
    quality_modifiers = scenario.success_criteria || %{}

    # Simple quality calculation - could be more sophisticated
    # Ensure minimum baseline
    base_score * 0.8 + 0.2
  end

  defp calculate_context_utilization(result, lsp_enabled) do
    if lsp_enabled do
      # Calculate how effectively LSP context was used
      total_context = get_total_context_available(result)
      used_context = get_context_actually_used(result)

      if total_context > 0, do: used_context / total_context, else: 0.0
    else
      0.0
    end
  end

  defp count_errors(result) do
    case result.scenario_results do
      results when is_list(results) ->
        Enum.count(results, &(&1.status in [:failed, :timeout]))

      _ ->
        1
    end
  end

  defp calculate_completion_rate(result, _scenario) do
    case result.scenario_results do
      results when is_list(results) ->
        completed = Enum.count(results, &(&1.status == :completed))
        total = length(results)
        if total > 0, do: completed / total, else: 0.0

      _ ->
        0.0
    end
  end

  defp count_completed_tasks(results) do
    Enum.count(results, &(&1.status == :completed))
  end

  # Helper functions for LSP context simulation

  defp extract_symbols_from_workspace(workspace_path) do
    # Simulate symbol extraction from workspace files
    # In real implementation, would use tree-sitter or language-specific parsers

    workspace_path
    |> Lang.Native.FSScanner.scan(max_depth: 5)
    |> case do
      {:ok, %{tree: files}} ->
        files
        |> Enum.filter(&String.ends_with?(&1.path, [".ex", ".exs"]))
        |> Enum.flat_map(&extract_symbols_from_file/1)

      _ ->
        []
    end
  end

  defp extract_symbols_from_file(file_info) do
    # Extract basic symbols (modules, functions, etc.)
    # Simplified implementation
    [
      %{
        name: Path.basename(file_info.path, ".ex") |> Macro.camelize(),
        type: :module,
        file: file_info.path,
        line: 1
      }
    ]
  end

  defp analyze_dependencies(_workspace_path, dependencies) do
    # Return provided dependencies for now
    Enum.map(dependencies, &%{name: &1, type: :external})
  end

  defp infer_type_information(workspace_path) do
    # Simulate type inference
    # Would use Elixir's type system, Dialyzer, etc. in real implementation
    %{
      workspace_path: workspace_path,
      inferred_types: %{},
      type_errors: []
    }
  end

  defp build_cross_references(symbols) do
    # Build cross-reference map between symbols
    symbols
    |> Enum.map(&{&1.name, []})
    |> Map.new()
  end

  defp find_relevant_symbols(_target_file, lsp_context) do
    # Return relevant symbols for the target file
    Map.get(lsp_context, :symbols, [])
  end

  defp get_relevant_type_info(_target_file, lsp_context) do
    Map.get(lsp_context, :type_info, %{})
  end

  defp get_relevant_references(_target_file, lsp_context) do
    Map.get(lsp_context, :cross_references, %{})
  end

  defp calculate_context_size(lsp_context) do
    symbol_count = length(Map.get(lsp_context, :symbols, []))
    dependency_count = length(Map.get(lsp_context, :dependencies, []))
    reference_count = map_size(Map.get(lsp_context, :cross_references, %{}))

    symbol_count + dependency_count + reference_count
  end

  defp get_target_file_content(target, context) when is_binary(target) do
    file_path = Path.join([context.workspace_path, target])

    case File.read(file_path) do
      {:ok, content} -> content
      _ -> ""
    end
  end

  defp get_target_file_content(_, _), do: ""

  defp get_workspace_content(context) do
    # Get concatenated content of key files
    context.files
    # Limit to avoid huge context
    |> Enum.take(3)
    |> Enum.map(& &1.content)
    |> Enum.join("\n\n")
  end

  defp detect_language(file_path) when is_binary(file_path) do
    cond do
      String.ends_with?(file_path, [".ex", ".exs"]) -> "elixir"
      String.ends_with?(file_path, [".js", ".jsx"]) -> "javascript"
      String.ends_with?(file_path, [".ts", ".tsx"]) -> "typescript"
      String.ends_with?(file_path, [".py"]) -> "python"
      String.ends_with?(file_path, [".rs"]) -> "rust"
      true -> "text"
    end
  end

  defp detect_language(_), do: "elixir"

  defp format_lsp_context(context) when is_map(context) do
    lsp_context = Map.get(context, :lsp_context, %{})

    symbols_info =
      case Map.get(lsp_context, :symbols) do
        symbols when is_list(symbols) and length(symbols) > 0 ->
          "Available symbols: " <> Enum.map_join(symbols, ", ", & &1.name)

        _ ->
          "No symbols available"
      end

    dependencies_info =
      case Map.get(lsp_context, :dependencies) do
        deps when is_list(deps) and length(deps) > 0 ->
          "Dependencies: " <> Enum.map_join(deps, ", ", & &1.name)

        _ ->
          "No dependencies"
      end

    type_info =
      case Map.get(lsp_context, :type_info) do
        %{inferred_types: types} when map_size(types) > 0 ->
          "Type information available"

        _ ->
          "No type information"
      end

    [symbols_info, dependencies_info, type_info]
    |> Enum.join("\n")
  end

  defp format_lsp_context(_), do: ""

  defp extract_lsp_features_used(result, false), do: []

  defp extract_lsp_features_used(result, true) do
    # Analyze which LSP features were effectively used
    features = []

    features =
      if Map.has_key?(result, :symbols_referenced) do
        ["symbol_resolution" | features]
      else
        features
      end

    features =
      if Map.has_key?(result, :type_info_used) do
        ["type_inference" | features]
      else
        features
      end

    features =
      if Map.has_key?(result, :cross_references_used) do
        ["cross_references" | features]
      else
        features
      end

    features
  end

  defp get_total_context_available(result) do
    # Calculate total LSP context that was available
    case get_in(result, [:environment, :lsp_context]) do
      %{symbols: symbols, dependencies: deps, cross_references: refs} ->
        length(symbols || []) + length(deps || []) + map_size(refs || %{})

      _ ->
        0
    end
  end

  defp get_context_actually_used(result) do
    # Calculate how much context was actually used
    # This would be determined by analyzing the generated output
    # For now, return a simulated value
    total_available = get_total_context_available(result)
    # Assume 60-80% utilization for successful tasks
    case result.scenario_results do
      results when is_list(results) ->
        success_rate = calculate_completion_rate(result, nil)
        round(total_available * (0.6 + success_rate * 0.2))

      _ ->
        0
    end
  end

  defp track_test_metrics(session_id, test_id, result, user_id, organization_id) do
    # Track in LSP analytics system
    event_data = %{
      user_id: user_id,
      organization_id: organization_id,
      session_id: session_id,
      request_id: test_id,
      lsp_method: :comparison_test,
      lsp_enabled: result.lsp_enabled,
      completion_time_ms: result.completion_time_ms,
      tokens_processed: estimate_tokens_processed(result),
      context_lines: estimate_context_lines(result),
      quality_score: result.quality_score,
      error_count: result.error_count,
      success: result.status == :completed
    }

    case LSPMeasurementEvent.create(event_data) do
      {:ok, _event} ->
        :ok

      {:error, reason} ->
        Logger.warn("Failed to track test metrics", reason: reason, test_id: test_id)
    end
  end

  defp estimate_tokens_processed(result) do
    # Rough estimate of tokens processed
    # In practice, would track actual token counts
    base_tokens = 1000

    case result.results do
      %{scenario_results: results} when is_list(results) ->
        base_tokens * length(results)

      _ ->
        base_tokens
    end
  end

  defp estimate_context_lines(result) do
    # Estimate context lines used
    if result.lsp_enabled do
      (result.context_utilization * 100) |> round()
    else
      # Minimal context without LSP
      10
    end
  end

  defp notify_test_completion(session_id, test_id, result) do
    PubSub.broadcast(
      Lang.PubSub,
      "lsp_comparison:#{session_id}",
      {:test_completed, test_id, result}
    )
  end

  defp notify_test_failure(session_id, test_id, error_result) do
    PubSub.broadcast(
      Lang.PubSub,
      "lsp_comparison:#{session_id}",
      {:test_failed, test_id, error_result}
    )
  end
end
