# LANG Cost Calculation System

A comprehensive cost tracking and optimization system for the LANG Universal Text Intelligence Platform, inspired by ExLLM's cost calculation patterns and designed for seamless integration with the LSP chatroom at localhost:4001.

## Overview

This system provides real-time cost tracking, provider optimization, and budget monitoring for all AI operations within LANG, with special focus on the LSP chatroom experience. It includes sophisticated batch processing, caching strategies, and intelligent provider selection.

## 🚀 Key Features

### Real-Time Cost Tracking
- **Live Cost Updates**: Real-time cost feedback during chat sessions
- **Token-Level Precision**: Accurate input/output token counting and pricing
- **Multi-Provider Support**: OpenAI, Anthropic, Gemini, xAI, Qwen, Codex, Ollama
- **Session Aggregation**: Cumulative cost tracking across conversations

### Intelligent Provider Selection
- **Cost Optimization**: Automatic selection of cheapest viable option
- **Quality Optimization**: Smart routing to highest quality models
- **Speed Optimization**: Fast response time prioritization
- **Local Model Support**: Integration with nearby Qwen and Codex instances

### Advanced Batch Processing
- **Concurrent Processing**: Configurable concurrency limits for bulk operations
- **Cache-First Strategy**: Intelligent caching to reduce redundant requests
- **Failure Resilience**: Retry logic with exponential backoff
- **Progress Tracking**: Real-time progress updates with cost monitoring

### LSP Integration
- **Chatroom Integration**: Direct integration with LSP server at localhost:4001
- **Real-Time Updates**: Live cost notifications to LSP clients
- **Budget Monitoring**: Proactive alerts when approaching cost limits
- **Session Persistence**: Cost state maintained across LSP sessions

## 📁 System Architecture

```
lang/lib/lang/
├── tokens/
│   ├── cost.ex                 # Core cost calculation engine
│   ├── cost_session.ex         # Session-level cost tracking
│   └── types.ex               # Type definitions (updated)
├── conversation/
│   ├── chat_builder.ex         # Fluent chat API with cost tracking
│   └── batch_processor.ex     # Advanced batch processing
└── lsp/
    └── chat_cost_integration.ex # LSP chatroom integration
```

## 🔧 Core Components

### 1. Lang.Tokens.Cost

Main cost calculation engine with comprehensive provider support.

```elixir
# Basic cost calculation
{:ok, cost} = Lang.Tokens.Cost.calculate(:openai, "gpt-4o", %{
  input_tokens: 1000,
  output_tokens: 500
})

# Provider comparison
costs = Lang.Tokens.Cost.compare_providers(token_usage, [
  {:openai, "gpt-4o-mini"},
  {:anthropic, "claude-3-5-haiku-20241022"},
  {:ollama, "llama3.1:8b"}
])

# Cost formatting
formatted = Lang.Tokens.Cost.format_cost(0.0045)  # "$0.0045"
```

### 2. Lang.Tokens.CostSession

Session-level cost tracking with comprehensive analytics.

```elixir
# Start session
session = Lang.Tokens.CostSession.new("lsp_chat_123", %{
  budget_limit: 5.00
})

# Add message costs
session = Lang.Tokens.CostSession.add_message_cost(session, cost_data)

# Get formatted summary for LSP
display = Lang.Tokens.CostSession.format_for_lsp(session, style: :detailed)
```

### 3. Lang.Conversation.ChatBuilder

Fluent API for cost-aware chat operations.

```elixir
{:ok, response} =
  Lang.Conversation.ChatBuilder.new()
  |> ChatBuilder.with_messages(messages)
  |> ChatBuilder.with_cost_tracking(limit: 0.50)
  |> ChatBuilder.with_auto_provider_selection(:cost_optimized)
  |> ChatBuilder.with_lsp_integration()
  |> ChatBuilder.execute()
```

### 4. Lang.Conversation.BatchProcessor

High-throughput batch processing with cost optimization.

```elixir
{:ok, results} = Lang.Conversation.BatchProcessor.process(requests, %{
  concurrency: 10,
  cost_limit: 5.00,
  cache_enabled: true,
  progress_callback: fn progress ->
    IO.puts("Progress: #{progress.completed}/#{progress.total}")
  end
})
```

### 5. Lang.LSP.ChatCostIntegration

LSP chatroom integration with real-time cost feedback.

Handles LSP methods:
- `lang.chat.send_with_cost_tracking`
- `lang.chat.get_session_cost_summary`
- `lang.chat.set_budget_limit`
- `lang.chat.optimize_provider_selection`
- `lang.chat.batch_process_requests`

## 🎯 Supported Providers & Models

### Cloud Providers
- **OpenAI**: gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-3.5-turbo, o1-preview
- **Anthropic**: claude-3-5-sonnet, claude-3-5-haiku, claude-3-opus
- **Google**: gemini-1.5-pro, gemini-1.5-flash, gemini-1.0-pro
- **xAI**: grok-beta

### Local & Cost-Effective Options
- **Qwen**: qwen2.5-72b-instruct, qwen2.5-7b-instruct, qwen-turbo
- **Codex**: code-davinci-002, github-copilot (subscription-based)
- **Ollama**: llama3.1:8b, codestral:22b, mixtral:8x7b (free local models)

## 💻 LSP Client Usage

### JavaScript/TypeScript LSP Client

```typescript
// Send cost-tracked message
const response = await client.sendRequest('lang.chat.send_with_cost_tracking', {
  message: 'Explain machine learning',
  session_id: 'chat_123',
  cost_options: {
    limit: 0.50,
    real_time_updates: true,
    provider_optimization: 'cost_optimized'
  }
});

// Get session cost summary
const summary = await client.sendRequest('lang.chat.get_session_cost_summary', {
  session_id: 'chat_123',
  format: 'detailed'
});

// Set budget limit
await client.sendRequest('lang.chat.set_budget_limit', {
  session_id: 'chat_123',
  budget_limit: 2.00,
  alert_threshold: 0.8
});

// Batch process requests
const batchResult = await client.sendRequest('lang.chat.batch_process_requests', {
  requests: [
    { messages: [{content: 'What is AI?'}], provider: 'openai', model: 'gpt-4o-mini' },
    { messages: [{content: 'Explain neural networks'}], provider: 'anthropic', model: 'claude-3-5-haiku' }
  ],
  options: {
    concurrency: 5,
    cost_limit: 1.00
  }
});
```

### Real-Time Cost Notifications

```typescript
// Listen for cost updates
client.onNotification('lang/cost_update', (update) => {
  console.log(`Current message cost: ${update.current_message_cost}`);
  console.log(`Session total: ${update.session_total_cost}`);
  console.log(`Token usage: ${update.token_usage.total_tokens} tokens`);
});

// Listen for batch progress
client.onNotification('lang/batch_progress', (progress) => {
  console.log(`Batch progress: ${progress.completed}/${progress.total}`);
  console.log(`Total cost so far: ${progress.total_cost}`);
});
```

## 🔍 Cost Optimization Strategies

### 1. Provider Selection Strategies
- **`cost_optimized`**: Always choose cheapest option
- **`quality_optimized`**: Prefer GPT-4, Claude Sonnet for complex tasks
- **`speed_optimized`**: Prioritize fast response times
- **`local_preferred`**: Use local models when possible
- **`balanced`**: Balance cost, quality, and speed

### 2. Caching Strategies
- **Content-based caching**: Hash-based deduplication
- **TTL-based expiration**: Configurable time-to-live
- **Storage backends**: Redis for speed, S3 for persistence
- **Cache hit optimization**: Intelligent cache warming

### 3. Batch Processing Optimization
- **Intelligent grouping**: Group by provider/model for efficiency
- **Adaptive concurrency**: Adjust based on provider performance
- **Cost-aware batching**: Prioritize cheaper requests first
- **Failure isolation**: Prevent single failures from blocking batches

## 🏗️ Integration with LANG Architecture

### Ash Framework Integration
```elixir
# Cost tracking is integrated with existing Ash resources
# Session costs are automatically tracked in user billing
case Lang.Billing.can_make_request?(organization_id) do
  {:ok, :allowed} ->
    # Process with cost tracking
    Lang.Events.track_event(%{
      event_type: "ai_request_with_cost",
      cost: cost_data.total_cost,
      user_id: user.id
    })
end
```

### Oban Background Jobs
```elixir
# Batch processing leverages Oban for background work
%{requests: large_request_batch}
|> Lang.Workers.BatchCostProcessor.new(queue: :analysis, priority: 1)
|> Oban.insert()
```

### Native Performance Integration
```elixir
# Cost calculations leverage existing native NIFs for performance
# Token estimation uses optimized native functions
tokens = Lang.Native.FSScanner.estimate_tokens_for_content(content)
```

## 📊 Cost Monitoring & Analytics

### Session Analytics
- Total session cost and token usage
- Provider/model breakdown with efficiency metrics
- Cost trends over time
- Budget utilization tracking

### Performance Metrics
- Average cost per message/token
- Cache hit rates and savings
- Batch processing efficiency
- Provider response time vs cost correlation

### Budget Management
- Proactive budget alerts at 80% utilization
- Hard limits to prevent overruns
- Usage recommendations for cost optimization
- Historical spend analysis

## 🚨 Cost Alerts & Notifications

### Alert Types
- **Budget Exceeded**: When session/user exceeds set limits
- **High Cost Warning**: When single operation is unusually expensive
- **Efficiency Warning**: When cost efficiency drops below thresholds
- **Provider Recommendation**: Suggesting more cost-effective alternatives

### LSP Integration
Real-time alerts are sent directly to LSP clients as notifications:

```json
{
  "method": "lang/cost_alert",
  "params": {
    "type": "budget_exceeded",
    "message": "🚨 Budget exceeded! Current: $1.25, Budget: $1.00",
    "session_id": "chat_123",
    "current_cost": 1.25,
    "budget_limit": 1.00
  }
}
```

## 🔄 Caching & Storage Integration

### Redis Integration
```elixir
# Fast caching for frequent requests
Lang.Tokens.Cost.calculate_with_cache(:openai, "gpt-4o-mini", token_usage)
```

### S3 Storage Backend
When you need S3 integration for large-scale caching:
```elixir
ChatBuilder.new()
|> ChatBuilder.with_cache(
  storage_backend: :s3,
  ttl: :infinity,  # Long-term caching
  bucket: "lang-cost-cache"
)
```

**Note**: The system is ready for S3 integration - let us know when you need the storage service connected.

## 🧪 Testing & Demo

Run the comprehensive demo to see all features:

```bash
cd lang
elixir demo_cost_system.exs
```

This demonstrates:
- ✅ Basic cost calculation across providers
- ✅ Provider comparison and optimization
- ✅ Session-level cost tracking simulation
- ✅ Batch processing with concurrency
- ✅ Cost optimization recommendations

## 🚀 Getting Started

1. **LSP Server**: Ensure LANG LSP server is running on localhost:4001
2. **Cost Tracking**: Enable cost tracking in your chat requests
3. **Provider Config**: Configure your preferred providers and API keys
4. **Budget Limits**: Set appropriate budget limits for cost control
5. **Caching**: Enable caching for repeated queries

### Quick Start Example

```elixir
# In your LSP client or IEx session
{:ok, response} =
  Lang.Conversation.ChatBuilder.new()
  |> ChatBuilder.with_messages([
    %{role: "user", content: "Hello, LANG!"}
  ])
  |> ChatBuilder.with_session_id("my_chat")
  |> ChatBuilder.with_cost_tracking(limit: 1.00)
  |> ChatBuilder.with_auto_provider_selection(:cost_optimized)
  |> ChatBuilder.with_lsp_integration(port: 4001)
  |> ChatBuilder.execute()

# Response includes full cost breakdown
IO.inspect(response.cost)
```

## 🔮 Future Enhancements

- **Machine Learning Cost Prediction**: Predict costs based on query complexity
- **Dynamic Pricing Updates**: Real-time provider pricing updates
- **Advanced Analytics Dashboard**: Web UI for cost analysis
- **Team/Organization Budgets**: Multi-user budget management
- **Cost Optimization ML**: AI-powered provider selection optimization

---

**Ready to bring intelligent cost management to your LANG LSP chatroom!** 🎉

For questions or support, check the existing LANG documentation or create an issue in the repository.
