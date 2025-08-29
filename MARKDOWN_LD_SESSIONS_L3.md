# Markdown‑LD — Embedded Sessions (L3 Optional)

Status: Optional extension for referencing live, authenticated sessions (SSH, Unix socket, or proxied WebSocket) from Markdown so renderers can attach and present a terminal/TUI/application view. The Markdown carries only metadata and policy. All execution and authentication happen server‑side. No secrets are embedded.

## 1. Goals

- Reference a session endpoint (SSH/Unix/WS) from Markdown.
- Allow UI to render a terminal/TUI for that session via a server‑mediated, authenticated connection.
- Keep the document safe: no credentials in Markdown; everything is opt‑in, server‑only.
- Make session refs diffable and portable across repos.

## 2. Session Blocks

- Fence language: `session` (opaque payload; attributes drive behavior).
- Required attributes:
  - `lds:session=<id>` — stable session id (unique within document).
  - `lds:proto=ssh|unix|ws` — protocol family.
  - `lds:policy=disabled|attach|trusted` — default `disabled`.
- Optional attributes (by proto):
  - Common: `lds:title=...`, `lds:cap=interactive|read-only` (default `interactive`), `lds:cols=<int>`, `lds:rows=<int>`.
  - SSH: `lds:host=example.com`, `lds:port=22`, `lds:user=deploy`, `lds:fingerprint=sha256:...` (server pins SSH host key). Credentials are never embedded.
  - Unix: `lds:path=/var/run/app.sock` (server‑local; only usable via server proxy).
  - WS: `lds:url=wss://backend.example.com/socket` (server will still mint tickets; client never connects directly unless policy permits).
  - Connect endpoint: `lds:connect=/api/sessions/{id}/connect` (server route to mint a short‑lived ticket/JWS and return the proxy URL).
  - Rendering hint: `lds:mode=pty|raw|app` — `pty` wraps with a PTY for terminals; `raw` is byte stream; `app` signals a custom TUI/application.

Example (SSH)
```session {lds:session=sess-1 lds:proto=ssh lds:host=staging.example.com lds:port=22 lds:user=deploy lds:fingerprint=sha256:AbCd... lds:policy=attach lds:cap=interactive lds:connect=/api/sessions/sess-1/connect lds:cols=100 lds:rows=28}
# Staging shell (no credentials stored here)
# Connect via server to show terminal/TUI.
```

Example (Unix socket via server proxy)
```session {lds:session=app-ui lds:proto=unix lds:path=/var/run/app/ui.sock lds:policy=attach lds:mode=app lds:connect=/api/sessions/app-ui/connect}
# Interactive TUI exposed over a Unix socket (server-local).
```

Example (Proxied WS)
```session {lds:session=debug-1 lds:proto=ws lds:url=wss://svc.internal:7443/tty lds:policy=attach lds:mode=pty lds:connect=/api/sessions/debug-1/connect}
# PTY over an internal WebSocket (proxied by server).
```

## 3. Connect Flow (Server‑only)

- Client never dials SSH/Unix/WS endpoints directly.
- UI POSTs to `lds:connect` with the document’s session id and desired caps (`cols/rows`, `cap`).
- Server authenticates the user/org, validates policy, and returns:
  - `wss_url`: the server‑hosted proxy WebSocket (e.g., `wss://app.example.com/attach/:ticket`)
  - `ticket`: short‑lived signed token (JWS/COSE) with claims: `sub`, `org`, `session_id`, `proto`, `cap`, `exp`, `nonce`, and per‑proto params (e.g., `host`, `port`, `user`, `path`).
  - `provenance`: `{ runner: "ssh-proxy", version: "1.4.2", container_digest: "sha256:..." }`
- UI opens the `wss_url` with `Sec-WebSocket-Protocol: mdld.sess.v1` and `Authorization: Bearer <ticket>` (or as query param if required).
- Initial client message (JSON):
  - `{"type":"hello","cols":..., "rows":..., "mode":"pty|raw|app"}`
- Proxy starts the upstream (SSH/Unix/WS), forwards bytes; resize with `{"type":"resize","cols":...,"rows":...}`.

Note: Message framing is transport‑specific on the proxy (binary payload streaming with small JSON control messages is recommended). This spec does not mandate a single wire format; only the handshake fields.

## 4. Security & Policy

- No credentials in Markdown. Never embed passwords, keys, tokens, or agent forwarding directives.
- SSH: require `lds:fingerprint` and pin host key on the proxy; TOFU is not permitted by default.
- Unix: `lds:path` is server‑local; proxy enforces allowlist.
- WS: even with a `lds:url`, client SHOULD use server proxy with minted tickets, unless org policy explicitly allows direct (trusted) connections.
- Default `lds:policy=disabled`; connections require explicit user action and server approval.
- Capabilities:
  - `read-only`: proxy discards client input (view‑only).
  - `interactive`: enable bidirectional I/O.
- Resource limits: enforce idle timeout, max duration, max bandwidth; audit session start/stop.

## 5. Attestation (Optional but Recommended)

- The server MAY emit an adjacent attestation JSON block for provenance and policy.
```json {lds:attestation-for=sess-1}
{"session_id":"sess-1","proto":"ssh","host":"staging.example.com","port":22,"user":"deploy","fingerprint":"sha256:AbCd...","cap":"interactive","runner":"ssh-proxy","version":"1.4.2","container_digest":"sha256:...","ts":"2025-08-28T12:34:56Z","sig_alg":"ed25519","signature":"base64..."}
```
- Clients MAY require valid signature and field consistency before enabling “Connect”.

## 6. Rendering Guidance (UI)

- Show a “Connect” button for `lds:policy=attach|trusted`.
- On connect, negotiate PTY size from `lds:cols/rows` (fall back to UI size).
- Terminal renderer for `mode=pty`; pass bytes raw; handle ANSI.
- For `mode=app`, allow a custom app renderer (inclusive protocol). If unknown, fall back to terminal.
- Never auto‑connect on page load; user must explicitly click/connect.

## 7. Diff & Merge

- Session blocks are inert metadata; diffs are standard block updates.
- Changing `lds:fingerprint` or endpoint is a significant change; consider highlighting in UI.
- No outputs are embedded by default (live sessions); recordings (casts) may be included via terminal extension if desired.

## 8. Compliance

- L3 (this doc): recognize `session` fences with `lds:*` attributes; implement server‑mediated connect flow.
- L2/L1: treat session fences as inert code blocks.

*** End of File
