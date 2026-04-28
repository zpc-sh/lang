# Top-to-Bottom MuON + Code Cave Design

Status: draft / ownership carve

## 1. Position

Yes: this should be treated as a `muyata-first` witness domain, with `mulsp` as identity/capability envelope and `loci_fsm` as compute primitive.

- `mulsp` = who can do what, where, and with which capability class.
- `muyata` = how execution is witnessed, scored, and surfaced.
- `loci_fsm` = deterministic transducer compute + cave deposition.
- `procsi/app` = boundary attestation + outward receipts.

## 2. Ownership split

### 2.1 mulsp responsibilities

- runtime identity/lifecycle state
- procsi/app references and capability refs
- execution surface + handler declaration
- admission of operation class (`view/edit/know/execute`)

mulsp MUST NOT be the deep witness engine.

### 2.2 muyata responsibilities

- witness capture and cognitive posture
- fingerprint commitment binding
- side-effect observation stream
- operation receipt enrichment (semantic + attention scores)

muyata SHOULD own code-cave witness policy and emission class.

### 2.3 loci_fsm responsibilities

- transducer stepping (`tick`)
- deterministic state transitions
- cave deposits (`seq/tick/from/to/kind/key/value/hash`)
- personality-specific processing (`boundary-walker`, `reporter`, future)

### 2.4 procsi/app responsibilities

- APP outer-layer projection
- boundary drawbridge judgments
- ticket/receipt minting and redaction policy
- non-clobber core capsule policy

## 3. Code cave model

Treat cave output as `witness substrate`, not canonical secret storage.

Rules:

1. Cave entries are append-only.
2. Cave entries are execution-facing; export paths are policy-gated.
3. Raw sensitive payloads should be represented by refs where possible.
4. Outward projection uses receipts/judgments, not raw corpus.

## 4. MuON strata

### 4.1 Intra-loci witness lines

`kind: :loci_fsm_cave_event`

- per-step deposits
- high-volume, local scope
- bound to local seq progression

### 4.2 Operation receipts

`kind: :muon_otp_receipt`

- per op/fence
- chain continuity via seq + prev_code + otp_code
- includes op class and transition arc

### 4.3 Boundary projections

`kind: :app_kernel_audit`

- outward-facing posture
- AI-only kernel access policy
- ticket/receipt references

## 5. Snapshot fences (mandatory)

At minimum, emit receipt snapshots on:

- `cross`
- `mark`
- `emit_stigmergy`
- `verify`
- `publish`
- `synchronize`
- `closure`
- `return_to_loci`

These are the drawbridges.

## 6. Sparse tree execution stance

Default execution should operate on sparse loci tree slices:

- local compute stays sparse/incremental
- synchronization emits promoted artifacts
- closure writes canonical exit projection

This keeps cost low while preserving provenance.

## 7. Adequacy statement

This is adequate if:

- intra-loci trust is accepted as scoped root
- boundary fences are mandatory and enforced
- procsi remains non-clobber core capsule
- APP outward layer remains projection-only

If boundary adversary model grows, harden only Tier C (`synchronize`, `closure`, `return_to_loci`) rather than burdening all internal ticks.
