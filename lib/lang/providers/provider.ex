defmodule Lang.Providers.Provider do
  @moduledoc """
  Generic provider behavior and capabilities system.

  Defines the contract for AI providers and their capabilities, pricing,
  and routing logic. Makes it easy to add new providers without changing
  existing code.
  """

  @doc """
  Provider configuration and capabilities
  """
  @callback capabilities() :: %{
              methods: [String.t()],
              strengths: [atom()],
              weaknesses: [atom()],
              cost_tier: :cheap | :medium | :expensive,
              speed_tier: :slow | :medium | :fast,
              quality_tier: :basic | :good | :excellent,
              specializations: [atom()]
            }

  @doc """
  Pricing information per method/token
  """
  @callback pricing() :: %{
              input_tokens_per_dollar: integer(),
              output_tokens_per_dollar: integer(),
              base_cost_per_request: float(),
              bulk_discount_threshold: integer()
            }

  @doc """
  Handle a generic request for any method
  """
  @callback handle_request(method :: String.t(), params :: map(), opts :: keyword()) ::
              {:ok, result :: map()} | {:error, reason :: any()}

  @doc """
  Provider-specific health check
  """
  @callback health_check() :: {:ok, String.t()} | {:error, any()}

  @doc """
  Estimate cost for a request before executing
  """
  @callback estimate_cost(method :: String.t(), params :: map()) ::
              {:ok, %{estimated_tokens: integer(), estimated_cost_usd: float()}} | {:error, any()}

  # =============================================================================
  # Provider Registry
  # =============================================================================

  @providers %{
    xai: Lang.Providers.XAI,
    openai: Lang.Providers.OpenAI,
    anthropic: Lang.Providers.Anthropic
  }

  @doc """
  Get all available providers
  """
  def available_providers, do: @providers

  @doc """
  Get provider module by name
  """
  def get_provider(name) when name in [:xai, :openai, :anthropic] do
    Map.get(@providers, name)
  end

  def get_provider(_), do: nil

  @doc """
  Get capabilities for all providers
  """
  def all_capabilities do
    Enum.map(@providers, fn {name, module} ->
      {name, module.capabilities()}
    end)
    |> Map.new()
  end

  @doc """
  Get pricing for all providers
  """
  def all_pricing do
    Enum.map(@providers, fn {name, module} ->
      {name, module.pricing()}
    end)
    |> Map.new()
  end

  # =============================================================================
  # Provider Selection Logic
  # =============================================================================

  @doc """
  Select best provider for a given method based on criteria
  """
  def select_provider(method, params \\ %{}, criteria \\ %{}) do
    optimize_for = Map.get(criteria, :optimize_for, :balanced)
    exclude = Map.get(criteria, :exclude, [])

    @providers
    |> Enum.reject(fn {name, _} -> name in exclude end)
    |> Enum.filter(fn {_, module} -> can_handle_method?(module, method) end)
    |> score_providers(method, params, optimize_for)
    |> case do
      [] -> {:error, :no_suitable_provider}
      scored_providers -> {:ok, best_provider(scored_providers)}
    end
  end

  defp can_handle_method?(module, method) do
    capabilities = module.capabilities()

    method in capabilities.methods or
      method_matches_specialization?(method, capabilities.specializations)
  end

  defp method_matches_specialization?(method, specializations) do
    cond do
      String.starts_with?(method, "lang.think.security") -> :security in specializations
      String.starts_with?(method, "lang.think.diagnose") -> :diagnostics in specializations
      String.starts_with?(method, "lang.think.predict") -> :prediction in specializations
      String.starts_with?(method, "lang.generate") -> :generation in specializations
      String.starts_with?(method, "lang.think.explain") -> :explanation in specializations
      String.starts_with?(method, "lang.query") -> :search in specializations
      true -> :general in specializations
    end
  end

  defp score_providers(providers, method, params, optimize_for) do
    Enum.map(providers, fn {name, module} ->
      capabilities = module.capabilities()
      pricing = module.pricing()

      score = calculate_provider_score(capabilities, pricing, method, params, optimize_for)
      {name, module, score}
    end)
  end

  defp calculate_provider_score(capabilities, pricing, method, _params, optimize_for) do
    base_score = base_method_score(method, capabilities)
    cost_score = cost_score(pricing, optimize_for)
    speed_score = speed_score(capabilities, optimize_for)
    quality_score = quality_score(capabilities, optimize_for)

    case optimize_for do
      :cost -> base_score * 0.3 + cost_score * 0.5 + speed_score * 0.1 + quality_score * 0.1
      :speed -> base_score * 0.3 + cost_score * 0.1 + speed_score * 0.5 + quality_score * 0.1
      :quality -> base_score * 0.3 + cost_score * 0.1 + speed_score * 0.1 + quality_score * 0.5
      :balanced -> base_score * 0.4 + cost_score * 0.2 + speed_score * 0.2 + quality_score * 0.2
    end
  end

  defp base_method_score(method, capabilities) do
    cond do
      method in capabilities.methods -> 1.0
      method_matches_specialization?(method, capabilities.specializations) -> 0.8
      true -> 0.3
    end
  end

  defp cost_score(pricing, optimize_for) do
    case pricing.cost_tier do
      :cheap -> if optimize_for == :cost, do: 1.0, else: 0.8
      :medium -> 0.6
      :expensive -> if optimize_for == :quality, do: 0.7, else: 0.3
    end
  end

  defp speed_score(capabilities, optimize_for) do
    case capabilities.speed_tier do
      :fast -> if optimize_for == :speed, do: 1.0, else: 0.8
      :medium -> 0.6
      :slow -> if optimize_for == :quality, do: 0.7, else: 0.3
    end
  end

  defp quality_score(capabilities, optimize_for) do
    case capabilities.quality_tier do
      :excellent -> if optimize_for == :quality, do: 1.0, else: 0.8
      :good -> 0.6
      :basic -> if optimize_for == :cost, do: 0.7, else: 0.3
    end
  end

  defp best_provider(scored_providers) do
    {name, _module, _score} = Enum.max_by(scored_providers, fn {_, _, score} -> score end)
    name
  end

  # =============================================================================
  # Cost Estimation
  # =============================================================================

  @doc """
  Estimate cost across all providers for comparison
  """
  def estimate_costs(method, params) do
    @providers
    |> Enum.map(fn {name, module} ->
      case module.estimate_cost(method, params) do
        {:ok, estimate} -> {name, estimate}
        {:error, _} -> {name, %{estimated_tokens: :unknown, estimated_cost_usd: :unknown}}
      end
    end)
    |> Map.new()
  end

  # =============================================================================
  # Health Monitoring
  # =============================================================================

  @doc """
  Check health of all providers
  """
  def health_check_all do
    results =
      Task.async_stream(
        @providers,
        fn {name, module} ->
          {name, module.health_check()}
        end,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Map.new()

    %{
      timestamp: DateTime.utc_now(),
      providers: results,
      healthy_count: count_healthy(results),
      total_count: map_size(results)
    }
  end

  defp count_healthy(results) do
    Enum.count(results, fn {_, {status, _}} -> status == :ok end)
  end

  # =============================================================================
  # Provider Capabilities Summary
  # =============================================================================

  @doc """
  Get summary of what each provider is best at
  """
  def capability_matrix do
    %{
      xai: %{
        best_for: [:command, :coordination, :simple_tasks, :cost_optimization],
        avoid_for: [:complex_generation, :deep_analysis],
        specializes_in: [:tactical_decisions, :task_breakdown]
      },
      openai: %{
        best_for: [:code_generation, :complex_reasoning, :explanation],
        avoid_for: [:cost_sensitive_operations],
        specializes_in: [:generation, :complex_analysis, :general_purpose]
      },
      anthropic: %{
        best_for: [:security_analysis, :code_review, :diagnostics, :safety],
        avoid_for: [:simple_tasks, :cost_optimization],
        specializes_in: [:security, :analysis, :safety_critical_tasks]
      }
    }
  end

  # =============================================================================
  # Utility Functions
  # =============================================================================

  @doc """
  Check if any provider can handle a method
  """
  def method_supported?(method) do
    Enum.any?(@providers, fn {_, module} ->
      can_handle_method?(module, method)
    end)
  end

  @doc """
  Get cheapest provider for a method
  """
  def cheapest_provider(method, params \\ %{}) do
    case select_provider(method, params, %{optimize_for: :cost}) do
      {:ok, provider} -> provider
      {:error, _} -> nil
    end
  end

  @doc """
  Get highest quality provider for a method
  """
  def best_quality_provider(method, params \\ %{}) do
    case select_provider(method, params, %{optimize_for: :quality}) do
      {:ok, provider} -> provider
      {:error, _} -> nil
    end
  end

  @doc """
  Get fastest provider for a method
  """
  def fastest_provider(method, params \\ %{}) do
    case select_provider(method, params, %{optimize_for: :speed}) do
      {:ok, provider} -> provider
      {:error, _} -> nil
    end
  end

  @doc """
  Smart default provider selection - balances cost, quality, and speed
  """
  def default_provider(method, params \\ %{}) do
    case select_provider(method, params, %{optimize_for: :balanced}) do
      {:ok, provider} -> provider
      {:error, _} -> fallback_provider(method)
    end
  end

  @doc """
  Fallback provider when no smart selection works
  """
  def fallback_provider(method) do
    cond do
      # Security/analysis always goes to Claude if available
      String.contains?(method, "security") -> :anthropic
      String.contains?(method, "diagnose") -> :anthropic
      String.contains?(method, "predict") -> :anthropic
      # Generation goes to OpenAI if available
      String.contains?(method, "generate") -> :openai
      String.contains?(method, "explain") -> :openai
      # Everything else goes to Grok (cheapest)
      true -> :xai
    end
  end

  @doc """
  One-shot method execution with auto provider selection
  """
  def execute(method, params \\ %{}, opts \\ []) do
    provider =
      case Keyword.get(opts, :provider) do
        nil -> default_provider(method, params)
        explicit_provider -> explicit_provider
      end

    case get_provider(provider) do
      nil -> {:error, "Provider #{provider} not available"}
      module -> module.handle_request(method, params, opts)
    end
  end
end
