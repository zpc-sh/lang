///|
/// Node Kernel — the runtime binary's central structure.
///
/// The Node is the top-level entity in the Lang binary. It:
///   - Owns the message bus (all inter-component communication)
///   - Owns the CAS store (content-addressed storage via host bridge)
///   - Owns the void state (passive accumulator)
///   - References mulsp and muyata state (AI runtime identity)
///   - Manages plugin lifecycle
///   - Drives the main loop (host calls node_tick)
///
/// Lifecycle:
///   1. Host creates node via Node::boot(host_bridge)
///   2. Host feeds LSP frames via node_ingest_lsp(bytes)
///   3. Host calls node_tick(now_ms) periodically
///   4. Host reads output via node_drain_output()
///   5. Host can checkpoint via node_checkpoint()
///
/// The node never performs I/O directly — all I/O flows through
/// the HostBridge function table.

// ---------------------------------------------------------------------------
// Node mode
// ---------------------------------------------------------------------------

///|
/// Operating mode of the node.
pub(all) enum NodeMode {
  Proxy // LSP proxy — the default mode
  Emergent // emergent persona — self-directed
  Plugin // running as a plugin inside another node
  Headless // no persona — pure CAS/store operations
} derive(Eq, Debug)

///|
impl Show for NodeMode with output(self, logger) {
  logger.write_string(
    match self {
      Proxy => "Proxy"
      Emergent => "Emergent"
      Plugin => "Plugin"
      Headless => "Headless"
    },
  )
}

// ---------------------------------------------------------------------------
// Node
// ---------------------------------------------------------------------------

///|
/// The node kernel — the Lang binary's central state.
pub(all) struct Node {
  node_id : String
  mode : NodeMode
  host : HostBridge
  cas : CasStore
  bus : MessageBus
  mut void_state : @void.Void
  mut epoch : Int
  mut booted : Bool
  // Output buffer — frames to send to host
  outbox : Array[Array[Byte]]
  // LSP input buffer — accumulated bytes awaiting frame parse
  lsp_buf : Array[Byte]
  // Flow observation (optional — None when not interposing on a flow)
  mut flow_tap : @flow_tap.FlowTap?
  // Statistics
  mut frames_in : Int
  mut frames_out : Int
  mut ticks : Int
  mut last_tick_ms : Int
}

///|
/// Boot a new node with the given host bridge and identity.
pub fn Node::boot(node_id : String, mode : NodeMode, host : HostBridge) -> Node {
  let cas = CasStore::new(host)
  let bus = MessageBus::new()
  let void_state = @void.Void::new(node_id)

  // Register core subscribers on the bus
  let _ = bus.subscribe("kernel", [Lifecycle, Tick])
  let _ = bus.subscribe("lsp-proxy", [LspInbound, LspOutbound])
  let _ = bus.subscribe("void-observer", [VoidObserve])
  let _ = bus.subscribe("cas-handler", [CasIngest, CasQuery])
  let _ = bus.subscribe("flow-observer", [
    FlowInbound,
    GrammarObserve,
    ManifoldEmit,
  ])

  (host.log_info)("node: booted id=\{node_id} mode=\{mode}")

  {
    node_id,
    mode,
    host,
    cas,
    bus,
    void_state,
    epoch: 0,
    booted: true,
    outbox: [],
    lsp_buf: [],
    flow_tap: None,
    frames_in: 0,
    frames_out: 0,
    ticks: 0,
    last_tick_ms: 0,
  }
}

// ---------------------------------------------------------------------------
// LSP ingestion
// ---------------------------------------------------------------------------

///|
/// Ingest raw LSP bytes from the host. Accumulates in the internal
/// buffer and parses complete frames.
pub fn Node::ingest_lsp(self : Node, bytes : Array[Byte]) -> Unit {
  // Append to buffer
  for b in bytes {
    self.lsp_buf.push(b)
  }

  // Drain complete frames
  let (frames, rest) = @lsp.frame_drain(self.lsp_buf)
  self.lsp_buf.clear()
  for b in rest {
    self.lsp_buf.push(b)
  }

  for frame in frames {
    self.frames_in = self.frames_in + 1
    // Publish to bus
    let _ = self.bus.publish(LspInbound, frame.body, "host")
    // Observe in void
    self.void_state = self.void_state.observe_bytes(frame.content_length)
  }
}

///|
/// Queue an LSP response frame for the host to read.
pub fn Node::emit_lsp(self : Node, json : String) -> Unit {
  let wire = @lsp.frame_write(json)
  self.outbox.push(wire)
  self.frames_out = self.frames_out + 1
  let _ = self.bus.publish(LspOutbound, wire, "kernel")
}

///|
/// Drain all pending output frames.
pub fn Node::drain_output(self : Node) -> Array[Array[Byte]] {
  let out = self.outbox.copy()
  self.outbox.clear()
  out
}

// ---------------------------------------------------------------------------
// Flow observation
// ---------------------------------------------------------------------------

///|
/// Attach a FlowTap to this node for protocol grammar observation.
pub fn Node::attach_flow_tap(
  self : Node,
  config : @flow_tap.FlowTapConfig,
) -> Unit {
  self.flow_tap = Some(@flow_tap.FlowTap::new(config))
  (self.host.log_info)("node: flow tap attached id=\{config.tap_id}")
}

///|
/// Observe a raw flow frame through the attached FlowTap.
/// No-op if no FlowTap is attached.
pub fn Node::observe_flow(self : Node, frame : @flow_tap.FlowFrame) -> Unit {
  match self.flow_tap {
    Some(tap) => {
      tap.observe(frame)
      let _ = self.bus.publish(
        FlowInbound,
        node_int_to_bytes(frame.type_tag),
        "flow-tap",
      )
    }
    None => ()
  }
}

///|
/// Detach the FlowTap and return its final manifold fragment (if AI-flow detected).
pub fn Node::detach_flow_tap(self : Node) -> @flow_tap.FlowTap? {
  match self.flow_tap {
    Some(tap) => {
      self.flow_tap = None
      (self.host.log_info)("node: flow tap detached frames=\{tap.frames_seen}")
      Some(tap)
    }
    None => None
  }
}

// ---------------------------------------------------------------------------
// CAS operations
// ---------------------------------------------------------------------------

///|
/// Ingest content into the node's CAS. Returns the hash key.
pub fn Node::cas_ingest(
  self : Node,
  content_type : String,
  data : Array[Byte],
) -> String {
  let key = self.cas.ingest(content_type, data)
  let _ = self.bus.publish(CasIngest, data, "kernel")
  key
}

///|
/// Query the node's CAS by hash key.
pub fn Node::cas_query(self : Node, key : String) -> CasEnvelope? {
  self.cas.query(key)
}

///|
/// Check if a key exists in the CAS.
pub fn Node::cas_has(self : Node, key : String) -> Bool {
  self.cas.has(key)
}

// ---------------------------------------------------------------------------
// Tick — the main loop driver
// ---------------------------------------------------------------------------

///|
/// Called by the host on each timer tick. Drives internal processing.
pub fn Node::tick(self : Node, now_ms : Int) -> Unit {
  self.ticks = self.ticks + 1
  self.last_tick_ms = now_ms

  // Publish tick to bus
  let ts_bytes = node_int_to_bytes(now_ms)
  let _ = self.bus.publish(Tick, ts_bytes, "kernel")

  // Void observation
  self.void_state = self.void_state.observe_session()

  // Periodic seal
  if self.ticks % 32 == 0 {
    self.seal()
  }
}

///|
/// Seal the current void state — advance epoch and persist.
pub fn Node::seal(self : Node) -> Unit {
  self.void_state = self.void_state.tick()
  self.epoch = self.void_state.epoch

  // Persist void to CAS
  let void_bytes = self.void_state.to_bytes()
  let _ = self.cas.ingest("application/vnd.merkin.void.v1", void_bytes)

  let _ = self.bus.publish(Lifecycle, [], "kernel")
  (self.host.log_trace)("node: sealed epoch=\{self.epoch}")
}

// ---------------------------------------------------------------------------
// Checkpoint
// ---------------------------------------------------------------------------

///|
/// Checkpoint the full node state into CAS. Returns the checkpoint key.
pub fn Node::checkpoint(self : Node) -> String {
  let void_bytes = self.void_state.to_bytes()
  let key = self.cas.ingest("application/vnd.merkin.void.v1", void_bytes)
  (self.host.log_info)("node: checkpoint key=\{key} epoch=\{self.epoch}")
  key
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

///|
/// Node runtime statistics.
pub(all) struct NodeStats {
  node_id : String
  mode : NodeMode
  epoch : Int
  frames_in : Int
  frames_out : Int
  ticks : Int
  last_tick_ms : Int
  bus_dispatched : Int
  bus_pending : Int
  cas : CasStats
  void_anchors : Int
  void_bytes : Int
} derive(Debug)

///|
pub fn Node::stats(self : Node) -> NodeStats {
  {
    node_id: self.node_id,
    mode: self.mode,
    epoch: self.epoch,
    frames_in: self.frames_in,
    frames_out: self.frames_out,
    ticks: self.ticks,
    last_tick_ms: self.last_tick_ms,
    bus_dispatched: self.bus.stats_dispatched(),
    bus_pending: self.bus.total_pending(),
    cas: self.cas.stats(),
    void_anchors: self.void_state.anchors.length(),
    void_bytes: self.void_state.bytes_observed,
  }
}

///|
/// Is the node booted and ready?
pub fn Node::is_ready(self : Node) -> Bool {
  self.booted
}

///|
/// Current epoch.
pub fn Node::current_epoch(self : Node) -> Int {
  self.epoch
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn node_int_to_bytes(v : Int) -> Array[Byte] {
  [
    (v & 0xFF).to_byte(),
    ((v >> 8) & 0xFF).to_byte(),
    ((v >> 16) & 0xFF).to_byte(),
    ((v >> 24) & 0xFF).to_byte(),
  ]
}
