# LANG LSP Test Harness

This harness lets testers (and AI agents) exercise the LANG LSP locally with optional network capture and session recording.

## Components

- `scripts/lsp_harness.sh` — boots LSP (TCP 4001), performs an initialize sanity check, keeps server alive for a limited time.
- `scripts/capture_lsp_pcap.sh` — captures TCP traffic on port 4001 to rotating PCAP files (tcpdump/tshark).
- `scripts/gen_tester_tokens.sh` — generates ephemeral debug tokens/keys for local testers.
 - `scripts/gen_tester_tokens_batch.sh` — generates N tester token bundles for multi-client dev flows.
- Asciinema (optional) — records terminal sessions as cast files for replay/embedding.
- Markdown‑LD docs — embed recordings and session metadata (see below).

## Prerequisites

- Elixir + Mix (app compiles)
- `nc` (netcat) for the built‑in sanity check (recommended)
- tcpdump or tshark for network capture (optional, needs sudo)
- asciinema for recording (optional)

## 1) Start the LSP (no auth, loopback)

```bash
# Compile once if needed
mix deps.get && mix compile

# Start on 127.0.0.1:4001 for 30 minutes
LSP_PORT=4001 LSP_DURATION_SECONDS=1800 ./scripts/lsp_harness.sh
```

What it does:
- Boots LANG app with the LSP TCP server (no Phoenix)
- Waits for port 4001, sends an `initialize` request, prints first response bytes
- Keeps BEAM alive for the configured duration (Ctrl‑C to stop)
- Logs: `/tmp/lang_lsp.out` and `/tmp/lang_lsp.err`

## 2) Network capture (optional)

Capture LSP traffic to a rotating PCAP (requires tcpdump or tshark):

```bash
# Default: 5 files x 10MB to /tmp
sudo LSP_PORT=4001 ./scripts/capture_lsp_pcap.sh
```

Inspect with Wireshark or tshark:

```bash
wireshark /tmp/lsp_4001_*.pcap
# or
tshark -r /tmp/lsp_4001_*.pcap
```

Tips:
- Keep on loopback; if an agent is remote, use an SSH tunnel instead of exposing the port:
  - `ssh -N -L 4001:127.0.0.1:4001 you@host`
- Consider anonymizing captured JSON payloads before sharing.

## 3) Record the session (optional)

```bash
# Start recording and open a shell with LSP running in background
asciinema rec -t "Agent vs LANG LSP" ./agent_lsp.cast -- \
  bash -lc 'LSP_PORT=4001 mix run -e "Application.ensure_all_started(:lang); :timer.sleep(60_000*30)" & echo "[LSP] up on 127.0.0.1:4001"; exec bash'

# Replay locally
asciinema play ./agent_lsp.cast
```

Embed in Markdown‑LD:

```session {lds:session=bench-1 lds:proto=unix lds:path=/tmp lds:policy=attach lds:mode=pty}
# Agent vs LANG LSP on loopback
```

```json {ldt:cast-for=bench-1}
{ ... contents of agent_lsp.cast ... }
```

Optional attestation (provenance):

```json {ldt:attestation-for=bench-1}
{"input_hash":"sha256:...","output_hash":"sha256:...","runner":"asciinema","version":"2.x","container_digest":"sha256:...","ts":"2025-08-28T12:34:56Z","sig_alg":"ed25519","signature":"..."}
```

## 4) Agent/test harness connection

Point the agent’s LSP client at `127.0.0.1:4001` over TCP (no auth). Minimal sequence:
- initialize → wait for result
- initialized (notification)
- textDocument/didOpen → textDocument/completion/hover/formatting

Raw TCP sanity check (via `nc`):

```bash
REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{},"clientInfo":{"name":"probe","version":"0.1"}}}'
LEN=$(printf "%s" "$REQ" | wc -c | awk '{print $1}')
printf "Content-Length: %s\r\n\r\n%s" "$LEN" "$REQ" | nc 127.0.0.1 4001 | head -c 400
```

## 5) Tester tokens (optional)

Generate ephemeral tokens/keys for local testers (loopback/MCP bridges, etc.):

```bash
./scripts/gen_tester_tokens.sh > /tmp/tester_tokens.env
source /tmp/tester_tokens.env
# Now have: MCP_DEBUG_TOKEN, TESTER_API_KEY, SESSION_DEBUG_TICKET
```

Share the export lines privately; these are not persisted and should not be committed.

### Dev flow: 5 parallel LSP clients

Generate 5 token bundles and hand one to each client/agent:

```bash
./scripts/gen_tester_tokens_batch.sh 5
# Example output directory:
#   /tmp/lang_lsp_testers_20250828_130102/
#     client-1.env ... client-5.env
```

Tester usage (per client):

```bash
source /tmp/lang_lsp_testers_*/client-1.env
# Optional: after LSP initialize, send a custom identify notification for logs:
#   method: "lang/tester/identify", params: { token: "$MCP_DEBUG_TOKEN", clientId: "$CLIENT_ID" }
# Note: raw LSP over TCP has no auth; tokens are for identification in harness/MCP bridges.
```

## 6) Troubleshooting

- Port not listening
  - Ensure the app compiled and `lsp_harness.sh` didn’t error
  - Check `/tmp/lang_lsp.err`
- No response to initialize
  - Validate JSON and `Content-Length` bytes; CRLF header line endings are required
- Editor/agent fails to connect
  - Verify it targets `127.0.0.1:4001` or a proper local SSH tunnel

## Safety & Policy

- The LSP TCP endpoint is unauthenticated; keep it on loopback or SSH tunnel
- Do not run long‑lived servers in test CI; prefer time‑limited runs via the harness
- Avoid recording secrets in casts or PCAPs; sanitize before sharing
