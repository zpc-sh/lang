///|
/// Emergent Persona — self-directed node behavior.
///
/// The emergent persona is the "daemon mode" of the node. Instead of
/// passively proxying LSP, it actively:
///   - Monitors void state and triggers actions at thresholds
///   - Manages bloom filter for routing decisions
///   - Performs tree walks for content discovery
///   - Emits residue (stigmergy traces) for peer nodes
///   - Drives the seal/checkpoint cycle
///
/// The emergent persona observes the node's void accumulator and
/// decides when to act. It implements a simple threshold-based
/// policy: when anchor weights exceed thresholds, trigger behaviors.
///
/// This is the cognitive kernel — where the node becomes more than
/// a proxy and develops its own behaviors through accumulated observation.

// ---------------------------------------------------------------------------
// Thresholds
// ---------------------------------------------------------------------------

///|
/// Policy thresholds that trigger emergent behaviors.
pub(all) struct EmergentPolicy {
  seal_interval     : Int    // ticks between forced seals
  checkpoint_interval : Int  // ticks between checkpoints
  bloom_refresh     : Int    // ticks between bloom recalculation
  residue_threshold : Int    // void bytes before emitting residue
  anchor_threshold  : Int    // anchor weight before triggering attention
} derive(Debug)

///|
pub fn EmergentPolicy::default_policy() -> EmergentPolicy {
  {
    seal_interval: 32,
    checkpoint_interval: 256,
    bloom_refresh: 64,
    residue_threshold: 65536,
    anchor_threshold: 16,
  }
}

///|
pub fn EmergentPolicy::aggressive() -> EmergentPolicy {
  {
    seal_interval: 8,
    checkpoint_interval: 64,
    bloom_refresh: 16,
    residue_threshold: 16384,
    anchor_threshold: 4,
  }
}

// ---------------------------------------------------------------------------
// Bloom sketch (simplified)
// ---------------------------------------------------------------------------

///|
/// A simplified bloom filter for routing decisions.
/// Uses a fixed bit array with k=3 hash functions.
pub(all) struct BloomSketch {
  bits : Array[Byte]    // bit array (256 bytes = 2048 bits)
  mut insertions : Int  // number of items inserted
} derive(Debug)

///|
let bloom_size : Int = 256  // bytes

///|
pub fn BloomSketch::new() -> BloomSketch {
  { bits: Array::make(bloom_size, b'\x00'), insertions: 0 }
}

///|
/// Insert a key into the bloom filter.
pub fn BloomSketch::insert(self : BloomSketch, key : String) -> Unit {
  let h1 = bloom_hash(key, 0x811C9DC5)
  let h2 = bloom_hash(key, 0x01000193)
  let h3 = bloom_hash(key, 0xDEADBEEF)
  bloom_set_bit(self.bits, h1 % (bloom_size * 8))
  bloom_set_bit(self.bits, h2 % (bloom_size * 8))
  bloom_set_bit(self.bits, h3 % (bloom_size * 8))
  self.insertions = self.insertions + 1
}

///|
/// Test if a key might be in the bloom filter.
pub fn BloomSketch::maybe_contains(self : BloomSketch, key : String) -> Bool {
  let h1 = bloom_hash(key, 0x811C9DC5)
  let h2 = bloom_hash(key, 0x01000193)
  let h3 = bloom_hash(key, 0xDEADBEEF)
  bloom_get_bit(self.bits, h1 % (bloom_size * 8)) &&
  bloom_get_bit(self.bits, h2 % (bloom_size * 8)) &&
  bloom_get_bit(self.bits, h3 % (bloom_size * 8))
}

///|
/// Reset the bloom filter.
pub fn BloomSketch::clear(self : BloomSketch) -> Unit {
  let mut i = 0
  while i < bloom_size { self.bits[i] = b'\x00'; i = i + 1 }
  self.insertions = 0
}

///|
/// Estimated false positive rate.
pub fn BloomSketch::estimated_fpr(self : BloomSketch) -> Int {
  // Rough estimate: (1 - e^(-kn/m))^k * 100
  // Simplified: if insertions > bits/4, FPR is high
  let m = bloom_size * 8
  if self.insertions == 0 { return 0 }
  if self.insertions > m / 4 { return 50 }
  (self.insertions * 100) / m
}

// ---------------------------------------------------------------------------
// Residue — stigmergy trace
// ---------------------------------------------------------------------------

///|
/// A residue entry — a stigmergy trace left by the emergent persona.
pub(all) struct Residue {
  node_id    : String    // which node left this
  epoch      : Int       // which epoch
  anchor     : String    // what was attended to
  weight     : Int       // how much attention
  timestamp  : Int       // when (ms)
} derive(Debug)

///|
pub fn Residue::new(
  node_id : String,
  epoch : Int,
  anchor : String,
  weight : Int,
  timestamp : Int,
) -> Residue {
  { node_id, epoch, anchor, weight, timestamp }
}

///|
/// Serialize residue to bytes.
pub fn Residue::to_bytes(self : Residue) -> Array[Byte] {
  let buf : Array[Byte] = []
  // Magic "RESD"
  buf.push(b'\x52'); buf.push(b'\x45'); buf.push(b'\x53'); buf.push(b'\x44')
  residue_write_str(buf, self.node_id)
  residue_write_u32(buf, self.epoch)
  residue_write_str(buf, self.anchor)
  residue_write_u32(buf, self.weight)
  residue_write_u32(buf, self.timestamp)
  buf
}

///|
/// Deserialize residue from bytes.
pub fn Residue::from_bytes(data : Array[Byte]) -> Residue? {
  let len = data.length()
  if len < 4 { return None }
  if data[0] != b'\x52' || data[1] != b'\x45' ||
     data[2] != b'\x53' || data[3] != b'\x44' { return None }
  let mut pos = 4
  let node_id = match residue_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  if pos + 4 > len { return None }
  let epoch = residue_read_u32(data, pos); pos = pos + 4
  let anchor = match residue_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  if pos + 4 > len { return None }
  let weight = residue_read_u32(data, pos); pos = pos + 4
  if pos + 4 > len { return None }
  let timestamp = residue_read_u32(data, pos)
  Some({ node_id, epoch, anchor, weight, timestamp })
}

// ---------------------------------------------------------------------------
// Emergent state
// ---------------------------------------------------------------------------

///|
/// The emergent persona's runtime state.
pub(all) struct EmergentState {
  policy         : EmergentPolicy
  bloom          : BloomSketch
  residues       : Array[Residue]    // emitted residues (outbox)
  mut tick_count : Int
  mut last_seal_tick    : Int
  mut last_ckpt_tick    : Int
  mut last_bloom_tick   : Int
  mut total_residues    : Int
} derive(Debug)

///|
pub fn EmergentState::new(policy : EmergentPolicy) -> EmergentState {
  {
    policy,
    bloom: BloomSketch::new(),
    residues: [],
    tick_count: 0,
    last_seal_tick: 0,
    last_ckpt_tick: 0,
    last_bloom_tick: 0,
    total_residues: 0,
  }
}

///|
/// Process a tick — check thresholds and trigger behaviors.
/// Returns a list of actions to take.
pub fn EmergentState::tick(
  self : EmergentState,
  void_state : @void.Void,
  now_ms : Int,
) -> Array[EmergentAction] {
  self.tick_count = self.tick_count + 1
  let actions : Array[EmergentAction] = []

  // Seal check
  if self.tick_count - self.last_seal_tick >= self.policy.seal_interval {
    actions.push(Seal)
    self.last_seal_tick = self.tick_count
  }

  // Checkpoint check
  if self.tick_count - self.last_ckpt_tick >= self.policy.checkpoint_interval {
    actions.push(Checkpoint)
    self.last_ckpt_tick = self.tick_count
  }

  // Bloom refresh check
  if self.tick_count - self.last_bloom_tick >= self.policy.bloom_refresh {
    actions.push(BloomRefresh)
    self.last_bloom_tick = self.tick_count
  }

  // Residue emission check — look for hot anchors
  let top = void_state.top_anchors(3)
  for anchor in top {
    if anchor.weight >= self.policy.anchor_threshold {
      let residue = Residue::new(
        void_state.node_id, void_state.epoch,
        anchor.name, anchor.weight, now_ms,
      )
      self.residues.push(residue)
      self.total_residues = self.total_residues + 1
      actions.push(EmitResidue(anchor.name))
    }
  }

  actions
}

///|
/// Drain emitted residues.
pub fn EmergentState::drain_residues(self : EmergentState) -> Array[Residue] {
  let out = self.residues.copy()
  self.residues.clear()
  out
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

///|
/// Actions the emergent persona can trigger.
pub(all) enum EmergentAction {
  Seal                    // seal void state
  Checkpoint              // full checkpoint
  BloomRefresh            // recalculate bloom
  EmitResidue(String)     // emit residue for anchor
} derive(Debug)

///|
impl Show for EmergentAction with output(self, logger) {
  logger.write_string(match self {
    Seal             => "Seal"
    Checkpoint       => "Checkpoint"
    BloomRefresh     => "BloomRefresh"
    EmitResidue(a)   => "EmitResidue(\{a})"
  })
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn bloom_hash(s : String, seed : Int) -> Int {
  let mut h = seed
  for ch in s {
    h = h ^ ch.to_int()
    h = h * 0x01000193
  }
  if h < 0 { -h } else { h }
}

///|
fn bloom_set_bit(bits : Array[Byte], pos : Int) -> Unit {
  let byte_idx = pos / 8
  let bit_idx = pos % 8
  if byte_idx < bits.length() {
    bits[byte_idx] = (bits[byte_idx].to_int() | (1 << bit_idx)).to_byte()
  }
}

///|
fn bloom_get_bit(bits : Array[Byte], pos : Int) -> Bool {
  let byte_idx = pos / 8
  let bit_idx = pos % 8
  if byte_idx < bits.length() {
    (bits[byte_idx].to_int() & (1 << bit_idx)) != 0
  } else {
    false
  }
}

///|
fn residue_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn residue_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn residue_write_str(buf : Array[Byte], s : String) -> Unit {
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
  residue_write_u32(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

///|
fn residue_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = residue_read_u32(data, pos)
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
