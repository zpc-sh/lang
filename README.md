<div align="center">
  <img src="priv/static/images/lang_logo.svg" alt="LANG Logo" width="600">
  <h1>LANG - Universal Text Intelligence Platform</h1>
</div>

LANG extends Language Server Protocol (LSP) and Tree-sitter parsing beyond code to provide semantic understanding, intelligent completions, and analysis for ANY structured content format.

## 🚀 Features

### Universal Text Intelligence
- **Multi-Format Analysis** - Support for 20+ text formats including code, documentation, data, and communication formats
- **Intelligent Completions** - Context-aware suggestions for any text format
- **Real-time Diagnostics** - Quality analysis and improvement suggestions
- **Semantic Understanding** - Deep content analysis beyond syntax

### Conversation Rehearsal Engine
- **Scenario-Based Practice** - Job interviews, sales calls, negotiations, presentations
- **Branching Conversations** - Explore different response paths and outcomes
- **Performance Analytics** - Track improvement over time with detailed metrics
- **AI-Powered Feedback** - Get strategic recommendations for better outcomes

### Stylometric Analysis
- **Writing Fingerprinting** - Identify unique writing patterns and styles
- **Authorship Attribution** - Compare writing samples for similarity analysis
- **Style Obfuscation** - Modify writing patterns while preserving meaning
- **Privacy Protection** - Advanced techniques to anonymize writing style

### Time Machine
- **Content Evolution** - Track how documents change over time
- **Branching Timelines** - Create alternate versions and merge changes
- **Temporal Navigation** - Jump between any point in content history
- **Snapshot Management** - Save and restore content states

### Language Server Protocol
- **Universal LSP** - Works with any editor supporting LSP
- **Real-time Analysis** - Instant feedback as you type
- **Cross-Format Support** - Seamless experience across all supported formats
- **Extensible Architecture** - Easy to add new formats and capabilities

## 🛠️ Quick Start

### Prerequisites

- Elixir 1.15+
- PostgreSQL 12+
- Node.js 18+ (for assets)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd lang

# Install dependencies and setup database
mix setup

# Start the platform
mix phx.server
```

Visit `http://localhost:4000` to access the web interface.

### LSP Server

Connect your editor to the LANG LSP server on `localhost:4001`:

**VS Code** - Add to settings.json:
```json
{
  "lang.server.host": "127.0.0.1",
  "lang.server.port": 4001
}
```

**Neovim** - Add to your LSP config:
```lua
require'lspconfig'.lang.setup{
  cmd = {"nc", "127.0.0.1", "4001"}
}
```

## 📖 Usage Examples

### Text Analysis API

```bash
# Analyze a markdown document
curl -X POST http://localhost:4000/api/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "content": "# Project Overview\n\nThis document outlines...",
    "format": "markdown",
    "options": {
      "include_suggestions": true,
      "complexity_analysis": true
    }
  }'
```

Response:
```json
{
  "status": "success",
  "data": {
    "format": "markdown",
    "content_size": 1247,
    "analysis": {
      "complexity_score": 6.2,
      "readability_score": 8.1,
      "structure_quality": 9.0,
      "suggestions": [
        "Consider adding more headers to improve structure"
      ]
    },
    "completions": [...],
    "diagnostics": [...]
  }
}
```

### Conversation Rehearsal

```bash
# Start a job interview rehearsal
curl -X POST http://localhost:4000/api/conversation/start \
  -H "Content-Type: application/json" \
  -d '{
    "scenario": "job_interview",
    "participants": ["candidate", "interviewer"]
  }'

# Add a conversation turn
curl -X POST http://localhost:4000/api/conversation/{session_id}/turn \
  -H "Content-Type: application/json" \
  -d '{
    "speaker": "interviewer",
    "message": "Tell me about your experience with distributed systems.",
    "metadata": {}
  }'
```

### Stylometric Analysis

```elixir
# Analyze writing style
{:ok, analysis} = Lang.analyze_writing_style("""
  I believe that artificial intelligence represents one of the most 
  significant technological advances of our time. The implications 
  extend far beyond mere computational efficiency.
""")

IO.inspect(analysis.fingerprint)
# => %{hash: "A1B2C3...", vector: [0.75, 0.82, ...]}

# Compare two writing samples  
{:ok, comparison} = Lang.Stylometrics.AnalysisEngine.compare_writing_styles(
  sample1, sample2
)

IO.puts("Similarity: #{comparison.similarity_score}")
IO.puts("Same author: #{comparison.likely_same_author}")
```

### Time Machine

```elixir
# Create a timeline for document evolution
{:ok, timeline} = Lang.create_timeline("doc_123", initial_content)

# Add states as document evolves
{:ok, state1} = Lang.TimeMachine.Core.add_state(timeline.id, revised_content)
{:ok, state2} = Lang.TimeMachine.Core.add_state(timeline.id, final_content)

# Navigate to previous state
{:ok, previous} = Lang.TimeMachine.Core.navigate_to_state(timeline.id, state1.id)

# Create a branch for alternate version
{:ok, branch} = Lang.TimeMachine.Core.create_branch(timeline.id, state1.id, "alternate_version")
```

## 🔧 Configuration

Key configuration options in `config/config.exs`:

```elixir
config :lang, :text_intelligence,
  default_analysis_timeout: 30_000,
  max_document_size_mb: 50,
  supported_formats: ["markdown", "javascript", "python", ...]

config :lang, :lsp,
  port: 4001,
  host: "127.0.0.1", 
  max_connections: 1000

config :lang, :conversation_rehearsal,
  max_session_duration_hours: 2,
  max_conversation_turns: 1000

config :lang, :stylometrics,
  confidence_threshold: 0.7,
  obfuscation_intensity_default: 0.5

config :lang, :timemachine,
  max_states_per_timeline: 10000,
  cleanup_interval_minutes: 30
```

## 🧪 Development

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/lang/text_intelligence/analysis_engine_test.exs

# Run tests with coverage
mix test --cover
```

### Code Quality

```bash
# Format code
mix format

# Run linter
mix credo

# Run static analysis
mix dialyzer

# Pre-commit checks
mix precommit
```

### Adding New Format Support

1. **Register the format** in `ParserRegistry`:
```elixir
"newformat" => %{
  parser: :builtin_newformat, 
  domain: "specialized"
}
```

2. **Implement the parser** in `AnalysisEngine`:
```elixir
defp parse_newformat(content) do
  # Your parsing logic here
  {:ok, %{type: :newformat, ...}}
end
```

3. **Add LSP completions** in `LSP.Server`:
```elixir
defp generate_newformat_completions(_document, _position) do
  # Format-specific completions
end
```

## 🏗️ Architecture

### Core Components

- **ParserRegistry** - Central registry for all supported formats
- **AnalysisEngine** - Core text analysis and intelligence
- **RehearsalEngine** - Conversation practice and branching
- **LSP.Server** - Language Server Protocol implementation
- **TimeMachine.StateManager** - Temporal content management
- **Stylometrics.AnalysisEngine** - Writing style analysis
- **Security.RateLimiter** - API protection and throttling

### Data Flow

```
Editor/Client → LSP Server → Analysis Engine → Parser Registry
                     ↓              ↓              ↓
              Real-time        Intelligence    Format-specific
              Feedback         Generation       Processing
```

### Supported Formats

| Category | Formats | Parser Type |
|----------|---------|-------------|
| **Code** | JavaScript, Python, Elixir, TypeScript, Rust, Go | Builtin |
| **Docs** | Markdown, Text, RST, AsciiDoc | Builtin |
| **Data** | JSON, YAML, TOML, XML, CSV | Builtin |
| **Comm** | Conversation, Email, Chat | Composite |
| **Other** | Log files, SQL, RegEx | Specialized |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes and add tests
4. Run the test suite: `mix precommit`
5. Commit your changes: `git commit -m 'Add amazing feature'`
6. Push to the branch: `git push origin feature/amazing-feature`
7. Open a Pull Request

### Development Setup

```bash
# Install development dependencies
mix deps.get

# Setup database
mix ecto.setup

# Install git hooks
mix git_hooks.install

# Start development server with live reload
mix phx.server
```

## 📚 Documentation

- [API Reference](docs/api.md)
- [LSP Protocol Guide](docs/lsp.md)  
- [Format Support Guide](docs/formats.md)
- [Conversation Rehearsal](docs/rehearsal.md)
- [Stylometric Analysis](docs/stylometrics.md)
- [Time Machine](docs/timemachine.md)
- [Deployment Guide](docs/deployment.md)

## 🔒 Security

LANG includes comprehensive security features:

- **Rate Limiting** - Configurable limits per operation and user
- **Content Validation** - Input sanitization and size limits  
- **Privacy Protection** - Style obfuscation for anonymity
- **Audit Logging** - Complete activity tracking

Report security issues to: security@lang-platform.dev

## 📊 Performance

### Benchmarks

| Operation | Documents/sec | Latency (p99) |
|-----------|---------------|---------------|
| Text Analysis | 500 | 45ms |
| LSP Completion | 1000 | 15ms |
| Style Fingerprinting | 200 | 120ms |
| Conversation Turn | 800 | 25ms |

### Scaling

- **Horizontal Scaling** - Stateless design allows easy clustering
- **Background Processing** - Oban for async analysis jobs
- **Caching** - Redis for frequently accessed results
- **Database** - PostgreSQL with optimized indexes

## 🎯 Roadmap

### v1.1 (Next Release)
- [ ] Machine Learning integration for better predictions
- [ ] Real-time collaboration features  
- [ ] Mobile app support
- [ ] Advanced style transfer capabilities

### v1.2 (Future)
- [ ] Plugin architecture for custom analyzers
- [ ] Integration with popular writing tools
- [ ] Advanced conversation AI models
- [ ] Multi-language support

### v2.0 (Long-term)
- [ ] Distributed processing architecture
- [ ] Advanced privacy features
- [ ] Enterprise SSO integration
- [ ] Advanced analytics dashboard

## 📄 License

Copyright (c) 2024 LANG Platform

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- Phoenix Framework team for the excellent web platform
- Ash Framework for the resource layer architecture
- Tree-sitter project for parsing inspiration
- Language Server Protocol specification authors
- The Elixir community for ecosystem support

## 📞 Support

- **Documentation**: [docs.lang-platform.dev](https://docs.lang-platform.dev)
- **Issues**: [GitHub Issues](https://github.com/lang-platform/lang/issues)
- **Discussions**: [GitHub Discussions](https://github.com/lang-platform/lang/discussions)
- **Email**: support@lang-platform.dev
- **Chat**: [Discord Server](https://discord.gg/lang-platform)

---

**Built with ❤️ using Elixir and Phoenix**

*Transforming how we interact with text, one format at a time.*