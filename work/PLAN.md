Title: Agent-First LSP Auth Rollout Plan

Goals
- Consistent first-time success for AI agents connecting via WS (target ≥ 95%).
- Keep LSP unmodified; move auth to transport (JWT ticket) + app billing.
- Bind raw LSP to localhost; expose Phoenix WS attach only.

Phases
1) API + WS attach
   - Add POST /api/v2/lsp/connect (JWT RS256 ticket, ttl≤300s, sub/org/scope/jti/cid)
   - Add GET /ws/lsp (validate ticket; proxy to 127.0.0.1:4001)
   - Add /api/v2/lsp/preflight (auth/billing readiness hints)

2) SDK + Docs
   - TypeScript helper: mintTicket(auth) → {wss_url,ticket,cid}; connect(wss_url,ticket)
   - Agent Quickstart + common errors
   - LATP doc: transport-level auth profile for LSP

3) Edge (optional)
   - HAProxy JWT verify (RS256) + stick-table rate limit by org
   - WS upgrade routes only; no exposure of port 4001

4) Observability
   - Telemetry for mint/attach failures: agent/version/env/error/where/latency
   - Dashboard for first-time pass rate

5) Pilot & Iterate
   - Onboard 2–3 agents; iterate until ≥ 95% first-time pass

Milestones
- M1: Endpoints live + docs (LATP, Quickstart)
- M2: TS helper + basic telemetry
- M3: Edge snippets + first pilot
- M4: Support matrix ≥ 80% green, then 95%

Notes
- CID is server-derived and included in JWT; echoed in initializeResult.serverInfo.auth.cid
- Billing gate at mint time; optional first-attach metering

