# LANG Universal Text Intelligence Platform

Welcome to the comprehensive documentation for LANG, the Universal Text Intelligence Platform that transforms any text into actionable insights using advanced parsing, analysis, and AI capabilities.

## What is LANG?

LANG is a sophisticated web application built with Phoenix, Ash Framework, and native Rust NIFs for high-performance text analysis. It provides:

- **Universal Text Analysis** - Parse and analyze any text format
- **Native Performance** - 60-100x faster processing with Rust NIFs
- **Real-time Processing** - LiveView interfaces with instant feedback
- **Comprehensive APIs** - RESTful APIs with authentication
- **Advanced Parsing** - Tree-sitter semantic code analysis
- **AI Integration** - Large language model capabilities
- **SaaS Platform** - Multi-tenant with subscription tiers

## Quick Start

### Authentication
1. **Register** at `/auth` to create your account
2. **Get API Key** from Settings → Security → API Keys
3. **Make API Calls** using Bearer token authentication

### Web Interface
- **Dashboard** - Overview of your projects and usage
- **Text Analysis** - Interactive text processing interface
- **Settings** - Account, organization, and API management
- **API Portal** - Browse API documentation and test endpoints

### API Usage
```bash
# Authenticate
curl -H "Authorization: Bearer your-api-key" \
  https://lang.example.com/api/v1/projects

# Analyze text
curl -X POST \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"content": "Your text here", "format": "markdown"}' \
  https://lang.example.com/api/v1/analyze
```

## Architecture

### Technology Stack
- **Backend**: Elixir/Phoenix 1.8 with LiveView
- **Database**: PostgreSQL with Ash.Postgres
- **Performance**: Native Rust NIFs via Rustler
- **Frontend**: LiveView with Tailwind CSS
- **Background Jobs**: Oban for async processing
- **Authentication**: AshAuthentication with JWT tokens
- **Caching**: Redis for performance optimization

### Core Components

#### 1. Native Processing Engine (`Lang.Native.*`)
High-performance Rust NIFs for:
- **FSScanner** - Filesystem traversal and content search
- **TreeParser** - Tree-sitter based semantic analysis
- **PerfEngine** - Performance-critical text processing
- **LangParser** - Universal text format parsing

#### 2. Analysis Framework (`Lang.Analysis.*`)
- **Projects** - Organize analysis work
- **Sessions** - Track analysis runs
- **Files** - Manage analyzed content
- **Violations** - Code quality and rule violations

#### 3. Accounts System (`Lang.Accounts.*`)
- **Users** - User management with AshAuthentication
- **Organizations** - Multi-tenant organization support
- **API Keys** - Secure API access management
- **Subscriptions** - Billing tiers and limits

#### 4. Events & Analytics (`Lang.Events.*`)
- **Event Tracking** - Comprehensive user action logging
- **Usage Analytics** - API usage monitoring
- **Performance Metrics** - System performance tracking

## Documentation Sections

### [Getting Started](./guides/getting-started.md)
- Installation and setup
- First API call
- Web interface tour

### [API Reference](./api/index.md)
- Authentication
- Endpoints documentation
- Request/response examples
- Rate limiting

### [Tutorials](./tutorials/index.md)
- Text analysis workflows
- Code quality scanning
- Document processing
- Integration examples

### [Architecture](./architecture/index.md)
- System design
- Native NIFs performance
- Database schema
- Background processing

### [Development](./development/index.md)
- Local development setup
- Contributing guidelines
- Testing strategies
- Deployment guide

## Features Overview

### Text Analysis
- **Universal Format Support** - Markdown, JSON, YAML, code files
- **Semantic Analysis** - Tree-sitter based parsing
- **Content Classification** - Automatic format detection
- **Quality Metrics** - Complexity, readability, maintainability

### Code Analysis
- **Multi-language Support** - JavaScript, Python, Elixir, Rust, Go
- **Architectural Rules** - Custom rule definitions
- **Complexity Metrics** - Cyclomatic and cognitive complexity
- **Documentation Coverage** - Comment ratio analysis

### Performance Features
- **Native Speed** - Rust NIFs for critical operations
- **Streaming Processing** - Handle large documents efficiently
- **Batch Operations** - Process multiple files concurrently
- **Caching** - Redis-backed performance optimization

### Enterprise Features
- **Multi-tenant** - Organization-based access control
- **API Rate Limiting** - Configurable per subscription tier
- **Usage Analytics** - Detailed usage tracking and reporting
- **Webhook Support** - Real-time notifications
- **SSO Integration** - Enterprise authentication (planned)

## Subscription Tiers

### Free Tier
- 1,000 API requests/month
- Web interface access
- Basic text analysis
- Community support

### Professional ($29/month)
- 50,000 API requests/month
- Advanced analysis features
- Priority support
- Custom rules (limited)

### Enterprise ($99/month)
- Unlimited API requests
- Full feature access
- Custom integrations
- Dedicated support

## Support

- **Documentation**: Browse this documentation site
- **API Portal**: Interactive API testing at `/api-portal`
- **Community**: Join our community discussions
- **Support**: Contact support for enterprise customers

## Latest Updates

### Version 1.0.0
- Complete AshAuthentication integration
- Native Rust NIF performance engine
- Real-time LiveView interfaces
- Comprehensive API documentation
- Multi-tenant SaaS platform

---

**Ready to get started?** [Create your account](/auth) or [explore the API](/api-portal).