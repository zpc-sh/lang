# LANG LSP Debug Harness

A comprehensive debugging environment for the LANG LSP server with real-time monitoring, collaborative debugging, and multi-client testing capabilities.

## 🚀 Quick Start

The simplest way to get started is with the unified startup script:

```bash
# Start basic debug environment (LSP server + debug stream)
./scripts/start_lsp_debug.sh quick

# Start full environment with WebSocket monitoring and dashboard
./scripts/start_lsp_debug.sh full

# Start interactive test client
./scripts/start_lsp_debug.sh client
```

## 📁 Debug Harness Components

### 1. Enhanced Zed Configuration (`.zed/settings.json`)

Your Zed editor is already configured with:
- Connection to LANG LSP server via TCP-STDIO bridge (`127.0.0.1:4001`)
- Comprehensive LSP feature support (completion, hover, diagnostics, etc.)
- Debug-friendly settings with verbose logging
- Enhanced UI with diagnostic highlighting

**Usage**: Simply open your project in Zed and the LSP will connect automatically.

### 2. Main Debug Harness (`scripts/lsp_debug_harness.sh`)

A comprehensive shell-based debug harness with:
- LSP server management
- Multi-client simulation
- Real-time debug streaming
- Performance monitoring
- Log aggregation

```bash
# Start LSP server with debug streaming
./scripts/lsp_debug_harness.sh --mode server --save-logs

# Run test clients against existing server
./scripts/lsp_debug_harness.sh --mode client --clients 5

# Interactive mode with menu
./scripts/lsp_debug_harness.sh --interactive
```

**Features**:
- **Server Mode**: Starts LSP server with debug output streaming
- **Client Mode**: Runs multiple test clients for load testing
- **Monitor Mode**: Monitors existing LSP server
- **Interactive Mode**: Menu-driven interface for manual testing

### 3. WebSocket Debug Monitor (`scripts/lsp_websocket_debug.exs`)

An Elixir-based WebSocket server providing:
- Real-time LSP message streaming
- Web dashboard for monitoring
- Multi-client test simulation
- Performance metrics collection

```bash
# Start WebSocket monitor with dashboard
./scripts/lsp_websocket_debug.exs --lsp-port 4001 --ws-port 4003 --http-port 4004
```

**Connections**:
- **Dashboard**: `http://127.0.0.1:4004/`
- **WebSocket**: `ws://127.0.0.1:4003/debug`
- **Health Check**: `http://127.0.0.1:4004/health`
- **Metrics API**: `http://127.0.0.1:4004/api/metrics`

### 4. Interactive Test Client (`scripts/lsp_test_client.exs`)

A simple Elixir-based LSP client for testing:
- Interactive menu for manual testing
- Predefined test scenarios
- Custom request/notification support
- Real-time message display

```bash
# Interactive mode
./scripts/lsp_test_client.exs --interactive

# Run specific scenario
./scripts/lsp_test_client.exs --scenario completion
```

## 🔧 Usage Scenarios

### Scenario 1: Basic Development Debugging

For day-to-day development with LSP debugging:

```bash
# Terminal 1: Start LSP server with debug stream
./scripts/start_lsp_debug.sh quick

# Terminal 2: Connect to debug stream
nc 127.0.0.1 4002

# Use Zed editor normally - all LSP traffic will be visible in Terminal 2
```

### Scenario 2: Comprehensive Debugging Session

For in-depth debugging with full monitoring:

```bash
# Start full environment
./scripts/start_lsp_debug.sh full

# Opens:
# - LSP server on 127.0.0.1:4001
# - Debug stream on 127.0.0.1:4002  
# - WebSocket on 127.0.0.1:4003
# - Dashboard at http://127.0.0.1:4004/
```

Then:
1. Open the dashboard in your browser: `http://127.0.0.1:4004/`
2. Use Zed editor for LSP interactions
3. Watch real-time debugging in the dashboard
4. Connect additional debug clients via WebSocket

### Scenario 3: Collaborative Debugging

Multiple developers can connect to the same debug session:

```bash
# Developer 1: Start the debug environment
./scripts/start_lsp_debug.sh full

# Developer 2-N: Connect to WebSocket debug stream
websocat ws://127.0.0.1:4003/debug
# OR use the web dashboard at http://127.0.0.1:4004/
```

### Scenario 4: Load Testing

Test the LSP server under load:

```bash
# Terminal 1: Start LSP server
./scripts/start_lsp_debug.sh quick

# Terminal 2: Run multiple test clients
./scripts/lsp_debug_harness.sh --mode client --clients 10 --iterations 20

# Terminal 3: Monitor performance
./scripts/lsp_debug_harness.sh --mode monitor
```

## 🔌 Connection Methods

### TCP Debug Stream

Connect with any TCP client:
```bash
# netcat
nc 127.0.0.1 4002

# telnet  
telnet 127.0.0.1 4002

# socat
socat - TCP:127.0.0.1:4002
```

### WebSocket Debug Stream

Connect with WebSocket clients:
```bash
# websocat
websocat ws://127.0.0.1:4003/debug

# wscat
wscat -c ws://127.0.0.1:4003/debug
```

### HTTP Dashboard

Access via web browser:
- **Main Dashboard**: `http://127.0.0.1:4004/`
- **Health Check**: `http://127.0.0.1:4004/health`
- **Metrics API**: `http://127.0.0.1:4004/api/metrics`

```bash
# Get metrics via curl
curl http://127.0.0.1:4004/api/metrics | jq
```

## 📊 Debug Information Available

### LSP Message Flow
- **Request/Response pairs** with timing information
- **Notification messages** (didOpen, didChange, etc.)
- **Error messages** with stack traces
- **Method-specific data** (completions, diagnostics, etc.)

### Performance Metrics
- **Response times** for each LSP method
- **Client connection counts**
- **Message throughput** (messages/second)
- **Memory usage** and process statistics
- **Error rates** and failure patterns

### Server State
- **Active connections** and client information
- **Document state** (open files, versions)
- **Capabilities** negotiated with clients
- **Configuration** and initialization parameters

## ⚙️ Configuration

### Environment Variables

```bash
export LSP_PORT=4001          # LSP server port
export DEBUG_PORT=4002        # Debug stream port  
export WS_PORT=4003           # WebSocket server port
export HTTP_PORT=4004         # HTTP dashboard port
export LSP_DEBUG=1            # Enable LSP debug mode
export LANG_DEBUG=1           # Enable LANG debug mode
export MIX_ENV=dev            # Mix environment
```

### Debug Levels

Control verbosity with log levels:
- `debug`: Full verbose output
- `info`: Standard operational messages  
- `warn`: Warnings and errors only

### Zed Editor Configuration

Your `.zed/settings.json` includes:
- LSP server connection via TCP-STDIO bridge
- Enhanced debugging settings
- Diagnostic highlighting
- Auto-formatting configuration

## 🔍 Advanced Usage

### Custom LSP Methods

Test LANG-specific LSP methods:
```bash
./scripts/lsp_test_client.exs --interactive

# Then use option 5 to test:
# - lang/fs/list       - List filesystem contents
# - lang/fs/read       - Read file contents  
# - lang/fs/search     - Search in files
# - lang/insights/list - List code insights
# - lang/ml/code_quality - Analyze code quality
```

### WebSocket API

Send custom commands via WebSocket:
```javascript
// Connect to WebSocket
const ws = new WebSocket('ws://127.0.0.1:4003/debug');

// Send ping
ws.send(JSON.stringify({ type: 'ping' }));

// Start test client
ws.send(JSON.stringify({ 
  type: 'start_test_client', 
  config: { lsp_port: 4001 } 
}));
```

### Log Aggregation

When using `--save-logs`, logs are saved to:
```
tmp/lsp_debug/TIMESTAMP_lsp_server.log
tmp/lsp_debug/TIMESTAMP_debug_stream.log  
tmp/lsp_debug/TIMESTAMP_client_N.log
tmp/lsp_debug/TIMESTAMP_monitor.log
```

## 🚨 Troubleshooting

### LSP Server Won't Start

```bash
# Check port availability
nc -z 127.0.0.1 4001 && echo "Port in use" || echo "Port available"

# Check Mix environment
mix compile

# Start with verbose logging
LSP_DEBUG=1 LANG_DEBUG=1 ./scripts/start_lsp_debug.sh quick
```

### Zed Not Connecting

1. Check that the TCP-STDIO bridge script exists:
   ```bash
   ls -la scripts/lsp/lang_tcp_stdio_bridge.js
   ```

2. Test the bridge manually:
   ```bash
   node scripts/lsp/lang_tcp_stdio_bridge.js --host 127.0.0.1 --port 4001
   ```

3. Check Zed logs (usually in `~/.local/share/zed/logs/`)

### WebSocket Issues

```bash
# Test WebSocket connection
websocat ws://127.0.0.1:4003/debug

# Check if port is listening
ss -tulpn | grep :4003
```

### Performance Issues

1. **Reduce client count** for testing:
   ```bash
   ./scripts/start_lsp_debug.sh full  # Uses 2 clients by default
   ```

2. **Monitor system resources**:
   ```bash
   htop  # or top
   ```

3. **Check debug logs** for error patterns

## 📝 Contributing to Debug Harness

### Adding New Debug Features

1. **For shell-based features**: Extend `lsp_debug_harness.sh`
2. **For WebSocket features**: Extend `lsp_websocket_debug.exs`
3. **For Zed features**: Update `.zed/settings.json`

### Debug Data Format

Debug messages follow this structure:
```json
{
  "type": "lsp_message",
  "direction": "sent|received",
  "message": { /* LSP message */ },
  "timestamp": "2024-01-01T12:00:00.000Z",
  "session_id": "abc123",
  "client_id": "client_1"
}
```

### Testing Changes

Always test with multiple scenarios:
```bash
# Test basic functionality
./scripts/start_lsp_debug.sh quick

# Test full environment  
./scripts/start_lsp_debug.sh full

# Test with multiple clients
./scripts/lsp_debug_harness.sh --mode client --clients 3

# Test interactive client
./scripts/start_lsp_debug.sh client
```

## 🎯 Tips for Effective Debugging

1. **Start Simple**: Use `quick` mode for basic debugging
2. **Use Dashboard**: The web dashboard provides the best overview
3. **Filter Noise**: Use log levels to reduce verbose output
4. **Monitor Performance**: Watch response times for performance issues
5. **Save Logs**: Use `--save-logs` for post-session analysis
6. **Test Scenarios**: Use predefined scenarios for consistent testing
7. **Collaborative Debug**: Share WebSocket URL for team debugging

## 🔗 Related Documentation

- **Main Project**: See `AGENTS.md` for project guidelines
- **LSP Implementation**: Check `lib/lang/lsp/` for server code
- **Native Operations**: See native NIFs in `native/` directory
- **Testing**: Standard test suite in `test/`

---

**Happy Debugging!** 🐛✨

The debug harness is designed to make LSP development and troubleshooting as smooth as possible. If you encounter issues or have suggestions for improvements, please contribute back to the harness.