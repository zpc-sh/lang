defmodule Lang.Providers.Router do
  @moduledoc """
  Provider router for coordinating multiple AI providers.

  Routes requests to the most appropriate provider based on:
  - Task complexity and type
  - Cost optimization
  - Provider availability
  - Performance requirements
  """

  require Logger
  alias Lang.Providers.{XAI, OpenAI, Anthropic}

  # =============================================================================
  # Provider Selection
  # =============================================================================

  @doc """
  Route a request to the most appropriate AI provider
  """
  def route_request(method, params, opts \\ []) do
    provider = select_provider(method, params, opts)

    Logger.info("Routing #{method} to #{provider}", params: sanitize_params(params))

    case provider do
      :xai -> XAI.handle_request(method, params, opts)
      :openai -> OpenAI.handle_request(method, params, opts)
      :anthropic -> Anthropic.handle_request(method, params, opts)
      :error -> {:error, "No suitable provider available"}
    end
  end

  @doc """
  Route specifically to Grok for mission command operations
  """
  def command_mission(request, opts \\ []) do
    XAI.command_mission(request, opts)
  end

  @doc """
  Route for tactical analysis - always uses Grok
  """
  def analyze_situation(context, question, opts \\ []) do
    XAI.analyze_situation(context, question, opts)
  end

  # =============================================================================
  # Provider Selection Logic
  # =============================================================================

  defp select_provider(method, params, opts) do
    # Override provider if explicitly specified
    case Keyword.get(opts, :provider) do
      nil -> auto_select_provider(method, params, opts)
      provider when provider in [:xai, :openai, :anthropic] -> provider
      _ -> :error
    end
  end

  defp auto_select_provider(method, params, opts) do
    complexity = assess_complexity(method, params)
    cost_priority = Keyword.get(opts, :cost_priority, :balanced)

    case method do
      # Mission command always goes to Grok
      "mission_command" -> :xai
      "tactical_analysis" -> :xai
      # Think methods - route by complexity
      "lang.think.explain_intent" -> route_think_method(complexity, cost_priority)
      "lang.think.explain_why" -> route_think_method(complexity, cost_priority)
      "lang.think.explain_how" -> route_think_method(complexity, cost_priority)
      # Claude excels at diagnostics
      "lang.think.diagnose" -> :anthropic
      # Security-minded analysis
      "lang.think.predict_bugs" -> :anthropic
      # Obviously Claude for security
      "lang.think.security_scan" -> :anthropic
      "lang.think.find_semantic" -> route_search_method(complexity, cost_priority)
      # GPT-4 good at complex flow analysis
      "lang.think.trace_flow" -> :openai
      # Generation methods
      # GPT-4 excellent at code generation
      "lang.generate.from_spec" -> :openai
      # TDD generation
      "lang.generate.from_tests" -> :openai
      "lang.generate.dockerfile" -> route_generation_method(complexity, cost_priority)
      # Simple operations
      # Grok for straightforward queries
      "lang.query.simple" -> :xai
      "lang.fs.explain_structure" -> route_by_cost(cost_priority)
      # Default routing
      _ -> route_by_complexity_and_cost(complexity, cost_priority)
    end
  end

  # =============================================================================
  # Routing Strategies
  # =============================================================================

  defp route_think_method(:simple, :cost_first), do: :xai
  defp route_think_method(:simple, _), do: :xai
  defp route_think_method(:medium, :cost_first), do: :xai
  defp route_think_method(:medium, _), do: :openai
  defp route_think_method(:complex, _), do: :openai
  # Most thorough analysis
  defp route_think_method(:critical, _), do: :anthropic

  defp route_search_method(:simple, _), do: :xai
  defp route_search_method(:medium, :cost_first), do: :xai
  defp route_search_method(:medium, _), do: :openai
  # Deep semantic analysis
  defp route_search_method(:complex, _), do: :anthropic
  defp route_search_method(:critical, _), do: :anthropic

  defp route_generation_method(:simple, :cost_first), do: :xai
  defp route_generation_method(:simple, _), do: :openai
  defp route_generation_method(:medium, _), do: :openai
  # GPT-4 best at generation
  defp route_generation_method(:complex, _), do: :openai
  defp route_generation_method(:critical, _), do: :openai

  # Cheapest option
  defp route_by_cost(:cost_first), do: :xai
  # Most thorough
  defp route_by_cost(:quality_first), do: :anthropic
  # Good balance
  defp route_by_cost(:balanced), do: :openai

  defp route_by_complexity_and_cost(:simple, :cost_first), do: :xai
  defp route_by_complexity_and_cost(:simple, _), do: :xai
  defp route_by_complexity_and_cost(:medium, :cost_first), do: :xai
  defp route_by_complexity_and_cost(:medium, _), do: :openai
  defp route_by_complexity_and_cost(:complex, :cost_first), do: :openai
  defp route_by_complexity_and_cost(:complex, _), do: :anthropic
  defp route_by_complexity_and_cost(:critical, _), do: :anthropic

  # =============================================================================
  # Complexity Assessment
  # =============================================================================

  defp assess_complexity(method, params) do
    base_complexity = method_base_complexity(method)

    # Adjust based on parameters
    adjusted_complexity =
      base_complexity
      |> adjust_for_file_size(params)
      |> adjust_for_context_size(params)
      |> adjust_for_urgency(params)

    adjusted_complexity
  end

  defp method_base_complexity("lang.think.explain_intent"), do: :medium
  defp method_base_complexity("lang.think.explain_why"), do: :medium
  defp method_base_complexity("lang.think.explain_how"), do: :medium
  defp method_base_complexity("lang.think.diagnose"), do: :complex
  defp method_base_complexity("lang.think.predict_bugs"), do: :complex
  defp method_base_complexity("lang.think.security_scan"), do: :critical
  defp method_base_complexity("lang.think.find_semantic"), do: :medium
  defp method_base_complexity("lang.think.trace_flow"), do: :complex
  defp method_base_complexity("lang.generate.from_spec"), do: :complex
  defp method_base_complexity("lang.generate.from_tests"), do: :complex
  defp method_base_complexity("lang.generate.dockerfile"), do: :simple
  defp method_base_complexity("lang.query.natural"), do: :medium
  defp method_base_complexity(_), do: :simple

  defp adjust_for_file_size(complexity, %{file_size: size}) when size > 10_000 do
    increase_complexity(complexity)
  end

  defp adjust_for_file_size(complexity, %{file_path: path}) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > 10_000 -> increase_complexity(complexity)
      _ -> complexity
    end
  end

  defp adjust_for_file_size(complexity, _), do: complexity

  defp adjust_for_context_size(complexity, %{context: context}) when is_binary(context) do
    if String.length(context) > 5000 do
      increase_complexity(complexity)
    else
      complexity
    end
  end

  defp adjust_for_context_size(complexity, _), do: complexity

  defp adjust_for_urgency(complexity, %{priority: :critical}), do: :critical

  defp adjust_for_urgency(complexity, %{priority: :high}) do
    increase_complexity(complexity)
  end

  defp adjust_for_urgency(complexity, _), do: complexity

  defp increase_complexity(:simple), do: :medium
  defp increase_complexity(:medium), do: :complex
  defp increase_complexity(:complex), do: :critical
  defp increase_complexity(:critical), do: :critical

  # =============================================================================
  # Multi-Provider Operations
  # =============================================================================

  @doc """
  Execute mission with multiple providers coordinated by Grok
  """
  def execute_mission(mission_request, opts \\ []) do
    # Step 1: Get mission plan from Grok
    case XAI.command_mission(mission_request, opts) do
      {:ok, %{mission_plan: %{tasks: tasks}}} ->
        # Step 2: Execute tasks in parallel
        execute_mission_tasks(tasks, opts)

      {:ok, %{raw_response: response}} ->
        # Fallback if structured parsing failed
        {:ok, %{mission_response: response, tasks_executed: 0}}

      {:error, error} ->
        {:error, "Mission planning failed: #{error}"}
    end
  end

  defp execute_mission_tasks(tasks, opts) do
    # Sort by priority
    sorted_tasks =
      Enum.sort_by(tasks, fn task ->
        case task.priority do
          :critical -> 0
          :high -> 1
          :medium -> 2
          :low -> 3
        end
      end)

    # Execute tasks
    results =
      Task.async_stream(
        sorted_tasks,
        fn task ->
          execute_single_task(task, opts)
        end,
        timeout: 30_000
      )
      |> Enum.to_list()

    # Consolidate results
    consolidate_mission_results(results)
  end

  defp execute_single_task(task, opts) do
    provider = normalize_provider_name(task.provider)

    case provider do
      :openai -> OpenAI.handle_task(task, opts)
      :anthropic -> Anthropic.handle_task(task, opts)
      :xai -> XAI.simple_task(task.description, opts)
      _ -> {:error, "Unknown provider: #{task.provider}"}
    end
  end

  defp normalize_provider_name("OpenAI"), do: :openai
  defp normalize_provider_name("GPT-4"), do: :openai
  defp normalize_provider_name("Anthropic"), do: :anthropic
  defp normalize_provider_name("Claude"), do: :anthropic
  defp normalize_provider_name("xAI"), do: :xai
  defp normalize_provider_name("Grok"), do: :xai

  defp normalize_provider_name(name) when is_binary(name) do
    String.downcase(name) |> String.to_existing_atom()
  rescue
    ArgumentError -> :unknown
  end

  defp consolidate_mission_results(results) do
    successful = Enum.filter(results, fn {status, _} -> status == :ok end)
    failed = Enum.filter(results, fn {status, _} -> status == :error end)

    %{
      total_tasks: length(results),
      successful_tasks: length(successful),
      failed_tasks: length(failed),
      results: Enum.map(successful, fn {:ok, result} -> result end),
      errors: Enum.map(failed, fn {:error, error} -> error end)
    }
  end

  # =============================================================================
  # Health Monitoring
  # =============================================================================

  @doc """
  Check health of all providers
  """
  def health_check do
    providers = [:xai, :openai, :anthropic]

    results =
      Task.async_stream(
        providers,
        fn provider ->
          {provider, check_provider_health(provider)}
        end,
        timeout: 10_000
      )
      |> Enum.to_list()
      |> Enum.map(fn {:ok, result} -> result end)

    %{
      timestamp: DateTime.utc_now(),
      overall_status: determine_overall_health(results),
      provider_status: Map.new(results)
    }
  end

  defp check_provider_health(:xai), do: XAI.health_check()
  defp check_provider_health(:openai), do: {:ok, "Not implemented yet"}
  defp check_provider_health(:anthropic), do: {:ok, "Not implemented yet"}

  defp determine_overall_health(results) do
    if Enum.any?(results, fn {_, {status, _}} -> status == :ok end) do
      :healthy
    else
      :unhealthy
    end
  end

  # =============================================================================
  # Utilities
  # =============================================================================

  defp sanitize_params(params) when is_map(params) do
    # Remove sensitive data from logs
    Map.drop(params, [:api_key, :auth_token, :password])
  end

  defp sanitize_params(params), do: params
end
