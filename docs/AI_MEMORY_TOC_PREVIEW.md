# AI Memory TOC Preview (Lang)

This note explains how to preview AI Memory content stored in Folder’s OCI registry using the TOC layer, and how to validate Folder endpoints when they are ready.

## Overview

- Command: `mix folder.toc.preview OWNER REPO REFERENCE PATH`
- Resolves `PATH` via the TOC layer (`application/vnd.folder.ai.toc.v1+json`) in the target manifest.
- Fetches the layer blob:
  - Inlines small text/JSON within caps
  - Returns a blob URI for large/binary content (307 policy)
- Uses the Folder adapter’s registry helpers directly (no billing gate), obeying timeouts and caps.

## Prerequisites

- Folder base URL and token (PAT or short‑lived JWT mint enabled):
  - `export FOLDER_URL=http://127.0.0.1:7070`
  - `export FOLDER_TOKEN=...` (optional if minting enabled)
- Optional token mint: Folder implements `POST /api/v1/auth/token` (client_credentials). The adapter parses `WWW‑Authenticate` and retries.

## Usage

```bash
mix folder.toc.preview OWNER REPO REFERENCE PATH
# Example
mix folder.toc.preview acme ai/memory/foundation latest memory/foundation/patterns.md
```

- On success:
  - For text: prints a preview up to `LANG_STORAGE_PREVIEW_MAX_BYTES` and respects `LANG_STORAGE_PREVIEW_MAX_LINES`.
  - For binaries/large: prints a blob URI (follow with curl; may be pre‑signed).
- Errors:
  - `auth_required` (WWW‑Authenticate challenge present)
  - `toc_missing` (manifest has no TOC layer)
  - `not_found` (path not present in TOC)

## Safety & Limits (env overrides)

- `LANG_STORAGE_INLINE_TEXT_MAX_BYTES` (default: 1_048_576)
- `LANG_STORAGE_FORCE_INLINE_BINARIES` (default: false)
- `LANG_STORAGE_PREVIEW_MAX_LINES` (default: 500)
- `LANG_STORAGE_PREVIEW_MAX_BYTES` (default: 65_536)
- `LANG_STORAGE_MANIFEST_CACHE_TTL` (default: 60)

## Validate Folder Endpoints

- One‑pager: `scripts/folder_rollout_validation.md` (curl flows for registry handshake, manifest, blob with 307, search, VFS).
- Scripted validator: `mix run scripts/validate_folder.exs` (Req‑based smoke tests).

## Related Docs

- `docs/FOLDER_API_SYNC.jsonld` – JSON‑LD profiles and examples (manifest, TOC, memory layer, search).
- `docs/FOLDER_API_SYNC.md` – Summary of TOC, streaming, search, token exchange.

Notes
- The adapter never buffers large blobs by default; it prefers URIs when size/type exceeds caps.
- Token and manifest caches are small ETS tables with short TTLs; no long‑running processes are started.
