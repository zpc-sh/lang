# Markdown‑LD Profile v0.1 (Draft)

Status: Draft (experimental). This repository defines a pragmatic profile to combine CommonMark markdown with JSON‑LD 1.1 semantics for editing, diffing, merging, and streaming.

## 1. Scope and Goals

- Preserve JSON‑LD semantics during editing and diffs.
- Maintain Markdown readability and CommonMark compatibility.
- Support real‑time, chunked updates and three‑way merge for collaboration.

Non‑goals: Full JSON‑LD expansion/flattening rules in this profile (can be layered later).

## 2. Embedding Semantics in Markdown

### 2.1 JSON‑LD Carriage
- YAML frontmatter with `jsonld: { ... }` holds an object per document.
- Fenced code blocks with language `json`, `json-ld`, `jsonld`, or `application/ld+json` embed JSON‑LD objects or arrays.
- Optional dev shorthand lines: `JSONLD: s,p,o` (non‑standard; for prototyping only).

### 2.2 Subject and Properties
- Subject `@id` becomes the JSON‑LD subject; if absent, generate a stable blank node id using a hash of the object.
- `@type` yields `rdf:type` triples (single or list).
- Object values:
  - Strings/numbers/booleans → literal object.
  - Objects with `@id` → reference triple and recursively include the nested object’s triples.
  - Objects without `@id` → literal JSON string of the nested object.

## 3. Document Model (Editing)

### 3.1 Blocks
Normalized block kinds: `:heading`, `:paragraph`, `:list`, `:list_item`, `:code_block`, `:blockquote`, `:table`, `:thematic_break`, `:link`, `:image`.

### 3.2 Paths
Paths are arrays of integers indexing into the structural order (e.g., `[block_idx, inline_idx]`). Paths are stable for the duration of a diff; insertions shift following indices.

### 3.3 Inline
Inline edits are represented as token LCS operations: `{:keep|:insert|:delete, token}`.

## 4. Diff Model

Change kinds:
- Blocks: `:insert_block`, `:delete_block`, `:update_block`, `:move_block`.
- Inline: `:insert_inline`, `:delete_inline`, `:update_inline` (inline ops are nested inside `:update_block` payloads).
- Semantics: `:jsonld_add`, `:jsonld_remove`, `:jsonld_update`.

`Patch` groups changes with provenance (`from`, `to`, metadata). Streaming emits per‑chunk patches.

## 5. Merge Semantics

Three‑way merge inputs: base, ours, theirs (as patches). Conflict reasons:
- `:same_segment_edit`, `:delete_vs_edit`, `:move_vs_edit`, `:order_conflict`, `:jsonld_semantic`.

Resolution guidance:
- Auto‑merge when edits are disjoint (different paths).
- Prefer non‑destructive updates when one side only inserts inline tokens and the other is a strict superset result.
- JSON‑LD conflicts should prefer contextually valid graphs; exact policy is application‑defined.

Unresolved conflicts are returned with sufficient context for UIs.

## 6. Streaming

Events: `:init_snapshot`, `:chunk_patch`, `:ack`, `:complete`.

Chunking strategies:
- Paragraph grouping (default): split by blank lines, group up to N paragraphs.
- Structural (recommended): group under headings, keep stable chunk IDs derived from heading anchors and positions. Stable IDs are included in event metadata.

Ordering: Clients apply patches in chunk order; acks are per‑chunk.

## 7. Security and Safety

- Treat embedded JSON as untrusted input; parse with robust libraries (e.g., Jason), avoid execution.
- Limit patch sizes and chunk counts to prevent abuse.

## 8. Compliance Levels

L1 (Core): Block diff, inline ops, three‑way merge skeleton, basic JSON‑LD extraction from fences/frontmatter, streaming events.

L2 (Semantic): JSON‑LD context handling, expansion/flattening before diffing; semantic merge policies.

L3 (Advanced): CRDT/OT integration, structural chunk stability across heavy edits, OT‑friendly streaming.

## 9. References

- CommonMark Spec: https://spec.commonmark.org/
- JSON‑LD 1.1: https://www.w3.org/TR/json-ld11/
- RDF Concepts: https://www.w3.org/TR/rdf11-concepts/

