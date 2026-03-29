# LANG MCP Broker Security Layer

A comprehensive security wrapper for Model Context Protocol (MCP) servers that prevents direct internet exposure and provides enterprise-grade isolation, authentication, and monitoring.

## Overview

The LANG MCP Broker Security Layer is designed to solve a critical security problem: **MCP servers were never designed for direct internet exposure**. This broker provides a secure, authenticated, and monitored wrapper around MCP servers, ensuring they can be safely used in production environments.

## Security Model

### Core Principles

1. **Zero Direct Exposure** - MCP servers never have direct internet access
2. **Authentication Required** - All access requires valid API keys or user sessions
3. **Request Sanitization** - All MCP requests are validated and sanitized
4. **Process Isolation** - Each MCP server runs in an isolated process
5. **Resource Limits** - Strict limits on connections, memory, and processing time
6. **Comprehensive Auditing** - All MCP interactions are logged and monitored

### Threat Model

The broker assumes:
- MCP requests may contain malicious payloads (command injection, path traversal)
- MCP servers may be compromised or misbehaving
- Users may attempt privilege escalation through MCP
- MCP responses may contain oversized or malicious content
- Network attackers cannot directly reach MCP servers

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   AI Agent      │────│  LANG LSP Server │────│  Phoenix Web    │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                                │ Authenticated HTTP/WS
                                ▼
                       ┌─────────────────┐
                       │  MCP Controller │
                       │                 │
                       └─────────────────┘
                                │
                                │ Validated Requests
                                ▼
                       ┌─────────────────┐
                       │  Security Layer │
                       │                 │
                       └─────────────────┘
                                │
                                │ Sanitized Requests
                                ▼
                       ┌─────────────────┐
                       │   MCP Broker    │
                       │                 │
                       └─────────────────┘
                                │
                      ┌─────────┼─────────┐
                      │         │         │
                      ▼         ▼         ▼
              ┌─────────────┐ ┌───────┐ ┌─────────┐
              │ Filesystem  │ │  Git  │ │Database │
              │ MCP Server  │ │Server │ │ Server  │
              └─────────────┘ └───────┘ └─────────┘
              (Isolated Processes)
```

## Components

### 1. MCP Broker (`Lang.MCP.Broker`)

Core orchestration component that manages MCP server lifecycle:

- **Connection Management**: Start/stop/health check MCP servers
- **Resource Limits**: Enforce per-user connection limits
- **Circuit Breakers**: Protect against misbehaving servers
- **Process Supervision**: Automatic recovery from crashes

### 2. Security Wrapper (`Lang.MCP.Security`)

Comprehensive request/response validation:

- **Request Sanitization**: Remove dangerous patterns and limit sizes
- **Path Traversal Prevention**: Block `../` and absolute paths
- **Command Injection Protection**: Filter shell metacharacters
- **Content Validation**: Check file extensions and content types
- **Rate Limiting**: Per-user and per-operation limits

### 3. Connection Pool (`Lang.MCP.Pool`)

Efficient connection management:

- **Pre-warming**: Common server types kept ready
- **Just-in-time**: On-demand creation for less common servers
- **Idle Cleanup**: Automatic disconnection of unused connections
- **Health Monitoring**: Continuous health checks and recovery

### 4. Stream Bridge (`Lang.MCP.StreamBridge`)

Real-time streaming for large responses:

- **Phoenix PubSub Integration**: Seamless real-time updates
- **Session Isolation**: Per-user streaming channels
- **Connection Multiplexing**: Multiple agents sharing connections
- **Redis State Management**: Persistent session state

### 5. API Controller (`LangWeb.Api.V2.McpController`)

Authenticated HTTP endpoints:

- `POST /api/v2/mcp/connect` - Request MCP server access
- `GET /api/v2/mcp/status/:stream_id` - Check connection status
- `DELETE /api/v2/mcp/disconnect/:stream_id` - Clean disconnect
- WebSocket `/socket` - Real-time streaming communication

## Usage

### 1. Request MCP Connection

```http
POST /api/v2/mcp/connect
Authorization: Bearer <api_key>

{
  "server_type": "filesystem",
  "config": {
    "root_path": "workspace/project"
  },
  "session_id": "my_session_123"
}
```

Response:
```json
{
  "connection_id": "mcp_conn_abc123",
  "stream_id": "mcp_stream_def456",
  "status": "connected",
  "server_info": {
    "server_type": "filesystem",
    "created_at": "2024-12-19T15:30:00Z",
    "endpoints": {
      "status": "/api/v2/mcp/status/mcp_stream_def456",
      "disconnect": "/api/v2/mcp/disconnect/mcp_stream_def456"
    }
  }
}
```

### 2. WebSocket Streaming

```javascript
const socket = new WebSocket('wss://api.lang.dev/socket');

// Authenticate
socket.send(JSON.stringify({
  topic: 'mcp:mcp_stream_def456',
  event: 'join',
  payload: { token: 'your_auth_token' }
}));

// Send MCP request
socket.send(JSON.stringify({
  topic: 'mcp:mcp_stream_def456',
  event: 'mcp_request',
  payload: {
    type: 'mcp_request',
    request: {
      method: 'fs/list',
      params: { path: 'src' }
    }
  }
}));

// Receive streaming response
socket.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.event === 'mcp_response') {
    console.log('MCP Response:', data.payload);
  }
};
```

### 3. Check Status

```http
GET /api/v2/mcp/status/mcp_stream_def456
Authorization: Bearer <api_key>
```

Response:
```json
{
  "stream_id": "mcp_stream_def456",
  "connection_status": "active",
  "stream_status": "streaming",
  "progress": {
    "total_chunks": 5,
    "sent_chunks": 3,
    "completion_percentage": 60.0
  },
  "stats": {
    "created_at": "2024-12-19T15:30:00Z",
    "last_activity": "2024-12-19T15:32:15Z",
    "session_id": "my_session_123"
  }
}
```

## Supported MCP Server Types

### Filesystem (`filesystem`)
- **Operations**: list, read, stat, exists
- **Security**: Sandboxed to configured root directory
- **Limits**: 1MB max file size, allowed extensions only

### Git (`git`)
- **Operations**: clone, status, diff, log
- **Security**: URL validation, ref sanitization
- **Limits**: HTTPS/SSH only, no local repositories

### Database (`database`)
- **Operations**: query, schema, tables
- **Security**: SQL injection prevention, read-only mode
- **Limits**: Query timeout, result size limits

### Web Search (`web_search`)
- **Operations**: search, fetch, extract
- **Security**: URL allowlist, content filtering
- **Limits**: Rate limiting, result count limits

### Code Analysis (`code_analysis`)
- **Operations**: parse, analyze, lint, format
- **Security**: Language allowlist, resource limits
- **Limits**: File size limits, processing timeout

## Configuration

### Environment Variables

```bash
# MCP Configuration
MCP_MAX_CONNECTIONS_PER_USER=5
MCP_DEFAULT_IDLE_TIMEOUT=900000  # 15 minutes
MCP_HEALTH_CHECK_INTERVAL=30000  # 30 seconds
MCP_REQUEST_TIMEOUT=30000        # 30 seconds

# Security Configuration
MCP_MAX_REQUEST_SIZE=1048576     # 1MB
MCP_MAX_RESPONSE_SIZE=10485760   # 10MB
MCP_MAX_ARRAY_LENGTH=1000
MCP_MAX_STRING_LENGTH=100000
MCP_MAX_NESTING_DEPTH=10

# Rate Limiting
MCP_CONNECT_RATE_LIMIT=10        # per hour
MCP_REQUEST
_RATE_LIMIT=1000      # per hour
```

### Oban Queue Configuration

```elixir
config :lang, Oban,
  queues: [
    mcp: 5,                    # MCP lifecycle management
    analysis: 10,              # File analysis tasks
    default: 10                # General background tasks
  ]
```

## Security Features

### Request Validation

- **Size Limits**: 1MB request, 10MB response maximum
- **Pattern Blocking**: Command injection, path traversal prevention
- **Extension Filtering**: Only allowed file extensions
- **Depth Limits**: Maximum 10 levels of JSON nesting
- **String Limits**: Maximum 100KB string length
- **Array Limits**: Maximum 1000 array items

### Authentication & Authorization

- **API Key Authentication**: Bearer token validation
- **User Session Authentication**: JWT token validation
- **Rate Limiting**: Per-user and per-operation limits
- **Resource Limits**: Maximum 5 connections per user
- **Session Isolation**: User data completely isolated

### Process Isolation

- **Supervised Processes**: Each MCP server runs under supervision
- **Resource Limits**: Memory and CPU constraints
- **Process Monitoring**: Health checks and automatic recovery
- **Graceful Shutdown**: Clean termination on errors
- **Crash Recovery**: Automatic restart with circuit breaker

### Audit & Monitoring

- **Comprehensive Logging**: All MCP requests/responses logged
- **Security Events**: Blocked requests tracked and alerted
- **Performance Metrics**: Connection pools, response times
- **Usage Analytics**: User activity and resource utilization
- **Health Monitoring**: Real-time status and alerting

## Deployment

### Development

```bash
# Start the application
mix phx.server

# Run tests
mix test

# Check security
mix test test/lang/mcp/security_test.exs
```

### Production

```bash
# Build release
mix release

# Deploy with security controls
MIX_ENV=prod mix release
MCP_MAX_CONNECTIONS_PER_USER=10 _build/prod/rel/lang/bin/lang start
```

### Health Checks

```bash
# Check MCP broker status
curl -H "Authorization: Bearer $API_KEY" \
  https://api.lang.dev/api/v2/mcp/health

# Monitor metrics
curl -H "Authorization: Bearer $API_KEY" \
  https://api.lang.dev/api/v2/mcp/metrics
```

## Monitoring & Alerting

### Key Metrics

- **Connection Pool Health**: Available vs busy connections
- **Request Success Rate**: Successful vs failed requests
- **Security Events**: Blocked malicious requests
- **Response Times**: Average MCP request processing time
- **Resource Utilization**: Memory and CPU usage per server

### Alerts

- **Circuit Breaker Open**: MCP server type unavailable
- **High Error Rate**: >5% of requests failing
- **Security Violations**: Multiple blocked requests from user
- **Resource Exhaustion**: Connection pool at capacity
- **Process Crashes**: MCP server processes dying

## Troubleshooting

### Common Issues

#### "Connection limit exceeded"
- **Cause**: User has reached maximum connections (default: 5)
- **Solution**: Disconnect unused connections or increase limit

#### "Server type not allowed"
- **Cause**: Requesting unsupported MCP server type
- **Solution**: Use supported types: filesystem, git, database, web_search, code_analysis

#### "Request too large"
- **Cause**: Request exceeds 1MB size limit
- **Solution**: Reduce request size or process in chunks

#### "Dangerous pattern detected"
- **Cause**: Request contains blocked patterns (path traversal, command injection)
- **Solution**: Remove dangerous patterns from request

### Debug Mode

```bash
# Enable debug logging
export LANG_LOG_LEVEL=debug

# View MCP-specific logs
tail -f log/dev.log | grep "MCP"
```

### Performance Tuning

```elixir
# Increase connection pool sizes
config :lang, :mcp,
  default_pool_size: 5,
  max_pool_size: 20

# Adjust timeouts
config :lang, :mcp,
  connection_timeout: 60_000,
  idle_timeout: 1_800_000  # 30 minutes
```

## Contributing

### Running Tests

```bash
# All tests
mix test

# Security tests only
mix test test/lang/mcp/security_test.exs

# Integration tests
mix test test/lang_web/controllers/api/v2/mcp_controller_test.exs
```

### Adding New MCP Server Types

1. Create server module in `lib/lang/mcp/servers/`
2. Add validation rules in `Lang.MCP.Security`
3. Update allowed server types list
4. Add comprehensive tests
5. Update documentation

### Security Guidelines

- **Never bypass security validation** - All requests must go through security layer
- **Always validate user input** - Assume all input is malicious
- **Use allowlists, not blocklists** - Explicitly allow safe operations
- **Log security events** - Track and alert on blocked requests
- **Test security boundaries** - Include attack scenarios in tests

## License

This MCP broker security layer is part of the LANG Universal Text Intelligence Platform.

## Support

For security issues or questions about the MCP broker:

- **Security Issues**: security@lang.dev (GPG key available)
- **General Support**: support@lang.dev
- **Documentation**: https://docs.lang.dev/mcp-broker

---

**⚠️ Security Notice**: This broker is designed to make MCP servers safe for internet exposure. However, always follow security best practices, keep dependencies updated, and monitor for security advisories.
