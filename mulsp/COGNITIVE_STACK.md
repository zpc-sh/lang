# mulsp / muyata Cognitive Stack

*mulsp speaks. muyata listens. procsi decides. merkin remembers why.*

This document maps the open work needed to make the full cognitive stack
operational. Read alongside `WASM_BRIDGE.md` and `procsi/docs/procsi-high-order-structure.md`.

---

## What already exists and compiles

| Component | Location | Status |
|---|---|---|
| mulsp edge organism | `mulsp/` | 26 tests passing |
| muyata witness organism | `muyata/` | 37 tests passing |
| merkin/api wasm export layer | `merkin/api/`, `merkin/wasm_entry/` | wasm-gc builds clean |
| procsi-core identity library | `procsi/core/` | 24 tests passing, wasm builds clean |
| Lang.Mulsp birthing/registry | `lang/lib/lang/mulsp/` | compiles, wired into supervisor |
| Mulsp.Control runtime config channel | `mulsp/lib/mulsp/control.ex` | working |
| Mulsp.Merkin.Wasm stub + 3-mode bridge | `mulsp/lib/mulsp/merkin/wasm.ex` | stub mode active |

---

## The wasm linear memory model — codecaves

This is the central architectural choice. Path B (wasmex on standard BEAM) uses
wasm linear memory for ephemeral secret storage. The wasm heap is the codecave.

### Why wasm linear memory

- mulsp and procsi-core run as wasmex-hosted wasm instances inside a BEAM process
- The wasm linear memory is only reachable through `Wasmex.Memory` — not via
  any Elixir term, not serializable, not inspectable from outside the instance
- Secrets injected into memory at partition boot live in that address space and
  nowhere else — no ETS, no disk, no log
- When the wasm instance is dropped, the memory is GC'd
- The wasm boundary is the security boundary

### What lives in the codecave

```
Wasm linear memory layout (conceptual, per mulsp instance):

[0x0000 — 0x00FF]   procsi-core internal state (session, manifest, tickets)
[0x0100 — 0x01FF]   merkin tree hot state (bloom + active epoch)
[0x0200 — 0x0FFF]   Shape store (APP-wrapped behavioral fingerprints for this loci)
[0x1000 — 0x1FFF]   Coglet zone (compressed micro-embeddings from Haiku)
[0x2000 — 0x2FFF]   Materials magazine (runtime-injected files, docs, context)
[0x3000 — 0x3FFF]   Secret staging area (API keys, signing material — sign-only mode)
[0x4000 —         ]  Heap (merkin envelope data, procsi challenge registry)
```

The layout is logical — wasmex manages actual allocation. The "zones" are
manifested via allocated buffers whose pointers are tracked in wasm global
slots.

### Injection protocol

Lang.Mulsp.Birthing injects materials into a freshly started wasm instance:

```elixir
# After spawning the mulsp BEAM process and its wasm instances are ready:
Mulsp.Wasm.Runtime.inject(instance_ref, :shapes, app_wrapped_shape_binary)
Mulsp.Wasm.Runtime.inject(instance_ref, :coglets, coglet_binary)
Mulsp.Wasm.Runtime.inject(instance_ref, :materials, material_binary)
# Secrets (sign-only — raw never leaves):
Mulsp.Wasm.Runtime.inject(instance_ref, :signing_key, wrapped_key_material)
```

Internally, `inject/3` calls `wasmex_write_ptr` which writes into the wasm
instance's linear memory via `Wasmex.Memory.write_binary/4`. The receiving
wasm function updates the zone pointer globals.

---

## The cognitive wrapping layers in mulsp

Each incoming LSP/DC request passes through the trust onion before reaching dispatch.
This is not blocking — passive layers (0, 1, 2) happen asynchronously. The
request proceeds; the continuity evidence accumulates in the manifest.

```
Request arrives (TCP/DC/Gopher)
       │
       ▼
[Layer 0 — Network]          Mulsp.Transport.Tcp / DC / Gopher
  Already implemented.        Validates framing. Routes to Dispatch.
       │
       ▼
[Layer 1 — Continuity]       Mulsp.Procsi  ← OPEN
  procsi-core.wasm call:      session.advance() → manifest entry
  Checks: is session alive?   Issues continuity ticket if healthy.
  Async: doesn't block.       Blocks only if session is :broken.
       │
       ▼
[Layer 2 — Witness]          muyata.Observer.Tap  ← partially done
  muyata tap observes         Records byte count, method name, response shape.
  the request residue.        Feeds into Census + Heatmap.
  Fully async.
       │
       ▼
[Layer 3 — Challenge]        Mulsp.Procsi  ← OPEN
  On escalation only.         Procsi issues challenge if:
  Not inline for most ops.    - continuity score < 0.7
                              - method is in guard_methods partition field
                              - ingress object needs judgment
       │
       ▼
[Layer 4 — Substrate]        Mulsp.Procsi + merkin.wasm  ← OPEN
  APP-wrapped shapes in       bloom_check(token) against shape store.
  the wasm codecave.          Returns SubstrateMatch: :match | :near | :unknown
       │
       ▼
[Layer 5 — Core]             Lang.Mulsp.Registry / genius loci  ← OPEN
  Deep admission.             Only for sanctum-zone operations.
  Requires core ticket.       mulsp asks Lang; Lang asks genius loci.
       │
       ▼
Mulsp.Dispatch.dispatch/3    Already implemented.
```

---

## Open work — prioritized

### P0: Mulsp.Procsi — procsi-core wasm bridge

Mirror of `Mulsp.Merkin.Wasm` but for procsi-core.wasm.

```elixir
# lib/mulsp/procsi.ex
defmodule Mulsp.Procsi do
  # Loads procsi-core.wasm via wasmex.
  # Maintains one wasm instance per mulsp partition (one per AI session).
  # Wraps the ProcsiAgent façade: open, advance, issue_challenge,
  # verify_response, plan.

  def open(loci_id),                     # → :ok, seeds session
  def advance(),                         # → session continuity tick
  def issue_challenge(mode, archetype),  # → {:ok, %Challenge{}}
  def verify_response(response),         # → {:ok, %ChallengeResult{}, ticket?}
  def plan(),                            # → {:ok, plan_text}  (for Finger .plan)
end
```

This requires the procsi/core wasm entry point. Create `procsi/core/wasm_entry/`
following the same pattern as `merkin/wasm_entry/`:

```sh
cd procsi/core
# Create wasm_entry/ package (is-main: true, re-exports api/* functions)
moon build --target wasm --release --package nocsi/procsi-core/wasm_entry
cp _build/wasm/release/build/wasm_entry/wasm_entry.wasm \
   ../../lang/mulsp/priv/procsi.wasm
```

Note: procsi-core uses `--target wasm` (linear memory), not `wasm-gc`.
wasmex requires linear memory. This is consistent with Path B.

### P0: Mulsp.Wasm.Runtime — the codecave manager

Central manager for mulsp's wasm instances. Replaces the per-module
GenServer pattern with a unified runtime that owns both merkin.wasm and
procsi.wasm as a paired set per partition.

```elixir
defmodule Mulsp.Wasm.Runtime do
  # Loads both wasm modules at partition start.
  # Exposes inject/3 for Lang-side material injection.
  # Provides read_ptr/3, write_ptr/4 for internal use.
  # Tracks zone pointers (shape store, coglet zone, materials magazine).

  def start_link(partition),
  def inject(zone, binary),       # :shapes | :coglets | :materials | :signing_key
  def merkin(),                   # → {:ok, merkin_instance}
  def procsi(),                   # → {:ok, procsi_instance}
end
```

### P0: Partition fields for loci identity

Add to `Mulsp.Partition`:

```elixir
loci_id: nil,           # String — which genius loci this partition serves
substrate_scope: nil,   # String — e.g. "claude/opus/project:codex/*"
shape_store: :empty,    # :empty | {:loaded, ptr}
coglet_zone: :empty,    # :empty | {:loaded, ptr}
guard_methods: [],      # List of method names requiring Layer 3+ check
sanctum_methods: [],    # List of method names requiring Layer 5 ticket
```

Lang.Mulsp.Partition.for_context/2 already builds the base; these fields
extend it with identity binding.

### P1: Wire continuity into Mulsp.Dispatch

Dispatch currently goes straight to route/handle. Add procsi middleware:

```elixir
# In Dispatch.handle_call {:dispatch, ...}:
:ok = Mulsp.Procsi.advance()          # Layer 1: tick continuity
:ok = Mulsp.Observer.Tap.observe(request)  # Layer 2: witness
result = route_and_handle(...)
result
```

The advance() call is non-blocking (cast) for standard ops. Only escalates
to a synchronous challenge if the procsi session state requires it.

### P1: Finger server serves procsi .plan

`Mulsp.Finger.Server` already runs. Wire it to procsi:

```elixir
# In Finger.Server handle_connection:
{:ok, plan_text} = Mulsp.Procsi.plan()
:gen_tcp.send(sock, plan_text <> "\r\n")
```

The `.plan` output from procsi renders:

```
loci: codex/opus-session-abc123
presence: online
attestation: behavioral+continuity
continuity: stable
edge-rev: 47
master-rev: 3
ingress: open
surface: mulsp/gopher/finger/lsp
location: undisclosed
trust-band: layer-1
drift: 0.03
```

This is what clients see on `finger @mulsp-host:7079`.

### P1: muyata shape capture → Lang feedback

muyata already has Census + Heatmap. The missing piece: a `Muyata.Shape`
gets sealed and sent to Lang, which APP-wraps it and injects it back into
mulsp's codecave as a behavioral fingerprint.

```
muyata.Observer.Heatmap
  → Muyata.Shape.seal()          # produces %Shape{framing, message_types, coverage}
    → HTTP/DC to Lang            # Lang.Mulsp.ShapeIngester
      → APP-wrap                 # encode opaque to humans
        → Lang.Mulsp.Registry.inject_shape(node_id, wrapped_shape)
          → Mulsp.Wasm.Runtime.inject(:shapes, wrapped_binary)
            → procsi bloom_check uses shapes for substrate matching
```

### P2: Mulsp.Wasm.Runtime.inject — actual wasmex memory write

The inject call needs wasmex memory primitives:

```elixir
defp write_zone(store, instance, memory, zone, binary) do
  # 1. Call wasm alloc(byte_size(binary)) → ptr
  {:ok, [ptr]} = Wasmex.call_function(store, instance, "alloc", [byte_size(binary)])
  # 2. Write binary into linear memory at ptr
  :ok = Wasmex.Memory.write_binary(memory, ptr, binary)
  # 3. Call wasm register_zone(zone_id, ptr, len)
  {:ok, _} = Wasmex.call_function(store, instance, "register_zone", [zone_id(zone), ptr, byte_size(binary)])
  {:ok, ptr}
end
```

The `alloc` and `register_zone` exports need to be added to `merkin/api/api.mbt`
and `procsi/core/wasm_entry/entry.mbt`. They are simple linear memory operations —
trivial with `--target wasm` (linear memory; not wasm-gc).

### P2: Mulsp.Procsi.challenge flow

When dispatch escalates (continuity score drops, guard_method hit):

```elixir
# 1. Issue challenge
{:ok, challenge} = Mulsp.Procsi.issue_challenge(:embedded, "codex")
# 2. Present to AI (via Gopher? via LSP response with challenge field?)
# 3. Receive response (from next request carrying challenge_id + response_text)
{:ok, result, ticket} = Mulsp.Procsi.verify_response(response)
# 4. If ticket issued → proceed to dispatch; if not → quarantine to /inbox
```

The challenge transport surface: LSP responses can carry an `x-procsi-challenge`
header field. The AI's next request carries `x-procsi-response`. This is
seamless — the AI doesn't know it's being challenged. The response IS
the work (WorkAsProof mode).

### P3: Mulsp.Ingress — attested inbox zones

The six zones from the high-order structure doc:

```elixir
defmodule Mulsp.Ingress do
  # Zone-based object movement for AI-facing file/material operations.
  # Backed by wasm linear memory (in-session) or ETS (cross-session).

  @zones [:inbox, :quarantine, :staging, :workspace, :sanctum, :receipts]

  def receive(object_hash, source_ref),  # → :inbox
  def judge(object_hash),               # → {:ok, verdict, ticket?}
  def move(object_hash, zone_to),       # requires ticket for deep zones
  def read(object_hash, zone),          # → {:ok, binary} | {:error, :zone_denied}
end
```

The sanctum zone is only accessible with a Layer 5 core ticket. This is
the storage zone for the AI's materials magazines — what Lang drops into
the mulsp instance for rapid context loading.

### P4: Sign-only capability interface

The anti-distillation model: raw API keys never leave the wasm heap.
Lang injects signing material via `inject(:signing_key, ...)`. mulsp
exposes only:

```elixir
Mulsp.Capability.sign(object_hash)      # → {:ok, signature_hash}
Mulsp.Capability.wrap(object_hash, recipient)  # → {:ok, wrapped_hash}
```

The wasm instance performs the operation; only the result surfaces.

---

## Build pipeline (target state)

```
procsi/core/
  └─ moon build --target wasm --release → procsi.wasm

merkin/
  └─ make priv  (already works)         → merkin.wasm

lang/mulsp/priv/
  ├─ merkin.wasm   ← merkin wasm export
  └─ procsi.wasm   ← procsi-core wasm export

# On mulsp partition start:
Mulsp.Wasm.Runtime starts with both wasm instances loaded
Mulsp.Procsi opens session for loci_id from partition
Mulsp.Merkin.Wasm switches from :stub to :wasmex mode
Lang.Mulsp.Birthing.inject_materials(node_id, shapes, coglets, materials)
```

---

## The fast compilation / resolution claim

Each mulsp instance is a pre-loaded cognitive workspace for one AI session:

- procsi-core.wasm carries the session identity and trust state
- merkin.wasm carries the evidence substrate (bloom-indexed)
- the shape store (codecave) carries behavioral fingerprints of this loci
- the coglet zone carries Haiku-compressed micro-embeddings of prior work
- the materials magazine carries pre-loaded files, docs, context

When a request arrives, the AI operates against a warm, pre-indexed cognitive
context. There's no round-trip to load context — it's already in the wasm
instance's memory. The bloom sketch tells procsi in O(1) whether prior work
is relevant. The coglets guide attention. The materials are immediately
addressable.

This is what "rapid compilation and resolution for AI" means in practice:
the cognitive substrate is loaded and indexed before the AI needs it.

---

## Summary of open items

| Priority | Item | Complexity | Unblocks |
|---|---|---|---|
| P0 | procsi/core wasm_entry (--target wasm) | Low | Mulsp.Procsi |
| P0 | Mulsp.Wasm.Runtime (paired wasm instance manager) | Medium | everything |
| P0 | merkin/api alloc + register_zone exports | Low | codecave injection |
| P0 | Partition: loci_id, substrate_scope, guard_methods | Low | Layer 1,4 |
| P1 | Mulsp.Procsi (procsi-core wasmex bridge) | Medium | Layer 1,3,4,5 |
| P1 | Dispatch procsi middleware (advance + tap) | Low | continuity tracking |
| P1 | Finger .plan from procsi | Low | boundary visibility |
| P1 | muyata → shape → Lang → inject pipeline | Medium | substrate layer |
| P2 | Mulsp.Wasm.Runtime.inject (actual memory write) | Medium | codecave model |
| P2 | Mulsp.Procsi challenge flow (embedded/WorkAsProof) | Medium | Layer 3 |
| P3 | Mulsp.Ingress zone model | Medium | materials magazine |
| P4 | Sign-only capability interface | High | anti-distillation |
