# Markdown-LD Profile v0.3 (Proposed)

Status: Owner-driven proposal. This profile combines CommonMark with JSON-LD 1.1 semantics that are pragmatic, readable, and implementable at high performance. It defines carriage, derivation, diff/merge, and streaming rules with strict backwards compatibility to CommonMark.

## 1. Scope and Goals

- Preserve JSON-LD semantics across edits, diffs, and merges.
- Maintain Markdown readability and CommonMark compatibility (no breaking syntax).
- Support real-time streaming via chunked patches with stable IDs.
- Promote deterministic extraction suitable for SIMD-accelerated parsing.

Non-goals: Remote context fetching, full JSON-LD API fidelity (e.g., framing, flattening) inside this profile. These can be layered externally.

## 2. Syntax: How Semantics Are Carried

Markdown-LD supports two categories of semantics:
- Explicit JSON-LD islands (verbatim JSON/JSON-LD)
- Derived RDF triples from Markdown constructs under a current subject

### 2.1 Frontmatter

Use YAML frontmatter to declare document-level context and defaults (quote JSON-LD keys for YAML validity):

```yaml
---
"@context":
  schema: "https://schema.org/"
  "@vocab": "https://example.org/vocab/"
ld:
  base: "https://example.org/"
  subject: "post:1"
  infer: true            # enable derived triples
---
```

Rules:
- Keys allowed under `@context` follow JSON-LD 1.1 (local only, no remote fetch).
- Under `ld:` (profile namespace), recognize:
  - `base`: base IRI for relative subjects/links
  - `subject`: default subject (IRI or CURIE)
  - `infer`: boolean to enable derived triples (default true)
- A legacy `jsonld: { ... }` object is treated as an embedded island (v0.1 compat).

### 2.2 Code Fences (JSON-LD Islands)

Fenced code blocks with languages `json`, `json-ld`, `jsonld`, `application/ld+json` embed JSON-LD objects or arrays. Example:

```json-ld
{
  "@context": {"schema": "https://schema.org/"},
  "@id": "post:1",
  "@type": "schema:Article",
  "schema:name": "Hello World"
}
```

Rules:
- Parse as JSON; expand using the minimal expander (no remote contexts).
- Yield triples via the expansion rules in section 4.
- If an object lacks `@id`, generate a deterministic blank node: `_:sha256(jcs(expanded_obj))[0..12]`, where `jcs(...)` is RFC 8785 JSON Canonicalization Scheme applied to the expanded object (see Determinism).

### 2.3 Dev Shorthand (Optional)

Single-line shorthand for prototyping (non-standard):

```
JSONLD: post:1, schema:name, Hello World
```

Rules:
- Exactly three unquoted, comma-separated tokens: subject, predicate, object. No commas inside tokens.
- Quoting/escaping is intentionally not supported to keep it unambiguous. This facility is for tests only and MAY be ignored by conforming implementations.

### 2.4 Attribute Lists (Inline Annotations)

Markdown-LD adopts a lightweight attribute list syntax on supported elements. This is CommonMark-compatible and ignored by renderers that don’t support it.

Mini grammar (unambiguous):
- Allowed on headings, links, images, and tables (not paragraphs by default; paragraph-level attributes are an optional L3 extension).
- Attribute list: trailing `{ ... }`.
- Keys: `[A-Za-z_][A-Za-z0-9._:-]*` (reserve `ld:*`).
- Values: quoted `"..."` with JSON escapes, or unquoted tokens without spaces. Optional language `"..."@en` or datatype `"..."^^xsd:date`.
- Whitespace around `=` and separators is insignificant.

Examples:
- Heading as subject and type:

```
# Hello World {#post-1 ld:@id=post:1 ld:@type=[schema:Article, ex:Note]}
```

- Link as predicate/object:

```
[Alice](https://example.com/alice){ld:prop=schema:author}
```

- Image as predicate/object:

```
![Cover](cover.jpg){ld:prop=schema:image}
```

Rules:
- `#... {#id}` sets the HTML id; `ld:@id` sets the JSON-LD subject for the section.
- `ld:@type` accepts a single value or JSON list; emit one `rdf:type` triple per value. Lists are only allowed for `ld:@type` in inline attributes.
- `ld:prop=IRI` on a link/image emits `<current-subject> IRI <target>` (href/src expanded to IRI).
- `ld:value=...` with `ld:prop` emits a literal triple (href/src ignored for RDF; still used visually). Apply the same scalar typing rules as attribute objects (numbers, booleans, `".."@lang`, `".."^^datatype`). If `ld:value` is absent, href/src becomes the object IRI.
- Optional `ld:lang`, `ld:datatype` apply to `ld:value`.

### 2.5 Lists and Tables (Structured Nodes)

- Attribute objects (blocks): only recognized as list items starting with `- { ... }` to avoid ambiguity with prose. Use the mini grammar (below). Drop JSON-in-braces or hybrid forms.
- Tables as property matrices (opt-in with `{ld:table=properties}` on the table): each row maps `header -> value` as predicates for the current subject or row subject (if first column is `@id`).

### 2.6 Heading-Scoped Subjects

- Each heading can define a subject via `ld:@id`. If omitted, a stable subject is derived from the heading’s slug + `ld.base`.
- The current subject is the nearest ancestor heading with a subject, or the document subject.
- Blocks under a section emit derived triples against the current subject.

## 3. Subject, Context, and Scoping Rules

Subject stack (from innermost to outermost):
1) Explicit island subject in a code fence/attribute object
2) Inline `ld:@id` on the block
3) Heading `ld:@id` subject
4) Document subject from frontmatter `ld.subject`
5) Generated blank node

Context resolution (no network):
- Merge contexts in order: document frontmatter, then island-local `@context`.
- Support `@vocab`, prefix definitions, and term definitions as per the minimal expander.
- Expand property keys and `@type` values to IRIs; coerce `@type: @id` to `{"@id": iri}`.

## 4. Extraction Algorithm (Normative)

Goals: deterministic, single-pass friendly. Pseudocode outline:

1) Parse frontmatter; capture `@context`, `ld.base`, `ld.subject`, `ld.infer` (default true).
2) Walk the Markdown AST in document order, maintaining a subject stack and inherited context.
3) For each node:
   - Code fences tagged as JSON/JSON-LD → parse, expand (local contexts only), emit triples via object rules.
   - Attribute lists with `ld:` keys → if `ld:@id`/`ld:@type`, update section subject and emit `rdf:type`.
   - Links/images with `ld:prop` → emit `<subject> prop <target>` (URL as IRI; image alt/title ignored for RDF unless `ld:value`).
   - Attribute objects in list items `{...}` → parse with the mini grammar; emit triples.
   - Tables marked `{ld:table=properties}` → per row emit `<subject> prop value` for non-empty cells.
4) Fallback derivations (enabled when `ld.infer=true`, optional L3 extension):
   - Paragraphs with `key: value` at start and attribute `{ld:prop=IRI}` → emit literal triple.
5) For nested objects without `@id`, generate a deterministic blank node and recurse.

Triple formation rules (resolved inconsistency; nested objects without `@id` ALWAYS become deterministic blank nodes and recurse; literal JSON requires explicit `@value` or `@type: @json`):
- `@type` → `rdf:type` (one triple per value)
- Scalars → literal objects (string/number/boolean as lexical form)
- Objects with `@id` → IRI objects and recurse to include their triples
- Objects without `@id` → deterministic blank node (see Determinism) and recurse

## 5. Diff Model (Normative)

Change kinds:
- Blocks: `:insert_block`, `:delete_block`, `:update_block`, `:move_block`
- Inline: `:insert_inline`, `:delete_inline`, `:update_inline` (nested in `:update_block`)
- Semantics: `:jsonld_add`, `:jsonld_remove`, `:jsonld_update`

Triple diffing:
- Index by `(expanded_s, expanded_p)`; if only in A → `:jsonld_remove`, only in B → `:jsonld_add`, in both with different object sets → granular add/remove.
- Normalize objects: use RDF 1.1 N-Quads lexical form for IRIs/literals (datatype IRIs normalized, language tags lowercased). JSON literals (only via explicit `@value`/`@type: @json`) are canonicalized via JCS before comparison.
- For multi-valued properties, compare as sets of `(s,p,o)`; produce per-value adds/removes. Use `@list` (from `[]` suffix) to preserve order.

Patch envelope:
- `from`, `to` revs (opaque), `changes: [...]`, `meta` map. Streaming uses the same change model scoped to chunks.

## 6. Merge Semantics

Three-way merge inputs: base, ours, theirs (as patches). Conflicts:
- `:same_segment_edit`, `:delete_vs_edit`, `:move_vs_edit`, `:order_conflict`, `:jsonld_semantic`.

Resolution guidance:
- Auto-merge disjoint paths.
- Inline conflicts: prefer non-destructive coalescing when one change is a strict superset.
- JSON-LD conflicts: prefer graph validity (application policy hook); surface unresolved conflicts with `(s,p)` context.

## 7. Streaming

Events: `:init_snapshot`, `:chunk_patch`, `:ack`, `:complete`.

Chunking strategies:
- Paragraphs: split by blank lines; group up to N paragraphs (`max_paragraphs`).
- Headings: group under headings; stable chunk IDs are `sha256(jcs({heading_path, block_index, text_hash}))[:12]`, where `heading_path` is the array of anchor slugs from root to current heading, `block_index` is ordinal within the section, and `text_hash` is `sha256` of the block text after normalization. Include stable IDs in event metadata.

Ordering: apply patches in chunk order; acknowledgements are per chunk. Move detection uses the stable chunk ID; same ID in a different location is `:move_block`. If both moved and edited, emit `:move_block` + `:update_block`.

## 8. Security and Safety

- Treat embedded JSON as untrusted; parse with robust libraries and never execute.
- Disallow remote context fetching; contexts must be inline.
- Limits (defaults, MAY be tightened): max context size 16KB, max object depth 32, max list length 1024, max patch size 256KB. On breach return `{:error, :limit_exceeded}`.

## 9. Compliance Levels

- L1 Core: Frontmatter context + doc subject; JSON/JSON-LD fences; triple diff; block/inline diff; streaming envelope. Excludes inline attribute lists to reduce implementation burden.
- L2 Inline: Attribute lists on headings/links/images; attribute objects in lists; property tables; heading-scoped subjects. See also D2 diagrams in `MARKDOWN_LD_DIAGRAMS_L2.md`.
- L3 Advanced: Semantic merge policies; CRDT/OT integration; stable chunking across heavy edits; rename detection for headings. See also Embedded Sessions in `MARKDOWN_LD_SESSIONS_L3.md`.

## 10. Media Types

- Source: `text/markdown+ld`
- Serialized graph (optional export): `application/ld+json; profile="markdown-ld"`

## 11. Examples

See `doc/spec_examples.md` for end-to-end documents and the extracted triples.

## 12. References

- CommonMark: https://spec.commonmark.org/
- JSON-LD 1.1: https://www.w3.org/TR/json-ld11/
- RDF Concepts: https://www.w3.org/TR/rdf11-concepts/
- RFC 8785 (JCS): https://www.rfc-editor.org/rfc/rfc8785

## 13. Determinism (RFC 8785)

- JSON Canonicalization Scheme (JCS, RFC 8785) is used everywhere we require a stable string of a JSON object: blank node IDs, stable chunk ID payloads, and literal JSON comparison.
- Blank node IDs: `_:sha256(jcs(expanded_obj))[0..12]`.
- Stable chunk ID payload: `jcs({"heading_path": [...], "block_index": n, "text_hash": sha256(text_norm)})`.

### Appendix A - Heading Slug Algorithm (Normative)
- Lowercase input, trim ends.
- Normalize to NFKD and strip diacritics to ASCII.
- Remove punctuation except `-` and `_`.
- Collapse all whitespace to single hyphen `-`.
- Collapse multiple hyphens, then trim leading/trailing hyphens.

### Appendix B - Text Normalization for `text_hash`
- Normalize line endings to `\n`.
- Trim trailing spaces on each line.
- Collapse runs of spaces/tabs to a single space.
- Remove trailing blank lines.

## 14. Attribute Objects (Mini Grammar, Normative)

- Scope: recognized only as list items beginning with `- { ... }`.
- Keywords allowed: `@id`, `@type`, `@context`.
- Properties: terms/CURIEs/IRIs expanded via context.
- Key suffix: `[]` is reserved for non-keyword properties only; it is forbidden on keywords (e.g., `@id[]`, `@type[]`).
- Entry separators: either commas or whitespace; precedence rules: commas inside `[...]` belong to list parsing; outside lists, a comma terminates the current entry; otherwise one or more spaces separate entries.
- Values: strings (`"..."` with JSON escapes, optional `@lang` or `^^datatype`), numbers (typed by lexical form below), booleans, IRIs `<...>` (absolute), CURIEs `prefix:suffix`, lists `[v (, v)*]`, nested objects `{ ... }`.
- Numbers typing by lexical form:
  - `-?0|[1-9][0-9]*` → xsd:integer
  - `-?(0|[1-9][0-9]*)\.[0-9]+` (no exponent) → xsd:decimal
  - Otherwise (contains `e|E`) → xsd:double
- Language tags: compare/emit using lowercase BCP-47; preserve original case if pretty-printing sources.
- IRIs: resolve relative IRIs against `ld.base` using WHATWG URL; if no `ld.base`, treat as a plain string in strict mode (error) or a string literal in lax mode.
- Disambiguation: unquoted tokens matching IRI/CURIE/number/boolean are typed; otherwise strings.
- Emission:
  - `@type`: one `rdf:type` triple per value (list expands).
  - Property kinds: IRI/CURIE → IRI object; scalars → literals; list with key suffix `[]` → `@list` (ordered); list without `[]` → multi-valued set (unordered).
  - Nested object without `@id` → deterministic blank node + recurse; with `@id` → link and recurse.
- Context merge: frontmatter then local `@context`; nested objects inherit the parent object’s merged context and then apply their own `@context`; later overrides earlier; no remote fetches.

## 15. Error Handling

Error taxonomy (normative): `:parse_error`, `:unknown_prefix`, `:invalid_context`, `:limit_exceeded`, `:invalid_value`, `:invalid_list`, `:invalid_iri`.

- Strict mode: any of the above aborts the attribute object block; record error with byte offsets; emit no triples.
- Lax mode: downgrade `:unknown_prefix` and `:invalid_value` to string literal; others remain hard errors. Unmatched quotes/brackets are always errors.
- Limits: max object depth 32, max list length 1024, max object size 16KB.

Move+edit ordering: when both happen for the same stable chunk ID within one patch, emit `:move_block` then `:update_block` to keep streaming consumers stable.
