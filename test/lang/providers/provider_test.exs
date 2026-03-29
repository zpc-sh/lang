defmodule Lang.Providers.ProviderTest do
  use ExUnit.Case, async: true
  import Mox
  alias Lang.Providers.Provider

  setup :verify_on_exit!

  describe "available_providers/0" do
    test "returns all configured providers" do
      providers = Provider.available_providers()
      assert Map.has_key?(providers, :xai)
      assert Map.has_key?(providers, :openai)
      assert Map.has_key?(providers, :anthropic)
    end
  end

  describe "get_provider/1" do
    test "returns correct provider module for valid names" do
      assert Provider.get_provider(:xai) == Lang.Providers.XAI
      assert Provider.get_provider(:openai) == Lang.Providers.OpenAI
      assert Provider.get_provider(:anthropic) == Lang.Providers.Anthropic
    end

    test "returns nil for invalid provider names" do
      assert Provider.get_provider(:invalid) == nil
      assert Provider.get_provider("string") == nil
    end
  end

  describe "select_provider/3" do
    setup do
      # Mock provider capabilities
      providers = %{
        xai: %{
          methods: ["lang.think.explain_intent", "simple_task"],
          strengths: [:command, :cost_optimization],
          cost_tier: :cheap,
          speed_tier: :fast,
          quality_tier: :good,
          specializations: [:command, :simple_tasks]
        },
        openai: %{
          methods: ["lang.generate.from_spec", "lang.think.explain_intent"],
          strengths: [:generation, :complex_reasoning],
          cost_tier: :expensive,
          speed_tier: :medium,
          quality_tier: :excellent,
          specializations: [:generation, :explanation]
        },
        anthropic: %{
          methods: ["lang.think.security_scan", "lang.think.diagnose"],
          strengths: [:security, :analysis],
          cost_tier: :expensive,
          speed_tier: :medium,
          quality_tier: :excellent,
          specializations: [:security, :diagnostics]
        }
      }

      # Mock pricing
      pricing = %{
        xai: %{cost_tier: :cheap, input_tokens_per_dollar: 5000},
        openai: %{cost_tier: :expensive, input_tokens_per_dollar: 500},
        anthropic: %{cost_tier: :expensive, input_tokens_per_dollar: 600}
      }

      {:ok, providers: providers, pricing: pricing}
    end

    test "selects provider based on method availability" do
      method = "lang.think.security_scan"

      # Mock the provider modules
      with_mocks([
        {Lang.Providers.XAI, [],
         [capabilities: fn -> %{methods: ["simple_task"], specializations: [:command]} end]},
        {Lang.Providers.OpenAI, [],
         [
           capabilities: fn ->
             %{methods: ["lang.generate.from_spec"], specializations: [:generation]}
           end
         ]},
        {Lang.Providers.Anthropic, [],
         [
           capabilities: fn ->
             %{methods: ["lang.think.security_scan"], specializations: [:security]}
           end
         ]}
      ]) do
        {:ok, provider} = Provider.select_provider(method)
        assert provider == :anthropic
      end
    end

    test "returns error when no provider can handle method" do
      method = "unsupported.method"

      with_mocks([
        {Lang.Providers.XAI, [], [capabilities: fn -> %{methods: [], specializations: []} end]},
        {Lang.Providers.OpenAI, [],
         [capabilities: fn -> %{methods: [], specializations: []} end]},
        {Lang.Providers.Anthropic, [],
         [capabilities: fn -> %{methods: [], specializations: []} end]}
      ]) do
        assert {:error, :no_suitable_provider} = Provider.select_provider(method)
      end
    end

    test "optimizes selection based on criteria" do
      method = "lang.think.explain_intent"

      # Mock providers that can both handle the method
      with_mocks([
        {Lang.Providers.XAI, [],
         [
           capabilities: fn ->
             %{
               methods: ["lang.think.explain_intent"],
               specializations: [:explanation],
               cost_tier: :cheap,
               speed_tier: :fast,
               quality_tier: :good
             }
           end,
           pricing: fn -> %{cost_tier: :cheap} end
         ]},
        {Lang.Providers.OpenAI, [],
         [
           capabilities: fn ->
             %{
               methods: ["lang.think.explain_intent"],
               specializations: [:explanation],
               cost_tier: :expensive,
               speed_tier: :medium,
               quality_tier: :excellent
             }
           end,
           pricing: fn -> %{cost_tier: :expensive} end
         ]},
        {Lang.Providers.Anthropic, [],
         [
           capabilities: fn -> %{methods: [], specializations: []} end
         ]}
      ]) do
        # Cost optimization should prefer XAI
        {:ok, provider} = Provider.select_provider(method, %{}, %{optimize_for: :cost})
        assert provider == :xai

        # Quality optimization should prefer OpenAI
        {:ok, provider} = Provider.select_provider(method, %{}, %{optimize_for: :quality})
        assert provider == :openai
      end
    end

    test "excludes providers specified in criteria" do
      method = "lang.think.explain_intent"

      with_mocks([
        {Lang.Providers.XAI, [],
         [
           capabilities: fn ->
             %{
               methods: ["lang.think.explain_intent"],
               specializations: [:explanation],
               cost_tier: :cheap,
               speed_tier: :fast,
               quality_tier: :good
             }
           end
         ]},
        {Lang.Providers.OpenAI, [],
         [
           capabilities: fn ->
             %{
               methods: ["lang.think.explain_intent"],
               specializations: [:explanation],
               cost_tier: :expensive,
               speed_tier: :medium,
               quality_tier: :excellent
             }
           end
         ]},
        {Lang.Providers.Anthropic, [],
         [capabilities: fn -> %{methods: [], specializations: []} end]}
      ]) do
        {:ok, provider} = Provider.select_provider(method, %{}, %{exclude: [:xai]})
        assert provider == :openai
      end
    end
  end

  describe "method_supported?/1" do
    test "returns true for supported methods" do
      with_mocks([
        {Lang.Providers.XAI, [],
         [capabilities: fn -> %{methods: ["test.method"], specializations: []} end]},
        {Lang.Providers.OpenAI, [],
         [capabilities: fn -> %{methods: [], specializations: []} end]},
        {Lang.Providers.Anthropic, [],
         [capabilities: fn -> %{methods: [], specializations: []} end]}
      ]) do
        assert Provider.method_supported?("test.method") == true
      end
    end

    test "returns false for unsupported methods" do
      with_mocks([
        {Lang.Providers.XAI, [], [capabilities: fn -> %{methods: [], specializations: []} end]},
        {Lang.Providers.OpenAI, [],
         [capabilities: fn -> %{methods: [], specializations: []} end]},
        {Lang.Providers.Anthropic, [],
         [capabilities: fn -> %{methods: [], specializations: []} end]}
      ]) do
        assert Provider.method_supported?("unsupported.method") == false
      end
    end
  end

  describe "cheapest_provider/2" do
    test "returns cheapest provider that can handle method" do
      method = "test.method"

      with_mock Provider,
        select_provider: fn _method, _params, %{optimize_for: :cost} ->
          {:ok, :xai}
        end do
        assert Provider.cheapest_provider(method) == :xai
      end
    end

    test "returns nil when no provider available" do
      method = "unsupported.method"

      with_mock Provider,
        select_provider: fn _method, _params, %{optimize_for: :cost} ->
          {:error, :no_suitable_provider}
        end do
        assert Provider.cheapest_provider(method) == nil
      end
    end
  end

  describe "best_quality_provider/2" do
    test "returns highest quality provider that can handle method" do
      method = "test.method"

      with_mock Provider,
        select_provider: fn _method, _params, %{optimize_for: :quality} ->
          {:ok, :anthropic}
        end do
        assert Provider.best_quality_provider(method) == :anthropic
      end
    end
  end

  describe "fastest_provider/2" do
    test "returns fastest provider that can handle method" do
      method = "test.method"

      with_mock Provider,
        select_provider: fn _method, _params, %{optimize_for: :speed} ->
          {:ok, :xai}
        end do
        assert Provider.fastest_provider(method) == :xai
      end
    end
  end

  describe "default_provider/2" do
    test "selects balanced provider" do
      method = "test.method"

      with_mock Provider,
        select_provider: fn _method, _params, %{optimize_for: :balanced} ->
          {:ok, :openai}
        end do
        assert Provider.default_provider(method) == :openai
      end
    end

    test "falls back to heuristic selection when balanced selection fails" do
      method = "lang.think.security_scan"

      with_mock Provider,
        select_provider: fn _method, _params, %{optimize_for: :balanced} ->
          {:error, :no_suitable_provider}
        end do
        # Should fallback to anthropic for security methods
        assert Provider.default_provider(method) == :anthropic
      end
    end
  end

  describe "fallback_provider/1" do
    test "chooses anthropic for security methods" do
      assert Provider.fallback_provider("lang.think.security_scan") == :anthropic
      assert Provider.fallback_provider("lang.security.audit") == :anthropic
    end

    test "chooses anthropic for diagnostic methods" do
      assert Provider.fallback_provider("lang.think.diagnose") == :anthropic
      assert Provider.fallback_provider("lang.debug.analyze") == :anthropic
    end

    test "chooses anthropic for prediction methods" do
      assert Provider.fallback_provider("lang.think.predict_bugs") == :anthropic
      assert Provider.fallback_provider("lang.predict.failures") == :anthropic
    end

    test "chooses openai for generation methods" do
      assert Provider.fallback_provider("lang.generate.from_spec") == :openai
      assert Provider.fallback_provider("lang.generate.code") == :openai
    end

    test "chooses openai for explanation methods" do
      assert Provider.fallback_provider("lang.think.explain_intent") == :openai
      assert Provider.fallback_provider("lang.explain.code") == :openai
    end

    test "chooses xai for unknown methods" do
      assert Provider.fallback_provider("unknown.method") == :xai
      assert Provider.fallback_provider("random.task") == :xai
    end
  end

  describe "execute/3" do
    test "executes method with auto-selected provider" do
      method = "test.method"
      params = %{test: "data"}

      mock_module = fn ->
        %{handle_request: fn _method, _params, _opts -> {:ok, "success"} end}
      end

      with_mocks([
        {Provider, [],
         [
           default_provider: fn _method, _params -> :xai end,
           get_provider: fn :xai -> mock_module.() end
         ]}
      ]) do
        assert {:ok, "success"} = Provider.execute(method, params)
      end
    end

    test "executes with explicitly specified provider" do
      method = "test.method"
      params = %{test: "data"}
      opts = [provider: :openai]

      mock_module = fn ->
        %{handle_request: fn _method, _params, _opts -> {:ok, "openai_result"} end}
      end

      with_mock Provider, get_provider: fn :openai -> mock_module.() end do
        assert {:ok, "openai_result"} = Provider.execute(method, params, opts)
      end
    end

    test "returns error for unavailable provider" do
      method = "test.method"
      params = %{test: "data"}
      opts = [provider: :nonexistent]

      with_mock Provider, get_provider: fn :nonexistent -> nil end do
        assert {:error, "Provider nonexistent not available"} =
                 Provider.execute(method, params, opts)
      end
    end
  end

  describe "health_check_all/0" do
    test "checks health of all providers" do
      expected_result = %{
        timestamp: DateTime.utc_now(),
        providers: %{
          xai: {:ok, "healthy"},
          openai: {:ok, "healthy"},
          anthropic: {:error, "connection failed"}
        },
        healthy_count: 2,
        total_count: 3
      }

      with_mocks([
        {Lang.Providers.XAI, [], [health_check: fn -> {:ok, "healthy"} end]},
        {Lang.Providers.OpenAI, [], [health_check: fn -> {:ok, "healthy"} end]},
        {Lang.Providers.Anthropic, [], [health_check: fn -> {:error, "connection failed"} end]}
      ]) do
        result = Provider.health_check_all()

        assert result.healthy_count == 2
        assert result.total_count == 3
        assert Map.has_key?(result, :timestamp)
        assert Map.has_key?(result, :providers)
      end
    end
  end

  describe "estimate_costs/2" do
    test "returns cost estimates from all providers" do
      method = "test.method"
      params = %{content: "test content"}

      with_mocks([
        {Lang.Providers.XAI, [],
         [
           estimate_cost: fn _method, _params ->
             {:ok, %{estimated_tokens: 100, estimated_cost_usd: 0.002}}
           end
         ]},
        {Lang.Providers.OpenAI, [],
         [
           estimate_cost: fn _method, _params ->
             {:ok, %{estimated_tokens: 100, estimated_cost_usd: 0.02}}
           end
         ]},
        {Lang.Providers.Anthropic, [],
         [
           estimate_cost: fn _method, _params ->
             {:error, "estimation failed"}
           end
         ]}
      ]) do
        estimates = Provider.estimate_costs(method, params)

        assert estimates.xai.estimated_cost_usd == 0.002
        assert estimates.openai.estimated_cost_usd == 0.02
        assert estimates.anthropic.estimated_cost_usd == :unknown
      end
    end
  end

  describe "capability_matrix/0" do
    test "returns capability matrix for all providers" do
      matrix = Provider.capability_matrix()

      assert Map.has_key?(matrix, :xai)
      assert Map.has_key?(matrix, :openai)
      assert Map.has_key?(matrix, :anthropic)

      # Check structure of each provider's capabilities
      for {_provider, capabilities} <- matrix do
        assert Map.has_key?(capabilities, :best_for)
        assert Map.has_key?(capabilities, :avoid_for)
        assert Map.has_key?(capabilities, :specializes_in)

        assert is_list(capabilities.best_for)
        assert is_list(capabilities.avoid_for)
        assert is_list(capabilities.specializes_in)
      end
    end
  end

  describe "Provider behavior validation" do
    test "all configured providers implement required callbacks" do
      providers = Provider.available_providers()

      for {_name, module} <- providers do
        # Check that module implements Provider behavior
        assert function_exported?(module, :capabilities, 0)
        assert function_exported?(module, :pricing, 0)
        assert function_exported?(module, :handle_request, 3)
        assert function_exported?(module, :health_check, 0)
        assert function_exported?(module, :estimate_cost, 2)
      end
    end
  end
end
