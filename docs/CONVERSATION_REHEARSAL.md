# Conversation Rehearsal Engine

Master any conversation scenario with LANG's intelligent rehearsal system featuring branching dialogue trees and predictive analytics.

## Overview

The Conversation Rehearsal Engine allows you to practice and optimize communication scenarios through:

- **Branching Conversations**: Explore different response paths and outcomes
- **Predictive Analytics**: See success probabilities for each response option
- **Performance Tracking**: Monitor improvement over time with detailed metrics
- **Scenario-Based Training**: Specialized training for interviews, sales, support, and negotiations

## Supported Scenarios

### Job Interviews
Practice behavioral questions, technical discussions, and salary negotiations.

```elixir
{:ok, session} = Lang.Conversation.RehearsalEngine.start_session(
  "job_interview",
  ["candidate", "interviewer"]
)
```

### Sales Conversations
Optimize discovery questions, handle objections, and improve closing techniques.

### Customer Support
Train empathetic responses and technical troubleshooting flows.

### Negotiations
Develop win-win strategies and practice boundary setting.

## API Usage

### Starting a Session

```bash
curl -X POST http://localhost:4000/api/conversation/start \
  -H "Content-Type: application/json" \
  -d '{
    "scenario": "job_interview",
    "participants": ["candidate", "interviewer"],
    "context": {
      "position": "Senior Software Engineer",
      "focus_areas": ["technical_skills", "culture_fit"]
    }
  }'
```

### Adding Turns

```bash
curl -X POST http://localhost:4000/api/conversation/{session_id}/turn \
  -d '{
    "speaker": "interviewer",
    "message": "Tell me about your experience with distributed systems."
  }'
```

Response includes intelligent branches with predicted outcomes:

```json
{
  "branches": [
    {
      "id": "confident_approach",
      "response_text": "I have extensive experience building scalable distributed systems...",
      "predicted_outcome": {
        "success_probability": 0.85,
        "engagement_level": 0.90
      }
    }
  ]
}
```

### Performance Analytics

```bash
curl http://localhost:4000/api/conversation/{session_id}/analysis
```

Get comprehensive analysis including:
- Communication effectiveness scores
- Sentiment progression
- Personalized recommendations
- Branching pattern analysis

## Best Practices

1. **Start with Clear Context**: Provide specific scenario details for better branch generation
2. **Explore Multiple Paths**: Use branching to practice different approaches
3. **Review Analytics**: Study performance metrics to identify improvement areas
4. **Practice Regularly**: Consistent rehearsal improves real-world performance

## Integration Examples

### Elixir

```elixir
# Start intensive interview preparation
{:ok, session} = Lang.Conversation.RehearsalEngine.start_session(
  "job_interview",
  ["candidate", "interviewer"]
)

# Simulate challenging question
{:ok, node} = Lang.Conversation.RehearsalEngine.add_conversation_turn(
  session.id,
  %{
    "speaker" => "interviewer",
    "message" => "Describe a time you failed at something important.",
    "metadata" => %{"difficulty" => "high", "category" => "behavioral"}
  }
)

# Analyze response options
Enum.each(node.branches, fn branch ->
  IO.puts("#{branch.strategy}: #{branch.predicted_outcome.success_probability}")
end)
```

### JavaScript/Node.js

```javascript
const lang = require('lang-client');

async function practiceNegotiation() {
  const session = await lang.conversation.start({
    scenario: 'negotiation',
    participants: ['buyer', 'seller']
  });
  
  const turn = await session.addTurn({
    speaker: 'buyer',
    message: 'Your asking price is too high. What\'s the lowest you\'ll go?'
  });
  
  // Analyze response strategies
  turn.branches.forEach(branch => {
    console.log(`${branch.strategy}: ${branch.predicted_outcome.success_probability * 100}% success`);
  });
}
```

## Advanced Features

### Custom Scenarios

Create domain-specific rehearsal scenarios:

```elixir
defmodule MyApp.CustomScenarios do
  def medical_consultation_branches(message) do
    [
      %{
        id: "empathetic_inquiry",
        response_text: "I understand your concern. Can you tell me more about when this started?",
        strategy: "patient_centered_communication",
        predicted_outcome: %{
          trust_building: 0.90,
          information_gathering: 0.85
        }
      }
    ]
  end
end
```

### Performance Tracking

Monitor improvement over time:

```elixir
# Get historical performance
{:ok, sessions} = Lang.Conversation.RehearsalEngine.list_sessions(%{
  "scenario" => "sales_call",
  "date_from" => "2024-01-01"
})

# Calculate improvement metrics
performance_trend = sessions
|> Enum.map(fn session ->
  {:ok, analysis} = Lang.Conversation.RehearsalEngine.get_conversation_analysis(session.id)
  analysis.effectiveness_scores.communication_clarity
end)
|> calculate_trend()
```