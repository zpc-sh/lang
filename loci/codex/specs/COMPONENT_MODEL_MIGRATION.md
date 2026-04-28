# Codex Capsule -> WebAssembly Component Model

## Decision
Use `wit/world.wit` as the ABI root-of-truth for cross-language interoperability.

Keep `codex_spec.mbt` as the semantic/domain contract (invariants, stage semantics,
validation behavior) implemented by MoonBit.

In short:
- WIT is the transport and component boundary contract.
- MoonBit spec/code is the behavior and invariant contract.

## Why WIT-first
- Component Model compliance is defined at the WIT/component boundary.
- `wit-bindgen` regeneration is deterministic and language-portable.
- Host/runtime implementations (Rust, Wasmtime, JS in future) can integrate from the same contract.

## Mapping from current capsule
Current MoonBit types/functions are mapped 1:1 in `wit/world.wit`.

- `CodexStage` -> `codex-stage`
- `MuonRole` -> `muon-role`
- `MuonEvent` -> `muon-event`
- `MuonChain` -> `muon-chain`
- `ConversationLocus` -> `conversation-locus`
- methods become `chain-*` and `locus-*` free functions

## Regeneration workflow
From `/home/locn/ratio/lang/loci/codex`:

```bash
wit-bindgen moonbit wit/world.wit --out-dir . --derive-eq --derive-show --ignore-stub
moon build --target wasm
wasm-tools component embed wit _build/wasm/release/build/gen/gen.wasm --encoding utf16 --output codex.embedded.wasm
wasm-tools component new codex.embedded.wasm --output codex.component.wasm
wasm-tools component wit codex.component.wasm
```

## Practical source-of-truth rule
- Edit `wit/world.wit` first for any interface shape change.
- Regenerate bindings.
- Implement/update logic in MoonBit stubs.
- Run tests + component-level smoke checks.

## Notes
- WIT does not express all behavioral invariants (e.g. digest determinism, tamper checks).
  Keep those in MoonBit tests/spec and optionally mirrored in prose/spec docs.
- If you later split responsibilities, keep `contract` as a stable exported interface and
  add additional interfaces/world imports instead of breaking existing function signatures.
