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
  # Public API
  # =============================================================================

  @doc """
  Route a request to the most appropriate AI provider
  """
  def route_request(method, params, opts \\ []) when is_atom(method) or is_binary(method) do
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
    complexity = estimate_complexity(method, params)
    cost_priority = Keyword.get(opts, :cost_priority, :balanced)

    case method do
      # Analysis methods
      "lang.think.explain_intent" -> route_think_method(complexity, cost_priority)
      "lang.think.explain_why" -> route_think_method(complexity, cost_priority)
      # Claude for nuanced explanations
      "lang.think.explain_how" -> :anthropic
      # GPT-4 for deep diagnosis
      "lang.think.diagnose" -> :openai
      "lang.think.predict_bugs" -> route_think_method(complexity, cost_priority)
      "lang.think.predict_performance" -> route_think_method(complexity, cost_priority)
      # Security needs thorough analysis
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

  defp route_by_cost(:cost_first), do: :xai
  defp route_by_cost(:balanced), do: :openai
  defp route_by_cost(:quality_first), do: :anthropic

  defp route_by_complexity_and_cost(:simple, :cost_first), do: :xai
  defp route_by_complexity_and_cost(:simple, _), do: :xai
  defp route_by_complexity_and_cost(:medium, :cost_first), do: :xai
  defp route_by_complexity_and_cost(:medium, _), do: :openai
  defp route_by_complexity_and_cost(:complex, _), do: :openai
  defp route_by_complexity_and_cost(:critical, _), do: :anthropic

  # =============================================================================
  # Complexity Estimation
  # =============================================================================

  defp estimate_complexity(_method, params) do
    # Estimate based on input size and task requirements
    content_size = get_content_size(params)
    requirements = Map.get(params, :requirements, [])
    context_size = get_context_size(params)

    cond do
      content_size < 100 and length(requirements) == 0 -> :simple
      content_size < 500 and length(requirements) < 3 -> :medium
      content_size < 2000 and context_size < 1000 -> :medium
      content_size > 5000 or context_size > 2000 -> :critical
      true -> :complex
    end
  end

  defp get_content_size(params) when is_map(params) do
    params
    |> Map.values()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&byte_size/1)
    |> Enum.sum()
  end

  defp get_content_size(_), do: 0

  defp get_context_size(params) do
    context = Map.get(params, :context, %{})

    case context do
      ctx when is_map(ctx) -> get_content_size(ctx)
      ctx when is_binary(ctx) -> byte_size(ctx)
      _ -> 0
    end
  end

  # =============================================================================
  # Fallback Handling
  # =============================================================================

  @doc """
  Handle request with automatic fallback to other providers
  """
  def route_with_fallback(method, params, opts \\ []) do
    primary = select_provider(method, params, opts)
    fallback_order = determine_fallback_order(primary)

    # Try each provider in order
    Enum.reduce_while([primary | fallback_order], {:error, "All providers failed"}, fn provider,
                                                                                       _acc ->
      case route_request(method, params, Keyword.put(opts, :provider, provider)) do
        {:ok, _result} = success ->
          {:halt, success}

        {:error, reason} ->
          Logger.warning("Provider #{provider} failed: #{inspect(reason)}")
          {:cont, {:error, reason}}
      end
    end)
  end

  defp determine_fallback_order(:xai), do: [:openai, :anthropic]
  defp determine_fallback_order(:openai), do: [:xai, :anthropic]
  defp determine_fallback_order(:anthropic), do: [:openai, :xai]
  defp determine_fallback_order(_), do: [:xai, :openai, :anthropic]

  # =============================================================================
  # Cost Tracking
  # =============================================================================

  @doc """
  Estimate cost for a request
  """
  def estimate_cost(method, params, provider) do
    token_count = estimate_tokens(params)

    base_cost =
      case provider do
        # $0.001 per 1K tokens (example)
        :xai -> token_count * 0.001 / 1000
        # $0.03 per 1K tokens
        :openai -> token_count * 0.03 / 1000
        # $0.015 per 1K tokens
        :anthropic -> token_count * 0.015 / 1000
        _ -> 0
      end

    # Add method-specific multipliers
    multiplier =
      cond do
        is_binary(method) and String.starts_with?(method, "lang.generate.") -> 2.0
        is_binary(method) and String.starts_with?(method, "lang.think.security") -> 1.5
        true -> 1.0
      end

    base_cost * multiplier
  end

  defp estimate_tokens(params) when is_map(params) do
    # Rough estimation: ~4 chars per token
    content_size = get_content_size(params)
    div(content_size, 4)
  end

  defp estimate_tokens(_), do: 100

  # =============================================================================
  # Provider Management
  # =============================================================================

  @doc """
  Check if a provider is available
  """
  def provider_available?(provider) do
    case provider do
      :xai -> XAI.available?()
      :openai -> OpenAI.available?()
      :anthropic -> Anthropic.available?()
      _ -> false
    end
  end

  @doc """
  Get list of available providers
  """
  def available_providers do
    [:xai, :openai, :anthropic]
    |> Enum.filter(&provider_available?/1)
  end

  @doc """
  Get provider capabilities
  """
  def provider_capabilities(provider) do
    case provider do
      :xai ->
        %{
          max_context: 100_000,
          supports_vision: true,
          supports_function_calling: true,
          supports_streaming: true,
          strengths: ["fast inference", "large context", "reasoning"],
          best_for: ["code analysis", "explanations", "completions"]
        }

      :openai ->
        %{
          max_context: 128_000,
          supports_vision: true,
          supports_function_calling: true,
          supports_streaming: true,
          strengths: ["code generation", "broad knowledge", "reliability"],
          best_for: ["code generation", "refactoring", "complex tasks"]
        }

      :anthropic ->
        %{
          max_context: 200_000,
          supports_vision: false,
          supports_function_calling: false,
          supports_streaming: true,
          strengths: ["thorough analysis", "safety", "nuanced understanding"],
          best_for: ["security analysis", "documentation", "explanations"]
        }

      _ ->
        %{}
    end
  end

  # =============================================================================
  # Health Checking
  # =============================================================================

  @doc """
  Perform health check on all providers
  """
  def health_check do
    providers = [:xai, :openai, :anthropic]

    results =
      providers
      |> Task.async_stream(&{&1, check_provider_health(&1)}, timeout: 5000)
      |> Enum.to_list()
      |> Enum.map(fn {:ok, result} -> result end)

    %{
      timestamp: DateTime.utc_now(),
      overall_status: determine_overall_health(results),
      provider_status: Map.new(results)
    }
  end

  defp check_provider_health(:xai), do: XAI.health_check()
  defp check_provider_health(:openai), do: Lang.Providers.OpenAI.health_check()
  defp check_provider_health(:anthropic), do: Lang.Providers.Anthropic.health_check()
  defp check_provider_health(:gemini), do: Lang.Providers.Gemini.health_check()
  defp check_provider_health(:opencode), do: Lang.Providers.OpenCode.health_check()

  defp determine_overall_health(results) do
    if Enum.any?(results, fn {_, {status, _}} -> status == :ok end) do
      :healthy
    else
      :unhealthy
    end
  end

  # =============================================================================
  # LSP-Specific Routing
  # =============================================================================

  @doc """
  Route LSP-specific requests (hover, completion, etc.)
  """
  def route_lsp(method, params, opts \\ []) do
    case method do
      :hover -> route_hover(params, opts)
      :completion -> route_completion(params, opts)
      :explain -> route_explain(params, opts)
      :refactor -> route_refactor(params, opts)
      :generate_tests -> route_generate_tests(params, opts)
      _ -> {:error, "LSP method #{method} not supported"}
    end
  end

  defp route_completion(params, opts) do
    # Completion is latency-sensitive, use fast providers
    provider = Keyword.get(opts, :provider) || select_completion_provider(params)

    prompt = build_completion_prompt(params)

    case provider do
      :xai ->
        XAI.complete(prompt, opts)

      :openai ->
        OpenAI.complete(prompt, opts)

      :anthropic ->
        Anthropic.complete(prompt, opts)

      _ ->
        {:error, "Invalid provider for completion"}
    end
  end

  defp route_hover(params, opts) do
    # Hover needs quick, accurate info
    provider = Keyword.get(opts, :provider, :xai)

    prompt = """
    Provide a brief, informative description for the following code element:

    Element: #{params.word}
    Context: #{params.context}
    Language: #{params.language}

    Format as markdown with:
    - Brief description
    - Type information if available
    - Example usage if relevant
    """

    case provider do
      :xai -> XAI.query(prompt, max_tokens: 200)
      :openai -> OpenAI.query(prompt, max_tokens: 200)
      :anthropic -> Anthropic.query(prompt, max_tokens: 200)
      _ -> {:error, "Invalid provider for hover"}
    end
  end

  defp route_explain(params, opts) do
    provider = Keyword.get(opts, :provider, :openai)

    prompt = """
    Explain the following #{params.language} code:

    ```#{params.language}
    #{params.code}
    ```

    Provide a clear, educational explanation covering:
    - What the code does
    - How it works
    - Key concepts used
    - Potential improvements
    """

    case provider do
      :xai -> XAI.analyze(prompt, opts)
      :openai -> OpenAI.analyze(prompt, opts)
      :anthropic -> Anthropic.analyze(prompt, opts)
      _ -> {:error, "Invalid provider for explain"}
    end
  end

  defp route_refactor(params, opts) do
    provider = Keyword.get(opts, :provider, :openai)

    prompt = """
    Refactor the following #{params.language} code for #{params.type}:

    ```#{params.language}
    #{params.code}
    ```

    Requirements:
    - Maintain exact functionality
    - Improve #{params.type}
    - Follow #{params.language} best practices
    - Include brief comments explaining changes

    Return only the refactored code.
    """

    case provider do
      :xai -> XAI.generate(prompt, opts)
      :openai -> OpenAI.generate(prompt, opts)
      :anthropic -> Anthropic.generate(prompt, opts)
      _ -> {:error, "Invalid provider for refactor"}
    end
  end

  defp route_generate_tests(params, opts) do
    provider = Keyword.get(opts, :provider, :openai)

    prompt = """
    Generate comprehensive tests for the following #{params.language} code:

    ```#{params.language}
    #{params.code}
    ```

    Requirements:
    - Cover all public functions/methods
    - Include edge cases
    - Test error conditions
    - Use appropriate testing framework for #{params.language}

    Return only the test code.
    """

    case provider do
      :xai -> XAI.generate(prompt, opts)
      :openai -> OpenAI.generate(prompt, opts)
      :anthropic -> Anthropic.generate(prompt, opts)
      _ -> {:error, "Invalid provider for test generation"}
    end
  end

  defp select_completion_provider(%{language: "elixir", prefix: prefix}) do
    # Grok is good for Elixir
    if String.length(prefix) < 20, do: :xai, else: :openai
  end

  defp select_completion_provider(%{language: language})
       when language in ["python", "javascript"] do
    # OpenAI excels at mainstream languages
    :openai
  end

  defp select_completion_provider(_) do
    # Default to Grok for speed
    :xai
  end

  defp build_completion_prompt(%{context: context, language: language, prefix: prefix} = params) do
    suffix = Map.get(params, :suffix, "")

    """
    Complete the following #{language} code at the cursor position:

    ```#{language}
    #{context.previous_lines |> Enum.join("\n")}
    #{prefix}<CURSOR>#{suffix}
    #{context.next_lines |> Enum.join("\n")}
    ```

    Provide only the code to insert at cursor position.
    Be concise and contextually appropriate.
    """
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
