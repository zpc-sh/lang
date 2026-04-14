///|
/// Message Bus — internal routing for the node kernel.
///
/// The bus is the central nervous system of the node. All communication
/// between node components flows through typed messages:
///   - LSP frames from the proxy
///   - Plugin invocations and responses
///   - Void observations
///   - Lifecycle events (attach, detach, seal, checkpoint)
///   - CAS operations (ingest, anchor, query)
///   - Peer messages (finger, gmu/1)
///
/// The bus is a simple synchronous dispatch — no async, no threads.
/// The host runtime drives the loop; the bus routes within one tick.
///
/// Messages carry a topic + payload. Subscribers register by topic.
/// Dispatch is linear scan — fine for the expected subscriber count (<32).

// ---------------------------------------------------------------------------
// Message topics
// ---------------------------------------------------------------------------

///|
/// Typed message topics for bus routing.
pub(all) enum Topic {
  LspInbound       // raw LSP frame arrived from host
  LspOutbound      // LSP frame to send to host
  PluginInvoke     // invoke a loaded plugin
  PluginResponse   // plugin returned a result
  VoidObserve      // void accumulation event
  CasIngest        // content to seal into CAS
  CasQuery         // query CAS by hash
  CasResult        // CAS query result
  Lifecycle        // node lifecycle event
  PeerInbound      // message from a peer node
  PeerOutbound     // message to a peer node
  FingerUpdate     // finger.plan changed
  Tick             // periodic timer tick
  FlowInbound      // raw frame from a flow adapter (PgTap, etc.)
  GrammarObserve   // grammar tree mutation event
  ManifoldEmit     // ManifoldFragment produced
} derive(Eq, Debug)

///|
impl Show for Topic with output(self, logger) {
  logger.write_string(match self {
    LspInbound    => "LspInbound"
    LspOutbound   => "LspOutbound"
    PluginInvoke  => "PluginInvoke"
    PluginResponse => "PluginResponse"
    VoidObserve   => "VoidObserve"
    CasIngest     => "CasIngest"
    CasQuery      => "CasQuery"
    CasResult     => "CasResult"
    Lifecycle     => "Lifecycle"
    PeerInbound   => "PeerInbound"
    PeerOutbound  => "PeerOutbound"
    FingerUpdate   => "FingerUpdate"
    Tick           => "Tick"
    FlowInbound    => "FlowInbound"
    GrammarObserve => "GrammarObserve"
    ManifoldEmit   => "ManifoldEmit"
  })
}

// ---------------------------------------------------------------------------
// Message
// ---------------------------------------------------------------------------

///|
/// A bus message — topic + opaque payload bytes + optional metadata.
pub(all) struct BusMessage {
  topic      : Topic
  payload    : Array[Byte]   // opaque payload (interpreted by subscriber)
  source     : String        // originator ID (e.g., "lsp-proxy", "plugin:lens", "kernel")
  sequence   : Int           // monotonic sequence number
} derive(Debug)

///|
impl Show for BusMessage with output(self, logger) {
  logger.write_string("BusMessage(topic=\{self.topic}, source=\{self.source}, seq=\{self.sequence}, len=\{self.payload.length()})")
}

// ---------------------------------------------------------------------------
// Subscriber
// ---------------------------------------------------------------------------

///|
/// A subscriber — a named handler for a set of topics.
pub(all) struct Subscriber {
  id       : String
  topics   : Array[Topic]     // which topics this subscriber cares about
  inbox    : Array[BusMessage] // pending messages
} derive(Debug)

///|
pub fn Subscriber::new(id : String, topics : Array[Topic]) -> Subscriber {
  { id, topics, inbox: [] }
}

///|
/// Does this subscriber want messages on the given topic?
pub fn Subscriber::wants(self : Subscriber, topic : Topic) -> Bool {
  for t in self.topics {
    if t == topic { return true }
  }
  false
}

///|
/// Drain all pending messages from the inbox.
pub fn Subscriber::drain(self : Subscriber) -> Array[BusMessage] {
  let msgs = self.inbox.copy()
  self.inbox.clear()
  msgs
}

///|
/// Number of pending messages.
pub fn Subscriber::pending(self : Subscriber) -> Int {
  self.inbox.length()
}

// ---------------------------------------------------------------------------
// MessageBus
// ---------------------------------------------------------------------------

///|
/// The message bus — subscribers + dispatch.
pub(all) struct MessageBus {
  subscribers : Array[Subscriber]
  mut sequence : Int           // global monotonic counter
  mut total_dispatched : Int   // lifetime counter
} derive(Debug)

///|
pub fn MessageBus::new() -> MessageBus {
  { subscribers: [], sequence: 0, total_dispatched: 0 }
}

///|
/// Register a subscriber. Returns its index.
pub fn MessageBus::subscribe(
  self : MessageBus,
  id : String,
  topics : Array[Topic],
) -> Int {
  let idx = self.subscribers.length()
  self.subscribers.push(Subscriber::new(id, topics))
  idx
}

///|
/// Publish a message to all matching subscribers.
/// Returns the number of subscribers that received it.
pub fn MessageBus::publish(
  self : MessageBus,
  topic : Topic,
  payload : Array[Byte],
  source : String,
) -> Int {
  self.sequence = self.sequence + 1
  let msg : BusMessage = {
    topic,
    payload,
    source,
    sequence: self.sequence,
  }
  let mut delivered = 0
  for sub in self.subscribers {
    if sub.wants(topic) {
      sub.inbox.push(msg)
      delivered = delivered + 1
    }
  }
  self.total_dispatched = self.total_dispatched + delivered
  delivered
}

///|
/// Drain messages for a specific subscriber by ID.
pub fn MessageBus::drain_for(self : MessageBus, id : String) -> Array[BusMessage] {
  for sub in self.subscribers {
    if sub.id == id {
      return sub.drain()
    }
  }
  []
}

///|
/// Total messages pending across all subscribers.
pub fn MessageBus::total_pending(self : MessageBus) -> Int {
  let mut total = 0
  for sub in self.subscribers {
    total = total + sub.pending()
  }
  total
}

///|
/// Total messages dispatched since creation.
pub fn MessageBus::stats_dispatched(self : MessageBus) -> Int {
  self.total_dispatched
}

///|
/// Current sequence number.
pub fn MessageBus::stats_sequence(self : MessageBus) -> Int {
  self.sequence
}

///|
/// Number of registered subscribers.
pub fn MessageBus::subscriber_count(self : MessageBus) -> Int {
  self.subscribers.length()
}
