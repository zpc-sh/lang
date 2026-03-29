# MCP Implementation Documentation

## Overview

This document provides comprehensive documentation for the Multi-Connection Protocol (MCP) implementation in the LANG project. The MCP system enables secure, scalable agent coordination through dynamic LSP forwarding with Client_ID enforcement.

## Architecture

### Core Components

1. **Proxy Router** (`lib/lang/proxy/router.ex`)
   - Entry point for MCP service calls
   - Client_ID validation and enforcement
   - Dispatch to appropriate MCP handlers

2. **Connection Manager** (`lib/lang/mcp/connection_manager.ex`)
   - MCP connection lifecycle management
   - Ash resource integration for persistence
   - Server type inference and configuration

3. **Stream Bridge** (`lib/lang/mcp/stream_bridge.ex`)
   - GenServer-based session management
   - Secure streaming with Client_ID validation
   - Real-time data streaming and multiplexing

4. **Ash Resources**
   - `Lang.MCP.Connection` - Connection tracking and metadata
   - `Lang.Agent.Swarm` - Agent swarm orchestration
   - `Lang.Events.*` - Event tracking and auditing

5. **Background Workers** (Oban)
   - `Lang.Workers.McpLifecycleWorker` - Connection maintenance
   - `Lang.Workers.AgentSwarmWorker` - Swarm provisioning

## Key Features

### Security & Access Control

- **Client_ID Enforcement**: All MCP operations require a valid Client_ID
- **Format Validation**: Client_ID must match `[a-zA-Z0-9_-]{10,64}` pattern
- **Connection Ownership**: Users can only access their own connections
- **Authorization Checks**: Rate limiting, permissions, and scope validation

### Scalability

- **GenServer Sessions**: Thread-safe session management
- **Ash Persistence**: ACID-compliant connection tracking
- **Background Processing**: Oban-based async operations
- **Connection Pooling**: Efficient resource utilization

### Event-Driven Architecture

- **AshEvents Integration**: Comprehensive event tracking
- **Real-time Notifications**: Phoenix PubSub broadcasting
- **Audit Trail**: Complete lifecycle logging
- **Monitoring**: Performance metrics and health checks

## API Reference

### Proxy Router MCP Methods

#### `connection.create`
Creates a new MCP connection with Client_ID validation.

**Parameters:**
```json
{
  "service": "mcp",
  "method": "connection.create",
  "params": {
    "url": "file:///path/to/resource",
    "server_type": "filesystem",
    "connection_params": {...}
  },
  "opts": {
    "client_id": "client_12345",
    "user_id": "user_123",
    "session_id": "session_456"
  }
}
```

**Response:**
```json
{
  "connection_id": "mcp_conn_abc123",
  "status": "connecting",
  "server_type": "filesystem"
}
```

#### `connection.destroy`
Destroys an existing MCP connection.

**Parameters:**
```json
{
  "service": "mcp",
  "method": "connection.destroy",
  "params": {
    "connection_id": "mcp_conn_abc123"
  },
  "opts": {
    "client_id": "client_12345"
  }
}
```

#### `connection.status`
Retrieves connection status and metadata.

**Parameters:**
```json
{
  "service": "mcp",
  "method": "connection.status",
  "params": {
    "connection_id": "mcp_conn_abc123"
  }
}
```

### LSP Agent Swarm Methods

#### `lang.agent.swarm_create`
Creates a new agent swarm with shared goals.

**Parameters:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "lang.agent.swarm_create",
  "params": {
    "goals": ["code analysis", "documentation"],
    "agent_count": 5,
    "coordinator_id": "coord_123"
  }
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "swarm_id": "swarm_abc123",
    "agent_ids": ["agent_1", "agent_2", "agent_3", "agent_4", "agent_5"],
    "status": "created"
  }
}
```

## Usage Examples

### Basic MCP Connection

```elixir
# Create connection via proxy router
envelope = %Lang.Proxy.Envelope{
  service: :mcp,
  method: "connection.create",
  params: %{
    "url" => "file:///tmp/workspace",
    "server_type" => "filesystem"
  },
  opts: %{
    "client_id" => "my_client_12345",
    "user_id" => "user_123"
  }
}

case Lang.Proxy.Router.dispatch(envelope) do
  {:ok, result} ->
    connection_id = result["connection_id"]
    IO.puts("Connection created: #{connection_id}")

  {:error, code, message, _} ->
    IO.puts("Connection failed: #{message}")
end
```

### Stream Creation with Validation

```elixir
# Create streaming session
case Lang.MCP.StreamBridge.create_stream(
  connection_id,
  "user_123",
  "session_456",
  %{"client_id" => "my_client_12345"}
) do
  {:ok, stream_id} ->
    IO.puts("Stream created: #{stream_id}")

    # Send streaming request
    Lang.MCP.StreamBridge.stream_mcp_request(
      stream_id,
      %{"method" => "list_directory", "params" => %{"path" => "/tmp"}}
    )

  {:error, {:client_id_invalid, reason}} ->
    IO.puts("Client_ID validation failed: #{reason}")
end
```

### Agent Swarm Orchestration

```elixir
# Create agent swarm via LSP
swarm_msg = %{
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "lang.agent.swarm_create",
  "params" => %{
    "goals" => ["analyze codebase", "generate docs"],
    "agent_count" => 3,
    "coordinator_id" => "main_coord"
  }
}

case Lang.LSP.Dispatch.process(swarm_msg) do
  {:ok, %{"result" => result}} ->
    swarm_id = result["swarm_id"]
    IO.puts("Swarm created: #{swarm_id}")

  {:error, reason} ->
    IO.puts("Swarm creation failed: #{reason}")
end
```

## Testing and Verification

### Test Commands

```bash
# Run comprehensive MCP integration tests
mix test test/mcp_integration_test.exs

# Run basic MCP harness test
mix mcp.harness

# Test with client flux simulation
mix mcp.harness --clients=10 --flux --duration=60

# Monitor MCP activity in real-time
mix mcp.harness --monitor

# Test agent swarm workflows
mix mcp.harness --swarm-test --agents=5

# Stress test with concurrent clients
mix mcp.harness --stress --clients=20 --duration=120
```

### Verification Scenarios

#### 1. Client Flux Without Crashes
- **Objective**: Ensure system handles rapid client connect/disconnect cycles
- **Test**: 50 concurrent clients with random connect/disconnect patterns
- **Expected**: No crashes, proper resource cleanup, accurate event tracking

#### 2. Client_ID Security Enforcement
- **Objective**: Verify Client_ID validation prevents unauthorized access
- **Test**: Attempt operations without Client_ID, with invalid format, mismatched ownership
- **Expected**: All invalid attempts rejected with appropriate error codes

#### 3. Agent Swarm Coordination
- **Objective**: Test full swarm creation and coordination workflow
- **Test**: Create swarms of varying sizes with different goals
- **Expected**: Successful swarm creation, proper Ash record persistence, event logging

#### 4. Concurrent Load Handling
- **Objective**: Verify system performance under load
- **Test**: 100+ concurrent MCP operations with streaming
- **Expected**: Stable performance, proper queuing, no resource leaks

## Configuration

### Environment Variables

```bash
# MCP Connection Settings
MCP_MAX_CONNECTIONS_PER_USER=10
MCP_CONNECTION_TIMEOUT=30000
MCP_STREAM_CHUNK_SIZE=65536

# Client_ID Validation
MCP_CLIENT_ID_MIN_LENGTH=10
MCP_CLIENT_ID_MAX_LENGTH=64
MCP_CLIENT_ID_PATTERN="^[a-zA-Z0-9_-]+$"

# Background Processing
MCP_WORKER_QUEUE_SIZE=1000
MCP_HEALTH_CHECK_INTERVAL=300000
```

### Ash Configuration

```elixir
# config/config.exs
config :lang, Lang.MCP,
  max_connections_per_user: 10,
  connection_timeout_ms: 30000,
  enable_circuit_breaker: true,
  health_check_interval_ms: 300_000
```

## Monitoring and Observability

### Event Types

The system tracks the following MCP-related events:

- `mcp_connection_created` - New connection established
- `mcp_connection_destroyed` - Connection terminated
- `mcp_client_connected` - Client session started
- `mcp_client_disconnected` - Client session ended
- `mcp_stream_created` - Streaming session initiated
- `mcp_stream_completed` - Streaming session finished
- `mcp_stream_error` - Streaming error occurred
- `agent_swarm_created` - Agent swarm provisioned
- `agent_swarm_provision` - Background swarm provisioning

### Metrics

Key metrics tracked:

- Active connections per user
- Connection success/failure rates
- Stream throughput and latency
- Client_ID validation success rate
- Background job queue depth
- Ash resource usage statistics

### Logging

Structured logging includes:

```elixir
Logger.info("MCP connection created",
  connection_id: "mcp_conn_abc123",
  client_id: "client_12345",
  user_id: "user_123",
  server_type: "filesystem"
)

Logger.warning("Client_ID validation failed",
  client_id: "invalid",
  reason: "format_invalid",
  operation: "connection.create"
)
```

## Troubleshooting

### Common Issues

#### Client_ID Validation Errors
- **Symptom**: Operations fail with "Invalid client ID" errors
- **Cause**: Missing or malformed Client_ID
- **Solution**: Ensure Client_ID is provided and matches required format

#### Connection Creation Failures
- **Symptom**: Connection creation returns error
- **Cause**: Invalid parameters, resource limits, or server issues
- **Solution**: Check parameters, verify server availability, check resource quotas

#### Stream Timeouts
- **Symptom**: Streaming operations timeout
- **Cause**: Network issues, server overload, or configuration
- **Solution**: Increase timeouts, check network connectivity, monitor server load

#### Ash Resource Errors
- **Symptom**: Database-related errors in logs
- **Cause**: Connection issues, schema mismatches, or resource constraints
- **Solution**: Verify database connectivity, check migrations, monitor resource usage

### Debug Commands

```bash
# Check MCP connection status
Lang.MCP.ConnectionManager.get_connection_status("mcp_conn_abc123")

# View active streams
Lang.MCP.StreamBridge.get_stats()

# Query Ash resources
Lang.MCP.Connection
|> Ash.Query.for_read(:by_user, %{user_id: "user_123"})
|> Ash.read()

# Check event logs
Lang.Events.ApiUsageEvent
|> Ash.Query.filter(event_type == "mcp_connection_created")
|> Ash.read()
```

## Future Enhancements

### Planned Features

1. **Advanced Load Balancing**
   - Multi-server connection distribution
   - Geographic routing optimization
   - Predictive scaling based on usage patterns

2. **Enhanced Security**
   - JWT-based Client_ID validation
   - OAuth 2.0 integration
   - Fine-grained permission systems

3. **Performance Optimizations**
   - Connection pooling improvements
   - Streaming compression
   - Caching layer for metadata

4. **Monitoring Enhancements**
   - Real-time dashboards
   - Alerting system integration
   - Performance profiling tools

5. **Protocol Extensions**
   - WebSocket streaming support
   - Binary protocol options
   - Custom serialization formats

## Contributing

When extending the MCP implementation:

1. **Maintain Client_ID Enforcement**: All new MCP operations must validate Client_ID
2. **Follow Ash Patterns**: Use proper Ash resources and actions for data operations
3. **Add Event Tracking**: Include appropriate event logging for monitoring
4. **Update Tests**: Extend test coverage for new functionality
5. **Document Changes**: Update this documentation with new features

## Support

For issues or questions regarding the MCP implementation:

1. Check the troubleshooting section above
2. Review test output for error details
3. Examine event logs for diagnostic information
4. Consult the codebase for implementation examples

---

*This documentation is automatically generated from the MCP implementation codebase. Last updated: #{DateTime.utc_now() |> DateTime.to_iso8601()}*