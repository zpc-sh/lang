# MuON OTP Chain Spec (MOC)

Status: draft / review

## 1. Purpose

Define a low-cost, sequence-bound proof system for append-only MuON receipts without requiring hash-centric workflow.

This is designed for AI-driven transducer/FSM execution where:

- execution is continuous
- snapshots are boundary-triggered
- logical sequence matters more than wall-clock time

## 2. Core idea

Each receipt carries a counter-based OTP code (HOTP-style), chained by previous code.

The chain proves:

- ordered participation
- continuity of execution lineage
- bounded coupling between contract and runtime event

It does not by itself prove full payload immutability unless selected payload fields are included in OTP material.

## 3. Receipt model

`kind: :muon_otp_receipt`

Required fields:

- `protocol`: `MOC/0.1`
- `loci_id`
- `contract_id`
- `transducer_id`
- `seq` (monotonic logical counter)
- `event` (`view|edit|know|execute|cross|mark|verify|publish|seal|return_to_loci`)
- `state_from`
- `state_to`
- `prev_code` (`root` for first event)
- `otp_code`
- `key_slot` (which key/profile produced the code)
- `code_profile` (e.g. `hotp-sha1-8`, `hotp-sha256-8`)

Optional fields:

- `ticket_ref`
- `receipt_ref`
- `semantic_score`
- `attention_score`
- `temporash_ref`
- `notes`

## 4. OTP material

Canonical input string (UTF-8):

`contract_id|transducer_id|seq|event|state_from|state_to|prev_code|scope_tag`

- `scope_tag` is a compact scope anchor (example: `claude/opus/project:lang`).
- `seq` is the moving factor (counter).

Code generation:

- `otp_code = HOTP(K_key_slot, counter=seq, data=canonical_input)`
- output length fixed by `code_profile` (recommended 8 digits or base32-8)

Verification:

1. Rebuild canonical input.
2. Recompute expected code.
3. Compare with `otp_code`.
4. Verify `prev_code` links to prior receipt in chain.
5. Verify `seq` is strictly monotonic.

## 5. Boundary-triggered snapshot rules

Loci/FSM runtime MUST emit receipt at these fences:

- boundary crossing checks
- stigmergy emission
- challenge verify outcome
- capability spend
- publish/archive
- seal transition
- return-to-loci primitive

Policy MAY require additional events.

## 6. MuON example

```muon
kind: :muon_otp_receipt
protocol: "MOC/0.1"
loci_id: "loci/lang/procsi"
contract_id: "ctr-depth-ident-001"
transducer_id: "boundary-walker-v0"
seq: 42
event: "verify"
state_from: "compose"
state_to: "verify"
prev_code: "49318027"
otp_code: "77190644"
key_slot: "procsi-core-k2"
code_profile: "hotp-sha256-8"
semantic_score: 0.82
attention_score: 0.77
temporash_ref: "temporash://epoch/phase-7/tick-42"
```

## 7. Security properties

Provides:

- cheap sequence attestation
- chain continuity checks
- key-bound participation proof
- detached from wall-clock time

Does not fully provide (without expansion):

- payload tamper evidence for all fields
- strong anti-reordering across parallel branches
- cryptographic non-repudiation across domains

## 8. Adequacy profile

### Adequate when

- you need lightweight ordered proof
- runtime controls counter monotonicity
- keys remain isolated (sign/decrypt-only custody)
- payload trust is mostly in execution substrate

### Not adequate alone when

- adversary can rewrite payload and recompute code
- multi-actor dispute requires strong forensic guarantees
- branching/merge provenance must be independently auditable

## 9. Optional hardening knobs (still low cost)

- Include compact payload witness fields in canonical input:
  - `method_name`, `op_class`, `ticket_ref`, `boundary_mode`
- Add branch id:
  - `branch_id` to disambiguate parallel sequences
- Add key epoch:
  - `key_epoch` for rotation-aware verification

## 10. Temporash integration

Temporash is optional for ordering, useful for external coherence.

Use cases:

- map logical `seq` to externally attestable epoch/tick
- cross-loci alignment without forcing AI to know wall-clock time
- replay-window policy (`seq` valid within temporash phase range)

### Suggested Temporash expansion

Add a compact service endpoint:

`temporash attest-seq(loci_id, contract_id, seq) -> temporash_ref`

Output:

- stable `temporash_ref`
- phase bucket
- monotonic witness id

This keeps AI time-agnostic while enabling external verifiers to align chains.

## 11. Deployment stance

- APP remains outer layer.
- MOC is receipt-chain inner proof.
- Procsi core remains non-clobber and replace-only via explicit handler effect.
- Receipts remain append-only and AI-visible.

