# LANG Quick Start Guide

Get up and running with LANG's text intelligence platform in under 10 minutes.

## Installation

### Prerequisites
```bash
# Required
elixir >= 1.15
postgresql >= 12
node.js >= 18
```

### Setup
```bash
git clone https://github.com/your-org/lang.git
cd lang
mix deps.get
mix ecto.setup
mix phx.server
```

Visit http://localhost:4000

## First API Call

```bash
curl -X POST http://localhost:4000/api/v1/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "content": "function fibonacci(n) { return n <= 1 ? n : fibonacci(n-1) + fibonacci(n-2); }",
    "format": "javascript"
  }'
```

## Next Steps

- [Full API Documentation](API_DOCUMENTATION.md)
- [Conversation Rehearsal Guide](CONVERSATION_REHEARSAL.md)
- [Stylometric Analysis Guide](STYLOMETRIC_ANALYSIS.md)