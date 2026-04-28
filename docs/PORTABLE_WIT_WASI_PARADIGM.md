# Portable WIT/WASI Design Paradigm

This paradigm is extracted from `../loci` (`wit/*`, `wasm_entry/*`, `wasm_lib/*`) and integrated into `lang`.

## Core Pattern

1. Keep domain logic pure.
2. Expose two runtime surfaces:
   - Direct export surface (`String`/typed functions) for hosts that can pass rich values.
   - Integer slot ABI (`i32` + shared byte slots) for hosts with strict calling conventions.
3. Make execution contract-driven:
   - Emit self-describing contract/artifact lines.
   - Gate execution with explicit capability checks.
   - Provide a deterministic preflight bitmask.

## Why This Travels Well

- Works across WasmEdge, wasmex/BEAM, and other runtimes with different ABI constraints.
- Keeps host integration thin while preserving one canonical behavior.
- Makes policy and safety auditable in artifacts, not hidden in host glue.

## Implementation In This Repo

- Reusable helpers: [`/home/locn/ratio/lang/sdk/portable_wasi/portable_wasi.mbt`](/home/locn/ratio/lang/sdk/portable_wasi/portable_wasi.mbt)
  - `preflight_bits`
  - `block_has_ready_markers`
  - `has_required_capability`
  - `execute_command_json`
- Integrated wasm runtime path:
  - [`/home/locn/ratio/lang/sdk/wasm/host.mbt`](/home/locn/ratio/lang/sdk/wasm/host.mbt)
  - `lm_sdk_emit_contract`
  - `lm_sdk_contract_preflight`
- Canonical artifact emitter:
  - [`/home/locn/ratio/lang/loci/codex/codex.mbt`](/home/locn/ratio/lang/loci/codex/codex.mbt)
  - `codex_codex_handshake_artifact`

## Portable Template For New Projects

1. Define WIT world/interfaces first.
2. Build pure core implementation with no host I/O assumptions.
3. Add a direct export package (thin wrappers only).
4. Add a slot-ABI package (`slot_put`, `slot_len`, `op`, `out_len`, `out_get`).
5. Define canonical contract artifact lines and required capabilities.
6. Add preflight API and enforce gating before execute.
7. Test both positive and negative gates in wasm-level tests.

## Minimal Compatibility Contract

- Contract readiness markers:
  - `@deploy_ready true`
  - `@cross_repo_ready true`
- Required capability:
  - `fn:codex.connector.channel`
- Execute command:
  - `workspace/executeCommand` with command `lsp.dual.contract.execute`

