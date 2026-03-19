Title: Markdown‑LD Enhancements (Parser, Emitter, Validation, Stability)

Summary
- Robust Markdown‑LD parsing/emit with deterministic round‑trips and optional ID anchoring.
- JSON‑LD extraction from frontmatter and fenced blocks; validation hooks and hashing.

Core APIs
1) Parse
   - `MarkdownLD.parse(markdown_or_path, opts \\ []) :: {:ok, [%{doc: map(), location: %{file: binary, line: non_neg_integer}, meta: map()}]} | {:error, term}`
     - Sources:
       - Frontmatter key `jsonld:` (YAML map or JSON)
       - Fenced blocks ```jsonld ... ``` (multiple per file)
     - Options:
       - `anchors: :none | :headings | {:headings, base: iri}` — derive @id from headings
       - `context_loader: loader` (offline‑first)
       - `validate: true | false` with `schema: json_schema`
       - `hash: true | false` (compute Integrity via JSONLD.hash/2)

2) Emit
   - `MarkdownLD.emit(docs, opts \\ []) :: {:ok, iodata} | {:error, term}`
     - Deterministic ordering of keys and blocks; preserves stable layout
     - Options: `frontmatter: :json | :yaml`, `wrap: :fence | :frontmatter`, `anchors: same as parse`

3) Validate
   - `MarkdownLD.validate(docs, opts \\ []) :: {:ok, result} | {:error, %{errors: list}}`
     - Hook JSON Schema validation per extracted JSON‑LD document

4) Utilities
   - `MarkdownLD.scan(dir, opts)` — walks dirs for `*.md` and aggregates parse/validate/hash results
   - `MarkdownLD.to_integrity(doc, opts)` — calls `JSONLD.hash/2` (URDNA2015 default, offline)

Determinism
- Stable ordering of keys within emitted JSON‑LD blocks
- Stable ordering of multiple JSON‑LD blocks by heading order/file order
- Optional ID anchoring strategy:
  - Example: `{:headings, base: "https://example.org/spec#"}` → `@id` = base <> slugified_heading_path

Errors
- `{:invalid_frontmatter, reason}`
- `{:invalid_fenced_block, line}`
- `{:validation_failed, errors}`
- `{:context_unavailable, iri}` (from JSONLD side)

Telemetry
- `[:markdown_ld, :parse]` — count of blocks, duration
- `[:markdown_ld, :emit]` — bytes, duration
- `[:markdown_ld, :validate]` — errors count

Mix Tasks
- `mix markdown_ld.scan priv/lsp/specs --validate --hash --anchors headings` — prints a summary table with counts and hashes
- `mix markdown_ld.emit path/to/in.md --out path/to/out.md --frontmatter json`

Example
```elixir
{:ok, parts} = MarkdownLD.parse(File.read!("spec.md"), anchors: {:headings, base: "https://ex.org/spec#"}, validate: true)

Enum.each(parts, fn %{doc: jd} ->
  {:ok, integrity} = JSONLD.hash(jd, no_remote: true)
  IO.inspect(integrity)
end)

{:ok, rendered} = MarkdownLD.emit(parts, frontmatter: :json)
File.write!("spec.out.md", rendered)
```

