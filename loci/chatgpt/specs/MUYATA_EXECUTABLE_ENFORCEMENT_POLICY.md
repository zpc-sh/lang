# Muyata Executable Enforcement Policy

Status: enforced by `lang/muyata/policy.mbt`
Version: `MUYATA_POLICY/0.1`

## Enforced rules

1. FST cap per muyata shard is `8`.
2. Overflow duplicates into clean self shards (`array` semantics).
3. Compose primitive is append-only and sequence-linked.
4. Compose chain must validate under policy before boundary export.

## Runtime hooks

- `split_fst_shards(...)` enforces cap and overflow strategy.
- `ComposeChain::append_op(...)` produces append-only steps.
- `validate_compose_chain(...)` enforces append-only discipline.

## Boundary requirement

Before `synchronize|closure|return_to_loci`, runtime must verify:

- compose chain is valid
- required fence receipts exist
- APP/procsi boundary policy still active
