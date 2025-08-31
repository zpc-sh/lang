# Lang DevKit and Dev Routes (for Agents)

This app includes a small DevKit to help agents and developers exercise the end‑to‑end execution pipeline in a safe, dev‑only way.

- Dev Hub: `/dev/test`
- JSON‑LD Runner: `/dev/jsonld`
- Models Panel: `/dev/models`
- NIF Health: `/dev/nif`
- Dev impersonate: `/dev/auth/impersonate/:email`
- Admin APIs:
  - Metrics: `/dev/api/metrics/summary`, `/dev/api/metrics/lsp`, `/dev/api/metrics/nif`
  - LSP admin: `/dev/api/lsp/clients`, `/dev/api/lsp/methods`, `/dev/api/lsp/heartbeat`
  - Models (dev): `/dev/api/models`, `/dev/api/models/:id`, `/dev/api/models/drift`, `POST /dev/api/models/:id/render`

## Mounting the DevKit (Router)

DevKit routes are mounted via a helper macro. Ensure you only wrap `/dev` once to avoid router hangs.

```elixir
# router.ex
if Application.compile_env(:lang, :dev_routes) do
  use Lang.DevKit.Router

  # Mount generic DevKit routes – this defines its own "/dev" scope
  codex_devkit_routes(scope: "/dev", web_module: LangWeb)

  # App‑specific dev pages (do NOT nest another scope "/dev")
  live "/dev/lsp", LangWeb.LspEditor.LspEditorLive, :index
  live "/dev/agents", LangWeb.AgentsLive, :index
  live "/dev/proxy/terminal", LangWeb.ProxyTerminalLive, :index
  live "/dev/models", LangWeb.DevModelsLive, :index

  import Phoenix.LiveDashboard.Router
  live_dashboard "/dev/dashboard", metrics: LangWeb.Telemetry
  forward "/dev/mailbox", Plug.Swoosh.MailboxPreview
end
```

Important:
- Do not place an additional `scope "/dev"` around routes once you call `codex_devkit_routes/1`.
- Dev routes must remain behind `:dev_routes`; never enable in prod.

## JSON‑LD Runner

Open `/dev/jsonld` to paste and run JSON‑LD payloads. The runner dispatches actions to a whitelist via `Lang.DevKit.JSONLDActions`.

- Validate and Run buttons parse and execute the JSON.
- Events panel lets you subscribe to PubSub topics (e.g., `analysis:<session_id>`).
- Custom actions can be registered at runtime (dev‑only):
  - Echo: registers an action that echoes payload back
  - Broadcast: registers an action that broadcasts payload to a topic

Examples (also available as files under `priv/dev/jsonld`):
- Echo: `{ "lds:action": "custom.echo", "hello": "world" }`
- Broadcast: `{ "lds:action": "custom.broadcast", "msg": "hi from runner" }`
- Proxy SSH: see `priv/dev/jsonld/proxy_ssh.json`

## Dev Examples (Local Only)

- Files live under `priv/dev/jsonld/*` and are intended for local development only.
- Do not publish these files in any library package.
- When extracting the DevKit into a standalone library, exclude dev content via Hex package `files:` option.

## Notes for Multi‑Agent Workflows

- Avoid running multiple watchers or formatters concurrently if you see FD contention.
- Keep `:dev_routes` disabled in prod. Consider a runtime assertion to ensure it.
- Use the Admin APIs above as attach points for health and activity.

---

Questions or improvements? Consider adding docs or examples here to guide other agents.
## Model Docs Render & Drift

- Source of truth for models is JSON‑LD under `priv/dev/jsonld`. Model metadata is materialized to an ETS resource `Lang.Dev.ModelRegistry` with fields: `model_id`, `version`, `hash`, `path`, `rendered_at`.
- Render docs deterministically with:

```
mix devkit.render_docs           # render all models
mix devkit.render_docs --id echo # render only `echo` (match by filename)
```

- Rendered files are written to `priv/docs/rendered/<model_id>.md` with a YAML frontmatter including: `id`, `version`, `hash`, `provenance`, `generated_by`, `rendered_at`.
- Drift API compares registry hash vs. doc frontmatter hash and lists mismatches: `GET /dev/api/models/drift`.
 - JSON‑LD validation runs via a configurable validator (default: `Lang.Dev.Validator.Schema`).

### CI Lint

Run in CI to ensure docs are up-to-date and free of drift:

```
mix devkit.lint_docs          # renders then checks drift; exits non-zero on mismatch
mix devkit.lint_docs --no-render  # only checks drift (skip render step)
```

### Ingest (Gated)

Re-ingest a curated doc back into JSON‑LD (dev only):

```
mix devkit.ingest_doc --id <model_id>
```

Rules:
- Frontmatter must include id/version/hash; id must match.
- JSON code block’s canonical hash must equal frontmatter hash.
- If hash differs from registry, version must be bumped (semver monotonic).
- On success: updates `priv/dev/jsonld/<file>.json`, updates registry, and re-renders docs deterministically.

### Wiring routes (opt-in)

To expose the dev model APIs without disturbing existing routes, import the helper and mount inside your dev-only router block:

```
# in your Phoenix router
if Application.compile_env(:lang, :dev_routes) do
  import LangWeb.DevRoutes
  dev_model_routes(scope: "/dev/api", pipe: :api)
end
```

This adds:
- `GET /dev/api/models`
- `GET /dev/api/models/:id`
- `GET /dev/api/models/:id/history` (add `?diff=1` for diffs)
- `GET /dev/api/models/:id/history/diff` (use `?entry_id=EID` or `?from_id=A&to_id=B`)
- `GET /dev/api/models/drift`
- `POST /dev/api/models/:id/render`
- `POST /dev/api/models/ingest` (body: `{ "id": "<model_id>" }`)
- `POST /dev/api/models/:id/status` (body: `{ "status": "ready", "owner": "alice", "notes": "..." }`)
 - LSP trace (dev): `GET /dev/api/lsp/clients/:id/trace`, `POST /dev/api/lsp/clients/:id/tap`

All mutating endpoints enqueue Oban jobs and return 202 with a `job_id`. Subscribe to `"dev:models"` for progress; events are emitted via Ash.Notifier.PubSub on `Lang.Dev.ModelEvent` creates.

```
Phoenix.PubSub.subscribe(Lang.PubSub, "dev:models")
# You will receive Ash PubSub notifications for Lang.Dev.ModelEvent creations
# with event_type: "render_start" | "render_done" | "render_error" | "ingest_start" | "ingest_done" | "ingest_error".
```

### Injection Lint

```
mix devkit.lint_injection     # scan rendered docs for injection patterns; fails on findings
```

Agents may output Markdown with embedded prompt/log injection. Ingest only uses frontmatter + JSON code blocks and ignores free text. Docs sanitize frontmatter values and use quadruple fenced JSON blocks. Use the lint above in CI and prefer the JSON block when agents consume docs. Advanced policies will live in the Kyozo prompt framework.

### LSP Methods (dev-only, guarded)

Handlers (used by agents and tools) to operate on models without hitting HTTP:
- `lang.dev.models.list` → returns `[ %{id, version, hash, status, owner} ]`
- `lang.dev.models.get` → params: `{id}`; returns JSON‑LD map
- `lang.dev.models.history` → params: `{id, diff?}`; returns `{history: [...]}`
- `lang.dev.models.render` → params: `{id}`; enqueues render via Oban; returns `{job_id}`
- `lang.dev.models.ingest` → params: `{id}`; enqueues ingest via Oban; returns `{job_id}`
- `lang.dev.models.status` → params: `{id, status, changed_by?}`; guarded transitions
- `lang.dev.models.drift` → returns `{drift: [...]}`
- `lang.dev.models.diff` → params: `{id, entry_id}` to diff an entry against its previous; or `{id, from_id, to_id}` to diff two specific entries
 - `lang.dev.lsp.tap_start` / `tap_stop` → params: `{client_id, methods?, max?}`
 - `lang.dev.lsp.trace` → params: `{client_id, method?, since?, limit?}`

All methods are enabled only when `:dev_routes` is true and follow the same security constraints (provenance checks, canonical hashing, ingest gates).


### WS/LSP Tickets (dev)

Mint short-lived dev tickets for WS/LSP connects:

```
mix devkit.mint_ticket --user-id <uid> --org-id <oid> --scope proxy_ws --ttl 300
```

Use the token via query param or Authorization header:

```
wscat -c "wss://localhost:4000/api/sessions/abc123/connect?ticket=<TOKEN>"
# or
curl -H "Authorization: Bearer <TOKEN>" "wss://localhost:4000/api/sessions/abc123/connect"
```
