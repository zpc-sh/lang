# LSP Next Steps — Options & Rationale

This document outlines focused, high‑impact improvements to the LSP server and adjacent tooling. Each option includes what it delivers, why it helps, and implementation notes.

## Option A — Server Info + Health
- What:
  - `rpc.serverInfo`: version, uptime, connected_clients, active_documents, enabled adapters (LocalFS/Folder), billing gate status.
  - `rpc.health`: quick self‑checks with reasons (NIF availability, PubSub, Folder URL reachability, DB ready?, telemetry sink attached?).
- Why: One‑stop diagnostics for operators and harnesses.
- Notes:
  - Wire to `mix lsp.debug --explain` for readable results.
  - Add lightweight caching (e.g., 2s) to avoid spamming checks.

## Option B — Registry Search (LSP)
- What:
  - Handler `folder/registry.search` with params `{owner, repo?, q?, ann[key]=value, type?}`.
  - Pass‑through to Folder’s REST search, maps results to `{owner, repo, reference|digest, mediaType, annotations}`.
- Why: Discoverability by annotations (layerType, embeddings.model, workspace) without breaking OCI purity.
- Notes:
  - Add telemetry for request count and latency.
  - Add plan entries to `scripts/lsp_debug_plan.sample.json`.

## Option C — Capabilities & Errors Polish
- What:
  - Advertise new execute commands and methods in `serverInfo.capabilities`.
  - Normalize JSON‑RPC errors across `folder/*` and `insights/*` (e.g., `auth_required`, `billing_blocked`, `not_found`).
- Why: Consistent UX for clients; easier automated assertions.
- Notes:
  - Provide a mapping doc of error codes; add mini checks in `lsp.debug.session` plan.

## Option D — Backpressure & Rate Limits
- What:
  - Per‑client request budget (configurable); soft 429 with `retry-after` header for heavy methods (e.g., scans/search).
  - Telemetry rollups per client with top methods, counts.
- Why: Protects the server and gives clients clear guidance during load.
- Notes:
  - Integrate with existing telemetry sink (JSONL rollups already implemented).

## Option E — Test Harness Expansion
- What:
  - Curated sample call files (registry, vfs, insights) for `mix lsp.debug`.
  - CI‑friendly `mix lsp.debug.session` target that runs when Folder env is present; skips otherwise.
  - (Optional) Tiny HTML viewer for metrics JSONL (rollups, p95).
- Why: Repeatable, observable tests reduce regressions; quick onboarding.
- Notes:
  - Keep everything time‑bounded; no long‑running servers.

## Current Diagnostics (Already Implemented)
- Client: `mix lsp.debug` (ad‑hoc), `mix lsp.debug.session` (plan‑based), `--explain` output.
- Server: `LSP_DEBUG_LOG=/tmp/lsp_debug.jsonl` for structured request/response; telemetry events emitted.
- Telemetry sink: `LSP_METRICS_LOG=/tmp/lsp_metrics.jsonl` with periodic rollups (count/avg/p95 per method), configurable via `LSP_METRICS_FLUSH_MS`.

## Recommendation
- Start with A + B (Info/Health + Registry Search) for immediate operational value.
- Follow with C for consistency; D if load rises; E to harden CI/dev flows.

