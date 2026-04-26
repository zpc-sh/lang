# lang — Claude Orientation Guide

This repository is a MoonBit runtime for multi-model AI agents. It implements the
full stack from wire codecs (LSP/NNTP/Gopher/GMU-1) through session identity
(`mulsp`/`muyata`) to stigmergic coordination (`loci/claude`).

**Build system:** `moon` (MoonBit). Run `moon test` from the repo root to
verify all packages. Currently: 0 errors, tests pass.

---

## Recursive Spec Pattern

Every partition in this repo can self-describe via a `*_spec.mbt` + `*_spec_test.mbt`
pair. The pattern lets a fresh Claude instance understand any package immediately
and enforces that implementations stay aligned with their declared surface.

### How it works

```
<pkg>/
  <pkg>.mbt           ← implementation
  <pkg>_spec.mbt      ← self-emitted spec (metadata types + spec function)
  <pkg>_spec_test.mbt ← spec-driven tests (probes spec data + exercises real API)
```

**`<pkg>_spec.mbt`** defines:
- `<Pkg>Category` enum — functional subsystems (e.g. Lifecycle, Fork, Mutation)
- `SpecSize` enum — complexity class: Trivial / Small / Medium / Large
- `<Pkg>FuncType` enum — operational role: Constructor, Transition, Builder, etc.
- `<Pkg>FnSpec` struct — `{ name, category, size, func_type, can_fail }`
- `<pkg>_spec() -> Array[<Pkg>FnSpec]` — the partition presenting its full API as data

**`<pkg>_spec_test.mbt`** verifies:
- Per-category function counts (catches additions without spec updates)
- Type rules (e.g. Builder never fails, Codec entries are Large)
- Real API behaviour matches the declared metadata (transitions, round-trips, etc.)

### Canonical example: `mulsp`

`mulsp/mulsp_spec.mbt` documents 25 public functions across 5 categories:

| Category     | Count | Key types                           |
|--------------|-------|-------------------------------------|
| Lifecycle    | 7     | Constructor, Transition, Builder    |
| Fork         | 4     | Delegation, Predicate               |
| Mutation     | 8     | Builder (all infallible)            |
| Query        | 4     | Predicate, Counter (all Trivial)    |
| Serialization| 2     | Codec (both Large; from_bytes fails)|

`mulsp/mulsp_spec_test.mbt` has 25 tests, each grounded in `mulsp_spec()` data.

### Applying the pattern to a new partition

1. Read the existing implementation (`<pkg>.mbt`) and list all `pub fn` signatures.
2. Classify each function by category, size, type, and can_fail.
3. Create `<pkg>_spec.mbt`:
   - Copy the enum and struct definitions from `mulsp/mulsp_spec.mbt`.
   - Rename `Mulsp*` → `<Pkg>*`.
   - Fill in `<pkg>_spec()` with one entry per public function.
4. Create `<pkg>_spec_test.mbt`:
   - Write count tests for each category (these are the enforcement layer).
   - Write at least one behavioural test per category verifying can_fail contract.
5. Run `moon test` — all new tests must pass before commit.

### What makes this recursive

- The spec is **data** (`Array[FnSpec]`), not just prose. Tests consume it.
- Any Claude reading `<pkg>_spec.mbt` sees the full API surface in ≤100 lines.
- Count tests fail when the implementation diverges from the spec, forcing sync.
- A new Claude can apply this same pattern to any uncovered partition by following
  the steps above — the pattern is self-replicating across the repo.

---

## Package Map

| Package          | Purpose                                              |
|------------------|------------------------------------------------------|
| `mulsp`          | AI session identity (lifecycle, fork, serialization) |
| `muyata`         | Cognitive tier profile (Haiku/Sonnet/Opus + intent)  |
| `loci/claude`    | Haiku stigmergy via cave storage                     |
| `emergent`       | Residue emission and persona                         |
| `cave`           | CaveStore — tiered key-value storage (loci partition)|
| `lsp`            | LSP framing and JSON-RPC message classification      |
| `codex`          | Conversation locus over Muon chains                  |
| `spore`          | Mobile agent serialization                           |
| `finger`         | GMU/1 peer identity (FingerState)                    |
| `cognitive`      | Cognitive boundary classification                    |
| `plugin`         | Plugin registry and WASM interface                   |
| `node`           | Node kernel (HostBridge, bus, CAS)                   |
| `nntp`           | NNTP codec (gossip + OCI transport)                  |
| `gopher`         | Gopher codec (capability discovery)                  |
| `gemini`/`gemtext` | Gemini protocol and markup codec                   |
| `proto`          | Protocol registry                                    |
| `yata/*`         | Yata work units (void, flow, grammar, manifold)      |
| `net`            | Async TCP layer (M1 milestone — in progress)         |

---

## Key Invariants

- `MulspState` transitions are immutable — every mutation returns a new value.
- `MulspLifecycle` is a strict state machine; illegal transitions return `None`.
- The `loci` cave partition is the shared substrate for all stigmergy.
- `HaikuScout::observe` only deposits when lifecycle is `Active`.
- Wire formats use magic bytes + LE u32 length-prefixed UTF-8 strings.
- All serialization functions must round-trip: `from_bytes(to_bytes(x)) == Some(x)`.
