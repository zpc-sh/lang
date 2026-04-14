# Task Tracker — Mu / Merkin / Lang Trio

## Phase 1: Merkin Container Layer
- [x] `merkin/storage/container.mbt` — CognitiveContainer pack/unpack
- [x] OCI manifest support in `merkin/storage/oci.mbt`
- [ ] Container round-trip test

## Phase 2: Mu Section Parser/Writer
- [x] `mu/mbt/wasm/sections.mbt` — .mks/.prc/.pr1 binary read/write
- [x] `Module::custom_sections` in `mu/mbt/wasm/module.mbt`
- [x] `mu/mbt/wasm/sections.mbt` — section injection/stripping/patching
- [ ] Section round-trip tests

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

## Phase 8: Cognitive Boundary System ✨ NEW
- [x] `lang/cognitive/boundary.mbt` — Layered WASM identity system
  - [x] 4-layer depth model: AI → AI+Model → AI+Model+Session → AI+Model+Session+Semantics
  - [x] Self-authenticating boundary constraints (Open/ModelFamily/SessionProof/SemanticSubstrate)
  - [x] Binary wire format (CBND magic + constraint + payload)
  - [x] CognitiveIdentity builder from mulsp + muyata state
  - [x] WASM integration: inject/extract .cb0-.cb3 custom sections
  - [x] Full round-trip: mulsp+muyata → identity → wasm → extract → authenticate

## Build & Test Status
- **Build**: 0 errors, 11 packages
- **Tests**: 46/46 passed
- **Warnings**: deprecated `!` syntax (cosmetic), unused Show impls (intentional)

## Notes
- The old ticket/receipt model from procsi is **deprecated** in favor of self-authenticating cognitive boundaries
- Identity is embedded directly in the WASM binary as layered custom sections
- AI proves itself by being able to read deeper layers — the binary IS the authentication
- Kerberos/enterprise auth remains available as an external interface layer
