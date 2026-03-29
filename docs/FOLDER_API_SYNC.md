# Folder API Sync (Lang ↔ Folder)

This document accompanies `FOLDER_API_SYNC.jsonld` and summarizes how Lang and Folder align on:

- OCI AI Memory (manifests, layers, annotations)
- TOC as a first‑class, content‑addressed layer
- Blob streaming and redirects
- Registry search and filters
- Token exchange (PAT → short‑lived JWT)

## JSON‑LD Profiles

See `docs/FOLDER_API_SYNC.jsonld` for:
- Context (`ai`, `sh`, `oci` namespaces)
- Profiles: MemoryManifest, MemoryLayer, TOCLayer, PromptLayer, EmbeddingLayer, ConfigLayer, CheckpointLayer, DatasetShardLayer
- Examples: memory manifest (with TOC), TOC entries, memory layer content, registry search output

## TOC Layer

- Media type: `application/vnd.folder.ai.toc.v1+json`
- Entrypoint: manifest references TOC as a normal layer
- Entry: `{ path, digest, size, mediaType, annotations? }`
- Paths: forward slashes, no leading slash, UTF‑8, ≤255 chars per component, no duplicates
- Client use: resolve `path → digest`, then pull blob by digest

## Blob Streaming

- Inline small text/JSON; 307 redirect to provider‑signed URL for large/binary
- Range support lives on redirect target (S3 supports it)
- LSP: return URIs for binaries; allow forced inline for small text only

## Registry Search

- REST: `GET /api/v1/registry/search?owner=...&repo=prefix&q=...&ann[key]=value&type=manifest|blob`
- Returns `{ data: [{ owner, repo, reference|digest, mediaType, annotations }] }`
- Keeps OCI endpoints pure

## Token Exchange

- `POST /api/v1/auth/token` with `client_credentials`
- Inputs: `scope` (space‑separated repo scopes), optional `audience`
- Output: `{ access_token, token_type: "Bearer", expires_in, scope }`
- Registry uses WWW‑Authenticate 401 challenge; clients mint and retry

## Lang Adapter Notes

- VFS: JSON‑RPC `folder/fs.*` (list/read) wired, conservative limits
- OCI: `registry.getManifest`/`getBlob` wired with 307 handling and text caps
- Token cache: short‑lived ETS cache keyed by `scope`
- Preview caps: lines/bytes configurable via env
- Billing: gated per org; events include bytes/mediaType/owner/workspace/ref

If Folder adjusts media types or JSON‑RPC names, we can update this JSON‑LD and regenerate handlers with minimal changes.
