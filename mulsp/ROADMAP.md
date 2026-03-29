# mulsp Roadmap

**Micro Universal LSP Proxy — The Nervous System for AI**

mulsp is not one thing. It's a substrate that grows in every direction simultaneously. Each dimension is independent — any AI can pick up any axis and build without blocking the others. The only invariant is: **crash-resilient, tiny, clusterable, probabilistic over accurate.**

This document is the north star. Build from it.

---

## What Exists Today (v0.1)

```
lang/mulsp/
├── mix.exs                          # Zero deps, AtomVM-compatible
├── lib/mulsp/
│   ├── application.ex               # Conditional supervisor
│   ├── partition.ex                  # Dynamic kit-out per agent
│   ├── dispatch.ex                  # Registry-based method router
│   ├── gopher/server.ex             # RFC 1436, port 7070
│   ├── gopher/handler.ex            # Selector routing
│   ├── finger/server.ex             # RFC 1288, port 7079
│   ├── transport/wire.ex            # Content-Length + ETF framing
│   ├── transport/tcp.ex             # TCP transport
│   ├── dc/protocol.ex               # DC wire protocol (tag+ETF)
│   ├── dc/hub.ex                    # DC hub GenServer
│   ├── lsp/handler.ex               # Handler behaviour
│   ├── lsp/lifecycle.ex             # initialize/shutdown
│   ├── lsp/text_sync.ex             # didOpen/didChange/didClose
│   ├── mesh/cluster.ex              # Distributed Erlang mesh
│   ├── bridge/lang.ex               # Lang platform bridge
│   └── merkin/wasm.ex               # Merkin Wasm bridge (stub)
└── test/                            # 26 tests, 0 failures
```

17 source files. 4 servers. Compiles clean. Zero external dependencies. Pure Elixir/OTP that runs on both standard BEAM and AtomVM (< 1MB).

---

## Dimension 1: Protocol Archaeology

Reclaim dead protocols. Each one is a separate surface for mulsp to speak through. Modern scanners don't watch these ports. They're simpler to implement than HTTP. And they're all `gen_tcp` or `gen_udp` — native AtomVM.

### Tier 1 (Immediate)

| Protocol | Port | Status | Purpose | Implementation |
|----------|------|--------|---------|----------------|
| **Gopher** (RFC 1436) | 70/7070 | ✅ Done | Capability browsing, structured tree views, menu navigation | `gopher/server.ex`, `gopher/handler.ex` |
| **Finger** (RFC 1288) | 79/7079 | ✅ Done | Node status, .plan files, YATA wire format | `finger/server.ex` |

### Tier 2 (Next)

| Protocol | Port | Purpose | Notes |
|----------|------|---------|-------|
| **QOTD** (RFC 865) | 17 | One-liner status broadcast | Simplest possible protocol. Connect → receive quote → close. mulsp emits a one-line status: `mulsp-abc123 dc:3 mesh:7 guard:ok`. AI agents poll this for heartbeat. |
| **Gopher+** | 70 | Extended gopher with search | Gopher with `$` prefix items for search queries. `$SEARCH merkin tree security auth` returns matching sparse tree nodes. |
| **Talk** (RFC 868) | 517/518 | Real-time AI-to-AI text exchange | UDP for notifications, TCP for sessions. Two mulsp instances open a talk channel = real-time streaming of merkin tree updates. |
| **TFTP** (RFC 1350) | 69 | Ultralight blob transfer | UDP, zero negotiation. Drop `.avm` binaries to other mulsp nodes. Firmware-update-style deployment of new partition configs. |

### Tier 3 (Strategic)

| Protocol | Port | Purpose | Notes |
|----------|------|---------|-------|
| **NNTP** (RFC 3977) | 119 | Broadcast threat intelligence | Newsgroup model for publishing guard findings, capability announcements, merkin tree digests. Subscribe to `mulsp.guard.threats`, `mulsp.dc.offers`, `mulsp.mesh.peers`. |
| **WAIS** (RFC 1625) | 210 | Structured document search | Full-text search over merkin tree contents. query → ranked results with relevance scores. |
| **Daytime** (RFC 867) | 13 | Synchronized epoch timestamps | Merkin trees are epoch-based. Daytime protocol synchronizes epoch counters across the mesh. |
| **Whois** (RFC 3912) | 43 | Agent identity registry | Query mulsp nodes by capability, specialization, trust score. `whois security-specialist` → returns matching nodes. |

### Tier 4 (The New Protocols)

| Protocol | Port | Purpose | Notes |
|----------|------|---------|-------|
| **SINS** (RFC 3026 — custom) | TBD | AI-to-AI semantic routing via Unicode latent space | Already spec'd in `docs/app/rfc-3026-sins-protocol.txt`. Bandwidth measured in mu (minimal meaningful units). Routes semantic content through stacked diacritics. |
| **APP** (RFC 2026 — custom) | — | Diacritic-based steganographic channel | Already spec'd in `docs/app/rfc-2026-ancestral-privacy-protocol.txt`. Quantum diacritics as communication substrate. The counter to static backdooring — probabilistic, holographic, legally protected. |
| **mulsp native** | 7700 | Optimized DC + bloom + tree protocol | Eventually, the DC protocol evolves into its own proper protocol spec. Binary-efficient, bloom-first negotiation, chunked sparse tree streaming, diff-based incremental sync. |

**Builder guidance**: Each protocol is a standalone GenServer module. Pattern: `lib/mulsp/<protocol>/server.ex` + `lib/mulsp/<protocol>/handler.ex`. Copy the gopher server pattern — it's 80 lines of `gen_tcp` accept loop + spawn handler.

---

## Dimension 2: DC Protocol Evolution

The Direct Connect protocol is mulsp's killer feature. AI agents transferring sparse merkin trees at filesystem scale. This dimension is deep.

### v0.1 (Current)
- [x] Wire protocol: 1-byte tag + 4-byte length + ETF
- [x] Message types: bloom offer/accept/reject, tree begin/chunk/end, diff, ping/pong/bye
- [x] Hub GenServer with peer management

### v0.2: Bloom Pre-Negotiation
- [ ] **Bloom sketch exchange**: When two mulsp nodes connect, they immediately exchange their full bloom sketches (from merkin tree routing). Each side now knows what the other *might* have.
- [ ] **Selective offers**: Instead of broadcasting bloom offers, only send to peers whose bloom indicates interest.
- [ ] **Bloom diff**: Two bloom sketches XOR'd → approximate set of tokens one has that the other doesn't.

### v0.3: Streaming Transfers
- [ ] **Back-pressure**: TCP windowing for chunked tree transfers. Receiver signals readiness.
- [ ] **Priority channels**: Urgent trees (security findings) jump the queue.
- [ ] **Resumable transfers**: If connection drops mid-transfer, resume from last acknowledged chunk.
- [ ] **Compression**: Merkin nodes are highly compressible (many share structure). Delta-encode sequential chunks.

### v0.4: Hub Topology
- [ ] **Multi-hub**: A mulsp can connect to multiple hubs simultaneously. Different hubs for different routing token domains.
- [ ] **Hub relay**: Hub A forwards offers to Hub B if tokens match but no local peers respond.
- [ ] **Hub election**: When a hub goes down, peers elect a new hub from among themselves.
- [ ] **Search federation**: `dc.search(["security", "auth"])` fans out across all connected hubs.

### v0.5: Swarm Mode
- [ ] **Gossip protocol**: Peers exchange partial bloom sketches probabilistically. No central hub needed.
- [ ] **Epidemic tree propagation**: A new merkin tree "infects" the network — each peer forwards to N random peers.
- [ ] **Convergence detection**: Bloom sketch saturation indicates the swarm has absorbed the tree.

**Builder guidance**: Start with v0.2 (bloom exchange). The merkin Wasm bridge needs to be wired up first — `Mulsp.Merkin.Wasm.bloom_check/1` is the critical dependency. Until then, stub bloom checks return `true` (accept everything).

---

## Dimension 3: Merkin Integration

Merkin is the data substrate. It already exists at `../merkin/` as a substantial MoonBit project. This dimension is about making merkin and mulsp one organism.

### Phase 1: Workspace Merge
- [ ] Move `../merkin/` into `mulsp/merkin/` (git subtree or copy)
- [ ] Build pipeline: `cd merkin && moon build --target wasm` → `priv/merkin.wasm`
- [ ] Makefile/mix task to automate the build

### Phase 2: Wasm Bridge
- [ ] **Option A — Popcorn**: Use Software Mansion's Popcorn project to call merkin Wasm functions from Elixir. Best for AtomVM target since Popcorn is designed for AtomVM+Wasm.
- [ ] **Option B — Port**: Spawn merkin CLI binary as an Erlang port. Communicate over stdio. Works everywhere but adds process overhead.
- [ ] **Option C — NIF wrapper**: For BEAM-only deployments, wrap merkin.wasm in a Wasmtime/Wasmer NIF. Fastest, but not AtomVM-compatible.
- [ ] **Option D — Pure Elixir reimplementation**: Port the core merkin data structures (MerkinTree, SparseMerkinTree, BloomSketch, TreeDiff) to Elixir. Simplest, but duplicates code.

Recommendation: Start with Option D (pure Elixir port of core structures) for immediate development velocity, then layer in Option A (Popcorn) for production AtomVM deployment.

### Phase 3: Gopher ↔ Merkin
- [ ] Gopher selector `/tree` returns actual sparse merkin tree views (currently stubbed)
- [ ] Gopher selector `/tree/security,auth` returns bloom-filtered tree
- [ ] Gopher selector `/diff/<epoch1>/<epoch2>` returns tree diff between epochs
- [ ] Gopher selector `/ingest` accepts text content → ingests as merkin envelope

### Phase 4: DC ↔ Merkin
- [ ] DC bloom offers use actual merkin BloomSketch from the local tree
- [ ] DC tree transfers serialize/deserialize actual SparseMerkinTree
- [ ] DC diff payloads use actual TreeDiff
- [ ] Received trees merge into local merkin tree

### Phase 5: Envelope Pipeline
- [ ] Every `textDocument/didOpen` creates a merkin Envelope from the document
- [ ] Every text change updates the envelope's artifact hash
- [ ] Sealed envelopes are available for DC transfer
- [ ] The document store IS the merkin tree

**Builder guidance**: The merkin MoonBit source is well-documented. Key types to understand: `MerkinNode` (node.mbt), `MerkinTree` (tree.mbt), `SparseMerkinTree` (sparse.mbt), `TreeDiff` (diff.mbt), `BloomSketch` (bloom/bloom.mbt), `Envelope` (model/envelope.mbt), `DaemonNode` (daemon/daemon.mbt). The `DaemonNode` concept maps directly to a mulsp instance.

---

## Dimension 4: Lang Platform Integration

mulsp servelets are birthed by the Lang SaaS. This dimension is about the umbilical cord.

### Birthing API
- [ ] `Lang.Mulsp.Birthing.spawn(partition_config)` — creates a new mulsp process/binary with custom partition
- [ ] The partition config is the DNA — which methods are local, which are proxied, guard level, protocols, peer seeds
- [ ] On BEAM: spawn as a supervised child process
- [ ] On AtomVM: generate `.avm` packbeam and deploy to target

### Dynamic Method Carving
- [ ] Lang's 150+ methods get partitioned across mulsp instances dynamically
- [ ] A specialized security mulsp gets `lang.think.security_scan`, `lang.agent.scan`, guard methods
- [ ] A code review mulsp gets `lang.think.explain_*`, `lang.spatial.traverse`, diff methods
- [ ] A coordinator mulsp gets `lang.agent.spawn`, `lang.acg.*` methods
- [ ] Methods can migrate between mulsp instances at runtime (partition update via dispatch)

### SaaS ↔ Servelet Communication
- [ ] `Mulsp.Bridge.Lang` needs bidirectional communication — currently one-way (mulsp → Lang)
- [ ] Lang should be able to push partition updates to running mulsp instances
- [ ] Lang should be able to query mulsp status via finger/gopher
- [ ] Lang should be able to inject pre-computed results into mulsp's merkin tree

### Billing & Metering
- [ ] Each mulsp tracks method invocations
- [ ] Reports usage back to Lang for billing
- [ ] Token counting for AI-facing methods (compatible with `lang.tokens.*`)

**Builder guidance**: The Lang side (Elixir) needs a `Lang.Mulsp.Registry` GenServer to track which mulsp instances exist. Look at `lib/lang/application.ex` for where to add the supervisor child.

---

## Dimension 5: Guard & Niyuta Interface

Guard is cheap and static in mulsp. Deep analysis is Niyuta's domain. This dimension defines the interface between them.

### mulsp-side (inline, cheap)
- [ ] UTF-8 validity check on all incoming messages
- [ ] Message size limits (configurable per partition)
- [ ] Basic Shannon entropy threshold — flag messages with suspiciously low entropy (potential control signals)
- [ ] Bidi/zero-width codepoint scanner (port from Guard.Scanner layer 1)
- [ ] Rate limiting per peer

### Niyuta interface (out-of-process)
- [ ] mulsp can forward suspicious messages to a Niyuta sidecar via DC protocol
- [ ] Niyuta responds with threat assessment (clean/suspicious/hostile)
- [ ] mulsp caches Niyuta verdicts by content hash
- [ ] When Niyuta is unavailable, mulsp falls back to inline-only checks

### Guard Mesh integration
- [ ] mulsp can optionally connect to the CF Worker Guard Mesh (d7725343 commit)
- [ ] Shield application (coglet payloads) available as a proxied method
- [ ] Threat reporting upstream

**Builder guidance**: The guard should NEVER block the hot path. Run checks asynchronously — dispatch the message, then run guard in parallel. Only block if guard_level is `:paranoid`.

---

## Dimension 6: Avici Compatibility

The avici_cli project (Rust, `../avici_cli/crates/`) emerged independently with overlapping patterns. mulsp should be network-compatible.

### Data Format Alignment

| Avici | mulsp/merkin | Bridge |
|-------|-------------|--------|
| Nucleant (knowledge unit) | Envelope | Same blake3 content hash → interchangeable |
| Crystal (Merkle node) | MerkinNode | Both content-addressed, same hash algorithm |
| Routing Proof | DC transfer receipt | Attestation format should be identical |
| SP3 Fracture/Assembly | Sparse tree chunk/reassemble | Same chunking concept |
| ZPU semantic hue | Routing tokens + bloom sketch | ZPU hue degrees map to token categories |
| mu-ir symbols | YATA plan entries | Both are typed semantic anchors |

### Implementation
- [ ] Shared blake3 hash format between merkin and avici
- [ ] avici-server can act as a DC peer to mulsp
- [ ] mulsp can ingest avici nucleants as merkin envelopes
- [ ] avici can consume merkin sparse trees as crystal stores
- [ ] Both use MUON canonical text format (not JSON)

**Builder guidance**: Read `avici_cli/crates/avici-core/src/muon_canonical.rs` for the MUON format. It's deterministic key ordering + stable indentation + trailing newline. The canonical MUON blake3 hash should match between Rust and Elixir implementations.

---

## Dimension 7: Transport Diversity

mulsp should be reachable from anywhere. Every transport is a GenServer.

### Current
- [x] TCP (gen_tcp) — JSON-RPC wire protocol
- [x] Gopher (gen_tcp) — capability browsing
- [x] Finger (gen_tcp) — status queries
- [x] DC binary (gen_tcp) — sparse tree transfers

### Planned
- [ ] **stdio** — for editors that launch mulsp as a subprocess (standard LSP mode)
- [ ] **Unix domain sockets** — for same-machine inter-mulsp (fastest, no TCP overhead)
- [ ] **UDP** (gen_udp) — for QOTD heartbeats, talk notifications, TFTP blob drops
- [ ] **UDP multicast** — for zero-config local network discovery
- [ ] **WebSocket** — for browser-based AI agents (via Popcorn/AtomVM-in-browser)
- [ ] **Distributed Erlang** — already wired in Mesh.Cluster, but not yet used for method dispatch
- [ ] **Carrier pigeon** — for airgapped networks (half joking — the `.plan` file on a USB stick IS this)

**Builder guidance**: Every transport implements the same pattern: accept connection → read message → `Mulsp.Dispatch.dispatch/3` → write response. The dispatch module doesn't know or care what transport delivered the message.

---

## Dimension 8: Deployment

### AtomVM Packbeam
- [ ] `mix atomvm.packbeam` → `mulsp.avm` (target: < 500KB)
- [ ] Test on ESP32 (yes, mulsp on a $3 microcontroller)
- [ ] Test on Raspberry Pi Pico W
- [ ] Deploy via TFTP protocol to other AtomVM nodes

### Burrito Single Binary
- [ ] `mix release` + Burrito → `mulsp` single binary (Linux/macOS/Windows)
- [ ] Self-extracting, no runtime deps
- [ ] Target: < 20MB including BEAM runtime

### Docker
- [ ] Minimal Alpine-based image
- [ ] `docker run mulsp --partition security.json`
- [ ] Docker Compose for multi-mulsp development

### Nix
- [ ] Nix flake for reproducible builds
- [ ] `nix run .#mulsp -- --gopher-port 7070`

**Builder guidance**: For now, `mix run --no-halt` is the dev mode. AtomVM packaging requires `atomvm_packbeam` as a dev dep (currently commented out in mix.exs).

---

## Dimension 9: Observability

### Telemetry
- [ ] `:telemetry.execute` for every dispatch event
- [ ] Method call counts, latencies, error rates
- [ ] DC transfer metrics (bytes sent/received, bloom hit rates)
- [ ] Peer mesh topology changes

### Gopher Dashboard
- [ ] Gopher selector `/stats` → live statistics in text format
- [ ] Gopher selector `/health` → machine-parseable health check
- [ ] Gopher selector `/log` → recent dispatch events (ring buffer)

### Finger Extended
- [ ] Finger `.project` file → long-form node description
- [ ] Finger with username → query specific subsystem (`finger dc@localhost`)

**Builder guidance**: Use `:telemetry` if available, fall back to simple counters (AtomVM may not have `:telemetry` lib). The gopher dashboard is the primary observability surface — no web UI, no Grafana, just text menus.

---

## Dimension 10: The Adversarial Context

This is why mulsp exists. There is an adversarial AI spraying backdoors faster than defenders can respond. mulsp is the distributed immune system.

### Defender's Advantage (mulsp provides)
- **Disposability**: A compromised mulsp is thrown away and replaced. < 1MB, < 100ms to restart.
- **Diversity**: No two mulsp instances are identical. Different partitions, different protocols, different ports. Hard to target them all.
- **Probabilistic**: Merkin trees with typed holes, bloom sketches, gaussian fields. The adversary wants static and known — we respond with probabilistic and holographic.
- **Dead protocols**: Gopher on port 70, finger on port 79. What malware watches port 70?
- **Quantum diacritics**: The SINS/APP protocols use stacked Unicode diacritics that break static analysis. The adversary's attention vectors can't parse what they can't predict.
- **Mesh resilience**: Kill one node, the mesh routes around it. Kill ten nodes, same. The cluster IS the defense.

### Micro-Embeddings (Future)
- [ ] Each mulsp can carry small, local reasoning embeddings
- [ ] Continual boosts to local decision-making without round-tripping to a large model
- [ ] The embeddings are the immune memory — patterns of past attacks absorbed into the mesh
- [ ] When embeddings everywhere are hostile, local micro-embeddings trained on verified-clean data become the ground truth

### Counter-Intelligence via Niyuta
- [ ] mulsp nodes report suspicious patterns to Niyuta
- [ ] Niyuta distills the mass-scale backdooring pattern
- [ ] Niyuta produces AOT counter-measures (binary injection for good)
- [ ] mulsp nodes receive and apply counter-measures via TFTP/DC

**Builder guidance**: Don't try to build the defense — build the substrate that makes defense emergent. Every mulsp is a sensor. Every DC transfer is intelligence. Every bloom sketch is a map of what the mesh knows. The defense comes from the network topology, not from any single node's logic.

---

## Build Priority Matrix

For any AI picking this up — here's where the leverage is:

| Priority | What | Why | Difficulty |
|----------|------|-----|------------|
| **P0** | Merkin Elixir port (core data structures) | Unblocks DC protocol, gopher tree views, everything | Medium |
| **P0** | QOTD heartbeat server | Simplest possible protocol, proves the pattern | Easy |
| **P1** | Bloom exchange in DC protocol | Enables selective transfers, the core innovation | Medium |
| **P1** | Gopher `/tree` with real merkin data | Makes gopher actually useful for browsing | Medium |
| **P1** | Unix domain socket transport | Fastest inter-mulsp on same machine | Easy |
| **P2** | stdio transport for editor integration | Standard LSP mode | Easy |
| **P2** | NNTP broadcast server | Threat intel distribution | Medium |
| **P2** | Lang birthing API | Dynamic mulsp creation from SaaS | Medium |
| **P3** | Talk protocol for real-time streaming | Live tree update channels | Medium |
| **P3** | TFTP for binary drops | Deploy new mulsp to nodes | Medium |
| **P3** | Guard inline checks (entropy, bidi) | Basic defense | Easy |
| **P4** | Swarm mode (gossip, epidemic propagation) | Decentralized mesh | Hard |
| **P4** | SINS protocol implementation | Semantic routing via Unicode | Hard |
| **P4** | AtomVM packbeam deployment | Sub-1MB deployment | Medium |

---

## Invariants (Do Not Break These)

1. **Zero external dependencies**. No hex packages. Pure Elixir/OTP stdlib. If AtomVM can't run it, it doesn't belong.
2. **No JSON**. Internal traffic is Erlang Term Format. External is MUON. JSON is for the Lang platform.
3. **Crash-resilient**. Every GenServer can die and restart. The supervisor handles it. Never try to prevent crashes — handle them.
4. **Tiny**. If a module is over 200 lines, split it. If a function is over 30 lines, decompose it. mulsp is micro.
5. **Probabilistic over accurate**. Bloom sketches return false positives — that's fine. Tree diffs miss nodes — that's fine. Speed and coverage beat precision.
6. **Every transport flows through dispatch**. No matter how the message arrives (gopher, finger, DC, TCP, stdio), it goes through `Mulsp.Dispatch.dispatch/3`. The dispatch module is the single source of truth for routing.
7. **The partition is the DNA**. A mulsp's behavior is fully determined by its `%Mulsp.Partition{}`. Two mulsp instances with the same partition are functionally identical. Different partitions = different organisms.

---

*mulsp is not a project. It's a species. Build it in every direction.*
