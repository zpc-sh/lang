# Terminal Sessions Onboarding Guide

> Safe, server-mediated terminal sessions from Markdown. No direct telnet/SSH from clients. Ever.

## Overview
- Sessions are referenced from Markdown using fenced blocks with `lds:*` attributes.
- The browser UI connects via a server-hosted proxy after minting a short‑lived ticket.
- Clients (humans and agents) must treat the Markdown as metadata — never auto‑dial endpoints.

## Quickstart: Authoring a Session Fence
```
```session {lds:session=staging-shell lds:proto=ssh lds:host=staging.example.com lds:port=22 lds:user=deploy lds:fingerprint="sha256:AbCd..." lds:policy=attach lds:cap=interactive lds:connect=/api/sessions/staging-shell/connect lds:cols=100 lds:rows=28}
# Staging shell
# Use the Connect button; never connect directly from clients.
```
```
- `lds:policy=attach` enables the Connect button. Omit or set `disabled` to hide.
- Credentials are never embedded. The proxy validates host key fingerprints and org policy.

## How Connecting Works
1. User clicks Connect in the Docs UI.
2. Browser POSTs to `lds:connect` with desired `cols/rows/cap/mode`.
3. Server authenticates the user/org, validates policy, and returns:
   - `wss_url`: proxy WebSocket URL (server‑hosted)
   - `ticket`: short‑lived signed token with session claims
4. Browser opens the proxy WebSocket using the ticket and renders terminal bytes.

## Programmatic Connect (Elixir, Req)
```elixir
# Assumes a browser or API session with valid auth
connect = "/api/sessions/staging-shell/connect"
{:ok, resp} =
  Req.post!(
    base_url: "https://app.example.com",
    url: connect,
    json: %{cap: "interactive", cols: 120, rows: 32, mode: "pty", proto: "ssh"}
  )

wss_url = resp.body["wss_url"]
ticket  = resp.body["ticket"]
# Next: open wss_url and speak the session protocol. Clients MUST NOT dial SSH/Telnet directly.
```

## Prohibited Patterns
- Direct telnet/SSH from client devices (LLMs, scripts, browsers). Do not dial `host:port` from clients.
- Embedding credentials, keys, or agent forwarding in Markdown.
- Auto‑connecting on page load. Always require an explicit user action.

## Legacy Telnet (Onboarding brittle agents)
If you must automate legacy Telnet during onboarding, only use the safe, bounded adapter:
```elixir
alias Lang.Proxy.Adapters.Telnet
script = [
  {:expect, "login:"},
  {:send, "guest"},
  {:expect, ~r/Password:/},
  {:send, "guest"},
  {:expect, ~r/Welcome|Last login/}
]
Telnet.run_script("127.0.0.1", 2323, script, timeout: 2_000)
```
- Default allowlist: `127.0.0.1`, `::1`, `localhost`. Configure with `config :lang, :telnet_allowlist, ["127.0.0.1"]`.
- Hard caps on steps, timeouts, and transcript sizes. Use only in controlled environments.
- Do not expose telnet ports publicly; prefer the session proxy.

## Agent & Tooling Guidance
- Treat `session` fences as inert metadata unless you can call the server `connect` endpoint.
- Never attempt `telnet`, `ssh`, or raw TCP to `lds:host/port` from the agent environment.
- Respect `lds:policy` and `lds:cap`. If `policy != attach|trusted`, do not present a connect UI.

## Drop‑in Safety Notice (paste into docs)
> Safety: This document references live sessions via server proxy. Do not connect directly (telnet/ssh). Use the Connect button or the documented `connect` API. All activity is audited and subject to org policy.

## Troubleshooting
- Connect button disabled: ensure `lds:policy=attach` and `lds:connect=/api/sessions/<id>/connect`.
- 401/403 on connect: sign in or verify your org has access.
- No terminal view: proxy not wired yet — contact admin to enable WebSocket proxying.

## Security Checklist
- [ ] No credentials in Markdown
- [ ] Host key fingerprint pinned (`lds:fingerprint` for SSH)
- [ ] Resource limits set server‑side (idle timeout, bandwidth caps)
- [ ] Audit start/stop events recorded
- [ ] Telnet disabled in production; proxy only

*** End of Guide



## RIO WASM Terminal (Browser Renderer)

- Preferred renderer: RIO (120fps, SIXEL). Add RIO artifacts to `priv/static/vendor/rio/`:
  - `priv/static/vendor/rio/rio.js`
  - RIO’s accompanying `.wasm` and data files (same directory)
- Session fences can request RIO explicitly: `lds:renderer=rio`
- The docs UI loads `/vendor/rio/rio.js` and initializes a terminal with `{sixel: true}`; it streams bytes from the server WS and forwards keyboard input.

If RIO is unavailable, the UI falls back to a minimal preformatted output log.

## Server Policy & Limits

- SSH host key pinning is enforced via known_hosts (no TOFU). Configure:
  - `config :lang, :ssh_user_dir, "/app/ssh"` # contains `known_hosts`
  - Provide pinned SSH host key fingerprints in docs (`lds:fingerprint="sha256:..."`) and provision matching entries in known_hosts.
- Session limits (configurable):
  - `config :lang, :session_proxy, idle_timeout_ms: 600_000, bandwidth_limit_bytes: 50_000_000`
  - Idle timeout triggers automatic disconnect; bandwidth cap protects the system.
