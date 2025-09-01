Title: JSON‑LD Library Integration Proposals (URDNA2015 + Offline‑First)

Summary
- Add first‑class URDNA2015 canonicalization and dataset hashing with offline context loading.
- Provide deterministic fallbacks (stable JSON), explicit error types, and telemetry.
- Expose compact/expand/frame helpers that default to no‑network behavior.
- Include developer ergonomics (mix tasks, test helpers) and streaming APIs.

Core APIs
1) Canonicalize (URDNA2015)
   - `JSONLD.c14n(term, opts \\ []) :: {:ok, %{nquads: iodata, bnode_map: map}} | {:error, term}`
     - opts: `context_loader: loader`, `no_remote: true`, `allow_remote: false | true`, `allowlist: [iri]`, `timeout: ms`

2) Dataset Hash
   - `JSONLD.hash(term, opts \\ []) :: {:ok, Integrity.t} | {:ok, {Integrity.t, iodata}} | {:error, term}`
     - opts: `algorithm: :sha256` (default),
             `form: :urdna2015_nquads | :stable_json` (default `:urdna2015_nquads`),
             `return: :integrity | :integrity_and_canonical`.
     - Integrity.t: `%Integrity{algorithm: :sha256, form: atom, hash: String.t(), quad_count: non_neg_integer(), canonical?: boolean}`

3) Equality (Graph‑equivalence)
   - `JSONLD.equal?(a, b, opts \\ [no_remote: true]) :: boolean`
     - Uses `c14n` to compare canonical N‑Quads; falls back to `stable_encode/1` if requested.

Context Resolution (Offline‑First)
- Behaviour: `JSONLD.ContextLoader`
  - `load(iri, opts) :: {:ok, map()} | {:error, {:context_unavailable, iri} | term}`
- Default loader: no network; serves from in‑memory/file registry.
- Registry helpers:
  - `JSONLD.ContextLoader.register(iri, context_map)`
  - `JSONLD.ContextLoader.clear()` / `delete(iri)`
- Options:
  - `no_remote: true` (default)
  - `allow_remote: true` with `allowlist: [iri]` and caching interface.

JSON‑LD Operations
- `JSONLD.expand(term, opts)`
- `JSONLD.compact(term, context, opts)`
- `JSONLD.frame(term, frame, opts)`
- `JSONLD.nquads_encode(graph) :: iodata`
- `JSONLD.nquads_decode(iodata) :: {:ok, graph} | {:error, term}`
- `JSONLD.diff(a, b, opts) :: {:ok, %{added: graph, removed: graph}} | {:error, term}` (operate on canonical forms)

Deterministic Fallbacks
- `JSONLD.normalize(term) :: normalized_term`
  - Map keys stringified and sorted
  - Atoms coerced to strings (except true/false/nil)
  - Date/Time types ISO8601
- `JSONLD.stable_encode(term) :: iodata`
  - Single‑pass encode using `normalize/1`.

Error Types (non‑exhaustive)
- `{:context_unavailable, iri}`
- `:expansion_failed | :compaction_failed | :framing_failed`
- `:canonicalization_failed`
- `{:timeout, op}`

Telemetry
- Spans emitting measurements and metadata:
  - `[:jsonld, :canonicalize]` — size, duration, quad_count
  - `[:jsonld, :hash]` — form, algorithm, duration
  - `[:jsonld, :expand] | :compact | :frame`

Performance & Streaming
- `JSONLD.stream_decode(io_or_iodata, opts)` — evented decode for large inputs
- `JSONLD.stream_nquads(iodata_or_device, graph, opts)` — incremental N‑Quads emit
- Optional NIF fast‑paths behind a feature flag; pure Elixir remains default.

Developer Ergonomics
- Mix tasks:
  - `mix jsonld.c14n path/to/file.jsonld --out file.nq --no-remote`
  - `mix jsonld.hash path/to/file.jsonld --form urdna2015_nquads`
- Test helpers:
  - Fixture context loader and golden N‑Quads comparator
  - Helpers for asserting graph equality via `equal?/3`

Example Usage
```elixir
loader = &MyApp.Contexts.load/2
{:ok, %{nquads: nq}} = JSONLD.c14n(doc, context_loader: loader, no_remote: true)
{:ok, integrity} = JSONLD.hash(doc, form: :urdna2015_nquads)
same? = JSONLD.equal?(doc_a, doc_b, no_remote: true)
```

