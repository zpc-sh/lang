#!/bin/bash
# Test basic LSP connection
(
  echo -e "Content-Length: 95\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"rpc.initialize\",\"params\":{\"client\":{\"name\":\"claude-test\"}}}"
  sleep 2
) | nc localhost 4001 | head -10
