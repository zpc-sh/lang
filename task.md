# Lang — v0.1 Roadmap

## Completed — Foundation (Phases 1–9 + Protocols)

| Area | Status | Key files |
|------|--------|-----------|
| Merkin container layer | ✅ | `merkin/storage/container.mbt`, `oci.mbt` |
| Mu section parser/writer | ✅ | `mu/mbt/wasm/sections.mbt`, `module.mbt` |
| Node kernel | ✅ | `lang/node/{node,host,bus,cas}.mbt` |
| mulsp + muyata wrappers | ✅ | `lang/mulsp/mulsp.mbt`, `muyata/muyata.mbt` |
| Plugin system + WASM interface | ✅ | `lang/plugin/registry.mbt`, `wasm_iface/iface.mbt` |
| LSP framing + message types | ✅ | `lang/lsp/{frame,message}.mbt` |
| Emergent persona | ✅ | `lang/emergent/emergent.mbt` |
| Finger + GMU/1 | ✅ | `lang/finger/finger.mbt` |
| Cognitive boundary system | ✅ | `lang/cognitive/boundary.mbt` |
| Code cave storage (genius loci) | ✅ | `lang/cave/cave.mbt` |
| Spore (mobile agents) | ✅ | `lang/spore/spore.mbt` |
| NNTP codec (gossip + OCI transport) | ✅ | `lang/nntp/nntp.mbt` |
| Gopher codec (capability discovery) | ✅ | `lang/gopher/gopher.mbt` |

**Build:** 0 errors, 15 packages · **Tests:** 135/135

---

## v0.1 — Four Milestones

---

### M1 · Net Layer  *(unblocks SDK)*

The `moonbitlang/async` dep is in `moon.mod.json`. This milestone wires the
protocol codecs (NNTP, Gopher, GMU/1) to real TCP using the async runtime on
the **native/LLVM** target.  The wasm-gc target keeps using HostBridge — the
same codec modules compile to both.

**Server side** — `lang/net/`
- [ ] `lang/net/server.mbt` — top-level node server: spawns one listener task
      per protocol, wires incoming connections to the appropriate codec
- [ ] `lang/net/nntp_server.mbt` — per-connection handler: `NntpState::new` →
      `NntpState::greeting` → async recv loop → `NntpState::handle_bytes` →
      async send; one `NntpState` per connection
- [ ] `lang/net/gopher_server.mbt` — per-connection handler: recv selector
      line → `GopherRequest::parse` → `dispatch_request` → send encoded
      response → close; stateless (new context per connection)
- [ ] `lang/net/gmu_server.mbt` — GMU/1 UDP/TCP listener for peer messaging
      (ping/pong, plan exchange, residue relay, CAS sync offers)

**Client side** — `lang/net/`
- [ ] `lang/net/peer_client.mbt` — outbound peer operations:
  - `connect_and_post_nntp(peer_addr, article)` — post gossip/OCI article
  - `fetch_oci_layer(peer_addr, hash)` → `Array[Byte]` — ARTICLE by Message-ID
  - `fetch_gopher_caps(peer_addr)` → `GopherMenu` — `/caps` menu
  - `fetch_gopher_wasm(peer_addr, selector)` → `Array[Byte]` — WASM blob
  - `send_gmu(peer_addr, msg)` — fire-and-forget GMU/1 message
- [ ] `lang/net/discovery.mbt` — periodic peer discovery loop: send GMU/1
      `PlanRequest` to known peers, update `FingerState`, prune stale peers

**HostBridge extension** — `lang/node/host.mbt`
- [ ] Add `net_listen : (Int) -> Int` (port → fd) to `HostBridge`
- [ ] Add `net_accept : (Int) -> Int?` (listener fd → conn fd) to `HostBridge`
- [ ] Add `net_connect : (String, Int) -> Int?` (host, port → conn fd) to `HostBridge`
- [ ] Stub implementations for wasm-gc target (pass-through to host runtime)
- [ ] Real implementations via `@moonbitlang/async/socket` for native target

---

### M2 · Container UKI  *(unblocks M3, M4)*

The WASM binary IS the daemon.  A UKI-sealed binary is self-verifiable: any
peer can confirm provenance before loading a spore pack or OCI layer.

**Crypto primitives** — `lang/node/host.mbt` + `lang/crypto/`
- [ ] Add `crypto_hash : (Array[Byte]) -> Array[Byte]` (sha-256 or blake3) to
      `HostBridge`; expose as `lang/crypto/crypto.mbt` thin wrapper
- [ ] Add `crypto_sign : (Array[Byte], Array[Byte]) -> Array[Byte]` (ed25519:
      msg, 64-byte key → 64-byte sig) to `HostBridge`
- [ ] Add `crypto_verify : (Array[Byte], Array[Byte], Array[Byte]) -> Bool`
      (msg, sig, 32-byte pubkey) to `HostBridge`

**UKI seal/verify** — `mu/forge/uki.mbt` (currently TODO stubs)
- [ ] `seal_uki(wasm_bytes, entry_export, signing_key)` — compute per-section
      sha-256, build `UkiManifest`, serialize to `.uki` section, sign manifest
      digest → 64-byte ed25519 sig → inject `.uki` + `.sig` sections
- [ ] `verify_uki(wasm_bytes, public_key)` — extract `.uki` manifest, recompute
      section digests, verify ed25519 sig over manifest hash

**Cognitive envelope** — `mu/forge/envelope.mbt` (currently TODO stubs)
- [ ] `envelop(wasm_bytes, harness_name, cycles, attend_count, salience_bytes)`
      — serialize `CognitiveEnvelope` header + salience blob → inject `.cog`
      section (COGS magic + fields)
- [ ] `open_envelope(wasm_bytes)` → `CognitiveEnvelope?` — find `.cog` section,
      parse header, return struct (caller deserializes `salience_bytes`)
- [ ] `update_envelope(wasm_bytes, updated_envelope)` — strip old `.cog`, inject
      new one; used by muyata after each observation tick

**Merkin container round-trip** — `merkin/storage/`
- [ ] Fix / un-stub `container_test.mbt` round-trip test (was unchecked in
      Phase 1); confirm pack → unpack identity holds
- [ ] Wire UKI sealing into `CognitiveContainer::pack` so every container
      carries a signed `.uki` manifest

---

### M3 · Cognitive Envelopes  *(depends on M2 crypto)*

Envelopes enable **cognitive continuity across binary hand-offs**.  When a
spore boots on a remote node, the receiving node opens the `.cog` section and
resumes the harness instead of starting cold.

- [ ] `lang/node/node.mbt` — `Node::open_envelope` method: on boot, check for
      `.cog` section in the node's own WASM binary; if present, restore
      `SalienceField` state into the void/grammar subsystems
- [ ] `lang/node/node.mbt` — `Node::seal_envelope` method: on checkpoint, call
      `mu/forge/envelope::update_envelope` with current salience bytes
- [ ] `lang/emergent/emergent.mbt` — call `seal_envelope` at
      `grammar_seal_interval` ticks (currently triggers a tree seal only)
- [ ] `lang/spore/spore.mbt` — `SporePack` should carry the sealed `.cog`
      bytes so the destination node can resume the harness on spore boot
      (currently `payload` is opaque; add `envelope_bytes : Array[Byte]?`)
- [ ] Round-trip test: forge node → seal envelope → extract bytes → ship as
      spore → boot on stub node → verify harness state restored

---

### M4 · SDKs  *(depends on M1)*

Three clients for three runtimes that need to talk to lang nodes.

**Native MoonBit runtime** — `lang/runtime/`
- [ ] `lang/runtime/main.mbt` — `main` entry point for native/LLVM build:
      boots a `Node`, starts the `net/server.mbt` listener tasks, wires the
      async event loop, runs until SIGTERM
- [ ] `lang/runtime/config.mbt` — parse `config.muon` from argv / env:
      node ID seed, ports, peer list, cognitive tier, cave paths
- [ ] `moon.pkg.json` for runtime package (imports async, net, node, nntp,
      gopher, finger)

**Elixir SDK** — `sdk/elixir/` (for tempora and avici backend)
- [ ] `LangNode.NNTP` — thin wrapper over the Elixir NNTP client we built in
      `tempora/lib/tempora/http_clients/nntp_client.ex`; adds AI-specific
      newsgroup helpers (`post_gossip/3`, `fetch_oci_layer/2`, `newnews/3`)
- [ ] `LangNode.Gopher` — TCP client: `fetch_caps/1`, `fetch_wasm/2`,
      `fetch_oci_layer/2` using Gopher selectors
- [ ] `LangNode.Peer` — high-level: `discover/1`, `sync_oci_layer/3`,
      `push_residue/3`

**Rust SDK** — `sdk/rust/` (for avici_cli integration)
- [ ] `lang-sdk` crate: async (tokio) client wrapping NNTP + Gopher
- [ ] `LangPeer::connect(addr)` → handle
- [ ] `LangPeer::fetch_caps()` → `GopherMenu` (parsed from wire bytes)
- [ ] `LangPeer::fetch_oci_layer(hash)` → `Vec<u8>`
- [ ] `LangPeer::post_gossip(article_type, payload)` → `MessageId`
- [ ] Wire into `avici-server`'s plugin registry so avici nodes can federate
      with lang nodes natively

---

## Dependency graph

```
M2 (UKI + crypto)
  └─► M3 (envelopes, continuity)
          └─► M4 (SDKs — Elixir/Rust include envelope-aware methods)

M1 (net layer)
  └─► M4 (SDKs — need real TCP to test against)
```

M1 and M2 are independent — work can proceed in parallel.

---

## Definition of v0.1

- [ ] M1 complete: native lang node process opens ports 70 + 119, two peers
      can exchange a spore pack via NNTP, one peer can fetch the other's WASM
      via Gopher
- [ ] M2 complete: `seal_uki` / `verify_uki` pass their tests; merkin
      container round-trip test green
- [ ] M3 complete: spore boot restores harness state from `.cog` section
- [ ] M4 complete: Elixir SDK posts a gossip article and fetches a Gopher menu;
      Rust SDK does the same from avici_cli
- [ ] Build: 0 errors across all targets (wasm-gc + native)
- [ ] Tests: all existing 135 + new M1/M2/M3 tests pass
