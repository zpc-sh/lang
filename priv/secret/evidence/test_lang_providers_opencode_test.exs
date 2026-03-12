@@ SNAPSHOT of test/lang/providers/opencode_test.exs @@
defmodule Lang.Providers.OpenCodeTest do
  use ExUnit.Case, async: true

  alias Lang.Providers.OpenCode

  describe "provider behavior" do
    test "implements capabilities/0" do
      capabilities = OpenCode.capabilities()

      assert is_map(capabilities)
      assert is_list(capabilities.methods)
      assert "completion" in capabilities.methods
      assert "hover" in capabilities.methods
      assert "explain" in capabilities.methods
      assert capabilities.cost_tier == :cheap
      assert capabilities.speed_tier == :fast
      assert capabilities.quality_tier == :basic
    end

    test "implements pricing/0" do
      pricing = OpenCode.pricing()

      assert is_map(pricing)
      assert pricing.input_tokens_per_dollar == 1_000_000
      assert pricing.output_tokens_per_dollar == 1_000_000
      assert pricing.base_cost_per_request == 0.0
    end

    test "is always available" do
      assert OpenCode.available?() == true
    end

    test "health check returns ok" do
      assert {:ok, message} = OpenCode.health_check()
      assert is_binary(message)
      assert String.contains?(message, "OpenCode Agents running locally")
    end

    test "estimate_cost always returns zero cost" do
      params = %{code: "def hello, do: :world", language: "elixir"}

      assert {:ok, estimate} = OpenCode.estimate_cost("completion", params)
      assert estimate.estimated_cost_usd == 0.0
      assert is_integer(estimate.estimated_tokens)
      assert estimate.estimated_tokens > 0
    end
  end

  describe "LSP method handlers" do
    test "handles completion requests" do
      params = %{
        prefix: "def ",
        language: "elixir",
        context: "# Context here"
      }

      assert {:ok, result} = OpenCode.handle_request("completion", params)

      assert is_binary(result.completion)
      assert result.provider == "opencode"
      assert result.model == "opencode-dev"
      assert is_float(result.confidence)
      assert result.confidence > 0.0 and result.confidence <= 1.0
      assert result.metadata.language == "elixir"
    end

    test "handles hover requests" do
      params = %{
        symbol: "process_data",
        language: "elixir",
        context: "def process_data(input), do: input"
      }

      assert {:ok, result} = OpenCode.handle_request("hover", params)

      assert is_binary(result.hover_content)
      assert String.contains?(result.hover_content, "process_data")
      assert String.contains?(result.hover_content, "elixir")
      assert result.provider == "opencode"
      assert is_float(result.confidence)
    end
  end
end
