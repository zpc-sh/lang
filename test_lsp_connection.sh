#!/usr/bin/env bash
set -euo pipefail

# Simple LSP Connection Test
# Tests basic connectivity to the LANG LSP server
#
# Usage:
#   ./test_lsp_connection.sh [host] [port]

HOST="${1:-127.0.0.1}"
PORT="${2:-4001}"

echo "🚀 Testing LANG LSP Connection"
echo "Target: $HOST:$PORT"
echo ""

# Check if netcat is available
if ! command -v nc >/dev/null 2>&1; then
    echo "❌ netcat (nc) is required but not installed"
    exit 1
fi

# Check if port is listening
echo -n "Checking if port $PORT is open..."
if nc -z "$HOST" "$PORT" 2>/dev/null; then
    echo " ✅ Port is open"
else
    echo " ❌ Port is not open"
    echo ""
    echo "💡 To start the LSP server, run:"
    echo "   ./scripts/start_lsp_debug.sh quick"
    exit 1
fi

# Create LSP initialize request
INIT_REQUEST='{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "processId": null,
        "rootUri": "file:///tmp/test",
        "capabilities": {
            "textDocument": {
                "completion": {
                    "completionItem": {
                        "snippetSupport": true
                    }
                }
            }
        },
        "clientInfo": {
            "name": "test-client",
            "version": "1.0.0"
        }
    }
}'

# Calculate content length
CONTENT_LENGTH=$(echo -n "$INIT_REQUEST" | wc -c | tr -d ' ')

# Create full LSP message with Content-Length header
LSP_MESSAGE="Content-Length: $CONTENT_LENGTH\r\n\r\n$INIT_REQUEST"

echo "Sending LSP initialize request..."
echo "Request: $INIT_REQUEST"
echo ""

# Send request and capture response
echo "Response:"
if echo -e "$LSP_MESSAGE" | timeout 5 nc "$HOST" "$PORT"; then
    echo ""
    echo "✅ LSP server responded successfully!"
else
    echo ""
    echo "❌ No response from LSP server or timeout"
    exit 1
fi

echo ""
echo "🎉 LSP connection test completed"
echo ""
echo "💡 Next steps:"
echo "   1. Configure your editor to connect to $HOST:$PORT"
echo "   2. For Zed, your .zed/settings.json is already configured"
echo "   3. For debugging: nc $HOST 4002 (if debug stream is running)"
echo "   4. For monitoring: ./scripts/start_lsp_debug.sh full"