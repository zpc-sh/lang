# Getting Started with LANG

Welcome to LANG, the Universal Text Intelligence Platform! This guide will help you get up and running quickly with text analysis, code quality scanning, and API integration.

## What is LANG?

LANG is a sophisticated text intelligence platform that transforms any text into actionable insights using:

- **Native Performance** - Rust NIFs provide 60-100x faster processing than pure Elixir
- **Universal Parsing** - Support for code files, documents, and structured data
- **Real-time Analysis** - LiveView interfaces with instant feedback
- **Enterprise APIs** - RESTful APIs with authentication and rate limiting
- **Multi-tenant SaaS** - Organization-based access control with subscription tiers

## Quick Start

### 1. Create Your Account

1. Visit [your-lang-instance.com/auth](/auth)
2. Click **"Register"** to create a new account
3. Fill in your details:
   - **Email** - Your email address
   - **Name** - Your full name
   - **Organization** - Your company or project name
   - **Password** - Secure password (8+ characters)

Your account will be created with:
- **Free tier** - 1,000 API requests per month
- **Organization** - Automatically created for you
- **API key** - Generated for immediate use

### 2. Get Your API Key

After registration, get your API key:

1. Go to **Settings** → **Security** → **API Keys**
2. Click **"New API Key"**
3. Enter a name (e.g., "My First Key")
4. **Copy the key immediately** - you won't see it again!

Your API key will look like: `lang_abcd1234...`

### 3. Make Your First API Call

Test your setup with a simple API call:

```bash
curl -X POST "https://your-lang-instance.com/api/v1/projects" \
  -H "Authorization: Bearer lang_your_api_key_here" \
  -H "Content-Type: application/json" \
  -d '{
    "project": {
      "name": "My First Project",
      "description": "Getting started with LANG"
    }
  }'
```

You should receive a response like:

```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "My First Project",
    "description": "Getting started with LANG",
    "status": "active",
    "created_at": "2025-01-15T10:30:00Z"
  }
}
```

## Web Interface Tour

### Dashboard

Visit `/dashboard` to see:

- **Project Overview** - Your recent projects and analysis sessions
- **Usage Statistics** - API calls, limits, and subscription details
- **Quick Actions** - Create projects, analyze text, view results

### Text Analysis Interface

Go to `/analyze` for interactive text analysis:

1. **Paste or upload text** - Any format supported
2. **Choose analysis type** - Code quality, documentation, structure
3. **View real-time results** - Instant feedback as you type
4. **Export results** - Download reports in multiple formats

### Settings

Access `/settings` to manage:

- **Profile** - Update your name, email, and preferences
- **Security** - Change password, manage API keys
- **Organization** - Organization details and member management
- **Billing** - Subscription tier and usage monitoring

## Text Analysis Examples

### Analyzing Code Quality

```bash
# Create a project for code analysis
curl -X POST "https://lang.nocsi.com/api/v1/projects" \
  -H "Authorization: Bearer lang_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "project": {
      "name": "Code Quality Scan",
      "settings": {
        "analysis_rules": ["complexity", "documentation", "security"]
      }
    }
  }'

# Create an analysis session
curl -X POST "https://lang.nocsi.com/api/v1/projects/PROJECT_ID/sessions" \
  -H "Authorization: Bearer lang_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "session": {
      "name": "Weekly Code Review",
      "analysis_type": "full_scan"
    }
  }'

# Analyze JavaScript code
curl -X POST "https://lang.nocsi.com/api/v1/sessions/SESSION_ID/analyze-text" \
  -H "Authorization: Bearer lang_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "function calculateTotal(items) {\n  let total = 0;\n  for (let i = 0; i < items.length; i++) {\n    total += items[i].price * items[i].quantity;\n  }\n  return total;\n}",
    "format": "javascript",
    "filename": "calculator.js"
  }'
```

Results will include:
- **Complexity metrics** - Cyclomatic and cognitive complexity
- **Quality scores** - Maintainability, readability, testability
- **Violations** - Code issues with severity levels
- **Suggestions** - Automated improvement recommendations

### Analyzing Documents

```bash
# Analyze Markdown documentation
curl -X POST "https://lang.nocsi.com/api/v1/sessions/SESSION_ID/analyze-text" \
  -H "Authorization: Bearer lang_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "# Project Documentation\n\nThis is a sample document...",
    "format": "markdown",
    "filename": "README.md"
  }'
```

Results include:
- **Structure analysis** - Headers, sections, organization
- **Readability metrics** - Grade level, complexity scores
- **Link validation** - Broken links and references
- **Content suggestions** - Improvements for clarity

## Understanding Results

### Complexity Metrics

- **Cyclomatic Complexity** (1-10+)
  - 1-4: Simple, easy to test
  - 5-7: Moderate complexity
  - 8-10: Complex, needs review
  - 11+: Very complex, refactor recommended

- **Cognitive Complexity** (1-15+)
  - 1-5: Easy to understand
  - 6-10: Moderate mental load
  - 11-15: Hard to understand
  - 16+: Very difficult, refactor needed

### Quality Scores

- **Maintainability** (0-100)
  - 85-100: Excellent
  - 65-84: Good
  - 45-64: Fair
  - 0-44: Poor

- **Readability** (0-100)
  - Based on naming, formatting, documentation

### Violation Severities

- **Error** - Must fix, breaks functionality
- **Warning** - Should fix, impacts quality
- **Info** - Consider fixing, minor improvement

## Subscription Tiers

### Free Tier (Current)
- 1,000 API requests/month
- Basic analysis features
- Web interface access
- Community support

### Professional ($29/month)
- 50,000 API requests/month
- Advanced analysis rules
- Custom rule configuration
- Priority support
- Webhook notifications

### Enterprise ($99/month)
- Unlimited API requests
- Full feature access
- Custom integrations
- Dedicated support
- SLA guarantees

## Rate Limits

Your API usage is monitored and limited based on your tier:

| Tier | Requests/Month | Rate Limit | Burst Limit |
|------|----------------|------------|-------------|
| Free | 1,000 | 10/minute | 50/hour |
| Professional | 50,000 | 100/minute | 500/hour |
| Enterprise | Unlimited | 1000/minute | 5000/hour |

Rate limit headers in responses:
```
X-RateLimit-Limit: 10
X-RateLimit-Remaining: 8
X-RateLimit-Reset: 1640995200
```

## Error Handling

Common HTTP status codes:

- **200 OK** - Request successful
- **401 Unauthorized** - Invalid/missing API key
- **403 Forbidden** - Insufficient permissions
- **422 Unprocessable Entity** - Validation errors
- **429 Too Many Requests** - Rate limit exceeded

Example error response:
```json
{
  "error": {
    "code": "validation_failed",
    "message": "The provided data is invalid",
    "details": {
      "name": ["can't be blank"],
      "content": ["is too large (maximum 1MB)"]
    }
  }
}
```

## Best Practices

### API Usage
1. **Store your API key securely** - Never commit to version control
2. **Handle rate limits gracefully** - Implement exponential backoff
3. **Use appropriate timeouts** - Network requests can fail
4. **Validate inputs locally** - Reduce failed API calls
5. **Cache results** - Avoid duplicate analyses

### Code Analysis
1. **Start with small files** - Test your workflow first
2. **Focus on high-impact issues** - Fix errors before warnings
3. **Use batch processing** - Analyze multiple files efficiently
4. **Set up webhooks** - Get notified of completion
5. **Track trends over time** - Monitor quality improvements

### Security
1. **Rotate API keys regularly** - Especially if compromised
2. **Use HTTPS only** - Never send keys over HTTP
3. **Limit API key scopes** - Only grant necessary permissions
4. **Monitor usage** - Watch for unusual activity
5. **Revoke unused keys** - Clean up old integrations

## Next Steps

Now that you're set up:

1. **[Explore the API Reference](/docs/api)** - Complete endpoint documentation
2. **[Try the Tutorials](/docs/tutorials)** - Step-by-step guides
3. **[Check Architecture Docs](/docs/architecture)** - Understand the system
4. **[Join the Community](/community)** - Get help and share experiences
5. **[Visit API Portal](/api-portal)** - Interactive API testing

## Getting Help

- **Documentation** - Browse this documentation site
- **API Portal** - Interactive testing at `/api-portal`
- **Community Support** - Free tier users
- **Email Support** - Professional and Enterprise tiers
- **GitHub Issues** - Bug reports and feature requests

## Troubleshooting

### Common Issues

**"Invalid API key" error**
- Check your key is copied correctly
- Ensure you're using `Bearer` authentication
- Verify key hasn't been revoked

**Rate limit exceeded**
- Check your current usage in Settings
- Implement retry logic with delays
- Consider upgrading your tier

**Analysis takes too long**
- Large files may need streaming
- Use batch endpoints for multiple files
- Check file size limits

**No results returned**
- Verify file format is supported
- Check content isn't empty
- Review analysis settings

Ready to dive deeper? Continue with our [API Reference](/docs/api) or try a hands-on [tutorial](/docs/tutorials)!