# LANG LSP — Editor Integration Guide

This guide explains how to connect an editor or tool to the LANG Language Server (LSP) for local development and testing.

## Overview

- Server: custom Elixir LSP server (`Lang.LSP.Server`)
- Transport: TCP (default), or stdio (for editor-embedded mode)
- Default TCP port: `4001` (configurable via `LSP_PORT` env var)
- Protocol: JSON‑RPC 2.0 + LSP 3.x

Do not start `mix phx.server`. For one‑off checks use `mix run -e` (terminates after the command).

## Quick Start (Local)

1) Ensure the app boots the LSP supervisor (default in dev):

```
mix run -e "Application.ensure_all_started(:lang)"
```

2) Verify the LSP server is listening on the configured port (default 4001):

```
lsof -iTCP:4001 -sTCP:LISTEN || echo "LSP not listening on 4001"
```

3) Send a minimal LSP initialize request over TCP to sanity‑check:

```
cat > /tmp/lsp-init.json <<'JSON'
Content-Length: 182\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{},"clientInfo":{"name":"probe","version":"0.1"}}}
JSON
nc 127.0.0.1 ${LSP_PORT:-4001} < /tmp/lsp-init.json
```

You should receive an `initialize` response with server capabilities, followed by an `initialized` notification.

## Configuration

- Port: set `LSP_PORT` in your environment (`.env.local` or export):

```
export LSP_PORT=4001
```

- The LSP supervisor uses `Application.get_env(:lang, :lsp_port, 4001)`.
- The central secrets helper `Lang.Security.Secrets.lsp_port/0` also reads `LSP_PORT`.

## VS Code (extension authors)

Use the VS Code Language Client to connect via stdio or TCP. Two options:

- Stdio (spawn the app with stdio mode): implement a server command that runs your release/script in stdio mode and wire it as the language server `command`.
- TCP (simpler for dev): connect to localhost/`LSP_PORT`.

Minimal TCP client (TypeScript):

```ts
import * as net from 'net';
import { StreamMessageReader, StreamMessageWriter } from 'vscode-jsonrpc/node';
import { createMessageConnection } from 'vscode-jsonrpc';

const socket = net.connect({ host: '127.0.0.1', port: Number(process.env.LSP_PORT || 4001) });
const reader = new StreamMessageReader(socket);
const writer = new StreamMessageWriter(socket);
const connection = createMessageConnection(reader, writer);

connection.onNotification((method, params) => console.log('notif', method, params));
connection.onRequest((method, params) => console.log('req', method, params));

connection.listen();

connection.sendRequest('initialize', {
  processId: null,
  rootUri: null,
  capabilities: {},
  clientInfo: { name: 'vscode-ext', version: '0.1.0' },
}).then((result) => {
  console.log('initialized', result);
  connection.sendNotification('initialized', {});
});
```

## Neovim (nvim‑lspconfig)

You can start a TCP client via `vim.lsp.start_client` and attach to buffers.

```lua
local client_id = vim.lsp.start_client({
  name = 'lang-lsp',
  cmd = nil,            -- no stdio command
  transport = 'tcp',    -- use TCP transport
  host = '127.0.0.1',
  port = tonumber(os.getenv('LSP_PORT') or '4001'),
})
if client_id then
  vim.lsp.buf_attach_client(0, client_id)
end
```

Alternatively, wrap the above in a small custom nvim‑lspconfig.

## Emacs (lsp‑mode)

Emacs lsp‑mode supports TCP connections via a custom client.

```elisp
(require 'lsp-mode)
(lsp-register-client
 (make-lsp-client :new-connection (lsp-tcp-connection (lambda () (list "127.0.0.1" (string-to-number (or (getenv "LSP_PORT") "4001")))))
                  :major-modes '(elixir-mode heex-ts-mode)
                  :server-id 'lang-lsp))
```

Then enable with `M-x lsp` in your buffer.

## Basic LSP Flow (for tools/tests)

- initialize → server returns capabilities
- initialized (client notification)
- textDocument/didOpen → send initial text
- completion/hover/formatting/etc.

Example JSON‑RPC message headers:

```
Content-Length: <byte_length>\r\n
\r\n
{"jsonrpc":"2.0","id":1,"method":"initialize",...}
```

Ensure the `Content-Length` includes only the JSON body bytes (no headers), and lines end with `\r\n` per LSP.

## Stdio Mode (advanced)

`Lang.LSP.Server` supports stdio mode for embedding inside an editor‑spawned process. This mode is typically wired by an editor extension that launches the app with a flag and speaks LSP over the process stdio. If you need this, add a small wrapper binary that sets mode `:stdio` when starting the server process.

## Troubleshooting

- Port not listening:
  - Confirm `mix run -e "Application.ensure_all_started(:lang)"` succeeds.
  - Check `LSP_PORT` and that no other process is bound to it.
- No response to initialize:
  - Validate `Content-Length` and CRLF in headers.
  - Ensure your client sends `initialized` after `initialize` response.
- Editor doesn’t attach:
  - Verify the client actually connects to `127.0.0.1:LSP_PORT`.
  - Check logs from `Lang.LSP.Server` for connections and errors.

## Safety Notes

- Local dev only; the TCP endpoint is unauthenticated and should not be exposed publicly.
- For CI/probes, use a short‑lived `mix run -e` boot to verify LSP without running long‑lived servers.

---

For deeper internals, see:
- `lib/lang/lsp/server.ex` — TCP/stdio implementation
- `lib/lang/lsp/supervisor.ex` — LSP supervisor
- `lib/lang/lsp/dispatch.ex` — request routing to handlers

