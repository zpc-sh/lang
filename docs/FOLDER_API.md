Base Auth

- Bearer: JWT in Authorization: Bearer
  <token> (user-scoped, team-aware).
- API Key:
  AshAuthentication.Strategy.ApiKey.Plug
  (header Authorization: Bearer
  <api_key>).
- Tenant: Pipelines set actor from
  bearer/api key; requests infer team via
  user/team relationship. For OCI, owner
  namespace determines team or user; no
  workspace scoping in registry.

JSON/JSON‑LD

- Default JSON; opt-in JSON‑LD via
  Accept: application/ld+json or ?
  format=jsonld.
- Optional compaction: ?compact=true
  (local context only).
- Contexts are assigned per endpoint
  (ai/storage/infrastructure).

OpenAPI

- Spec module: FolderWeb.ApiSpec.
- Export when needed (not automatic): - JSON: mix openapi.spec.json
  --spec FolderWeb.ApiSpec priv/openapi/
  folder.openapi.json - YAML: mix openapi.spec.yaml
  --spec FolderWeb.ApiSpec priv/openapi/
  folder.openapi.yaml

OCI Registry (read-only MVP)

- Base (no proxy): /registry/v2
- Handshake: GET /registry/v2/ → 200
- Manifests: GET /registry/
  v2/:owner/:repo[/sub...]/
  manifests/:reference - :reference = tag or digest
  (sha256:...) - Content-Type: application/
  vnd.oci.image.manifest.v1+json
- Blobs: GET /registry/v2/:owner/:repo[/
  sub...]/blobs/:digest - Digest format: sha256:<64-hex> - Streams bytes; content type based
  on stored metadata
- Namespacing: - :owner is team slug or user handle
  (first path segment). - Repo can be multi-segment (e.g.,
  ai/foundation/llm). - No workspace in path; workspace
  links go in manifest annotations
  (JSON‑LD friendly).
- Auth & ACLs: - Authorization: Bearer/API key. - Resolve owner: team or user; deny
  if not found/authorized. - Phase 2: Bearer token challenge
  (realm/service/scope) for Docker/OCI
  clients.
- Without proxy: endpoints accessible at
  http://host:port/registry/v2/... - With proxy for registry.folder.sh:
  map / -> app /registry so external
  clients see /v2/....

DPA Orchestration (planning-first)

- Base: /api/v1
- Plan (read-only): - GET /api/v1/dpa/orchestrate?
  workspace_id=<uuid> → {data: plan} - GET /api/v1/dpa/agents_md?
  workspace_id=<uuid> → {data: {path,
  content}} - GET /api/v1/dpa/plan_preview?
  workspace_id=<uuid> → {data: {dry_run,
  summary, ops_change}}
- Apply (explicit, authenticated): - POST /api/v1/dpa/plan_apply?
  workspace_id=<uuid> → creates Ops.Change
  to write folders + AGENTS.md
- JSON‑LD: orchestration endpoints
  assign infrastructure context.

AI / Embeddings

- Test embeddings: - GET /api/v1/ai/embeddings/test?
  provider=openai|gemini&text=... - Returns {data:{provider, dims,
  preview:[…]}} - JSON‑LD available via Accept; AI
  context provided.
- Chat & cost analytics (existing):
  summary dashboards and recent events
  via /api/v1/ai/costs/\*.
- Tokens/cost: AgentRunner records
  estimated costs; backfills true token
  usage when provider returns usage
  fields.

Workspaces + Files (scoped under team)

- Base: /api/v1/teams/:team_id
- Workspaces CRUD + storage: - resources /workspaces (index/show/
  create/update/delete) - POST /workspaces/:workspace_id/
  storage → change storage backend - GET /workspaces/:workspace_id/
  storage → storage info
- Files under workspace: - GET /workspaces/:workspace_id/
  files → list (search, tags,
  content_type, sort) - POST /workspaces/:workspace_id/
  files/upload → multipart upload (file,
  commit_message) - GET /workspaces/:workspace_id/
  files/:id/content → {data:{id, content}} - PATCH /workspaces/:workspace_id/
  files/:id/content → update content
  (commit_message) - GET /workspaces/:workspace_id/
  files/:id/versions → {data:[…]} - POST /workspaces/:workspace_id/
  files/:id/render → render to format
  (html returns text/html; others JSON) - PATCH /workspaces/:workspace_id/
  files/:id/rename → rename
  (commit_message) - POST /workspaces/:workspace_id/
  files/:id/view → mark viewed - POST /workspaces/:workspace_id/
  files/:id/duplicate → duplicate
- All file endpoints assign storage
  JSON‑LD context.

Storage / VFS

- VFS under workspace: - GET /workspaces/:workspace_id/
  storage/vfs → list VFS files (virtual

* real) - GET /workspaces/:workspace_id/
  storage/vfs/content?path=... → virtual
  file content - POST /workspaces/:workspace_id/
  storage/vfs/share → create share link
  (json/ld) - GET /workspaces/:workspace_id/
  storage/vfs/export?format=pdf|html|epub|
  json → export - POST /workspaces/:workspace_id/
  storage/vfs/templates → register
  template

- Storage admin (admin-only): - GET /api/v1/storage/admin/stats - GET /api/v1/storage/admin/
  schedules

Navigation & Services

- Deterministic navigation (no LLM): - GET /api/v1/teams/:team_id/
  navigation/path - GET /api/v1/teams/:team_id/
  navigation/navigate
- Services (containers) within
  workspace: - GET /api/v1/teams/:team_id/
  workspaces/:workspace_id/services - POST /api/v1/teams/:team_id/
  workspaces/:workspace_id/services
  (deploy) - POST /api/v1/teams/:team_id/
  workspaces/:workspace_id/analyze
  (topology)

Billing (existing)

- Stripe checkout & portal
  (authenticated): - POST /api/v1/billing/stripe/
  checkout - POST /api/v1/billing/stripe/portal
- Subscription status:
  - GET /api/v1/billing/subscription
- Apple receipt validation: - POST /api/v1/billing/apple/
  validate
- Future integration: bridge Lang’s
  usage metering to our CostTracker
  (events) so their monitoring emits token
  usage that we store; later settle via
  Stripe.

Auth bridging for Lang

- Use PAT/API keys for
  service-to-service (Bearer
  Authorization).
- Scopes: - Registry: repository:<owner>/
  <repo>[/*]:pull and :push - APIs: team-level (team_id path),
  workspace endpoints for file ops;
  registry detached from workspace.
- Token minting (optional): we can
  add a short‑lived JWT token exchange
  endpoint if Lang wants to federate
  PATs). For OCI clients, we’ll add a
  WWW‑Authenticate challenge (realm/
  service/scope) in the next phase.

Notes

- OCI upload flows (POST/PATCH/PUT)
  and Bearer token challenge are the
  next step; read-only endpoints will be
  scaffolded first.
- Registry owner namespace is team
  or user; no workspace in registry
  path. Workspace links go in manifest
  annotations (JSON‑LD-friendly).
- JSON‑LD negotiation is centralized
  and off by default; only engages when
  clients ask.

If this works, I can scaffold the
read-only /registry/v2 endpoints next,
then add uploads a

What You Can Store (OCI Artifacts)

Manifests (top-level, JSON)

- AI Memory Manifest: application/
  vnd.folder.ai.memory.manifest.v1+json - Describes a set of AI memory
  layers (foundation/domain/session/
  execution), prompts, embeddings,
  configs, dataset shards, and optional
  checkpoints.
- Training Manifest: application/
  vnd.folder.ai.training.manifest.v1+json - Points to datasets and checkpoints
  for training runs.
- Inference Manifest: application/
  vnd.folder.ai.inference.manifest.v1+json - Points to prompt layers, memory
  layers, optional checkpoints, and output
  artifacts.

Layers (blobs referenced by manifests)

- Memory Layer (JSON-LD): application/
  vnd.folder.ai.memory.layer.v1+json - Layer types: foundation, domain,
  session, execution. - Stores structured memory content
  (typically JSON-LD). We compress on
  store when flagged by annotations; read
  remains transparent.
- Embeddings (binary): application/
  vnd.folder.ai.embedding.v1+binary - Numeric vectors (float32/float64
  serialized); per-chunk embeddings or
  pooled vectors.
- Prompt Layer (JSON): application/
  vnd.folder.ai.prompt.v1+json - Prompt templates/configs used for
  inference, including variable bindings.
- Dataset Shard (JSONL): application/
  vnd.folder.ai.dataset.shard.v1+jsonl - Training data shards for
  ingestion/training runs.
- Checkpoint (binary): application/
  vnd.folder.ai.checkpoint.v1+binary - Model or state snapshots (opaque
  to the registry).
- Config (JSON): application/
  vnd.folder.ai.memory.config.v1+json - Runtime/configuration metadata:
  tokenizer specs, dimension settings,
  thresholds, etc.
- Generic JSON/Text - application/json, text/\*
  (supported for incidental metadata/
  configs)

Typical Manifests (Examples)

- Memory manifest (foundation/domain/
  session/execution) - Config layer (memory.config) - One or more memory.layer (JSON-LD) - Optional embeddings layer (binary)
  for fast lookups - Optional prompt layer
- Training manifest
  - N dataset.shard layers
  - Optional checkpoint layer
- Inference manifest - Prompt layer - Memory layers + embeddings layer - Outputs written separately (e.g.,
  a separate memory manifest tagged with
  run id)

Annotations (use these on manifests and/
or layers)

- Ownership and context (do not use
  workspace in path; annotate instead) - sh.folder.ownerType: team|user - sh.folder.ownerId: - sh.folder.workspace: (optional
  link; registry path remains detached)
- AI semantics - sh.folder.ai.layerType:
  foundation|domain|session|execution - sh.folder.ai.accessFrequency:
  high|medium|low - ai.run_id: - ai.user_id: - ai.session_jti:
- Embeddings meta - ai.embeddings.model:
  text-embedding-004|
  text-embedding-3-small|… - ai.embeddings.dims: 768|1536|…
- Cost/usage (if you want to surface it)
  - ai.total_tokens:
  - ai.cost_usd:
- Free-form - labels and annotations that your
  pipeline needs (kept deterministic when
  feasible)

Namespace & Repo Path

- Standard OCI naming at /registry/v2: - /registry/v2/:owner/:repo[/
  sub...]/manifests/:reference - /registry/v2/:owner/:repo[/
  sub...]/blobs/:digest
- owner: team slug or user handle (first
  segment; determines ACLs)
- repo: slash-separated path; you choose
  structure (e.g., ai/memory/foundation,
  inference/llm)
- reference: tag (latest, 2025-09-01) or
  digest (sha256:...)
- No workspace in the path; use
  annotations for workspace.

Media Types Recap

- application/
  vnd.oci.image.manifest.v1+json
  (manifests)
- application/
  vnd.folder.ai.memory.manifest.v1+json
- application/
  vnd.folder.ai.training.manifest.v1+json
- application/
  vnd.folder.ai.inference.manifest.v1+json
- application/
  vnd.folder.ai.memory.layer.v1+json
- application/
  vnd.folder.ai.memory.config.v1+json
- application/
  vnd.folder.ai.embedding.v1+binary
- application/
  vnd.folder.ai.dataset.shard.v1+jsonl
- application/
  vnd.folder.ai.prompt.v1+json
- application/
  vnd.folder.ai.checkpoint.v1+binary
- application/json (generic)

Auth & ACLs (registry)

- Bearer JWT or API Key.
- Owner resolution from path: - If :owner matches a Team slug →
  team namespace; member roles/policies
  apply. - If :owner matches a User handle →
  user namespace; user’s PAT applies.
- Scopes (for upload flows—phase 2):
  - repository:/[/*]:pull
  - repository:/[/*]:pull,push
- For Lang’s service accounts: issue
  team-scoped API keys or short-lived
  JWTs. Later we can add an OCI Bearer
  for Docker/ORAS.

Registry Behavior Notes

- Detached from workspace by design;
  keep workspace links in annotations.
- Deduplication: blobs stored
  content-addressably; multiple manifests
  can reference the same layers.
- JSON‑LD is available on normal
  APIs (Accept: application/ld+json).
  For registry manifests, stick to OCI
  media types; JSON‑LD semantics ride in
  annotations.

If you want, I can add a short registry
“catalog” doc for Lang with:

- Example manifest body and layers
- Example annotations
- Sample curl/ORAS pulls (read-only
  for now)
- Name/Tag/Digest validation rules and
  error mappings

1. A sample AI Memory Manifest + Layers
   (OCI-compliant)
2. What artifact types (layers) the
   registry supports
3. LSP FS (and minimal registry/
   telemetry) functions we need from them
4. Auth/ACLs and how to call our
   endpoints

Use this as a “quick start” doc.

— Sample: AI Memory Manifest (OCI)

Pull path (no proxy): GET /
registry/v2/:owner/:repo[/sub…]/
manifests/:reference

- Example: /registry/v2/acme/ai/memory/
  foundation/manifests/latest

Manifest (application/
vnd.oci.image.manifest.v1+json)
{
"schemaVersion": 2,
"mediaType": "application/
vnd.oci.image.manifest.v1+json",
"config": {
"mediaType": "application/
vnd.folder.ai.memory.manifest.v1+json",
"digest":
"sha256:1111111111111111111111111111111111111111111111111111111111111111",
"size": 512
},
"layers": [
{
"mediaType": "application/
vnd.folder.ai.memory.config.v1+json",
"digest":
"sha256:2222222222222222222222222222222222222222222222222222222222222222",
"size": 834,
"annotations": {
"sh.folder.ai.layerType":
"config",
"ai.embeddings.model":
"text-embedding-004",
"ai.embeddings.dims": "768"
}
},
{
"mediaType": "application/
vnd.folder.ai.memory.layer.v1+json",
"digest":
"sha256:3333333333333333333333333333333333333333333333333333333333333333",
"size": 4096,
"annotations": {
"sh.folder.ai.layerType":
"foundation",
"sh.folder.ai.accessFrequency":
"high",
"sh.folder.workspace":
"00000000-0000-0000-0000-000000000000"
}
},
{
"mediaType": "application/
vnd.folder.ai.embedding.v1+binary",
"digest":
"sha256:4444444444444444444444444444444444444444444444444444444444444444",
"size": 98304,
"annotations": {
"ai.embeddings.model":
"text-embedding-004",
"ai.embeddings.dims": "768"
}
},
{
"mediaType": "application/
vnd.folder.ai.prompt.v1+json",
"digest":
"sha256:5555555555555555555555555555555555555555555555555555555555555555",
"size": 512,
"annotations": {
"sh.folder.ai.layerType":
"session"
}
}
],
"annotations": {
"org.opencontainers.image.title":
"acme/ai/memory/foundation",
"org.opencontainers.image.created":
"2025-09-01T12:00:00Z",
"sh.folder.ownerType": "team",
"sh.folder.ownerId":
"11111111-2222-3333-4444-555555555555"
}
}

Config blob content (application/
vnd.folder.ai.memory.config.v1+json)
{
"tokenizer": "cl100k_base",
"context_window": 128000,
"embedding_provider": "gemini",
"embedding_model": "text-embedding-004",
"embedding_dims": 768,
"notes": "Foundation layer config for
ACME"
}

Memory layer content (application/
vnd.folder.ai.memory.layer.v1+json)
{
"@context": { "@vocab": "https://
folder.sh/vocab/ai#" },
"@type": "MemoryLayer",
"entries": [
{
"kind": "policy",
"title": "Architecture
Guidelines",
"content": "Use Phoenix/Ash/
AshPostgres. Minimize diffs.",
"tags": ["foundation", "policy"],
"lang": "en"
},
{
"kind": "example",
"title": "Preferred Pipelines",
"content": "Pattern: plan ->
preview -> apply via Ops.Change.",
"tags": ["foundation", "workflow"]
}
]
}

— Supported Registry Artifacts (OCI
layers)

- Manifests (JSON) - application/
  vnd.folder.ai.memory.manifest.v1+json - application/
  vnd.folder.ai.training.manifest.v1+json - application/
  vnd.folder.ai.inference.manifest.v1+json
- Layers: - Memory Layer
  (JSON-LD): application/
  vnd.folder.ai.memory.layer.v1+json - Memory Config (JSON): application/
  vnd.folder.ai.memory.config.v1+json - Embeddings (binary): application/
  vnd.folder.ai.embedding.v1+binary - Prompt (JSON): application/
  vnd.folder.ai.prompt.v1+json - Dataset Shard
  (JSONL): application/
  vnd.folder.ai.dataset.shard.v1+jsonl - Checkpoint (binary): application/
  vnd.folder.ai.checkpoint.v1+binary - Generic application/json, text/\*
  (supported)

Annotate manifests/layers

- Ownership/context: sh.folder.ownerType
  (team|user), sh.folder.ownerId (uuid),
  sh.folder.workspace (uuid optional)
- AI semantics: sh.folder.ai.layerType
  (foundation|domain|session|execution),
  sh.folder.ai.accessFrequency (high|
  medium|low)
- Embeddings: ai.embeddings.model,
  ai.embeddings.dims
- Usage: ai.total_tokens, ai.cost_usd
- Any stable, deterministic annotations
  you need

— LSP Functions We Need From Lang

We will expose APIs; LSP should call
these methods over JSON-RPC (or REST
translate). Minimal set we need to
support our FS + registry workflows.

Filesystem (workspace-scoped; we
implement)

- folder/fs.list - params: { workspaceId: string,
  path?: string } - returns: { entries: [{ name, path,
  type: "file"|"dir", size, mtime }] }
- folder/fs.read - params: { workspaceId: string,
  id?: string, path?: string, version?:
  string } - returns: { content: string,
  contentType?: string, version?: string }
- folder/fs.write - params: { workspaceId: string,
  id?: string, path: string, content:
  string, contentType?: string,
  commitMessage?: string } - returns: { id: string, version?:
  string }
- folder/fs.rename - params: { workspaceId: string,
  id: string, newTitle: string,
  commitMessage?: string } - returns: { id: string }
- folder/fs.delete - params: { workspaceId: string, id:
  string, commitMessage?: string } - returns: { ok: true }
- folder/fs.versions - params: { workspaceId: string,
  id: string } - returns: { versions: [{ id,
  createdAt, message }] }
- folder/fs.render - params: { workspaceId: string,
  id: string, format: "html"|"json"|...,
  options?: object } - returns: { content: string }
- folder/fs.upload - params: { workspaceId: string,
  path: string, blobBase64?: string,
  blobUri?: string, commitMessage?:
  string } - returns: { id: string }
- folder/fs.share - params: { workspaceId: string,
  path: string, ttl?: number } - returns: { url: string, expiresAt:
  string }
- folder/fs.search (optional) - params: { workspaceId:
  string, query: string, options?:
  { caseSensitive?: boolean, wholeWord?:
  boolean, fileTypes?: string[] } } - returns: { results: [{ fileId,
  filePath, matches, totalMatches }] }

Registry (read-first; we implement
endpoints; LSP can adopt curl/ORAS or
add JSON-RPC stubs)

- folder/registry.getManifest - params: { owner: string, repo:
  string, reference: string } - returns: { manifestJson: object }
- folder/registry.getBlob - params: { owner: string, repo:
  string, digest: string } - returns: { content: bytes or uri }
- (phase 2) upload flows: - folder/registry.beginUpload,
  folder/registry.appendUpload,
  folder/registry.finishBlob, folder/
  registry.putManifest

Telemetry (Lang → Folder; we persist for
billing later)

- folder/ai.emitUsage - params: { provider: string,
  model: string, inputTokens?: number,
  outputTokens?: number, costUsd?: string,
  runId?: string, annotations?: object } - returns: { ok: true }
- folder/ai.emitEvent - params: { type: string, data:
  object, runId?: string } - returns: { ok: true }

We’ll map these to our CostTracker/
metrics.

— Endpoints (high-level)

Registry (path-based, no proxy)

- GET /registry/v2/ → 200
- GET /registry/v2/:owner/:repo[/sub…]/
  manifests/:reference
- GET /registry/v2/:owner/:repo[/sub…]/
  blobs/:digest

Workspaces (team-scoped)

- GET /api/v1/teams/:team_id/
  workspaces/:workspace_id/files
- POST /api/v1/teams/:team_id/
  workspaces/:workspace_id/files/upload
- GET /api/v1/teams/:team_id/
  workspaces/:workspace_id/files/:id/
  content
- PATCH /api/v1/teams/:team_id/
  workspaces/:workspace_id/files/:id/
  content
- GET /api/v1/teams/:team_id/
  workspaces/:workspace_id/files/:id/
  versions
- POST /api/v1/teams/:team_id/
  workspaces/:workspace_id/files/:id/
  render
- PATCH /api/v1/teams/:team_id/
  workspaces/:workspace_id/files/:id/
  rename
- POST /api/v1/teams/:team_id/
  workspaces/:workspace_id/files/:id/view
- POST /api/v1/teams/:team_id/
  workspaces/:workspace_id/files/:id/
  duplicate

DPA Orchestration (planning-first)

- GET /api/v1/dpa/orchestrate?
  workspace_id=…
- GET /api/v1/dpa/agents_md?
  workspace_id=…
- GET /api/v1/dpa/plan_preview?
  workspace_id=…
- POST /api/v1/dpa/plan_apply?
  workspace_id=…

AI Utilities

- GET /api/v1/ai/embeddings/test?
  provider=openai|gemini&text=…

— Auth for LSP

Bearer ).

- Registry ACL by owner namespace
  (team/user). Registry is detached from
  workspace.
- For FS ops: workspace endpoints live
  under team scope; bearer JWT resolves
  team membership.
- JSON‑LD only when asked via Accept;
  registry sticks to OCI media types.

If you want, I can provide a 1‑pager for
Lang with:

- Memory manifest example and 1–2 layers
  (above),
- Media type table,
- Annotations list,
- Minimal curl/ORAS commands for
  manifests/blobs,
- JSON‑RPC names for FS ops so they can
  wire their LSP quickly.
