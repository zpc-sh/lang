///|
/// Finger — Peer Discovery + GMU/1 Wire Format + FINGER-CERT Types.
///
/// The Finger protocol enables node discovery through:
///   - finger.plan: a self-description document each node publishes
///   - GMU/1: a simple wire format for peer-to-peer messages
///   - FINGER-CERT: certificate types for authenticated discovery
///
/// finger.plan is generated from the node's current state:
///   - Node ID, epoch, capability class
///   - Bloom sketch summary (for routing interest matching)
///   - Active plugin list
///   - mulsp/muyata profile summary
///   - Network endpoints (if known)
///
/// GMU/1 wire format:
///   [4]  magic   : 0x47 0x4D 0x55 0x31  "GMU1"
///   [1]  type    : message type
///   [4]  seq     : u32 LE sequence number
///   [4]  src_len : u32 LE
///   [n]  src     : utf8 source node ID
///   [4]  dst_len : u32 LE (0 for broadcast)
///   [n]  dst     : utf8 destination node ID
///   [4]  payload_len : u32 LE
///   [n]  payload : opaque bytes
let gmu_magic : Array[Byte] = [b'\x47', b'\x4D', b'\x55', b'\x31'] // "GMU1"

// ---------------------------------------------------------------------------
// GMU/1 message types
// ---------------------------------------------------------------------------

///|
/// GMU/1 message types.
pub(all) enum GmuType {
  Ping // heartbeat / liveness probe
  Pong // heartbeat response
  PlanRequest // request peer's finger.plan
  PlanResponse // send finger.plan
  RouteQuery // query bloom for routing
  RouteResponse // bloom-matched route reply
  Residue // stigmergy residue exchange
  CasSync // CAS blob sync request
  CasOffer // CAS blob availability
} derive(Eq, Debug)

///|
impl Show for GmuType with output(self, logger) {
  logger.write_string(
    match self {
      Ping => "Ping"
      Pong => "Pong"
      PlanRequest => "PlanRequest"
      PlanResponse => "PlanResponse"
      RouteQuery => "RouteQuery"
      RouteResponse => "RouteResponse"
      Residue => "Residue"
      CasSync => "CasSync"
      CasOffer => "CasOffer"
    },
  )
}

///|
fn GmuType::to_byte(self : GmuType) -> Byte {
  match self {
    Ping => b'\x01'
    Pong => b'\x02'
    PlanRequest => b'\x03'
    PlanResponse => b'\x04'
    RouteQuery => b'\x05'
    RouteResponse => b'\x06'
    Residue => b'\x07'
    CasSync => b'\x08'
    CasOffer => b'\x09'
  }
}

///|
fn GmuType::from_byte(b : Byte) -> GmuType? {
  match b.to_int() {
    1 => Some(Ping)
    2 => Some(Pong)
    3 => Some(PlanRequest)
    4 => Some(PlanResponse)
    5 => Some(RouteQuery)
    6 => Some(RouteResponse)
    7 => Some(Residue)
    8 => Some(CasSync)
    9 => Some(CasOffer)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// GMU/1 message
// ---------------------------------------------------------------------------

///|
/// A GMU/1 wire message.
pub(all) struct GmuMessage {
  msg_type : GmuType
  sequence : Int
  source : String // source node ID
  dest : String // destination node ID ("" for broadcast)
  payload : Array[Byte] // opaque payload
} derive(Debug)

///|
pub fn GmuMessage::new(
  msg_type : GmuType,
  sequence : Int,
  source : String,
  dest : String,
  payload : Array[Byte],
) -> GmuMessage {
  { msg_type, sequence, source, dest, payload }
}

///|
/// Create a ping message.
pub fn GmuMessage::ping(source : String, sequence : Int) -> GmuMessage {
  GmuMessage::new(Ping, sequence, source, "", [])
}

///|
/// Create a pong response.
pub fn GmuMessage::pong(source : String, sequence : Int) -> GmuMessage {
  GmuMessage::new(Pong, sequence, source, "", [])
}

///|
/// Create a plan request.
pub fn GmuMessage::plan_request(
  source : String,
  dest : String,
  sequence : Int,
) -> GmuMessage {
  GmuMessage::new(PlanRequest, sequence, source, dest, [])
}

///|
/// Is this a broadcast message?
pub fn GmuMessage::is_broadcast(self : GmuMessage) -> Bool {
  self.dest.length() == 0
}

///|
/// Encode to wire bytes.
pub fn GmuMessage::encode(self : GmuMessage) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in gmu_magic {
    buf.push(b)
  }
  buf.push(self.msg_type.to_byte())
  finger_write_u32(buf, self.sequence)
  finger_write_str(buf, self.source)
  finger_write_str(buf, self.dest)
  finger_write_u32(buf, self.payload.length())
  for b in self.payload {
    buf.push(b)
  }
  buf
}

///|
/// Decode from wire bytes.
pub fn GmuMessage::decode(data : Array[Byte]) -> GmuMessage? {
  let len = data.length()
  if len < 9 {
    return None
  }
  if data[0] != gmu_magic[0] ||
    data[1] != gmu_magic[1] ||
    data[2] != gmu_magic[2] ||
    data[3] != gmu_magic[3] {
    return None
  }
  let msg_type = match GmuType::from_byte(data[4]) {
    Some(t) => t
    None => return None
  }
  let mut pos = 5
  let sequence = finger_read_u32(data, pos)
  pos = pos + 4
  let source = match finger_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let dest = match finger_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  if pos + 4 > len {
    return None
  }
  let payload_len = finger_read_u32(data, pos)
  pos = pos + 4
  if pos + payload_len > len {
    return None
  }
  let payload : Array[Byte] = []
  let mut i = 0
  while i < payload_len {
    payload.push(data[pos + i])
    i = i + 1
  }
  Some({ msg_type, sequence, source, dest, payload })
}

// ---------------------------------------------------------------------------
// finger.plan — node self-description
// ---------------------------------------------------------------------------

///|
/// A finger.plan document — what a node publishes for discovery.
pub(all) struct FingerPlan {
  node_id : String
  epoch : Int
  capability_class : String // "full", "read-only", "scoped"
  overlay : String // AI model overlay (e.g., "claude")
  tier : String // cognitive tier (e.g., "opus")
  mode : String // node mode (e.g., "proxy")
  plugin_names : Array[String] // active plugin names
  bloom_insertions : Int // bloom filter population
  endpoints : Array[String] // known network endpoints
  timestamp : Int // when this plan was generated
} derive(Debug)

///|
pub fn FingerPlan::generate(
  node_id : String,
  epoch : Int,
  capability_class : String,
  overlay : String,
  tier : String,
  mode : String,
  plugin_names : Array[String],
  bloom_insertions : Int,
  endpoints : Array[String],
  timestamp : Int,
) -> FingerPlan {
  {
    node_id,
    epoch,
    capability_class,
    overlay,
    tier,
    mode,
    plugin_names,
    bloom_insertions,
    endpoints,
    timestamp,
  }
}

///|
/// Serialize finger.plan to bytes.
pub fn FingerPlan::to_bytes(self : FingerPlan) -> Array[Byte] {
  let buf : Array[Byte] = []
  // Magic "FNGR"
  buf.push(b'\x46')
  buf.push(b'\x4E')
  buf.push(b'\x47')
  buf.push(b'\x52')
  finger_write_str(buf, self.node_id)
  finger_write_u32(buf, self.epoch)
  finger_write_str(buf, self.capability_class)
  finger_write_str(buf, self.overlay)
  finger_write_str(buf, self.tier)
  finger_write_str(buf, self.mode)
  finger_write_u32(buf, self.plugin_names.length())
  for name in self.plugin_names {
    finger_write_str(buf, name)
  }
  finger_write_u32(buf, self.bloom_insertions)
  finger_write_u32(buf, self.endpoints.length())
  for ep in self.endpoints {
    finger_write_str(buf, ep)
  }
  finger_write_u32(buf, self.timestamp)
  buf
}

///|
/// Deserialize finger.plan from bytes.
pub fn FingerPlan::from_bytes(data : Array[Byte]) -> FingerPlan? {
  let len = data.length()
  if len < 4 {
    return None
  }
  if data[0] != b'\x46' ||
    data[1] != b'\x4E' ||
    data[2] != b'\x47' ||
    data[3] != b'\x52' {
    return None
  }
  let mut pos = 4
  let node_id = match finger_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  if pos + 4 > len {
    return None
  }
  let epoch = finger_read_u32(data, pos)
  pos = pos + 4
  let capability_class = match finger_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let overlay = match finger_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let tier = match finger_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let mode = match finger_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  if pos + 4 > len {
    return None
  }
  let n_plugins = finger_read_u32(data, pos)
  pos = pos + 4
  let plugin_names : Array[String] = []
  let mut i = 0
  while i < n_plugins {
    match finger_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        plugin_names.push(s)
      }
      None => return None
    }
    i = i + 1
  }
  if pos + 4 > len {
    return None
  }
  let bloom_insertions = finger_read_u32(data, pos)
  pos = pos + 4
  if pos + 4 > len {
    return None
  }
  let n_endpoints = finger_read_u32(data, pos)
  pos = pos + 4
  let endpoints : Array[String] = []
  i = 0
  while i < n_endpoints {
    match finger_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        endpoints.push(s)
      }
      None => return None
    }
    i = i + 1
  }
  if pos + 4 > len {
    return None
  }
  let timestamp = finger_read_u32(data, pos)
  Some({
    node_id,
    epoch,
    capability_class,
    overlay,
    tier,
    mode,
    plugin_names,
    bloom_insertions,
    endpoints,
    timestamp,
  })
}

// ---------------------------------------------------------------------------
// FINGER-CERT types
// ---------------------------------------------------------------------------

///|
/// A FINGER-CERT — signed certificate for authenticated discovery.
pub(all) struct FingerCert {
  node_id : String
  public_key : Array[Byte] // 32-byte public key
  issued_at : Int // timestamp
  expires_at : Int // timestamp
  issuer : String // issuer node ID (self-signed if same)
  signature : Array[Byte] // 64-byte signature
} derive(Debug)

///|
pub fn FingerCert::new(
  node_id : String,
  public_key : Array[Byte],
  issued_at : Int,
  expires_at : Int,
  issuer : String,
  signature : Array[Byte],
) -> FingerCert {
  { node_id, public_key, issued_at, expires_at, issuer, signature }
}

///|
/// Is this cert self-signed?
pub fn FingerCert::is_self_signed(self : FingerCert) -> Bool {
  self.node_id == self.issuer
}

///|
/// Is this cert expired (given current timestamp)?
pub fn FingerCert::is_expired(self : FingerCert, now : Int) -> Bool {
  now > self.expires_at
}

///|
/// Is this cert valid (not expired, given current timestamp)?
pub fn FingerCert::is_valid(self : FingerCert, now : Int) -> Bool {
  now >= self.issued_at && now <= self.expires_at
}

// ---------------------------------------------------------------------------
// Finger state — the node's discovery context
// ---------------------------------------------------------------------------

///|
/// The node's discovery state.
pub(all) struct FingerState {
  mut plan : FingerPlan? // current published plan
  cert : FingerCert? // our cert
  known_peers : Array[PeerInfo] // discovered peers
  mut sequence : Int // GMU/1 sequence counter
} derive(Debug)

///|
/// Info about a discovered peer.
pub(all) struct PeerInfo {
  node_id : String
  mut plan : FingerPlan? // their finger.plan (if received)
  cert : FingerCert? // their cert (if received)
  mut last_seen : Int // timestamp of last message
  mut pings : Int // total pings exchanged
} derive(Debug)

///|
pub fn FingerState::new() -> FingerState {
  { plan: None, cert: None, known_peers: [], sequence: 0 }
}

///|
/// Update the published finger.plan.
pub fn FingerState::publish_plan(self : FingerState, plan : FingerPlan) -> Unit {
  self.plan = Some(plan)
}

///|
/// Get the next GMU/1 sequence number.
pub fn FingerState::next_sequence(self : FingerState) -> Int {
  self.sequence = self.sequence + 1
  self.sequence
}

///|
/// Record a peer sighting.
pub fn FingerState::note_peer(
  self : FingerState,
  node_id : String,
  timestamp : Int,
) -> Unit {
  for p in self.known_peers {
    if p.node_id == node_id {
      p.last_seen = timestamp
      p.pings = p.pings + 1
      return
    }
  }
  self.known_peers.push({
    node_id,
    plan: None,
    cert: None,
    last_seen: timestamp,
    pings: 1,
  })
}

///|
/// Update a peer's plan.
pub fn FingerState::update_peer_plan(
  self : FingerState,
  node_id : String,
  plan : FingerPlan,
) -> Unit {
  for p in self.known_peers {
    if p.node_id == node_id {
      p.plan = Some(plan)
      return
    }
  }
}

///|
/// Number of known peers.
pub fn FingerState::peer_count(self : FingerState) -> Int {
  self.known_peers.length()
}

///|
/// Find a peer by node ID.
pub fn FingerState::find_peer(
  self : FingerState,
  node_id : String,
) -> PeerInfo? {
  for p in self.known_peers {
    if p.node_id == node_id {
      return Some(p)
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn finger_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn finger_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF) |
  ((data[pos + 1].to_int() & 0xFF) << 8) |
  ((data[pos + 2].to_int() & 0xFF) << 16) |
  ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn finger_write_str(buf : Array[Byte], s : String) -> Unit {
  let encoded : Array[Byte] = []
  for ch in s {
    let cp = ch.to_int()
    if cp < 0x80 {
      encoded.push(cp.to_byte())
    } else if cp < 0x800 {
      encoded.push((0xC0 | (cp >> 6)).to_byte())
      encoded.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      encoded.push((0xE0 | (cp >> 12)).to_byte())
      encoded.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      encoded.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  finger_write_u32(buf, encoded.length())
  for b in encoded {
    buf.push(b)
  }
}

///|
fn finger_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len {
    return None
  }
  let n = finger_read_u32(data, pos)
  let start = pos + 4
  if start + n > len {
    return None
  }
  let sb = StringBuilder::new()
  let mut i = start
  let end = start + n
  while i < end {
    let b0 = data[i].to_int()
    if (b0 & 0x80) == 0 {
      sb.write_char(b0.to_char().unwrap())
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 && i + 1 < end {
      let b1 = data[i + 1].to_int()
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      sb.write_char(cp.to_char().unwrap())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < end {
      let b1 = data[i + 1].to_int()
      let b2 = data[i + 2].to_int()
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      sb.write_char(cp.to_char().unwrap())
      i = i + 3
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  Some((sb.to_string(), end))
}
