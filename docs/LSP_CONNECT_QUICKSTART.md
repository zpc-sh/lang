# LSP Connect Quickstart

A minimal, reliable path to get agents connecting to the LANG LSP server for the first time.

## 1) Start a time‑limited LSP server

Use the harness to boot only the LSP TCP server (no Phoenix), wait for the port, and sanity‑check initialize. It exits automatically after the duration.

```bash
LSP_PORT=4001 LSP_DURATION_SECONDS=900 ./scripts/lsp_harness.sh
```

Notes:
- Default host: `127.0.0.1`; default port: `4001`.
- Logs: `/tmp/lang_lsp.out` (stdout), `/tmp/lang_lsp.err` (stderr).
- CI: run the harness in a background job for smoke tests.

## 2) Diagnose connectivity

Run the one‑shot doctor. It checks TCP connect, LSP initialize, `rpc.ping`, and a tiny `lang.fs.scan`.

```bash
mix lsp.doctor
# Options: --host 127.0.0.1 --port 4001 --no-fs
```

If a step fails, the task prints hints (port, firewall, framing, logs) to get you unblocked quickly.

### Local smoke (one‑liner)

Start the LSP server in-process and run the doctor in one step:

```bash
mix lsp.smoke --port 4001
```

## 3) Quick calls

Use built‑in tasks to exercise the server.

```bash
mix lsp.ping
mix lsp.call rpc.initialize --json '{}'
mix lsp.call lang.fs.scan --json '{"path":".","max_depth":0}'
```

Flags/environment:
- `LSP_HOST`, `LSP_PORT` or `--host/--port` point tasks at a different server.

## 4) Agent basics (client implementers)

- Connect TCP to `LSP_HOST:LSP_PORT` with JSON‑RPC LSP framing (CRLF + `Content-Length` header).
- Send `initialize`, then send `initialized` (notification).
- Call methods like `rpc.ping` and `lang.*` as needed.
- Keep the socket open; reuse the connection for multiple requests.

## 5) Troubleshooting

- Connection refused: server not running or wrong port → start harness; verify `LSP_PORT`.
- Timeouts: firewall/NAT/port‑forwarding issues → allow inbound to the port.
- Initialize errors: verify CRLF and `Content-Length` framing; send `initialized` after `initialize`.
- Check logs: `/tmp/lang_lsp.err` and app logs.

## Related

- `scripts/lsp_harness.sh` – LSP‑only server launcher
- `mix lsp.doctor` – end‑to‑end check
- `mix lsp.ping`, `mix lsp.call` – quick invocations
