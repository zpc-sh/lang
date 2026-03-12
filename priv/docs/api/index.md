# LANG API Documentation

Welcome to the LANG Universal Text Intelligence Platform API. This REST API provides programmatic access to all text analysis, project management, and user account features.

## Base URL

```
https://your-lang-instance.com/api/v1
```

## Authentication

All API endpoints require authentication using Bearer tokens or API keys.

See also: Guides → Authentication & Org Context (/docs/guides/authentication) for header formats, session behavior, and organization scoping.

### Using API Keys (Recommended)

```bash
curl -H "Authorization: Bearer lang_your_api_key_here" \
  https://your-lang-instance.com/api/v1/projects
```

### Using JWT Tokens

```bash
curl -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  https://your-lang-instance.com/api/v1/projects
```

### Getting API Keys

1. Sign in to your LANG account
2. Go to **Settings** → **Security** → **API Keys**
3. Click **"New API Key"**
4. Copy the generated key (you won't see it again!)

## Rate Limits

Rate limits depend on your subscription tier:

| Tier | Requests/Month | Rate Limit |
|------|----------------|------------|
| Free | 1,000 | 10/minute |
| Professional | 50,000 | 100/minute |
| Enterprise | Unlimited | 1000/minute |

Rate limit headers are included in all responses:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1640995200
```

## Response Format

All API responses use JSON format:

### Success Response
```json
{
  "data": { /* response data */ },
  "meta": {
    "total": 42,
    "page": 1,
    "per_page": 20
  }
}
```

### Error Response
```json
{
  "error": {
    "code": "validation_failed",
    "message": "The provided data is invalid",
    "details": {
      "name": ["can't be blank"],
      "email": ["must be valid email address"]
    }
  }
}
```

## HTTP Status Codes

| Code | Meaning |
|------|---------|
| 200 | OK - Request successful |
| 201 | Created - Resource created successfully |
| 400 | Bad Request - Invalid request data |
| 401 | Unauthorized - Authentication required |
| 403 | Forbidden - Insufficient permissions |
| 404 | Not Found - Resource not found |
| 422 | Unprocessable Entity - Validation errors |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error - Server error |

# API Endpoints

## Projects

Projects organize your text analysis work and contain analysis sessions.

### List Projects

```http
GET /api/v1/projects
```

**Parameters:**
- `status` (optional): Filter by status (`active`, `archived`, `completed`)
- `order_by` (optional): Sort field (`inserted_at`, `updated_at`, `name`)
- `order_dir` (optional): Sort direction (`asc`, `desc`)

**Response:**
```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "My Analysis Project",
      "description": "Analyzing code quality for our application",
      "status": "active",
      "settings": {
        "max_file_size": 10485760,
        "excluded_patterns": ["*.log", "node_modules/*"]
      },
      "created_at": "2025-01-15T10:30:00Z",
      "updated_at": "2025-01-15T14:22:00Z"
    }
  ]
}
```

### Get Project

```http
GET /api/v1/projects/{id}
```

**Response:**
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "My Analysis Project",
    "description": "Analyzing code quality for our application",
    "status": "active",
    "settings": {
      "max_file_size": 10485760,
      "excluded_patterns": ["*.log", "node_modules/*"],
      "analysis_rules": ["complexity", "documentation", "security"]
    },
    "stats": {
      "total_sessions": 5,
      "total_files": 142,
      "total_violations": 23
    },
    "created_at": "2025-01-15T10:30:00Z",
    "updated_at": "2025-01-15T14:22:00Z"
  }
}
```

### Create Project

```http
POST /api/v1/projects
```

**Request Body:**
```json
{
  "project": {
    "name": "New Analysis Project",
    "description": "Project description",
    "settings": {
      "max_file_size": 10485760,
      "excluded_patterns": ["*.log", "*.tmp"],
      "analysis_rules": ["complexity", "documentation"]
    }
  }
}
```

### Update Project

```http
PUT /api/v1/projects/{id}
```

### Delete Project

```http
DELETE /api/v1/projects/{id}
```

### Archive Project

```http
POST /api/v1/projects/{id}/archive
```

## Analysis Sessions

Analysis sessions represent individual analysis runs within a project.

### List Sessions

```http
GET /api/v1/projects/{project_id}/sessions
```

### Create Session

```http
POST /api/v1/projects/{project_id}/sessions
```

**Request Body:**
```json
{
  "session": {
    "name": "Code Quality Scan",
    "description": "Weekly code quality analysis",
    "analysis_type": "full_scan",
    "settings": {
      "include_complexity": true,
      "include_documentation": true,
      "include_security": false
    }
  }
}
```

### Get Session

```http
GET /api/v1/sessions/{id}
```

**Response:**
```json
{
  "data": {
    "id": "session-uuid",
    "name": "Code Quality Scan",
    "status": "completed",
    "progress": 100,
    "stats": {
      "files_analyzed": 142,
      "violations_found": 23,
      "processing_time": 45.2
    },
    "created_at": "2025-01-15T10:30:00Z",
    "completed_at": "2025-01-15T10:31:30Z"
  }
}
```

### Cancel Session

```http
POST /api/v1/sessions/{id}/cancel
```

## File Upload and Analysis

### Upload Files

```http
POST /api/v1/sessions/{session_id}/upload
```

**Request:** Multipart form data with files

**Response:**
```json
{
  "data": {
    "uploaded_files": [
      {
        "filename": "app.js",
        "size": 12454,
        "format": "javascript",
        "status": "uploaded"
      }
    ]
  }
}
```

### Analyze Text

Analyze text content directly without file upload.

```http
POST /api/v1/sessions/{session_id}/analyze-text
```

**Request Body:**
```json
{
  "content": "const hello = 'world';\nconsole.log(hello);",
  "format": "javascript",
  "filename": "example.js"
}
```

**Response:**
```json
{
  "data": {
    "analysis": {
      "complexity": {
        "cyclomatic": 1,
        "cognitive": 1
      },
      "quality": {
        "maintainability": 85,
        "readability": 90
      },
      "violations": [
        {
          "rule": "no-console",
          "severity": "warning",
          "line": 2,
          "message": "Unexpected console statement"
        }
      ]
    }
  }
}
```

## Results

### List Files

```http
GET /api/v1/sessions/{session_id}/files
```

### Get File Analysis

```http
GET /api/v1/files/{id}
```

**Response:**
```json
{
  "data": {
    "id": "file-uuid",
    "filename": "app.js",
    "path": "/src/app.js",
    "format": "javascript",
    "size": 12454,
    "lines": 342,
    "analysis": {
      "complexity": {
        "cyclomatic": 15,
        "cognitive": 12,
        "nesting_depth": 4
      },
      "quality": {
        "maintainability": 75,
        "readability": 80,
        "testability": 65
      },
      "documentation": {
        "comment_ratio": 0.15,
        "documented_functions": 8,
        "total_functions": 12
      }
    },
    "violations": [
      {
        "id": "violation-uuid",
        "rule": "complexity",
        "severity": "warning",
        "line": 45,
        "column": 12,
        "message": "Function complexity too high",
        "suggestion": "Consider breaking this function into smaller functions"
      }
    ]
  }
}
```

### List Violations

```http
GET /api/v1/sessions/{session_id}/violations
```

**Parameters:**
- `severity` (optional): Filter by severity (`error`, `warning`, `info`)
- `rule` (optional): Filter by rule name
- `status` (optional): Filter by status (`open`, `resolved`, `ignored`)

### Get Violation

```http
GET /api/v1/violations/{id}
```

### Update Violation

```http
PUT /api/v1/violations/{id}
```

**Request Body:**
```json
{
  "violation": {
    "status": "resolved",
    "resolution_note": "Refactored function to reduce complexity"
  }
}
```

## Statistics

### User Statistics

```http
GET /api/v1/stats/user
```

**Response:**
```json
{
  "data": {
    "total_projects": 12,
    "total_sessions": 45,
    "total_files_analyzed": 2847,
    "total_violations": 156,
    "usage_this_month": {
      "api_calls": 1250,
      "limit": 50000,
      "percentage": 2.5
    },
    "top_file_types": [
      { "type": "javascript", "count": 1205 },
      { "type": "python", "count": 892 },
      { "type": "elixir", "count": 750 }
    ]
  }
}
```

### Session Statistics

```http
GET /api/v1/stats/sessions/{session_id}
```

## Webhooks

Configure webhooks to receive real-time notifications about analysis completion, violations, and other events.

### Webhook Events

- `session.completed` - Analysis session finished
- `session.failed` - Analysis session failed
- `violation.created` - New violation detected
- `project.archived` - Project archived
- `user.limit_exceeded` - Usage limit exceeded

### Webhook Payload

```json
{
  "event": "session.completed",
  "data": {
    "session_id": "session-uuid",
    "project_id": "project-uuid",
    "status": "completed",
    "stats": {
      "files_analyzed": 142,
      "violations_found": 23
    }
  },
  "timestamp": "2025-01-15T10:31:30Z"
}
```

## Code Examples

### Python SDK Example

```python
import requests

class LangClient:
    def __init__(self, api_key, base_url="https://lang.nocsi.com"):
        self.api_key = api_key
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        })
    
    def create_project(self, name, description=""):
        data = {
            "project": {
                "name": name,
                "description": description
            }
        }
        response = self.session.post(f"{self.base_url}/api/v1/projects", json=data)
        return response.json()
    
    def analyze_text(self, session_id, content, format_type):
        data = {
            "content": content,
            "format": format_type
        }
        response = self.session.post(
            f"{self.base_url}/api/v1/sessions/{session_id}/analyze-text",
            json=data
        )
        return response.json()

# Usage
client = LangClient("lang_your_api_key_here")
project = client.create_project("My Project", "Code analysis project")
```

### JavaScript/Node.js Example

```javascript
const axios = require('axios');

class LangClient {
  constructor(apiKey, baseUrl = 'https://lang.nocsi.com') {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
    this.client = axios.create({
      baseURL: `${baseUrl}/api/v1`,
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      }
    });
  }

  async createProject(name, description = '') {
    const response = await this.client.post('/projects', {
      project: { name, description }
    });
    return response.data;
  }

  async analyzeText(sessionId, content, format) {
    const response = await this.client.post(`/sessions/${sessionId}/analyze-text`, {
      content,
      format
    });
    return response.data;
  }
}

// Usage
const client = new LangClient('lang_your_api_key_here');
const project = await client.createProject('My Project', 'Code analysis project');
```

### cURL Examples

```bash
# Create a project
curl -X POST "https://lang.nocsi.com/api/v1/projects" \
  -H "Authorization: Bearer lang_your_api_key_here" \
  -H "Content-Type: application/json" \
  -d '{
    "project": {
      "name": "My Analysis Project",
      "description": "Analyzing code quality"
    }
  }'

# Analyze text
curl -X POST "https://lang.nocsi.com/api/v1/sessions/session-id/analyze-text" \
  -H "Authorization: Bearer lang_your_api_key_here" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "const hello = \"world\";\nconsole.log(hello);",
    "format": "javascript"
  }'

# Get project statistics
curl "https://lang.nocsi.com/api/v1/stats/user" \
  -H "Authorization: Bearer lang_your_api_key_here"
```

## Error Handling

### Common Error Responses

**401 Unauthorized**
```json
{
  "error": {
    "code": "unauthorized",
    "message": "Invalid or missing authentication token"
  }
}
```

**422 Validation Error**
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

**429 Rate Limited**
```json
{
  "error": {
    "code": "rate_limited",
    "message": "Too many requests. Please try again later.",
    "retry_after": 60
  }
}
```

## Best Practices

1. **Use API Keys**: More secure than JWT tokens for server-to-server communication
2. **Handle Rate Limits**: Implement exponential backoff for rate-limited requests
3. **Batch Operations**: Use batch endpoints when processing multiple files
4. **Webhook Verification**: Verify webhook signatures for security
5. **Error Handling**: Always handle API errors gracefully
6. **Caching**: Cache responses when appropriate to reduce API calls

## Support

- **Interactive Testing**: Use the [API Portal](/api-portal) to test endpoints
- **Community**: Join our developer community for support
- **Enterprise**: Contact support for enterprise-specific needs
- **Status**: Check [status.lang.dev] for API status updates
