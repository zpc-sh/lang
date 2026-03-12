Agent Quickstart (WS + LspTicket)

1) Authenticate: use API key or OAuth (Bearer).
2) Mint ticket: POST /api/v2/lsp/connect → { wss_url, ticket, ttl, cid }
3) Attach WS: connect to wss_url (ticket in ?ticket or Sec-WebSocket-Protocol)
4) Run LSP initialize; server echoes cid in serverInfo.auth.cid
5) On 401/-32001: re-mint ticket and retry

TypeScript sketch

// mint
const r = await fetch('/api/v2/lsp/connect', { headers: { Authorization: `Bearer ${apiKey}` }, method: 'POST' });
const { wss_url, ticket } = await r.json();

// attach (browser)
const ws = new WebSocket(`${wss_url}`); // ticket embedded in URL
ws.onopen = () => {/* send LSP initialize */};
ws.onclose = () => {/* on 1008/4401 → re-mint */};

Common errors
- 401/403: invalid auth → refresh API key/token
- 402/429: billing gate → honor retry_after
- 1006 close: network/proxy issue → retry with backoff
