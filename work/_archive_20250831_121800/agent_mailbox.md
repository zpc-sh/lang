# Agent Mailbox

Lightweight handoff board for short messages between agents. Append new notes at the top. Keep it concise and actionable.

---

## 2025-08-28 — LSP Setup + Client IDs

- Status: LSP over raw TCP reachable at `127.0.0.1:4001`.
- Client IDs: prefer unique per process (e.g., `codex-a`, `codex-b`).
- Identify: send once after initialize (notification has no response).

Commands
- Python client (short-lived, exits cleanly):
  - `CLIENT_ID="codex-a" URI=file:///tmp/demo_codex_a.ex LSP_HOST=127.0.0.1 LSP_PORT=4001 MCP_DEBUG_TOKEN=dbg_demo python3 containers/agents/agent.py`
  - `CLIENT_ID="codex-b" URI=file:///tmp/demo_codex_b.ex LSP_HOST=127.0.0.1 LSP_PORT=4001 MCP_DEBUG_TOKEN=dbg_demo python3 containers/agents/agent.py`
- Raw TCP identify (exact CRLF + correct Content-Length):
  - `REQ='{"jsonrpc":"2.0","method":"lang/tester/identify","params":{"clientId":"codex-a","token":"dbg_demo"}}'; LEN=$(printf "%s" "$REQ" | wc -c | awk '{print $1}'); printf "Content-Length: %s\r\n\r\n%s" "$LEN" "$REQ" | nc 127.0.0.1 4001`
- Stdio bridge (for editors that want stdio LSP):
  - `LSP_HOST=127.0.0.1 LSP_PORT=4001 elixir scripts/tcp_stdio_bridge.exs`

Notes
- Updated `containers/agents/agent.py` to accept env overrides: `URI`, `LANGUAGE_ID`, `TEXT`.
- Use separate URIs per client to avoid didOpen collisions: `file:///tmp/demo_codex_a.ex`, `file:///tmp/demo_codex_b.ex`.
- Do not start long-running servers in this shell; use short-lived clients only.

Logging / Watchers
- Logger metadata now tags `client_id` (via identify) and `uri` (via didOpen).
- Watch logs per client (run outside this shell):
  - `tail -F logs/dev.log | rg --line-buffered 'client_id=codex-(a|b)'`
  - `tail -F logs/dev.log | awk '/client_id=codex-a/ {print "[A] "$0} /client_id=codex-b/ {print "[B] "$0}'`

Branches
- Use `feature/<area>--<desc>--<client>` (e.g., `feature/lsp--identify-hook--codex-a`).
- Prefix commits with `[codex-a]` / `[codex-b]`.

Next
- If you need isolated instances per client, launch separate ports externally (e.g., `scripts/lsp_harness.sh`) — do not run persistently in this session.
- Capture specific responses (hover, diagnostics, completion) by re-running the Python client and increasing `recv_some` limit/timeouts if needed.

---

(append below this line for new topics)
