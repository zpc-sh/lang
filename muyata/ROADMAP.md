# muyata Roadmap

**The Emptiness — Emergent Protocol Understanding from Nothing**

muyata is mulsp's counterpart. If mulsp is fullness (a nervous system that knows what it is), muyata is emptiness (a perceptual substrate that starts from nothing and learns). Together they form sunyata — the complete picture.

muyata sits in front of any service, observes traffic, and emergently learns the protocol. It never modifies traffic. The void grows but never shrinks.

---

## What Exists Today (v0.1)

```
lang/muyata/
├── mix.exs                              # Zero deps, AtomVM-compatible
├── lib/muyata/
│   ├── application.ex                   # Conditional supervisor
│   ├── void.ex                          # The anti-partition (starts empty)
│   ├── shape.ex                         # Sealed protocol shapes (composable)
│   ├── conduit/listener.ex              # TCP listener on target port
│   ├── conduit/relay.ex                 # Bidirectional byte shuttle
│   ├── observer/tap.ex                  # Passive byte stream tap
│   ├── observer/framing.ex              # Emergent boundary detection
│   ├── observer/census.ex               # Message type classification
│   ├── observer/heatmap.ex              # Coverage heatmap (Rice's answer)
│   ├── substrate/tree.ex                # Merkin tree of knowledge
│   ├── substrate/bloom.ex               # Bloom filter of seen patterns
│   ├── substrate/epoch.ex               # Epoch management
│   ├── mesh/cluster.ex                  # Muyata-to-muyata clustering
│   ├── gopher/server.ex                 # RFC 1436 capability browsing
│   ├── gopher/handler.ex                # Selector routing
│   ├── finger/server.ex                 # RFC 1288 status queries
│   └── dc/peer.ex                       # DC protocol peer
└── test/                                # 37 tests, 0 failures
```

19 source files. 4 servers. Compiles clean. Zero external dependencies.

---

## Dimension 1: Framing Intelligence

The framing module is the key innovation — discovering message boundaries in unknown protocols.

### v0.1 (Current)
- [x] Seed hypotheses: length-prefixed, tag+length, delimiter
- [x] Confidence scoring with hit/miss tracking
- [x] Dominant hypothesis promotion at 0.7 threshold
- [x] Message extraction and forwarding to Census

### v0.2: Adaptive Hypotheses
- [ ] **Dynamic hypothesis generation**: If no seed hypothesis wins, generate new ones from observed byte patterns
- [ ] **Multi-layer framing**: Some protocols have framing within framing (e.g., TLS records containing HTTP)
- [ ] **Bidirectional correlation**: Client framing may differ from server framing (asymmetric protocols)
- [ ] **Hypothesis decay**: Old hypotheses that haven't gained confidence slowly decay

### v0.3: Protocol Fingerprinting
- [ ] **Known protocol detection**: If framing + first few message types match a known protocol signature, auto-label
- [ ] **Protocol families**: Group protocols by framing similarity (all tag+length protocols form a family)
- [ ] **Framing export**: Share discovered framing as part of Shape for other muyata instances

---

## Dimension 2: Heatmap & Coverage

### v0.1 (Current)
- [x] 256x256 byte-pair observation grid
- [x] Hot spots / cold spots API
- [x] ASCII rendering via gopher
- [x] Coverage percentage

### v0.2: Intelligent Probing
- [ ] **Cold spot analysis**: Identify regions of the protocol space that have never been observed
- [ ] **Probe suggestions**: Generate synthetic traffic patterns that would fill cold spots
- [ ] **Coverage convergence**: Track how fast coverage grows — plateau detection
- [ ] **Entropy mapping**: Overlay Shannon entropy per grid cell — distinguish structured vs. random regions

### v0.3: Cross-Instance Overlay
- [ ] **Heatmap merge**: Overlay heatmaps from multiple muyata instances observing the same protocol
- [ ] **Differential heatmap**: Show what one instance has seen that another hasn't
- [ ] **Composite coverage**: Union coverage across a swarm

---

## Dimension 3: Shape Evolution

### v0.1 (Current)
- [x] Shape sealing from current state
- [x] Shape merge and diff
- [x] ETF serialization for DC transfer

### v0.2: Composable Proxies
- [ ] **Shape.wrap/1**: Turn a sealed shape into a typed proxy module — muyata graduates from observer to intelligent proxy
- [ ] **Method generation**: From learned message types, generate handler functions
- [ ] **Shape versioning**: Track how a protocol shape evolves across epochs
- [ ] **Shape registry**: Named shapes stored persistently, queryable via gopher

### v0.3: Protocol Reconstruction
- [ ] **State machine inference**: From sequence patterns (Census transitions), reconstruct the protocol state machine
- [ ] **Response prediction**: Given a request type, predict likely response types
- [ ] **Anomaly detection**: Flag messages that don't match established patterns

---

## Dimension 4: Mesh & Collective Intelligence

### v0.1 (Current)
- [x] Peer registration (muyata and mulsp)
- [x] Shape broadcast/receive
- [x] Composite bloom (union of peer blooms)

### v0.2: Swarm Convergence
- [ ] **Automatic peer discovery**: Via gopher/finger queries or distributed Erlang
- [ ] **Shape gossip**: Periodically exchange shapes with random peers
- [ ] **Convergence tracking**: Measure how quickly the swarm reaches consensus on protocol understanding
- [ ] **Bloom-guided routing**: Use composite bloom to route queries to the muyata most likely to have relevant data

### v0.3: mulsp Integration
- [ ] **Join mulsp DC mesh**: muyata peers appear alongside mulsp peers in the hub
- [ ] **Cross-pollination**: mulsp's configured methods feed into muyata's tree (top-down meets bottom-up)
- [ ] **Sunyata queries**: Ask the combined mesh "what do you know about protocol X?" — answers from both mulsp (configured) and muyata (observed)

---

## Dimension 5: Beyond Network Protocols

muyata can observe any byte stream, not just TCP services.

### File System Observation
- [ ] Sit in front of a filesystem (FUSE mount) — learn file format patterns
- [ ] Each file type becomes a message type in the tree
- [ ] Coverage heatmap over file format space

### IPC Observation
- [ ] Unix domain socket interposition
- [ ] Pipe observation
- [ ] Shared memory region scanning

### API Observation
- [ ] HTTP request/response observation (muyata as HTTP proxy)
- [ ] gRPC wire format learning
- [ ] WebSocket frame analysis

---

## Dimension 6: Deployment

### Same as mulsp
- [ ] AtomVM packbeam (< 500KB target)
- [ ] Burrito single binary
- [ ] Docker container
- [ ] `docker run muyata --listen 5432 --upstream 127.0.0.1:5433`

---

## Invariants (Do Not Break These)

1. **Zero external dependencies** — pure Elixir/OTP stdlib
2. **No JSON** — ETF internally, MUON externally
3. **Crash-resilient** — supervisors handle restarts
4. **Tiny** — modules < 200 lines, functions < 30 lines
5. **Probabilistic over accurate** — framing hypotheses, bloom sketches, coverage approximation
6. **Never modify traffic** — muyata observes but never alters the byte stream
7. **The void grows but never shrinks** — knowledge is append-only within an epoch
8. **Rice's theorem is respected** — we never claim complete understanding, only probabilistic coverage

---

## Build Priority Matrix

| Priority | What | Why | Difficulty |
|----------|------|-----|------------|
| **P0** | Adaptive framing hypotheses | Better protocol detection | Medium |
| **P0** | Shape.wrap typed proxy | muyata graduates to something | Medium |
| **P1** | Heatmap cross-instance overlay | Swarm coverage | Easy |
| **P1** | Automatic peer discovery | Self-organizing mesh | Medium |
| **P1** | mulsp DC mesh integration | Sunyata complete | Medium |
| **P2** | Protocol fingerprinting | Known protocol auto-detect | Medium |
| **P2** | State machine inference | Protocol reconstruction | Hard |
| **P2** | HTTP proxy mode | Beyond TCP raw | Medium |
| **P3** | FUSE filesystem observation | Beyond network | Hard |
| **P3** | AtomVM deployment | Sub-1MB emptiness | Medium |

---

*muyata is not a proxy. It's the space between things — the void that learns to see.*
