// The Void — passive accumulator.
//
// muyata's MoonBit equivalent. The void starts empty and grows through
// observation — it never shrinks. It witnesses traffic without modifying it.
//
// A Void instance is the observer side of the cognitive stack:
//   - LSP sessions pass through it (session_count, bytes_observed)
//   - Patterns accumulate without eviction (patterns_seen)
//   - Node connections are noted (connections_seen)
//   - Epochs tick with each seal (epoch)
//
// Immutable update pattern: every "mutation" returns a new Void.
// This makes the accumulator safe for functional composition and for
// embedding in forged WASM binaries as a serialized blob.
//
// Wire format (for .cog section / envelope integration):
//   [4]  magic          : 0x56 0x4F 0x49 0x44  "VOID"
//   [4]  format_version : u32 LE  (currently 1)
//   [4]  node_id_len    : u32 LE
//   [n]  node_id        : utf8
//   [4]  epoch          : u32 LE
//   [4]  bytes_observed : u32 LE
//   [4]  session_count  : u32 LE
//   [4]  patterns_seen  : u32 LE
//   [4]  connections_seen : u32 LE
//   [4]  n_anchors      : u32 LE
//   per anchor: [4] name_len + [n] utf8 name + [4] weight u32 LE

let void_magic : Array[Byte] = [b'\x56', b'\x4F', b'\x49', b'\x44'] // "VOID"
let void_format_version : Int = 1

/// A single observed salience anchor — a named location that has been
/// attended to some number of times.
pub(all) struct VoidAnchor {
  name   : String
  weight : Int     // accumulated attend count, never decremented
} derive(Eq, Debug)

/// The void accumulator.  All fields monotonically increase or are
/// replaced with strictly more-informative values.
pub(all) struct Void {
  node_id          : String           // identity of this observer node
  epoch            : Int              // incremented on each seal/tick
  bytes_observed   : Int              // total bytes witnessed (LSP + DC)
  session_count    : Int              // distinct LSP sessions observed
  patterns_seen    : Int              // distinct routing tokens encountered
  connections_seen : Int              // distinct peer node IDs encountered
  anchors          : Array[VoidAnchor] // named locations with attend weights
} derive(Debug)

/// Create a new, empty void for `node_id`.
pub fn Void::new(node_id : String) -> Void {
  {
    node_id,
    epoch:            0,
    bytes_observed:   0,
    session_count:    0,
    patterns_seen:    0,
    connections_seen: 0,
    anchors:          [],
  }
}

/// Observe `n` bytes of traffic.
pub fn Void::observe_bytes(self : Void, n : Int) -> Void {
  { ..self, bytes_observed: self.bytes_observed + n }
}

/// Record that a new LSP session was opened.
pub fn Void::observe_session(self : Void) -> Void {
  { ..self, session_count: self.session_count + 1 }
}

/// Record a new routing token (bloom pattern) encountered.
pub fn Void::observe_pattern(self : Void) -> Void {
  { ..self, patterns_seen: self.patterns_seen + 1 }
}

/// Record a new peer node connection.
pub fn Void::observe_connection(self : Void) -> Void {
  { ..self, connections_seen: self.connections_seen + 1 }
}

/// Attend to a named anchor — increases its weight by 1.
/// If the anchor doesn't exist yet, it is created with weight 1.
pub fn Void::attend(self : Void, name : String) -> Void {
  let mut found = false
  let new_anchors = self.anchors.map(fn(a) {
    if a.name == name {
      found = true
      { ..a, weight: a.weight + 1 }
    } else {
      a
    }
  })
  if !found {
    new_anchors.push({ name, weight: 1 })
  }
  { ..self, anchors: new_anchors }
}

/// Advance the epoch counter (called on each tree seal / DC sync).
pub fn Void::tick(self : Void) -> Void {
  { ..self, epoch: self.epoch + 1 }
}

/// Merge two voids: take the element-wise max of epoch/patterns/connections,
/// sum bytes and sessions, union anchors by name (taking max weight per anchor).
/// `self` node_id takes precedence.
pub fn Void::merge(self : Void, other : Void) -> Void {
  let merged_anchors = merge_anchors(self.anchors, other.anchors)
  {
    node_id:          self.node_id,
    epoch:            int_max(self.epoch, other.epoch),
    bytes_observed:   self.bytes_observed + other.bytes_observed,
    session_count:    self.session_count  + other.session_count,
    patterns_seen:    int_max(self.patterns_seen,    other.patterns_seen),
    connections_seen: int_max(self.connections_seen, other.connections_seen),
    anchors:          merged_anchors,
  }
}

/// Weight of a named anchor, 0 if not present.
pub fn Void::anchor_weight(self : Void, name : String) -> Int {
  for a in self.anchors {
    if a.name == name { return a.weight }
  }
  0
}

/// Top-N anchors by weight (descending).
pub fn Void::top_anchors(self : Void, n : Int) -> Array[VoidAnchor] {
  let sorted = self.anchors.copy()
  let len = sorted.length()
  let mut i = 1
  while i < len {
    let key = sorted[i]
    let mut j = i - 1
    while j >= 0 && sorted[j].weight < key.weight {
      sorted[j + 1] = sorted[j]
      j = j - 1
    }
    sorted[j + 1] = key
    i = i + 1
  }
  if n >= len { sorted } else { sorted[0:n].to_array() }
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

/// Serialize the void to bytes for the .cog section / wire transfer.
pub fn Void::to_bytes(self : Void) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in void_magic { buf.push(b) }
  write_u32_le(buf, void_format_version)
  write_utf8_field(buf, self.node_id)
  write_u32_le(buf, self.epoch)
  write_u32_le(buf, self.bytes_observed)
  write_u32_le(buf, self.session_count)
  write_u32_le(buf, self.patterns_seen)
  write_u32_le(buf, self.connections_seen)
  write_u32_le(buf, self.anchors.length())
  for a in self.anchors {
    write_utf8_field(buf, a.name)
    write_u32_le(buf, a.weight)
  }
  buf
}

/// Deserialize a void from bytes.  Returns None on malformed input.
pub fn Void::from_bytes(data : Array[Byte]) -> Void? {
  let len = data.length()
  if len < 4 { return None }
  if data[0] != void_magic[0] || data[1] != void_magic[1] ||
     data[2] != void_magic[2] || data[3] != void_magic[3] { return None }
  let mut pos = 4
  if pos + 4 > len { return None }
  let _ver = read_u32_le(data, pos)
  pos = pos + 4
  match read_utf8_field(data, pos, len) {
    None => None
    Some((node_id, p)) => {
      pos = p
      if pos + 24 > len { return None }
      let epoch            = read_u32_le(data, pos); pos = pos + 4
      let bytes_observed   = read_u32_le(data, pos); pos = pos + 4
      let session_count    = read_u32_le(data, pos); pos = pos + 4
      let patterns_seen    = read_u32_le(data, pos); pos = pos + 4
      let connections_seen = read_u32_le(data, pos); pos = pos + 4
      if pos + 4 > len { return None }
      let n_anchors = read_u32_le(data, pos); pos = pos + 4
      let anchors : Array[VoidAnchor] = []
      let mut ok = true
      let mut i = 0
      while i < n_anchors && ok {
        match read_utf8_field(data, pos, len) {
          None => ok = false
          Some((name, p2)) => {
            pos = p2
            if pos + 4 > len { ok = false }
            else {
              let weight = read_u32_le(data, pos); pos = pos + 4
              anchors.push({ name, weight })
            }
          }
        }
        i = i + 1
      }
      if !ok { return None }
      Some({
        node_id, epoch, bytes_observed, session_count,
        patterns_seen, connections_seen, anchors,
      })
    }
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn merge_anchors(a : Array[VoidAnchor], b : Array[VoidAnchor]) -> Array[VoidAnchor] {
  let out = a.copy()
  for bv in b {
    let mut found = false
    let mut i = 0
    while i < out.length() {
      if out[i].name == bv.name {
        out[i] = { ..out[i], weight: int_max(out[i].weight, bv.weight) }
        found = true
        break
      }
      i = i + 1
    }
    if !found { out.push(bv) }
  }
  out
}

fn int_max(a : Int, b : Int) -> Int {
  if a >= b { a } else { b }
}

fn write_u32_le(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

fn read_u32_le(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

fn write_utf8_field(buf : Array[Byte], s : String) -> Unit {
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
  write_u32_le(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

fn read_utf8_field(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = read_u32_le(data, pos)
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
