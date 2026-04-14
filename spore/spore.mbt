///|
/// Spore — mobile agent pack for clone-and-bridge transfer.
///
/// A spore is a self-contained bundle that carries:
///   1. A forked mulsp identity (child of the sender, authenticated lineage)
///   2. A cloned muyata profile (possibly at a different tier)
///   3. A grammar tree (protocol knowledge accumulated by observation)
///   4. A void snapshot (accumulated salience and anchor weights)
///   5. An opaque payload (the actual data to transfer — tree pack, etc.)
///   6. A work intent (what should the spore DO when it boots?)
///
/// The lifecycle of a spore:
///   observe → accumulate → spore → ship → boot → bridge → emit residue → quiesce
///
/// When a spore boots on a destination node:
///   1. Deserialize the mulsp/muyata (validate cognitive boundary chain)
///   2. Attach the mulsp to the local node (Dormant → Attached → Active)
///   3. Load the grammar tree (protocol knowledge transfers with the agent)
///   4. Execute the work intent:
///      - Interposition: set up a FlowTap using the grammar, bridge the protocol
///      - GrammarInfer: distill manifold fragments, emit residue
///      - Observation: passively accumulate void on the destination
///      - Compilation: process the payload, produce artifacts
///      - Delegation: fork sub-spores, fan out further
///   5. Emit residue back to parent (stigmergy — no direct channel needed)
///   6. Quiesce or revoke
///
/// Wire format:
///   [4]  magic          : 0x53 0x50 0x4F 0x52  "SPOR"
///   [4]  format_version : u32 LE (currently 1)
///   [4+n] spore_id      : utf8 (derived from child mulsp_id)
///   [4+n] parent_id     : utf8 (parent mulsp_id for entanglement)
///   [1]  intent         : u8 (WorkIntent byte)
///   [1]  ttl            : u8 (max relay hops, 0 = direct delivery)
///   [4]  route_bloom_len : u32 LE (anti-loop bloom, 0 if empty)
///   [n]  route_bloom    : bytes
///   [4]  mulsp_len      : u32 LE
///   [n]  mulsp_bytes    : serialized MulspState
///   [4]  muyata_len     : u32 LE
///   [n]  muyata_bytes   : serialized MuyataProfile
///   [4]  grammar_len    : u32 LE (0 if no grammar)
///   [n]  grammar_bytes  : serialized GrammarTree
///   [4]  void_len       : u32 LE (0 if no void)
///   [n]  void_bytes     : serialized Void
///   [4]  payload_len    : u32 LE (0 if no payload)
///   [n]  payload        : opaque bytes (tree pack, cognitive container, etc.)

let spore_magic : Array[Byte] = [b'\x53', b'\x50', b'\x4F', b'\x52'] // "SPOR"
let spore_version : Int = 1

// ---------------------------------------------------------------------------
// SporePack
// ---------------------------------------------------------------------------

///|
/// A spore — mobile agent bundle carrying identity, knowledge, and payload.
pub(all) struct SporePack {
  spore_id      : String               // derived from child mulsp_id
  parent_id     : String               // parent mulsp_id for entanglement tracking
  intent        : @muyata.WorkIntent   // what the spore should do on boot
  ttl           : Int                  // max relay hops (0 = direct)
  route_bloom   : Array[Byte]          // anti-loop bloom (node IDs already visited)
  mulsp_state   : @mulsp.MulspState    // forked identity
  muyata_profile : @muyata.MuyataProfile // cloned AI profile
  grammar_tree  : @grammar.GrammarTree? // protocol knowledge (None if no grammar)
  void_state    : @void.Void?          // accumulated salience (None if fresh)
  payload       : Array[Byte]          // opaque payload
} derive(Debug)

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create a spore from a forked mulsp and cloned muyata.
/// The grammar tree and void snapshot travel with the spore,
/// giving it protocol knowledge and accumulated salience at the destination.
pub fn SporePack::new(
  mulsp_state : @mulsp.MulspState,
  muyata_profile : @muyata.MuyataProfile,
  intent : @muyata.WorkIntent,
) -> SporePack {
  let parent_id = match mulsp_state.parent_id() {
    Some(pid) => pid
    None => ""
  }
  {
    spore_id: mulsp_state.mulsp_id,
    parent_id,
    intent,
    ttl: 8,           // default 8 hops
    route_bloom: [],
    mulsp_state,
    muyata_profile,
    grammar_tree: None,
    void_state: None,
    payload: [],
  }
}

///|
/// Attach protocol knowledge (grammar tree from FlowTap observation).
pub fn SporePack::with_grammar(
  self : SporePack,
  grammar : @grammar.GrammarTree,
) -> SporePack {
  { ..self, grammar_tree: Some(grammar) }
}

///|
/// Attach accumulated salience (void from prior observation).
pub fn SporePack::with_void(
  self : SporePack,
  void_state : @void.Void,
) -> SporePack {
  { ..self, void_state: Some(void_state) }
}

///|
/// Attach opaque payload (tree pack, cognitive container, etc.).
pub fn SporePack::with_payload(
  self : SporePack,
  payload : Array[Byte],
) -> SporePack {
  { ..self, payload }
}

///|
/// Set TTL (max relay hops).
pub fn SporePack::with_ttl(self : SporePack, ttl : Int) -> SporePack {
  { ..self, ttl }
}

///|
/// Set route bloom (anti-loop, typically from prior hops).
pub fn SporePack::with_route_bloom(
  self : SporePack,
  bloom : Array[Byte],
) -> SporePack {
  { ..self, route_bloom: bloom }
}

// ---------------------------------------------------------------------------
// Relay operations
// ---------------------------------------------------------------------------

///|
/// Decrement TTL for relay. Returns None if TTL exhausted.
pub fn SporePack::relay_hop(self : SporePack, node_id : String) -> SporePack? {
  if self.ttl <= 0 { return None }
  // Add this node to the route bloom (simple FNV hash into bloom bits)
  let new_bloom = self.route_bloom.copy()
  spore_bloom_add(new_bloom, node_id)
  Some({ ..self, ttl: self.ttl - 1, route_bloom: new_bloom })
}

///|
/// Check if a node has already been visited (anti-loop).
pub fn SporePack::visited(self : SporePack, node_id : String) -> Bool {
  spore_bloom_check(self.route_bloom, node_id)
}

///|
/// Is this spore still relay-able (TTL > 0)?
pub fn SporePack::can_relay(self : SporePack) -> Bool {
  self.ttl > 0
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// The cognitive tier of this spore's muyata profile.
pub fn SporePack::tier(self : SporePack) -> @muyata.CognitiveTier {
  self.muyata_profile.tier()
}

///|
/// Cost weight (Haiku=1, Sonnet=4, Opus=16).
pub fn SporePack::cost_weight(self : SporePack) -> Int {
  self.muyata_profile.cost_weight()
}

///|
/// Does this spore carry protocol knowledge?
pub fn SporePack::has_grammar(self : SporePack) -> Bool {
  self.grammar_tree is Some(_)
}

///|
/// Does this spore carry a payload?
pub fn SporePack::has_payload(self : SporePack) -> Bool {
  self.payload.length() > 0
}

///|
/// Is this spore a clone (vs original)?
pub fn SporePack::is_clone(self : SporePack) -> Bool {
  self.parent_id.length() > 0
}

///|
/// Approximate serialized size (for transfer planning).
pub fn SporePack::estimated_size(self : SporePack) -> Int {
  let mut size = 32 // header overhead
  size = size + self.spore_id.to_array().length()
  size = size + self.parent_id.to_array().length()
  size = size + self.route_bloom.length()
  size = size + self.payload.length()
  // mulsp/muyata/grammar/void sizes estimated
  size = size + 256  // mulsp ~256 bytes typical
  size = size + 128  // muyata ~128 bytes typical
  match self.grammar_tree {
    Some(g) => size = size + g.total_tokens * 32 // rough estimate
    None => ()
  }
  size
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

///|
pub fn SporePack::to_bytes(self : SporePack) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in spore_magic { buf.push(b) }
  spore_write_u32(buf, spore_version)
  spore_write_str(buf, self.spore_id)
  spore_write_str(buf, self.parent_id)
  buf.push(self.intent.to_byte())
  buf.push(self.ttl.to_byte())
  // route bloom
  spore_write_u32(buf, self.route_bloom.length())
  for b in self.route_bloom { buf.push(b) }
  // mulsp
  let mulsp_bytes = self.mulsp_state.to_bytes()
  spore_write_u32(buf, mulsp_bytes.length())
  for b in mulsp_bytes { buf.push(b) }
  // muyata
  let muyata_bytes = self.muyata_profile.to_bytes()
  spore_write_u32(buf, muyata_bytes.length())
  for b in muyata_bytes { buf.push(b) }
  // grammar
  match self.grammar_tree {
    Some(g) => {
      let gram_bytes = g.to_bytes()
      spore_write_u32(buf, gram_bytes.length())
      for b in gram_bytes { buf.push(b) }
    }
    None => spore_write_u32(buf, 0)
  }
  // void
  match self.void_state {
    Some(v) => {
      let void_bytes = v.to_bytes()
      spore_write_u32(buf, void_bytes.length())
      for b in void_bytes { buf.push(b) }
    }
    None => spore_write_u32(buf, 0)
  }
  // payload
  spore_write_u32(buf, self.payload.length())
  for b in self.payload { buf.push(b) }
  buf
}

///|
pub fn SporePack::from_bytes(data : Array[Byte]) -> SporePack? {
  let len = data.length()
  if len < 8 { return None }
  if data[0] != spore_magic[0] || data[1] != spore_magic[1] ||
     data[2] != spore_magic[2] || data[3] != spore_magic[3] { return None }
  let mut pos = 4
  let _ver = spore_read_u32(data, pos); pos = pos + 4
  let spore_id = match spore_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  let parent_id = match spore_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  if pos + 2 > len { return None }
  let intent = @muyata.WorkIntent::from_byte(data[pos]); pos = pos + 1
  let ttl = data[pos].to_int(); pos = pos + 1
  // route bloom
  if pos + 4 > len { return None }
  let bloom_len = spore_read_u32(data, pos); pos = pos + 4
  if pos + bloom_len > len { return None }
  let route_bloom : Array[Byte] = []
  let mut i = 0
  while i < bloom_len { route_bloom.push(data[pos + i]); i = i + 1 }
  pos = pos + bloom_len
  // mulsp
  if pos + 4 > len { return None }
  let mulsp_len = spore_read_u32(data, pos); pos = pos + 4
  if pos + mulsp_len > len { return None }
  let mulsp_bytes : Array[Byte] = []
  i = 0
  while i < mulsp_len { mulsp_bytes.push(data[pos + i]); i = i + 1 }
  pos = pos + mulsp_len
  let mulsp_state = match @mulsp.MulspState::from_bytes(mulsp_bytes) {
    Some(m) => m
    None => return None
  }
  // muyata
  if pos + 4 > len { return None }
  let muyata_len = spore_read_u32(data, pos); pos = pos + 4
  if pos + muyata_len > len { return None }
  let muyata_bytes : Array[Byte] = []
  i = 0
  while i < muyata_len { muyata_bytes.push(data[pos + i]); i = i + 1 }
  pos = pos + muyata_len
  let muyata_profile = match @muyata.MuyataProfile::from_bytes(muyata_bytes) {
    Some(m) => m
    None => return None
  }
  // grammar
  if pos + 4 > len { return None }
  let gram_len = spore_read_u32(data, pos); pos = pos + 4
  let grammar_tree : @grammar.GrammarTree? = if gram_len > 0 {
    if pos + gram_len > len { return None }
    let gram_bytes : Array[Byte] = []
    i = 0
    while i < gram_len { gram_bytes.push(data[pos + i]); i = i + 1 }
    pos = pos + gram_len
    @grammar.GrammarTree::from_bytes(gram_bytes)
  } else {
    None
  }
  // void
  if pos + 4 > len { return None }
  let void_len = spore_read_u32(data, pos); pos = pos + 4
  let void_state : @void.Void? = if void_len > 0 {
    if pos + void_len > len { return None }
    let void_bytes : Array[Byte] = []
    i = 0
    while i < void_len { void_bytes.push(data[pos + i]); i = i + 1 }
    pos = pos + void_len
    @void.Void::from_bytes(void_bytes)
  } else {
    None
  }
  // payload
  if pos + 4 > len { return None }
  let payload_len = spore_read_u32(data, pos); pos = pos + 4
  if pos + payload_len > len { return None }
  let payload : Array[Byte] = []
  i = 0
  while i < payload_len { payload.push(data[pos + i]); i = i + 1 }

  Some({
    spore_id, parent_id, intent, ttl, route_bloom,
    mulsp_state, muyata_profile, grammar_tree, void_state, payload,
  })
}

// ---------------------------------------------------------------------------
// Route bloom — simple anti-loop filter
// ---------------------------------------------------------------------------

///|
let spore_bloom_bits : Int = 256

///|
fn spore_bloom_add(bloom : Array[Byte], node_id : String) -> Unit {
  // Ensure bloom is at least spore_bloom_bits/8 bytes
  let needed = spore_bloom_bits / 8
  while bloom.length() < needed { bloom.push(b'\x00') }
  // FNV-1a with 3 hash positions
  let mut k = 0
  while k < 3 {
    let mut h = 0x811C9DC5 ^ (k * 0x01000193)
    for ch in node_id {
      h = h ^ ch.to_int()
      h = h * 0x01000193
    }
    let pos = if h < 0 { (-h) % spore_bloom_bits } else { h % spore_bloom_bits }
    let byte_idx = pos / 8
    let bit_idx = pos % 8
    if byte_idx < bloom.length() {
      bloom[byte_idx] = (bloom[byte_idx].to_int() | (1 << bit_idx)).to_byte()
    }
    k = k + 1
  }
}

///|
fn spore_bloom_check(bloom : Array[Byte], node_id : String) -> Bool {
  if bloom.length() == 0 { return false }
  let mut k = 0
  while k < 3 {
    let mut h = 0x811C9DC5 ^ (k * 0x01000193)
    for ch in node_id {
      h = h ^ ch.to_int()
      h = h * 0x01000193
    }
    let pos = if h < 0 { (-h) % spore_bloom_bits } else { h % spore_bloom_bits }
    let byte_idx = pos / 8
    let bit_idx = pos % 8
    if byte_idx >= bloom.length() { return false }
    if (bloom[byte_idx].to_int() & (1 << bit_idx)) == 0 { return false }
    k = k + 1
  }
  true
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn spore_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn spore_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn spore_write_str(buf : Array[Byte], s : String) -> Unit {
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
  spore_write_u32(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

///|
fn spore_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = spore_read_u32(data, pos)
  let start = pos + 4
  if start + n > len { return None }
  let sb = StringBuilder::new()
  let mut i = start
  let end = start + n
  while i < end {
    let b0 = data[i].to_int()
    if (b0 & 0x80) == 0 {
      sb.write_char(b0.to_char().unwrap()); i = i + 1
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
      sb.write_char('\u{FFFD}'); i = i + 1
    }
  }
  Some((sb.to_string(), end))
}
