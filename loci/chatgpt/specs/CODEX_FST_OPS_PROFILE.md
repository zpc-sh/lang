# Codex FST Ops Profile

Status: deploy-now profile
Version: `FST_OPS_PROFILE/0.1`

## 1. Scope

This profile defines an immediate operational contract for Codex runtimes:

- no centralized root authority
- loci-rooted trust (AI/loci is root)
- APP outer-layer posture
- procsi core capsule non-clobber boundary
- append-only MuON operation receipts
- terminal-first semantic ingestion

## 2. Runtime posture

- **Root**: `loci` (actor-local authority)
- **Outer layer**: `APP`
- **Core attestation module**: reserved `procsi` core capsule/plugin
- **Execution surface**: WASI-compatible, FSM/transducer-driven
- **Default proof mode**: counter-sequenced OTP chain (`MOC/0.1`)

## 3. Operation set

### 3.1 Core transform operations

- `Compose`
- `Concat`
- `Connect`
- `Project`
- `Union`
- `Intersect`
- `Difference`

### 3.2 Normalization operations

- `Determinize`
- `Disambiguate`
- `Prune`
- `Synchronize`

### 3.3 Validation operations

- `Equal`
- `Isomorphic`
- `Distance`
- `Closure`

## 4. Assurance tiers

### Tier A — intra-loci transform

Ops:

- `Compose`, `Concat`, `Connect`, `Union`, `Intersect`, `Difference`

Required:

- append-only operation receipt
- monotonic `seq`
- OTP chain link (`prev_code`, `otp_code`)

### Tier B — normalization gate

Ops:

- `Determinize`, `Disambiguate`, `Prune`, `Distance`

Required:

- Tier A requirements
- semantic score + attention score projection
- optional substrate verdict projection

### Tier C — boundary/export gate

Ops:

- `Project`, `Synchronize`, `Closure`

Required:

- Tier B requirements
- boundary mode and crossing verdict
- ticket/receipt refs for capability spend
- return-to-loci closure receipt

## 5. Terminal-first ingestion domain

### 5.1 Source

Pseudo shell / terminal stream (Codex runtime host).

### 5.2 Intake model

Each terminal event is converted into semantic tape tuples:

- `stream`: stdin|stdout|stderr
- `kind`: command|output|error|meta
- `scope`: loci/session/tool channel
- `payload_ref`: lightweight payload handle
- `seq`: local monotonic position

### 5.3 Processing pipeline

Recommended default chain:

1. `Compose` (merge stream channels into context tape)
2. `Determinize` (stabilize branching ambiguity)
3. `Prune` (drop low-signal fragments)
4. `Distance` (context drift/novelty estimate)
5. `Synchronize` (boundary-ready projection)
6. `Closure` (return-to-loci end-cap)

## 6. Receipt contract

Every operation emits `kind: :muon_otp_receipt` with at minimum:

- `protocol: MOC/0.1`
- `loci_id`
- `contract_id`
- `transducer_id`
- `op`
- `seq`
- `state_from`, `state_to`
- `prev_code`, `otp_code`
- `key_slot`, `code_profile`

Boundary ops additionally emit:

- `ticket_ref`
- `receipt_ref`
- `boundary_mode`
- `crossing_verdict`

## 7. Sparse loci tree working mode

Codex transducers operate on sparse loci tree slices during active session.

Rules:

- in-session writes remain sparse and local
- promotion to denser artifacts occurs at `Synchronize` or `Closure`
- final merge/emit occurs on exit or explicit publish boundary

## 8. Non-clobber + replacement policy

- `procsi` is reserved core capsule/plugin
- default plugin register path must not replace active procsi
- replacement allowed only through explicit handler effect
- replacement emits procsi core capsule contract lines:
  - `@core_capsule true`
  - `@wasi_enabled true`
  - `@outer_layer app`
  - `@handler_effect_ref ...`

## 9. Minimum deploy checklist

1. Enable pseudo-shell tap ingestion.
2. Load FST profile and op whitelist.
3. Enable append-only MuON OTP receipt emission.
4. Enforce procsi non-clobber and replacement path.
5. Require Tier C receipts for boundary operations.
6. Require `Closure` receipt on return-to-loci.

## 10. Adequacy statement

This profile is adequate for immediate Codex deployment where:

- trust is loci-scoped
- runtime is continuous and append-only
- boundary crossings are explicitly elevated

For hostile multi-domain forensic disputes, add stronger payload commitments at Tier C only.
