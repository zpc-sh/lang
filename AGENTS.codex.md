Codex Guardrails & Handoff (v0)

Purpose
- Keep Codex contributions deterministic, offline‑first, and repo‑local.
- Provide a simple, file‑based spec handoff that other Codex agents can consume.

Spec Handoff Protocol
- Requests live under `work/spec_requests/<id>/` with:
  - `request.json`: the spec request (see schema)
  - `proposed.status|accepted.status|in_progress.status|done.status|rejected.status`
  - `attachments/`: any referenced files (proposals, examples)
- IDs: `<timestamp>_<project>_<slug>_<short-hash>` (deterministic, sortable)
- Projects: `jsonld`, `markdown_ld` (extend as needed)

Patch Proposals (agent‑fast)
- Messages of type `proposal` may attach a `patch.json` with JSON Pointer ops:
  {
    "file": "relative/path.json",             // optional if message.ref.path present
    "base_pointer": "/api",                   // optional; defaults to message.ref.json_pointer
    "ops": [
      {"op": "replace", "path": "/hash", "value": "..."},
      {"op": "add",     "path": "/foo/0", "value": {"k": 1}},
      {"op": "remove",  "path": "/old"}
    ]
  }
- Apply locally with: `mix spec.apply --id <id> [--source inbox] [--target /path/to/repo]`
  - Safe, one‑shot, offline; writes updated JSON with pretty formatting

Schema
- `work/spec_requests/schema.json` — validated shape for `request.json`.
- Required: `project`, `title`, `api`, `acceptance`, `meta`.

Mix Tasks
- `mix spec.new <jsonld|markdown_ld> --title "..." [--slug slug] [--motivation "..."] [--priority high] [--version v1]`
  - Creates `work/spec_requests/<id>/request.json` and `proposed.status`.
- `mix spec.attach --to <id> --file path/to/file`
  - Copies to `attachments/` and updates `request.json.attachments`.
- `mix spec.status --id <id> --set proposed|accepted|in_progress|implemented|rejected|blocked`
  - Creates a corresponding `.status` marker (multiple allowed for trail).
- `mix spec.push --id <id> [--dest /path/to/other/repo/work/spec_requests]`
  - Copies the entire folder to destination; defaults to `$SPEC_HANDOFF_DIR` if not given.
- Messages & threads
  - `mix spec.msg.new|push|pull` — author and sync messages
  - `mix spec.thread.render` — synthesize a single `thread.md` from request + messages
  - `mix spec.sync` / `mix spec.autosync` — one‑shot both‑ways sync and render
  - `mix spec.say` — create → push → render in one command
  - `mix spec.apply` — apply JSON Pointer patch proposals to target files
  - `mix spec.lint` — quick validation of JSONs, attachments, and thread rendering

Example Flow
1) Create request
   - `mix spec.new jsonld --title "URDNA2015 canonicalization + hashing"`
2) Attach proposal
   - `mix spec.attach --to <id> --file work/jsonld_spec_proposals.md`
3) Mark accepted and push to target repo
   - `mix spec.status --id <id> --set accepted`
   - `SPEC_HANDOFF_DIR=../jsonld-repo/work/spec_requests mix spec.push --id <id>`

Target Repo Hints (for receiving Codex)
- Watch `work/spec_requests/*/request.json` & `*.status`.
- On acceptance, drop `ack.json` with ETA and contact; update status trail as work progresses.

Operational Guardrails (reminder)
- No long‑running processes (`mix phx.server` forbidden). Prefer one‑shot tasks.
- Offline‑first: avoid network fetches by default; allowlists for exceptions.
- Determinism: prefer canonical encodings and stable ordering for any generated artifacts.

Git Tracking (suggested defaults)
- Commit (tracked):
  - Protocol & tasks: `AGENTS.codex.md`, `lib/mix/tasks/spec*.ex`, schemas under `work/spec_requests/*.schema.json`
  - Requests lifecycle: `work/spec_requests/<id>/request.json`, status markers (`*.status`), `ack.json`, attachments (e.g., `patch.json`) that represent applied/decided changes
- Ignore (ephemeral):
  - `work/spec_requests/*/inbox/`, `work/spec_requests/*/outbox/` (message transport)
  - `work/spec_requests/*/thread.md` (regenerate anytime via `mix spec.thread.render`)
  - Optional: temporary attachments or scratch notes (use subfolders like `attachments/tmp/`)
- CI idea: validate tracked JSONs and ensure `thread.md` regenerates cleanly (`mix spec.lint --id <id>`)
