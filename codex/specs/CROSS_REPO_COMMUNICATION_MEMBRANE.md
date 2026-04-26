# Cross-Repo Communication Membrane (loci <-> lang/mulsp)

## Decision

Daemon/runtime ownership belongs to executable surfaces, not contract loci.

- `../loci/loci/*`: profile/contracts/spec artifacts (typed holes, passports, dialogue ledgers).
- `../loci/daemon/*`, `../loci/cmd/main/*` or `lang/node|net|mulsp/*`: executable command/runtime behavior.
- `lang/codex/*`: cross-agent conversation model and ingestion surface for MuON chain artifacts.

For this move, retrieval target is **this repo (`lang`)** under mulsp-facing ownership.

## Why this split

- Keeps loci replayable and reviewable without drifting into runtime coupling.
- Lets runtime evolve with testable behavior in one place.
- Prevents dual ownership of daemon command semantics.

## Required crossing artifacts

Input artifacts from `../loci/loci/chatgpt`:

- `specs/mulsp-handoff-passport.muon`
- `specs/mulsp-handoff-bundle.sha256`
- `dialogue/chatgpt-codex.muonlog`
- `DIALOGUE_APPEND_ONLY_MUON_SPEC.md`

Local receiving artifacts in `lang`:

- `codex/specs/loci-mulsp-pickup-passport.muon`
- `codex/specs/CROSS_REPO_COMMUNICATION_MEMBRANE.md`
- `codex/tools/verify_loci_mulsp_handoff.sh`

## Crossing protocol (best-practice)

1. Emit source passport in loci (`intent: implement` or `intent: verify`).
2. Freeze bundle hash list (`*.sha256`) for all crossing files.
3. Receiver validates hashes and required files before any code changes.
4. Receiver emits reciprocal pickup passport in target repo.
5. Implement only in runtime-owned modules (`mulsp`/daemon/CLI), never inside locus-only docs.
6. Append one dialogue ledger entry with resulting refs and verdict.
7. If behavior moves, update docs to point to new owner and keep old locus as historical contract.

## Ownership matrix

- Conversation contract language/schema: `loci/chatgpt/*.md`, `*.muon`
- Dialogue append-only log format: loci spec + mu upstream spec candidate
- Command routing (`daemon conv ...`): runtime repo (`cmd/main`, daemon host, mulsp bridge)
- Runtime execution semantics (host I/O, state transitions): `lang/node`, `lang/mulsp`, runtime packages
- Conformance tests for bridge behavior: runtime repo
- Narrative/design residue: loci

## Noted artifact hygiene issue

`../loci/loci/chatgpt/dialogue/chatgpt-codex.muonlog` contains mixed atom spellings in one entry (`:codex_`, `:meta_dialogue_`).

Recommendation: keep append-only policy intact, but add a normalization rule in the parser/validator:

- reject unknown speaker atoms for new entries,
- keep legacy entries readable with explicit `status: :legacy_nonconforming` in diagnostics.
