# Loci Event Blockchain Spec

Status: handoff-ready
Version: `LOCI_EVENT_CHAIN/0.1`

## 1. Domain contract

In this domain, all runtime surfaces are normalized into:

- **event input**
- **event output**

No subsystem owns canonical history except `loci`.

## 2. Ownership model

- `loci`: canonical append-only readonly block chain
- `mulsp`: identity/capability lifecycle event emitter
- `muyata`: witness/context/transducer event emitter
- `procsi/app`: boundary attestation/ticket/receipt emitter
- `fst runtimes`: operation and coredump event emitters

## 3. Core data model

### 3.1 EventInput

```text
EventInput
- event_id : String
- source : mulsp|muyata|procsi|app|fst|terminal|system
- event_kind : String
- loci_id : String
- branch_id : String
- seq : Int
- payload_ref : String
- parent_event_refs : Array[String]
- return_to_loci_hint : Bool
```

### 3.2 EventOutput

```text
EventOutput
- output_id : String
- from_event_id : String
- output_kind : String
- projection_ref : String
- ticket_ref : String?
- receipt_ref : String?
- visibility : internal|boundary|external
```

### 3.3 LociBlock (canonical)

```text
LociBlock
- block_id : String
- height : Int
- loci_id : String
- branch_id : String
- parent_block_refs : Array[String]
- source : String
- event_kind : String
- seq : Int
- payload_ref : String
- event_ref : String
- return_to_loci_ref : String?
- readonly : Bool
```

## 4. Append semantics

1. Only `loci` may append canonical blocks.
2. Each append must reference parent block(s).
3. `height` is monotonic per branch.
4. Branch merges use multi-parent blocks.
5. `readonly` is always true post-append.

## 5. Event flow

1. Producer emits `EventInput`.
2. Validator checks policy (source, sequence, branch, required refs).
3. Loci appends `LociBlock`.
4. Optional `EventOutput` projection emitted.

## 6. Required fences

Must append blocks at:

- `cross`
- `mark`
- `emit_stigmergy`
- `verify`
- `publish`
- `synchronize`
- `closure`
- `return_to_loci`
- `runtime_coredump`

## 7. Fail-close rule

For code-cave workloads:

- on collapse/violation/unhandled event:
  1. emit coredump event
  2. append coredump block
  3. close branch

## 8. Sparse tree integration

Sparse loci tree remains working set.

Blockchain metadata layer records:

- where events came from
- which branch they flowed through
- when they returned to loci
- what outputs were projected

## 9. Security posture

- no raw secret export in canonical blocks
- secret zone refs only
- boundary projections are redacted outputs
- append-only readonly chain is authoritative

## 10. Minimum implementation features

- branch-aware append API
- deterministic block-id derivation
- sequence monotonicity checks
- merge block support
- coredump append hook
- projection filter by visibility
