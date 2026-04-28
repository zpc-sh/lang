# Three-Body Lock: Executable MoonBit Markdown

Status: mirrored from loci baseline  
Scope: `loci <-> mu <-> lang`  
Intent: keep all three projects in one contract-runtime paradigm and avoid drifting into two-way lock failure modes.

## Dialogue Protocol Note

This mirror is intentionally protocol-safe:
- source pattern maintained in `loci/docs/THREE_BODY_LOCK_EXECUTABLE_MOONBIT.md`
- local repo owners may extend sections, but should preserve lock schema fields
- cross-repo updates should flow by explicit dialogue/handoff packet, not silent overwrite

## Executable Snapshot

Run from this repo root:

```bash
./scripts/three_body_lock_snapshot.sh
```

Outputs:
- `artifacts/three-body-lock/snapshot.json`
- `artifacts/three-body-lock/snapshot.md`

## Required Shared Fields

- `project`
- `head`
- `branch`
- `contract_surface_version`
- `runtime_chain_status`
- `proof_status`
- `generated_at_utc`
