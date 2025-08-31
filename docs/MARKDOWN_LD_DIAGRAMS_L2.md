# Markdown-LD — Diagrams (L2 Optional)

Status: Optional extension for embedding and versioning diagrams while preserving Markdown compatibility. This profile is D2-only to reduce surface area and support deterministic, server-rendered graphs for data structure demos.

## 1. Goals

- Carry diagram intent via fenced code blocks; renderers MAY produce SVG alongside source.
- Keep outputs versioned and diffable via stable IDs and content hashes.
- Remain safe-by-default: no remote fetches or script execution in outputs.

## 2. Supported Fences

- Language: `d2` only.
- Required attribute: `ldg:diagram=<id>` (stable across edits; unique within the document).
- Optional attributes:
  - `ldg:title=...` — human title.
  - `ldg:seed=<int>` — deterministic layout seed for D2.
  - `ldg:engine=<name>` — renderer/layout hint (e.g., `dagre`), otherwise default.
  - `ldg:policy=disabled|sandboxed|trusted` — execution policy; default `disabled`.

Examples

```d2 {ldg:diagram=diag-3 ldg:seed=42}
app: "API"
db: "Postgres"
app -> db: "query"
```

## 3. Output Embedding (SVG)

Renderers MAY embed an adjacent SVG block keyed to the source via `ldg:render-for`:

```svg {ldg:render-for=diag-3 hash=sha256:... engine=d2@0.6.7 ts=2025-08-28T12:34:56Z}
<!-- sanitized SVG content here -->
```

Rules
- `ldg:render-for` MUST match a `ldg:diagram` id.
- `hash` MUST be `sha256(jcs({lang, code_norm, engine, seed}))` truncated or full. See Determinism.
- Renderers MUST sanitize SVG (strip scripts/event attrs); no external hrefs. Prefer server-side rasterization if your threat model requires it.
- If no renderer is available or policy forbids, leave only the source block.

Attestation (optional but recommended)
- Adjacent JSON block attesting to provenance and hashing:

```json {ldg:attestation-for=diag-3}
{"input_hash":"...","output_hash":"...","renderer":"d2","engine_version":"0.6.7","container_digest":"sha256:...","ts":"2025-08-28T12:34:56Z","sig_alg":"ed25519","signature":"..."}
```
- Clients MAY require valid attestation before displaying outputs.

## 4. Determinism

Normalization and hashing
- `lang`: `d2`.
- `code_norm`: trim trailing spaces, normalize line endings to `\n`, remove trailing blank lines.
- `engine`: renderer id (e.g., `d2@0.6.7+dagre`).
- `seed`: optional integer; if absent, omit from payload.
- `hash`: `sha256(jcs({lang, code_norm, engine, seed}))`.

Deterministic rendering guidance (non-normative)
- D2: set an explicit `seed`; pin layout engine; disable time/random defaults.

## 5. Diff Semantics

- Source changes: compare fence content and attributes. If `ldg:diagram` id unchanged but source differs, emit a `:update_block`; output block SHOULD be regenerated.
- Output changes: compare `hash`; if source unchanged and `hash` differs, mark as `:render_drift` (renderer/version mismatch) — treat as `:update_block`.
- Add/remove diagrams: `:insert_block` / `:delete_block` by id.

## 6. Security & Policy

- Server-only rendering: clients MUST treat `d2` fences as inputs only; rendering occurs on the server.
- Default `ldg:policy=disabled`. Renderers MUST NOT auto-render unless policy permits.
- `sandboxed`: allow rendering with strict sandbox (no network, bounded memory/time, no file I/O).
- `trusted`: renderer MAY run with broader capabilities but MUST still sanitize outputs.
- SVG sanitation: strip `<script>`, `on*` attributes, `foreignObject`, external references; inline styles only. Consider rasterizing to PNG for strict environments.

## 7. Caching

- Cache key: `{lang, engine, seed?, code_norm}` → `hash`.
- If a matching `hash` exists, embed the cached SVG; otherwise render and store.

## 8. Examples (Round-trip)

D2 with deterministic seed

```d2 {ldg:diagram=diag-3 ldg:seed=42}
app: API
queue: Oban
app -> queue: Enqueue job
```

```svg {ldg:render-for=diag-3 engine=d2@0.6.7+dagre hash=sha256:caf3...}
<!-- sanitized SVG here -->
```

```json {ldg:attestation-for=diag-3}
{"input_hash":"...","output_hash":"caf3...","renderer":"d2","engine_version":"0.6.7","container_digest":"sha256:...","ts":"2025-08-28T12:34:56Z","sig_alg":"ed25519","signature":"..."}
```

## 9. Compliance

- L2 (this doc): carry D2 fences and optional sanitized SVG outputs; compute/compare `hash`.
- L3 (optional): strict determinism profile (pinned engines/configs), renderer provenance metadata, and streaming updates.

*** End of File
