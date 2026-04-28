# Loci Event Chain Feature Requirements

Status: implementation checklist
Version: `LOCI_EVENT_CHAIN/0.1`

## Required features

1. Event normalization
- all producers emit EventInput shape
- unknown producers rejected by policy

2. Canonical append service
- loci-only append authority
- readonly block immutability after append
- deterministic block id generation

3. Branch and merge support
- per-branch monotonic height
- merge block with `parent_block_refs` length >= 2

4. Sequence discipline
- monotonic `seq` checks per source+branch
- duplicate event id rejection

5. Fence enforcement
- required block append on all mandatory fences
- hard fail if fence event lacks append

6. Coredump integration
- fail-close primitive emits coredump event
- coredump must append before branch closure

7. Projection layer
- EventOutput generation with visibility labels
- redaction policy for boundary/external

8. Provenance-through guarantee
- every block references prior lineage
- return-to-loci blocks include closure refs

## Optional upgrades

1. Counter-OTP chain fields for low-cost continuity proof
2. Temporash refs for external temporal coherence
3. Batch append for high-throughput terminal ingest
4. Compact binary encoding alongside MuON projection
