# OpenCode Provider Setup and Configuration

OpenCode Agents is a self-hosted AI provider designed for cost-free development and testing. It provides realistic AI responses without external API calls, making it perfect for CI/CD pipelines, local development, and testing workflows.

## ✨ Features

- **Zero Cost**: No API keys or external costs required
- **Fast Response**: Optimized for development speed (100-500ms responses)
- **Full LSP Support**: Completion, hover, explain, refactor, generate tests
- **Realistic Simulation**: Quality scores and response patterns similar to real AI
- **Always Available**: No rate limits or downtime
- **Perfect for Testing**: Consistent, predictable responses for test automation

## 🚀 Quick Setup

### 1. Provider Registration

The OpenCode provider is automatically registered in the LANG system. No additional configuration required!

```elixir
# Already included in lib/lang/providers/provider.ex
@providers %{
  xai: Lang.Providers.XAI,
  openai: Lang.Providers.OpenAI,
  anthropic: Lang.Providers.Anthropic,
  opencode: Lang.Providers.OpenCode  # ← Self-hosted provider
}
```

### 2. Basic Usage

```elixir
# Direct provider usage
{:ok, result} = Lang.Providers.OpenCode.handle_request("completion", %{
  prefix: "def calculate_",
  language: "elixir",
  context: "# Financial calculations"
})

# Through the provider system
{:ok, result} = Lang.Providers.Provider.execute("completion",
  %{prefix: "def ", language: "elixir"},
  provider: :opencode
)

# Auto-selection (will prefer OpenCode for testing scenarios)
{:ok, result} = Lang.Providers.Router.route_request("completion", %{
  prefix: "test_",
  language: "elixir"
})
```

### 3. Health Check

```elixir
# Verify provider is working
case Lang.Providers.OpenCode.health_check() do
  {:ok, message} -> IO.puts("✅ #{message}")
  {:error, reason} -> IO.puts("❌ Error: #{reason}")
end
```

## 📋 Supported Methods

### LSP Methods
- `completion` - Code completion suggestions
- `hover` - Symbol information on hover
- `explain` - Code explanation and analysis
- `refactor` - Code refactoring suggestions
- `generate_tests` - Test generation

### Think Methods
- `lang.think.explain_intent` - Analyze code intent
- `lang.think.find_semantic` - Semantic code search
- `lang.think.security_analysis` - Security vulnerability analysis
- `lang.think.diagnose_issue` - Error diagnosis and fixes

### Generation Methods
- `lang.generate.code` - Generate code from descriptions
- `lang.generate.documentation` - Auto-generate documentation

### Query Methods
- `lang.query.simple` - Simple Q&A responses
- `lang.fs.explain_structure` - Project structure analysis

## 🎯 Configuration Options

### Provider Selection Priority

Update your application config to prioritize OpenCode for testing:

```elixir
# config/dev.exs
config :lang, :provider_preferences, %{
  testing: :opencode,
  development: :opencode,
  cost_optimization: :opencode
}

# For production, use real providers
# config/prod.exs
config :lang, :provider_preferences, %{
  quality_first: :anthropic,
  balanced: :openai,
  cost_first: :xai
}
```

### Response Timing Configuration

```elixir
# lib/lang/providers/opencode.ex - Customize timing
@base_delay_ms 100      # Minimum response time
@max_delay_ms 500       # Maximum response time
```

## 🧪 Testing Integration

### Unit Tests

```elixir
defmodule MyApp.AIIntegrationTest do
  use ExUnit.Case

  test "code completion works with OpenCode" do
    params = %{
      prefix: "def my_function(",
      language: "elixir",
      context: "# User management module"
    }

    {:ok, result} = Lang.Providers.Provider.execute(
      "completion",
      params,
      provider: :opencode
    )

    assert result.provider == "opencode"
    assert is_binary(result.completion)
    assert result.confidence > 0.0
  end

  test "cost estimation is always zero" do
    {:ok, estimate} = Lang.Providers.OpenCode.estimate_cost(
      "completion",
      %{code: "def test, do: :ok"}
    )

    assert estimate.estimated_cost_usd == 0.0
    assert estimate.estimated_tokens > 0
  end
end
```

### Integration with Existing Tests

```elixir
# Replace expensive API calls in tests
defmodule MyApp.TestHelpers do
  def with_test_provider(test_func) do
    original_provider = Application.get_env(:lang, :default_provider)

    try do
      Application.put_env(:lang, :default_provider, :opencode)
      test_func.()
    after
      Application.put_env(:lang, :default_provider, original_provider)
    end
  end
end

# Usage in tests
test "expensive AI workflow" do
  TestHelpers.with_test_provider(fn ->
    # Your AI-dependent test here
    # Will use OpenCode instead of real APIs
  end)
end
```

### CI/CD Configuration

```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Install dependencies
        run: mix deps.get

      - name: Run tests with OpenCode provider
        run: |
          export LANG_DEFAULT_PROVIDER=opencode
          mix test
        # No API keys needed! Tests run without external costs
```

## 🔧 Development Workflow

### Local Development Setup

```bash
# 1. Clone and setup
git clone <your-lang-project>
cd lang
mix setup

# 2. Test OpenCode provider
mix run -e "
{:ok, result} = Lang.Providers.OpenCode.handle_request(\"completion\", %{
  prefix: \"def hello_\",
  language: \"elixir\"
})
IO.inspect(result)
"

# 3. Run with OpenCode as default
LANG_DEFAULT_PROVIDER=opencode mix phx.server
```

### Debugging and Development

```elixir
# Enable detailed logging for OpenCode
Logger.configure(level: :debug)

# Trace provider selection
{:ok, provider} = Lang.Providers.Provider.select_provider(
  "completion",
  %{language: "elixir"},
  %{optimize_for: :cost}
)
IO.puts("Selected provider: #{provider}")

# Benchmark response times
:timer.tc(fn ->
  Lang.Providers.OpenCode.handle_request("completion", %{prefix: "def "})
end)
```

## 📊 Metrics and Analytics

### Generate Test Data with OpenCode

```elixir
# Update generate_massive_metrics.exs to use OpenCode
defp select_provider_for_method(method) do
  # Use OpenCode 50% of the time for cost-free testing
  if :rand.uniform() < 0.5 do
    "opencode"
  else
    case method do
      :completion -> Enum.random(["xai", "openai", "anthropic"])
      # ... other methods
    end
  end
end
```

### Performance Comparison

```elixir
defmodule ProviderBenchmark do
  def compare_providers do
    methods = ["completion", "hover", "explain"]
    providers = [:opencode, :xai, :openai, :anthropic]

    results = for method <- methods, provider <- providers do
      case provider do
        :opencode ->
          # Always available, no API key needed
          time_provider_request(provider, method)
        _ ->
          # Skip if API key not configured
          if provider_available?(provider) do
            time_provider_request(provider, method)
          else
            {provider, method, :not_configured}
          end
      end
    end

    IO.inspect(results, label: "Provider Performance Comparison")
  end
end
```

## 🚦 Production Considerations

### When to Use OpenCode

✅ **Perfect for:**
- Unit and integration testing
- Local development
- CI/CD pipelines
- Prototyping and demos
- Cost-sensitive development
- Offline development

❌ **Not recommended for:**
- Production user-facing features
- High-quality code generation needs
- Complex reasoning tasks
- Critical security analysis

### Migration Strategy

```elixir
# Gradual migration approach
defmodule MyApp.AIService do
  def get_completion(params, opts \\ []) do
    provider = case Mix.env() do
      :test -> :opencode        # Tests always use OpenCode
      :dev -> opts[:provider] || :opencode    # Dev defaults to OpenCode
      :prod -> select_best_provider(params)   # Production uses real AI
    end

    Lang.Providers.Provider.execute("completion", params, provider: provider)
  end

  defp select_best_provider(params) do
    # Your production provider selection logic
    Lang.Providers.Provider.default_provider("completion", params)
  end
end
```

## 🔍 Troubleshooting

### Common Issues

**Provider not found:**
```elixir
# Ensure OpenCode is registered
providers = Lang.Providers.Provider.available_providers()
assert Map.has_key?(providers, :opencode)
```

**Responses seem too fast:**
```elixir
# OpenCode simulates processing time (100-500ms)
# If you need longer delays, update @base_delay_ms and @max_delay_ms
```

**Quality too low for tests:**
```elixir
# OpenCode provides basic quality for consistency
# For higher quality in specific tests, use real providers:
{:ok, result} = Lang.Providers.Provider.execute(
  "explain",
  params,
  provider: :anthropic  # Use real provider when needed
)
```

### Health Diagnostics

```elixir
# Full provider health check
health_status = Lang.Providers.Provider.health_check_all()
IO.inspect(health_status)

# OpenCode-specific diagnostics
defmodule OpenCodeDiagnostics do
  def run_diagnostics do
    tests = [
      {"Capabilities", fn -> Lang.Providers.OpenCode.capabilities() end},
      {"Availability", fn -> Lang.Providers.OpenCode.available?() end},
      {"Health Check", fn -> Lang.Providers.OpenCode.health_check() end},
      {"Basic Completion", fn ->
        Lang.Providers.OpenCode.handle_request("completion", %{prefix: "test"})
      end}
    ]

    Enum.each(tests, fn {name, test} ->
      case test.() do
        {:ok, _} -> IO.puts("✅ #{name}: PASS")
        result when is_map(result) -> IO.puts("✅ #{name}: PASS")
        true -> IO.puts("✅ #{name}: PASS")
        error -> IO.puts("❌ #{name}: FAIL - #{inspect(error)}")
      end
    end)
  end
end

OpenCodeDiagnostics.run_diagnostics()
```

## 📚 Next Steps

1. **Try the test script**: `mix run test_opencode_provider.exs`
2. **Update your tests** to use OpenCode for cost-free testing
3. **Configure CI/CD** to use OpenCode by default
4. **Set up development environment** with OpenCode as default provider
5. **Benchmark performance** compared to real providers
6. **Gradually migrate** testing workflows to OpenCode

## 🤝 Contributing

To improve OpenCode provider:

1. Add new method handlers in `lib/lang/providers/opencode.ex`
2. Enhance response realism in generator functions
3. Add language-specific completions
4. Improve test coverage in `test/lang/providers/opencode_test.exs`

---

**OpenCode Agents: Unlimited AI testing without the unlimited bills! 🚀💰**
