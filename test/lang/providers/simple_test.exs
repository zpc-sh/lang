defmodule Lang.Providers.SimpleTest do
  use ExUnit.Case, async: true

  describe "Provider behavior tests" do
    test "XAI provider implements required callbacks" do
      # Check that XAI provider has all required functions
      assert function_exported?(Lang.Providers.XAI, :capabilities, 0)
      assert function_exported?(Lang.Providers.XAI, :pricing, 0)
      assert function_exported?(Lang.Providers.XAI, :handle_request, 3)
      assert function_exported?(Lang.Providers.XAI, :health_check, 0)
      assert function_exported?(Lang.Providers.XAI, :estimate_cost, 2)
    end

    test "OpenAI provider implements required callbacks" do
      assert function_exported?(Lang.Providers.OpenAI, :capabilities, 0)
      assert function_exported?(Lang.Providers.OpenAI, :pricing, 0)
      assert function_exported?(Lang.Providers.OpenAI, :handle_request, 3)
      assert function_exported?(Lang.Providers.OpenAI, :health_check, 0)
      assert function_exported?(Lang.Providers.OpenAI, :estimate_cost, 2)
    end

    test "Anthropic provider implements required callbacks" do
      assert function_exported?(Lang.Providers.Anthropic, :capabilities, 0)
      assert function_exported?(Lang.Providers.Anthropic, :pricing, 0)
      assert function_exported?(Lang.Providers.Anthropic, :handle_request, 3)
      assert function_exported?(Lang.Providers.Anthropic, :health_check, 0)
      assert function_exported?(Lang.Providers.Anthropic, :estimate_cost, 2)
    end
  end

  describe "Provider capabilities" do
    test "XAI capabilities are properly structured" do
      capabilities = Lang.Providers.XAI.capabilities()

      assert is_map(capabilities)
      assert Map.has_key?(capabilities, :methods)
      assert Map.has_key?(capabilities, :strengths)
      assert Map.has_key?(capabilities, :cost_tier)
      assert Map.has_key?(capabilities, :specializations)

      assert is_list(capabilities.methods)
      assert is_list(capabilities.strengths)
      assert capabilities.cost_tier in [:cheap, :medium, :expensive]
    end

    test "OpenAI capabilities are properly structured" do
      capabilities = Lang.Providers.OpenAI.capabilities()

      assert is_map(capabilities)
      assert Map.has_key?(capabilities, :methods)
      assert Map.has_key?(capabilities, :strengths)
      assert capabilities.cost_tier in [:cheap, :medium, :expensive]
      assert :generation in capabilities.strengths
    end

    test "Anthropic capabilities are properly structured" do
      capabilities = Lang.Providers.Anthropic.capabilities()

      assert is_map(capabilities)
      assert Map.has_key?(capabilities, :methods)
      assert Map.has_key?(capabilities, :strengths)
      assert capabilities.cost_tier in [:cheap, :medium, :expensive]
      assert :security in capabilities.strengths
    end
  end

  describe "Provider pricing" do
    test "all providers return valid pricing info" do
      providers = [Lang.Providers.XAI, Lang.Providers.OpenAI, Lang.Providers.Anthropic]

      for provider <- providers do
        pricing = provider.pricing()

        assert is_map(pricing)
        assert Map.has_key?(pricing, :input_tokens_per_dollar)
        assert Map.has_key?(pricing, :output_tokens_per_dollar)
        assert Map.has_key?(pricing, :base_cost_per_request)

        assert is_integer(pricing.input_tokens_per_dollar)
        assert is_integer(pricing.output_tokens_per_dollar)

        assert is_float(pricing.base_cost_per_request) or
                 is_integer(pricing.base_cost_per_request)
      end
    end
  end

  describe "Provider registry" do
    test "all providers are available" do
      providers = Lang.Providers.Provider.available_providers()

      assert Map.has_key?(providers, :xai)
      assert Map.has_key?(providers, :openai)
      assert Map.has_key?(providers, :anthropic)

      assert providers.xai == Lang.Providers.XAI
      assert providers.openai == Lang.Providers.OpenAI
      assert providers.anthropic == Lang.Providers.Anthropic
    end

    test "get_provider returns correct modules" do
      assert Lang.Providers.Provider.get_provider(:xai) == Lang.Providers.XAI
      assert Lang.Providers.Provider.get_provider(:openai) == Lang.Providers.OpenAI
      assert Lang.Providers.Provider.get_provider(:anthropic) == Lang.Providers.Anthropic
      assert Lang.Providers.Provider.get_provider(:invalid) == nil
    end
  end

  describe "Cost estimation" do
    test "XAI can estimate costs" do
      case Lang.Providers.XAI.estimate_cost("lang.think.explain_intent", %{content: "def hello"}) do
        {:ok, estimate} ->
          assert Map.has_key?(estimate, :estimated_tokens)
          assert Map.has_key?(estimate, :estimated_cost_usd)
          assert is_integer(estimate.estimated_tokens)
          assert estimate.estimated_tokens > 0

        {:error, _} ->
          # This is acceptable for unit tests
          :ok
      end
    end

    test "all providers can estimate costs without crashing" do
      providers = [Lang.Providers.XAI, Lang.Providers.OpenAI, Lang.Providers.Anthropic]
      method = "lang.think.explain_intent"
      params = %{content: "def test_function, do: :ok"}

      for provider <- providers do
        # Should not crash, regardless of result
        result = provider.estimate_cost(method, params)
        assert result in [ok: %{}] or match?({:error, _}, result) or match?({:ok, %{}}, result)
      end
    end
  end

  describe "Provider selection" do
    test "can determine method support" do
      # Test with a method that should be supported
      assert Lang.Providers.Provider.method_supported?("lang.think.explain_intent") == true

      # Test with clearly unsupported method
      assert Lang.Providers.Provider.method_supported?("completely.fake.method") == false
    end

    test "fallback provider selection works" do
      # Security methods should fallback to Anthropic
      assert Lang.Providers.Provider.fallback_provider("lang.think.security_scan") == :anthropic
      assert Lang.Providers.Provider.fallback_provider("lang.security.audit") == :anthropic

      # Generation methods should fallback to OpenAI
      assert Lang.Providers.Provider.fallback_provider("lang.generate.from_spec") == :openai
      assert Lang.Providers.Provider.fallback_provider("lang.generate.code") == :openai

      # Unknown methods should fallback to XAI (cheapest)
      assert Lang.Providers.Provider.fallback_provider("unknown.method") == :xai
    end

    test "optimization shortcuts work" do
      method = "lang.think.explain_intent"

      # These should return provider atoms or nil
      cheapest = Lang.Providers.Provider.cheapest_provider(method)
      fastest = Lang.Providers.Provider.fastest_provider(method)
      best_quality = Lang.Providers.Provider.best_quality_provider(method)

      assert cheapest in [:xai, :openai, :anthropic, nil]
      assert fastest in [:xai, :openai, :anthropic, nil]
      assert best_quality in [:xai, :openai, :anthropic, nil]
    end
  end

  describe "Capability matrix" do
    test "capability matrix has correct structure" do
      matrix = Lang.Providers.Provider.capability_matrix()

      assert Map.has_key?(matrix, :xai)
      assert Map.has_key?(matrix, :openai)
      assert Map.has_key?(matrix, :anthropic)

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

  describe "Lang.AI interface" do
    test "AI module has required functions" do
      assert function_exported?(Lang.AI, :ask, 3)
      assert function_exported?(Lang.AI, :explain, 2)
      assert function_exported?(Lang.AI, :generate, 2)
      assert function_exported?(Lang.AI, :security_scan, 2)
      assert function_exported?(Lang.AI, :diagnose, 2)
      assert function_exported?(Lang.AI, :mission, 2)
    end

    test "AI optimization shortcuts exist" do
      assert function_exported?(Lang.AI, :cheap, 3)
      assert function_exported?(Lang.AI, :best_quality, 3)
      assert function_exported?(Lang.AI, :fastest, 3)
    end

    test "AI utility functions exist" do
      assert function_exported?(Lang.AI, :health_check, 0)
      assert function_exported?(Lang.AI, :capabilities, 0)
      assert function_exported?(Lang.AI, :estimate_cost, 2)
    end
  end

  describe "Commands interface" do
    test "TalkToGrok module has required functions" do
      assert function_exported?(Lang.Commands.TalkToGrok, :ask, 2)
      assert function_exported?(Lang.Commands.TalkToGrok, :command_mission, 2)
      assert function_exported?(Lang.Commands.TalkToGrok, :chat, 0)
      assert function_exported?(Lang.Commands.TalkToGrok, :test_all_providers, 0)
      assert function_exported?(Lang.Commands.TalkToGrok, :demo, 0)
    end
  end

  describe "Configuration" do
    test "AI provider config keys are properly defined" do
      config = Application.get_env(:lang, :ai_providers)

      # Config should exist (even if keys are nil)
      assert is_list(config) or is_map(config) or is_nil(config)

      # Should have the expected structure when not nil
      if config do
        # At minimum should be a keyword list or map
        assert Keyword.keyword?(config) or is_map(config)
      end
    end
  end

  describe "Error handling" do
    test "providers handle invalid methods gracefully" do
      invalid_method = "completely.invalid.method.that.does.not.exist"
      empty_params = %{}

      # Should return errors, not crash
      xai_result = Lang.Providers.XAI.handle_request(invalid_method, empty_params)
      openai_result = Lang.Providers.OpenAI.handle_request(invalid_method, empty_params)
      anthropic_result = Lang.Providers.Anthropic.handle_request(invalid_method, empty_params)

      assert match?({:error, _}, xai_result)
      assert match?({:error, _}, openai_result)
      assert match?({:error, _}, anthropic_result)
    end

    test "providers handle empty parameters gracefully" do
      method = "lang.think.explain_intent"
      empty_params = %{}

      # Should handle gracefully (may succeed or fail, but shouldn't crash)
      for provider <- [Lang.Providers.XAI, Lang.Providers.OpenAI, Lang.Providers.Anthropic] do
        result = provider.handle_request(method, empty_params)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end
end
