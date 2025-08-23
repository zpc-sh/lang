# MCP Broker Deployment & Integration Guide

**Status**: Production Ready
**Date**: December 2024
**Version**: 1.0.0

## Overview

This guide provides step-by-step instructions for deploying and integrating the LANG MCP Broker Security Layer in production environments. The broker transforms inherently insecure MCP servers into enterprise-grade, authenticated, and monitored services.

## Prerequisites

### System Requirements

- **Elixir**: 1.15+
- **Phoenix**: 1.8+
- **PostgreSQL**: 14+
- **Redis**: 6+ (for session state)
- **Memory**: 2GB+ per instance
- **CPU**: 2+ cores recommended

### Dependencies

```elixir
# In mix.exs
{:oban, "~> 2.15"},
{:phoenix, "~> 1.8"},
{:phoenix_pubsub, "~> 2.1"},
{:rustler, "~> 0.34.0"},
{:jason, "~> 1.4"}
```

## Installation

### 1. Add to Supervision Tree

```elixir
# lib/lang/application.ex
def start(_type, _args) do
  children = [
    # ... existing children ...

    # MCP Broker Security Layer
    {DynamicSupervisor, strategy: :one_for_one, name: Lang.MCP.ServerSupervisor},
    Lang.MCP.Broker,
    Lang.MCP.Pool,
    Lang.MCP.StreamBridge,
  ]

  opts = [strategy: :one_for_one, name: Lang.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 2. Router Configuration

```elixir
# lib/lang_web/router.ex
scope "/api/v2", LangWeb.Api.V2 do
  pipe_through [:api, :require_authenticated_api]

  # MCP Broker endpoints
  post "/mcp/connect", McpController, :connect
  get "/mcp/status/:stream_id", McpController, :status
  delete "/mcp/disconnect/:stream_id", McpController, :disconnect
end
```

### 3. WebSocket Configuration

```elixir
# lib/lang_web/endpoint.ex
socket "/socket", LangWeb.UserSocket,
  websocket: true,
  longpoll: false
```

```elixir
# lib/lang_web/user_socket.ex
channel "mcp:*", LangWeb.Api.V2.McpController
```

## Configuration

### Environment Variables

```bash
# Production environment
export MIX_ENV=prod

# MCP Broker Configuration
export MCP_MAX_CONNECTIONS_PER_USER=10
export MCP_DEFAULT_IDLE_TIMEOUT=900000    # 15 minutes
export MCP_HEALTH_CHECK_INTERVAL=30000    # 30 seconds
export MCP_CONNECTION_TIMEOUT=30000       # 30 seconds

# Security Configuration
export MCP_MAX_REQUEST_SIZE=1048576       # 1MB
export MCP_MAX_RESPONSE_SIZE=10485760     # 10MB
export MCP_MAX_ARRAY_LENGTH=1000
export MCP_MAX_STRING_LENGTH=100000
export MCP_MAX_NESTING_DEPTH=10

# Rate Limiting
export MCP_CONNECT_RATE_LIMIT=100         # per hour
export MCP_REQUEST_RATE_LIMIT=1000        # per hour

# Redis Configuration (for session state)
export REDIS_URL=redis://localhost:6379/0

# Monitoring
export ENABLE_MCP_METRICS=true
export MCP_LOG_LEVEL=info
```

### Elixir Configuration

```elixir
# config/prod.exs
config :lang, :mcp,
  # Connection pool settings
  default_pool_size: 3,
  max_pool_size: 10,
  pre_warm_servers: ["filesystem", "git"],

  # Timeouts
  connection_timeout: 30_000,
  idle_timeout: 900_000,        # 15 minutes
  health_check_interval: 30_000, # 30 seconds

  # Security limits
  max_connections_per_user: 10,
  max_request_size: 1_048_576,   # 1MB
  max_response_size: 10_485_760, # 10MB

  # Rate limiting
  rate_limits: %{
    "mcp_connect" => %{limit: 100, window: 3600},    # 100/hour
    "mcp_request" => %{limit: 1000, window: 3600},   # 1000/hour
  }

# Oban queue configuration
config :lang, Oban,
  queues: [
    default: 10,
    analysis: 10,
    mcp: 5,                      # MCP lifecycle management
  ]

# Redis for session state
config :lang, :redis_url, System.get_env("REDIS_URL")
```

## Deployment Steps

### 1. Database Migrations

No additional database tables are required - the broker uses existing Lang infrastructure.

### 2. Build and Release

```bash
# Install dependencies
mix deps.get

# Compile native NIFs (if using Rust extensions)
mix compile

# Run tests
mix test

# Build production release
MIX_ENV=prod mix release

# Or deploy directly
MIX_ENV=prod mix phx.server
```

### 3. Health Checks

```bash
# Basic health check
curl -H "Authorization: Bearer $API_KEY" \
  https://your-lang-instance.com/health

# MCP-specific health check
curl -H "Authorization: Bearer $API_KEY" \
  https://your-lang-instance.com/api/v2/mcp/health
```

## Integration Examples

### 1. Python Agent Integration

```python
import asyncio
import websockets
import json

class MCPClient:
    def __init__(self, base_url, api_key):
        self.base_url = base_url
        self.api_key = api_key
        self.ws = None
        self.stream_id = None

    async def connect_mcp_server(self, server_type, config=None):
        """Request MCP server connection"""
        headers = {"Authorization": f"Bearer {self.api_key}"}

        data = {
            "server_type": server_type,
            "config": config or {},
            "session_id": f"python_agent_{id(self)}"
        }

        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/api/v2/mcp/connect",
                headers=headers,
                json=data
            )

            if response.status_code == 201:
                result = response.json()
                self.stream_id = result["stream_id"]
                return result
            else:
                raise Exception(f"Connection failed: {response.text}")

    async def start_websocket(self):
        """Start WebSocket streaming connection"""
        if not self.stream_id:
            raise Exception("No stream_id - connect to MCP server first")

        uri = f"wss://{self.base_url}/socket"

        self.ws = await websockets.connect(uri)

        # Join MCP channel
        await self.ws.send(json.dumps({
            "topic": f"mcp:{self.stream_id}",
            "event": "join",
            "payload": {"token": self.api_key}
        }))

        return self.ws

    async def send_mcp_request(self, method, params=None):
        """Send MCP request through WebSocket"""
        if not self.ws:
            await self.start_websocket()

        request = {
            "topic": f"mcp:{self.stream_id}",
            "event": "mcp_request",
            "payload": {
                "type": "mcp_request",
                "request": {
                    "method": method,
                    "params": params or {}
                },
                "request_id": f"req_{asyncio.get_event_loop().time()}"
            }
        }

        await self.ws.send(json.dumps(request))

    async def listen_for_responses(self):
        """Listen for MCP responses"""
        async for message in self.ws:
            data = json.loads(message)
            if data.get("event") == "mcp_response":
                yield data["payload"]

# Usage example
async def main():
    client = MCPClient("https://api.lang.dev", "your-api-key")

    # Connect to filesystem server
    connection = await client.connect_mcp_server("filesystem", {
        "root_path": "workspace/project"
    })

    print(f"Connected: {connection['stream_id']}")

    # Start WebSocket
    await client.start_websocket()

    # Send filesystem request
    await client.send_mcp_request("fs/list", {"path": "src"})

    # Listen for responses
    async for response in client.listen_for_responses():
        print(f"MCP Response: {response}")
        break  # Just process one response for demo

if __name__ == "__main__":
    asyncio.run(main())
```

### 2. JavaScript/Node.js Integration

```javascript
const WebSocket = require('ws');
const axios = require('axios');

class MCPClient {
    constructor(baseUrl, apiKey) {
        this.baseUrl = baseUrl;
        this.apiKey = apiKey;
        this.ws = null;
        this.streamId = null;
    }

    async connectMCPServer(serverType, config = {}) {
        const response = await axios.post(`${this.baseUrl}/api/v2/mcp/connect`, {
            server_type: serverType,
            config: config,
            session_id: `node_agent_${Date.now()}`
        }, {
            headers: {
                'Authorization': `Bearer ${this.apiKey}`,
                'Content-Type': 'application/json'
            }
        });

        if (response.status === 201) {
            this.streamId = response.data.stream_id;
            return response.data;
        }

        throw new Error(`Connection failed: ${response.data}`);
    }

    async startWebSocket() {
        if (!this.streamId) {
            throw new Error('No stream_id - connect to MCP server first');
        }

        const wsUrl = this.baseUrl.replace('https://', 'wss://').replace('http://', 'ws://');
        this.ws = new WebSocket(`${wsUrl}/socket`);

        return new Promise((resolve, reject) => {
            this.ws.on('open', () => {
                // Join MCP channel
                this.ws.send(JSON.stringify({
                    topic: `mcp:${this.streamId}`,
                    event: 'join',
                    payload: { token: this.apiKey }
                }));
                resolve(this.ws);
            });

            this.ws.on('error', reject);
        });
    }

    async sendMCPRequest(method, params = {}) {
        if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
            await this.startWebSocket();
        }

        const request = {
            topic: `mcp:${this.streamId}`,
            event: 'mcp_request',
            payload: {
                type: 'mcp_request',
                request: {
                    method: method,
                    params: params
                },
                request_id: `req_${Date.now()}`
            }
        };

        this.ws.send(JSON.stringify(request));
    }

    onResponse(callback) {
        this.ws.on('message', (data) => {
            const message = JSON.parse(data);
            if (message.event === 'mcp_response') {
                callback(message.payload);
            }
        });
    }
}

// Usage
async function main() {
    const client = new MCPClient('https://api.lang.dev', 'your-api-key');

    // Connect to git server
    const connection = await client.connectMCPServer('git', {
        repository_url: 'https://github.com/user/repo.git'
    });

    console.log(`Connected: ${connection.stream_id}`);

    // Start WebSocket
    await client.startWebSocket();

    // Listen for responses
    client.onResponse((response) => {
        console.log('MCP Response:', response);
    });

    // Send git request
    await client.sendMCPRequest('git/status', {});
}

main().catch(console.error);
```

### 3. Rust Agent Integration

```rust
use tokio_tungstenite::{connect_async, tungstenite::Message};
use serde_json::{json, Value};
use reqwest::Client;
use std::collections::HashMap;

pub struct MCPClient {
    base_url: String,
    api_key: String,
    stream_id: Option<String>,
}

impl MCPClient {
    pub fn new(base_url: String, api_key: String) -> Self {
        Self {
            base_url,
            api_key,
            stream_id: None,
        }
    }

    pub async fn connect_mcp_server(&mut self, server_type: &str, config: HashMap<String, Value>) -> Result<Value, Box<dyn std::error::Error>> {
        let client = Client::new();
        let url = format!("{}/api/v2/mcp/connect", self.base_url);

        let payload = json!({
            "server_type": server_type,
            "config": config,
            "session_id": format!("rust_agent_{}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs())
        });

        let response = client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .json(&payload)
            .send()
            .await?;

        if response.status().is_success() {
            let result: Value = response.json().await?;
            self.stream_id = result["stream_id"].as_str().map(|s| s.to_string());
            Ok(result)
        } else {
            Err(format!("Connection failed: {}", response.status()).into())
        }
    }

    pub async fn start_websocket(&self) -> Result<(), Box<dyn std::error::Error>> {
        let stream_id = self.stream_id.as_ref().ok_or("No stream_id available")?;

        let ws_url = self.base_url
            .replace("https://", "wss://")
            .replace("http://", "ws://") + "/socket";

        let (ws_stream, _) = connect_async(&ws_url).await?;
        let (mut ws_sender, mut ws_receiver) = ws_stream.split();

        // Join MCP channel
        let join_message = json!({
            "topic": format!("mcp:{}", stream_id),
            "event": "join",
            "payload": { "token": self.api_key }
        });

        ws_sender.send(Message::Text(join_message.to_string())).await?;

        // Handle messages
        while let Some(msg) = ws_receiver.next().await {
            let msg = msg?;
            if let Message::Text(text) = msg {
                let parsed: Value = serde_json::from_str(&text)?;
                if parsed["event"] == "mcp_response" {
                    println!("MCP Response: {}", parsed["payload"]);
                }
            }
        }

        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut client = MCPClient::new(
        "https://api.lang.dev".to_string(),
        "your-api-key".to_string()
    );

    // Connect to filesystem server
    let mut config = HashMap::new();
    config.insert("root_path".to_string(), json!("workspace/project"));

    let connection = client.connect_mcp_server("filesystem", config).await?;
    println!("Connected: {:?}", connection);

    // Start WebSocket (this will run indefinitely)
    client.start_websocket().await?;

    Ok(())
}
```

## Monitoring & Operations

### 1. Health Monitoring

```bash
#!/bin/bash
# health_check.sh

API_KEY="your-api-key"
BASE_URL="https://api.lang.dev"

# Check MCP broker health
response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $API_KEY" \
  "$BASE_URL/api/v2/mcp/health")

http_code=$(echo "$response" | tail -c 4)

if [ "$http_code" -eq 200 ]; then
    echo "✅ MCP Broker healthy"
else
    echo "❌ MCP Broker unhealthy (HTTP $http_code)"
    exit 1
fi

# Check connection pool stats
pool_stats=$(curl -s -H "Authorization: Bearer $API_KEY" \
  "$BASE_URL/api/v2/mcp/stats")

echo "Connection Pool Stats: $pool_stats"
```

### 2. Metrics Collection

```elixir
# Custom metrics for monitoring
defmodule Lang.MCP.Metrics do
  use Prometheus.Metric

  @counter [
    name: :mcp_requests_total,
    help: "Total MCP requests processed",
    labels: [:server_type, :method, :status]
  ]

  @histogram [
    name: :mcp_request_duration_seconds,
    help: "MCP request processing time",
    labels: [:server_type, :method],
    buckets: [0.01, 0.1, 0.5, 1, 5, 10, 30]
  ]

  @gauge [
    name: :mcp_active_connections,
    help: "Currently active MCP connections",
    labels: [:server_type]
  ]

  def track_request(server_type, method, duration, status) do
    Prometheus.Counter.inc(name: :mcp_requests_total,
      labels: [server_type, method, status])

    Prometheus.Histogram.observe(name: :mcp_request_duration_seconds,
      labels: [server_type, method], value: duration)
  end

  def update_connection_count(server_type, count) do
    Prometheus.Gauge.set(name: :mcp_active_connections,
      labels: [server_type], value: count)
  end
end
```

### 3. Alerting Rules

```yaml
# prometheus_alerts.yml
groups:
- name: mcp_broker
  rules:
  - alert: MCPHighErrorRate
    expr: rate(mcp_requests_total{status="error"}[5m]) > 0.1
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High MCP error rate detected"

  - alert: MCPConnectionPoolFull
    expr: mcp_active_connections >= 10
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "MCP connection pool at capacity"

  - alert: MCPSlowResponses
    expr: histogram_quantile(0.95, mcp_request_duration_seconds) > 30
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "MCP requests taking too long"
```

## Security Operations

### 1. Security Monitoring

```bash
# Monitor for security violations
tail -f /var/log/lang/security.log | grep "mcp_security_violation" | \
  jq -r '[.timestamp, .user_id, .violation_type, .details] | @csv'
```

### 2. Rate Limit Monitoring

```elixir
# Check rate limit status
rate_limit_stats = Lang.Security.RateLimiter.get_stats()

if rate_limit_stats.block_rate > 5.0 do
  Logger.warning("High rate limit block rate: #{rate_limit_stats.block_rate}%")
  # Alert operations team
end
```

### 3. Incident Response

```bash
#!/bin/bash
# incident_response.sh

# Emergency: Disable MCP broker
curl -X POST -H "Authorization: Bearer $ADMIN_API_KEY" \
  "$BASE_URL/api/admin/mcp/disable"

# View recent security events
curl -H "Authorization: Bearer $ADMIN_API_KEY" \
  "$BASE_URL/api/admin/security/events?hours=1" | \
  jq '.events[] | select(.component == "mcp_broker")'

# Check active connections
curl -H "Authorization: Bearer $ADMIN_API_KEY" \
  "$BASE_URL/api/admin/mcp/connections" | \
  jq '.connections[] | {user_id, server_type, created_at}'
```

## Troubleshooting

### Common Issues

#### 1. Connection Limit Exceeded
```
Error: "user_connection_limit_exceeded"

Solution:
1. Check user's active connections:
   GET /api/v2/mcp/user/connections

2. Disconnect unused connections:
   DELETE /api/v2/mcp/disconnect/{stream_id}

3. Consider increasing limit in config
```

#### 2. MCP Server Crashes
```
Error: "mcp_server_crashed"

Diagnosis:
1. Check logs: grep "MCP.*crashed" /var/log/lang/app.log
2. Check memory usage: ps aux | grep mcp
3. Review circuit breaker status

Solution:
1. Broker automatically restarts crashed servers
2. Circuit breaker prevents cascade failures
3. Check for resource exhaustion
```

#### 3. WebSocket Connection Failures
```
Error: WebSocket connection timeout

Diagnosis:
1. Check authentication token validity
2. Verify stream_id is active
3. Check firewall/proxy settings

Solution:
1. Refresh authentication token
2. Reconnect to MCP server if needed
3. Check WebSocket proxy configuration
```

### Debug Mode

```elixir
# Enable debug logging
config :lang, :mcp, log_level: :debug

# Or at runtime
Logger.configure(level: :debug)
```

## Performance Tuning

### 1. Connection Pool Optimization

```elixir
# Adjust pool sizes based on usage
config :lang, :mcp,
  default_pool_size: 5,        # Start with 5 connections
  max_pool_size: 20,           # Allow up to 20
  pre_warm_servers: ["filesystem", "git", "database"]
```

### 2. Timeout Tuning

```elixir
# Adjust timeouts for your workload
config :lang, :mcp,
  connection_timeout: 60_000,   # 1 minute for slow operations
  idle_timeout: 1_800_000,      # 30 minutes for long sessions
  health_check_interval: 60_000 # 1 minute health checks
```

### 3. Memory Optimization

```elixir
# Limit memory usage per connection
config :lang, :mcp,
  max_request_size: 512_000,    # 512KB if you don't need large files
  max_response_size: 5_242_880, # 5MB response limit
  max_array_length: 500         # Limit array sizes
```

## Backup & Recovery

### 1. State Backup

```bash
# Backup active session state (Redis)
redis-cli BGSAVE

# Export connection configurations
curl -H "Authorization: Bearer $API_KEY" \
  "$BASE_URL/api/admin/mcp/export" > mcp_config_backup.json
```

### 2. Disaster Recovery

```bash
# Restart MCP broker service
systemctl restart lang-mcp-broker

# Or via application
curl -X POST -H "Authorization: Bearer $ADMIN_API_KEY" \
  "$BASE_URL/api/admin/mcp/restart"

# Check recovery status
curl -H "Authorization: Bearer $API_KEY" \
  "$BASE_URL/api/v2/mcp/health"
```

## Production Checklist

### Pre-Deployment ✅

- [ ] Environment variables configured
- [ ] Rate limits set appropriately
- [ ] Monitoring alerts configured
- [ ] Security tests passed
- [ ] Load testing completed
- [ ] Backup procedures tested

### Post-Deployment ✅

- [ ] Health checks passing
- [ ] Metrics collection working
- [ ] Security monitoring active
- [ ] Connection pools healthy
- [ ] WebSocket endpoints responsive
- [ ] Rate limiting functional

### Ongoing Operations ✅

- [ ] Regular security audits
- [ ] Performance monitoring
- [ ] Capacity planning
- [ ] Incident response procedures
- [ ] Update procedures documented

---

**Support Contacts:**
- Technical Issues: engineering@lang.dev
- Security Issues: security@lang.dev
- Emergency: +1-555-LANG-911

**Documentation:**
- API Reference: https://docs.lang.dev/mcp-broker/api
- Security Guide: https://docs.lang.dev/mcp-broker/security
- Monitoring: https://docs.lang.dev/mcp-broker/monitoring
