# LSP Auth Transport Profile (LATP)

- Goal: optional, transport-level auth for LSP without changing JSON-RPC methods.
- Ticket: JWT (RS256 preferred). Claims: sub, org, scope:"lsp_ws", exp≤300s, jti, cid, (ctx?).

WebSocket
- Preferred: Sec-WebSocket-Protocol: `lsp, jwt.<token>`
- Fallback: `?ticket=<jwt>` query param
- Server: verify signature/exp/scope; on fail 401 (or JSON-RPC -32001 if already WS)

Non-WS (optional profile)
- Place token at `initialize.initializationOptions.auth.token`
- On invalid: JSON-RPC error -32001, abort initialize

Errors (JSON-RPC)
- -32001 Unauthorized, -32003 Forbidden, -32029 Rate limited

Server hints (optional)
- `initializeResult.serverInfo.auth = { transport: ["websocket"], scheme: "jwt", scope: "lsp_ws", cid?: "..." }`

Security
- Always TLS (wss). TTL ≤ 5m. Prefer RS256 + JWK for edge verify. Redact tokens in logs.

Implementation notes
- Mint: POST /api/v2/lsp/connect (auth required) → { wss_url, ticket, ttl, cid }
- Attach: GET /ws/lsp?ticket=... → proxy to 127.0.0.1:4001
- Billing gate at mint; track events
