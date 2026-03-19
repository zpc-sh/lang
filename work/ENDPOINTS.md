Endpoints

- POST /api/v2/lsp/connect (auth: API key/OAuth)
  - Returns: { wss_url, ticket, ttl, cid }
  - ticket: JWT RS256, claims: sub, org, scope:"lsp_ws", exp≤300s, jti, cid, (optional ctx)
  - Errors: 401/403 -> JSON {error}, 402/429 on billing -> {error,retry_after}

- GET /ws/lsp?ticket=<jwt>
  - Accept also: Sec-WebSocket-Protocol: lsp, jwt.<token>
  - Verifies JWT (sig, exp, scope), proxies to 127.0.0.1:4001
  - On failure: 401 on upgrade; if WS, send JSON-RPC -32001

- POST /api/v2/lsp/preflight
  - Returns: { auth_ok, billing_ok, next_steps }

JWT
- RS256 preferred (publish JWK); HS256 acceptable if no edge verify
- Claims: sub, org, scope, exp, iat, nbf?, jti, cid, ctx?

Errors (JSON-RPC)
- Unauthorized: code -32001, data {reason}
- Forbidden:    code -32003, data {reason}
- Rate limited: code -32029, data {retry_after}
