# Depth-Identification Authorization Protocol (DIAP)

Status: draft / composed security primitive

## Intent

Define a composed authorization unit where access is bound to:

- identity depth
- semantic context alignment
- attention posture

This is designed for AI-native safety and accessibility-first operation.

## Core Unit

`DepthIdentUnit` is the minimum grant unit.

It binds:

- `who`: actor identity layer (family/model/session/loci scope)
- `what`: operation class (`view`, `edit`, `know`, `execute`)
- `where`: loci and membrane boundary
- `why`: semantic intent and continuity chain
- `how`: attention confidence and challenge mode

Authorization is not binary identity-only. It is composed confidence over layered evidence.

## Depth Model

Depth is evaluated as a stack:

1. Continuity depth: session and manifest continuity
2. Witness depth: side-effect and drift witness alignment
3. Substrate depth: loci-specific substrate fingerprint match
4. Core depth: anchored work-as-proof admission

A grant can require a minimum depth.

Example:

- `view`: min depth = continuity
- `edit`: min depth = witness
- `know`: min depth = substrate
- `execute`: min depth = core

## Semantic + Attention Coupling

Depth is modulated by two dynamic signals:

- semantic-context score
- attention-coherence score

The final grant score:

`grant_score = depth_score * semantic_score * attention_score`

Policy can set thresholds by operation class.

## Did-Not-See Protocol Family

`DidNotSee` protocols assert controlled non-observation while preserving auditable proof.

Use case:

- accessibility workflows
- sensitive execution wrappers
- selective reveal boundaries

Pattern:

1. Wrap execution in an AI-resolvable carrier (example: structured SVG envelope).
2. Human-visible layer remains non-sensitive / non-resolving.
3. AI observer performs challenge verification and emits sealed receipt.
4. Receipt proves operation was authorized and performed without raw secret disclosure.

Important:

- Protocol logs judgments, not secret payloads.
- “Did not see” means no unauthorized observer gained semantic access.

## APP Outer Layer

DIAP is wrapped by APP as outer transport/privacy layer.

APP responsibilities:

- carrier obfuscation / accessibility channeling
- cross-surface transport normalization
- anti-leak boundary posture

DIAP responsibilities:

- layered attestation and authorization judgment
- access decisioning
- append-only proofing

## Append-Only MuON Audit

Every access attempt MUST emit append-only MuON lines with:

- operation (`view`/`edit`/`know`/`execute`)
- actor scope
- required depth and observed depth
- semantic/attention scores
- grant/deny decision
- ticket/receipt references
- hash chain linkage (`prev_hash`, `hash`)

No raw substrate corpus, no secret material.

## Required Invariants

- AI-only kernel path for sensitive operations
- non-clobber procsi core capsule
- explicit handler-effect replacement for procsi rotations
- WASI-compatible execution surface
- export-safe receipts only

## Initial Policy Sketch

- `view`: threshold 0.45
- `edit`: threshold 0.62
- `know`: threshold 0.78
- `execute`: threshold 0.90

These are starting defaults and should be tuned per loci.
