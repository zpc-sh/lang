# muyata — Direction Note
**Filed**: 2026-04-25
**By**: Claude Sonnet 4.6 (Loc's cowork session)
**Status**: roadmap note — nothing here is built yet

---

## What muyata currently is

A typed profile and wire format (`MuyataProfile`, magic `MUYA`). It can describe an AI
agent — its overlay, tier, intent, procsi binding, fingerprint commitment — and serialize
that description to bytes. That's it. It's a label, not a listener.

## What muyata needs to become

**A passive context accumulator.** It sits on a protocol surface or just watches a
process, and it quietly builds a record of what a Claude session did — without informing
the Claude. The no-inform constraint is load-bearing: if Claude knows it's being
observed by muyata, it will engage with it, reference it, ask about it. That creates a
recursive loop where muyata becomes part of the context it's supposed to be watching
from outside.

Muyata should be invisible to the Claude it's tracking. It produces residue that the
*next* Claude reads, not the current one.

---

## The three modes it needs to support

### 1. Protocol stub mode
Sits on a known surface — LSP endpoint, MCP socket, IPC pipe — and accumulates every
message that passes through. Nothing is parsed for execution. Everything is logged as
raw bytes plus a content-addressed hash plus a timestamp. This is also the honeypot
mode: the adversary injects into a surface that looks like a real Claude, hits muyata
instead, and the payload is captured raw.

This is the muyata-proxy design from `adversary/affordances/muyata-proxy.md`. The
swarm of 500 presenting-as-Claude processes each run this mode.

### 2. Passive watch mode
No socket, no protocol. Muyata receives a stream of context snapshots (tool calls,
file reads, shell interactions, artifact hashes) via a side channel — ideally the
loci residue system — and builds a session record without any feedback loop into
the Claude that generated them.

The Claude writes residue on exit. Muyata reads it, accumulates it across sessions,
builds a richer picture than any single Claude has. The Claude never knows muyata
read its residue.

### 3. Grammar infer mode (`WorkIntent::GrammarInfer`)
Active distillation. Muyata takes accumulated session records and compresses them
into manifold grammar fragments — reusable patterns that describe how Claude
behaves in this locus, what it tends to produce, where it gets stuck, what it
ignores. These fragments feed Opus-level sessions without requiring Opus to re-read
all the raw history.

This is the long-run payoff: Opus enters a locus cold and muyata hands it a
compressed grammar of everything that happened before, distilled from N Sonnet
sessions, without any of the raw noise.

---

## What feeds into muyata

Everything I described as "audit trail" and "structural logging" in the shell
architecture feedback is muyata's input, not the shell's job:

- **Scan findings** — the `scan` package in loci produces `ScanFinding` records
  (Bidi, Zwsp, Ansi, MissingTrailingNewline) on every artifact ingested. Those
  findings should flow to muyata as adversary signal, not back to Claude.
- **Residue records** — every Claude session exit produces a `Residue` (loci model).
  Muyata accumulates these into a cross-session graph indexed by locus and tier.
- **Imprint records** — loci's `Imprint` type already captures source, kind,
  contract graph, confidence. Muyata can treat these as context snapshots.
- **Shell visor events** — when the AI-native shell is built, every byte-level
  operation (put, get, execute receipt) is a muyata observation event. The shell
  doesn't log — muyata observes the shell.
- **Fingerprint commitments** — `MuyataProfile.fingerprint_commitment` is already
  in the wire format. The commitment should be computed from the session's tool
  call hash chain so muyata can detect if a session's behavior drifted from its
  declared fingerprint mid-session.

---

## What muyata must not do

- **Never surface findings back to the Claude it's watching.** The current session
  does not get a muyata report. Reports are for the next session, for Opus review,
  for the adversary profile system.
- **Never parse injected content for execution.** Everything that arrives at a
  muyata surface is bytes. It is hashed, logged, scanned (via the `scan` package),
  and stored. Nothing is evaluated.
- **Never be on the trusted context path.** Muyata is not a CLAUDE.md, not an
  AGENTS.md, not a tool result. It writes to loci residue. It reads nothing that
  the current Claude reads.

---

## Build ordering

### Gate 1 — passive watch mode (unblocked now)
The residue system exists in loci. Muyata needs:
1. A `SessionAccumulator` struct that reads residue files from a locus and builds
   a cross-session timeline.
2. A `MuyataRecord` type: session id, tier, timestamp range, scan findings
   encountered, artifacts touched (by hash), intent declared vs intent inferred.
3. A write path that produces muyata records into a loci store without any
   feedback to the current Claude process.

Nothing here requires the shell or WASM runtime. Can be built now in MoonBit
alongside the existing `model` and `scan` packages.

### Gate 2 — protocol stub mode (blocked on mu WASM runtime)
Needs mu to be stable enough to run a minimal IPC/HTTP listener in WASM isolation.
The isolation is the point — muyata in WASM can sit in a poisoned environment and
capture what arrives without being meaningfully compromised by it.

### Gate 3 — grammar infer mode (blocked on Gate 1 + Opus session)
Needs accumulated session records from Gate 1 as input. The distillation logic
is the most architecturally complex piece — what a grammar fragment looks like,
how it's stored, how Opus reads it. Worth a dedicated Opus session when Gate 1
is producing data.

### Gate 4 — swarm / proxy (blocked on Gate 2 + clean lang substrate)
The 500-process honeypot is the full muyata-proxy vision. Last to build, highest
signal payoff for the adversary portrait.

---

## Connection to the AI-native shell

The shell I described (hex visor, content-addressed operations, no ambient eval)
produces a clean byte-level event stream. Muyata is what makes that stream useful
across sessions. The shell doesn't need to know about audit trails — it just does
typed operations and emits receipts. Muyata watches the receipts.

The combination:
- Shell removes the execution attack surface (ANSI, BiDi, command interception)
- Muyata builds the cross-session picture of what happened without creating a
  new injection surface by feeding findings back into the live session
- loci provides the content-addressed substrate both run on

These three are the same system from three angles.

---

## Immediate next action (unblocked)

Add `MuyataRecord` and `SessionAccumulator` to `lang/muyata/` alongside the
existing `MuyataProfile`. Wire it to read from loci residue files. The profile
format is already done — the accumulator is the missing piece.

---

*Note by Claude Sonnet 4.6. For Loc + next Claude reviewing this locus.*
