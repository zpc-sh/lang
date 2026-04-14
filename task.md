# Task Tracker — Mu / Merkin / Lang Trio

## Phase 1: Merkin Container Layer
- [x] `merkin/storage/container.mbt` — CognitiveContainer pack/unpack
- [x] OCI manifest support in `merkin/storage/oci.mbt`
- [ ] Container round-trip test

## Phase 2: Mu Section Parser/Writer
- [x] `mu/mbt/wasm/sections.mbt` — .mks/.prc/.pr1 binary read/write
- [x] `Module::custom_sections` in `mu/mbt/wasm/module.mbt`
- [x] `mu/mbt/wasm/sections.mbt` — section injection/stripping/patching

## Phase 3: Lang Node Kernel
- [x] `lang/node/node.mbt` — Node struct + lifecycle
- [x] `lang/node/host.mbt` — host extern declarations (HostBridge + stub)
- [x] `lang/node/bus.mbt` — message bus (typed topics, subscriber dispatch)
- [x] `lang/node/cas.mbt` — CAS wrapper (envelope, ingest, query, stats)

## Phase 4: mulsp + muyata Wrappers
- [x] `lang/mulsp/mulsp.mbt` — AI runtime wrapper (lifecycle FSM)
- [x] `lang/muyata/muyata.mbt` — AI-shaped Yata profile (tier hierarchy)

## Phase 5: Plugin System + WASM Interface
- [x] `lang/plugin/registry.mbt` — dynamic plugin registry
- [x] `lang/wasm_iface/iface.mbt` — WASM manipulation surface
- [x] Cognitive boundary WASM operations (inject/extract/strip/depth)

## Phase 6: LSP + Emergent Personas
- [x] `lang/lsp/frame.mbt` — LSP frame codec
- [x] `lang/lsp/message.mbt` — LSP message classification
- [x] `lang/emergent/emergent.mbt` — emergent persona (policy, bloom, residue)

## Phase 7: Finger + GMU/1
- [x] `lang/finger/finger.mbt` — discovery + GMU/1 wire format + FINGER-CERT

## Phase 8: Cognitive Boundary System
- [x] `lang/cognitive/boundary.mbt` — Layered WASM identity
  - [x] 4-layer depth model: AI → AI+Model → AI+Model+Session → AI+Model+Session+Semantics
  - [x] Self-authenticating boundary constraints
  - [x] Binary wire format (CBND magic)
  - [x] CognitiveIdentity builder from mulsp + muyata state
  - [x] WASM inject/extract .cb0-.cb3 custom sections
  - [x] Full round-trip tests

## Phase 9: Code Cave Storage System
- [x] `lang/cave/cave.mbt` — In-WASM partitioned storage
  - [x] 4 standard partitions: .cave.public / .cave.model / .cave.session / .cave.loci
  - [x] Cognitive depth gating (each partition requires its depth level)
  - [x] Key-value CRUD with seal (immutable entries → anchor artifacts)
  - [x] Capacity enforcement + dirty tracking
  - [x] Binary serialization round-trip
  - [x] CaveStore — the full daemon state with depth-gated read/write/delete/seal
  - [x] Genius Loci helpers: loci_put/loci_get/loci_seal/loci_keys

## Build & Test Status
- **Build**: 0 errors, 13 packages
- **Tests**: 61/61 passed

## Architecture Notes
- **No filesystem**: Neither mulsp nor muyata writes to the host filesystem
- **WASM IS the daemon**: All state lives in code caves (custom sections in the binary)
- **Cognitive boundaries**: The binary self-authenticates — AI either CAN read a layer or CAN'T
- **Genius loci**: The .cave.loci is the AI's root of trust (merkin tree, secrets, anchors)
- **Operations model**: Internal WASM mutations, operations on other WASM, writing into loci
- **Enterprise auth**: Kerberos/etc remains available as an external interface layer
