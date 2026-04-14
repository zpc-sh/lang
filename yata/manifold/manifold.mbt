///|
/// ManifoldFragment — behavioral grammar of an observed AI flow.
///
/// Distilled from a GrammarTree when the observed flow is identified
/// as AI traffic. Captures tree topology metrics and behavioral
/// signatures — HOW the AI communicates, not WHAT it says.
///
/// This is the "latent manifold grammar snippet." It's a finite
/// projection of the AI's behavioral manifold onto observable
/// structural features. Approximately computable (lossy by design).
///
/// Wire format:
///   [4]  magic          : 0x4D 0x4E 0x46 0x4C  "MNFL"
///   [4]  format_version : u32 LE (currently 1)
///   [4+n] fragment_id   : utf8
///   [4+n] source_tap    : utf8
///   [4]  observation_epoch : u32 LE
///   [4]  tree_depth     : u32 LE
///   [4]  tree_width     : u32 LE
///   [4]  node_count     : u32 LE
///   [4]  sealed_ratio   : u32 LE
///   [4]  salience_mean  : i32 LE
///   [4]  salience_spread : i32 LE
///   [32] heat_profile   : 8 x u32 LE
///   [32] mass_profile   : 8 x u32 LE
///   [4]  direction_ratio : u32 LE
///   [4]  n_tokens       : u32 LE
///   per token: [4+n] utf8
///   [4]  streaming_score : u32 LE
///   [4]  regularity_score : u32 LE
///   [4]  vocab_score    : u32 LE
///   [4+n] grammar_root  : utf8
///   [4]  grammar_hash   : 4 bytes

let mnfl_magic : Array[Byte] = [b'\x4D', b'\x4E', b'\x46', b'\x4C'] // "MNFL"
let mnfl_version : Int = 1
let profile_buckets : Int = 8

///|
/// Behavioral grammar fragment distilled from a GrammarTree.
pub(all) struct ManifoldFragment {
  fragment_id        : String
  source_tap         : String
  observation_epoch  : Int

  // Tree topology metrics
  tree_depth         : Int
  tree_width         : Int        // max branching factor
  node_count         : Int
  sealed_ratio       : Int        // sealed/total * 100

  // Behavioral signature (from gaussian salience)
  salience_mean      : Int        // average mu across nodes
  salience_spread    : Int        // max sigma across nodes

  // Traffic shape
  heat_profile       : Array[Int] // histogram of node heat values (8 buckets)
  mass_profile       : Array[Int] // histogram of node mass values (8 buckets)
  direction_ratio    : Int        // c2s_frames * 100 / total (0 if unknown)
  dominant_tokens    : Array[String] // top-8 routing tokens by mass (from bloom hot bits)

  // AI-likeness heuristics
  streaming_score    : Int        // 0-100
  regularity_score   : Int        // 0-100 (low sigma = high regularity)
  vocab_score        : Int        // 0-100 (routing token diversity)

  // Grammar commitment
  grammar_root       : String     // grammar tree root hash (CAS-referenceable)
  grammar_hash       : Array[Byte] // 4-byte FNV of serialized fragment
} derive(Debug)

// ---------------------------------------------------------------------------
// Distillation from GrammarTree
// ---------------------------------------------------------------------------

///|
/// Distill a ManifoldFragment from a GrammarTree.
/// `fragment_id` and `source_tap` are provided by the caller.
/// `direction_ratio` must be provided externally (FlowTap tracks this).
pub fn ManifoldFragment::distill(
  tree : @grammar.GrammarTree,
  fragment_id : String,
  source_tap : String,
  direction_ratio : Int,
) -> ManifoldFragment {
  let mut max_depth = 0
  let mut max_width = 0
  let mut sealed_count = 0
  let mut salience_sum = 0
  let mut salience_max_sigma = 0
  let mut n_nodes = 0

  let heat_values : Array[Int] = []
  let mass_values : Array[Int] = []

  tree.nodes.each(fn(_key, node) {
    n_nodes = n_nodes + 1
    if node.children.length() > max_width {
      max_width = node.children.length()
    }
    if node.state == @grammar.Sealed {
      sealed_count = sealed_count + 1
    }
    salience_sum = salience_sum + node.salience.mu
    if node.salience.sigma > salience_max_sigma {
      salience_max_sigma = node.salience.sigma
    }
    heat_values.push(node.heat)
    mass_values.push(node.mass)
  })

  // Compute depth via BFS from root
  match tree.active_root_key() {
    Some(root_key) => {
      max_depth = mnfl_compute_depth(tree, root_key)
    }
    None => ()
  }

  let sealed_ratio = if n_nodes > 0 { sealed_count * 100 / n_nodes } else { 0 }
  let salience_mean = if n_nodes > 0 { salience_sum / n_nodes } else { 0 }

  let heat_profile = mnfl_histogram(heat_values, profile_buckets)
  let mass_profile = mnfl_histogram(mass_values, profile_buckets)

  // Regularity score: low sigma = high regularity
  // sigma of 0 → 100, sigma of 5000+ → 0
  let regularity_score = if salience_max_sigma <= 0 {
    100
  } else if salience_max_sigma >= 5000 {
    0
  } else {
    100 - salience_max_sigma * 100 / 5000
  }

  // Vocab score: more distinct bloom bits = higher diversity
  let total_popcount = mnfl_total_popcount(tree)
  let max_possible = @grammar.gram_bloom_size * n_nodes
  let vocab_score = if max_possible > 0 {
    mnfl_int_min(total_popcount * 100 / max_possible, 100)
  } else {
    0
  }

  // Streaming score: based on direction_ratio.
  // Pure request-response (50/50) → 0. Heavily one-directional → high.
  let streaming_score = if direction_ratio <= 0 {
    0
  } else {
    let deviation = if direction_ratio > 50 {
      direction_ratio - 50
    } else {
      50 - direction_ratio
    }
    mnfl_int_min(deviation * 2, 100)
  }

  // Grammar root
  let grammar_root = match tree.active_root_key() {
    Some(key) => key
    None => ""
  }

  // Dominant tokens placeholder — extract from bloom hot bits
  // In practice we'd scan bloom positions, but for now use empty
  let dominant_tokens : Array[String] = []

  // Build fragment (without hash first, then compute hash)
  let fragment : ManifoldFragment = {
    fragment_id,
    source_tap,
    observation_epoch: tree.current_epoch(),
    tree_depth: max_depth,
    tree_width: max_width,
    node_count: n_nodes,
    sealed_ratio,
    salience_mean,
    salience_spread: salience_max_sigma,
    heat_profile,
    mass_profile,
    direction_ratio,
    dominant_tokens,
    streaming_score,
    regularity_score,
    vocab_score,
    grammar_root,
    grammar_hash: [],
  }

  // Compute grammar_hash from serialized fragment
  let bytes = fragment.to_bytes()
  let hash = mnfl_fnv_hash(bytes)
  { ..fragment, grammar_hash: hash }
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

///|
pub fn ManifoldFragment::to_bytes(self : ManifoldFragment) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in mnfl_magic { buf.push(b) }
  mnfl_write_u32(buf, mnfl_version)
  mnfl_write_str(buf, self.fragment_id)
  mnfl_write_str(buf, self.source_tap)
  mnfl_write_u32(buf, self.observation_epoch)
  mnfl_write_u32(buf, self.tree_depth)
  mnfl_write_u32(buf, self.tree_width)
  mnfl_write_u32(buf, self.node_count)
  mnfl_write_u32(buf, self.sealed_ratio)
  mnfl_write_i32(buf, self.salience_mean)
  mnfl_write_i32(buf, self.salience_spread)
  for v in self.heat_profile { mnfl_write_u32(buf, v) }
  // Pad to 8 buckets if needed
  let mut i = self.heat_profile.length()
  while i < profile_buckets { mnfl_write_u32(buf, 0); i = i + 1 }
  for v in self.mass_profile { mnfl_write_u32(buf, v) }
  i = self.mass_profile.length()
  while i < profile_buckets { mnfl_write_u32(buf, 0); i = i + 1 }
  mnfl_write_u32(buf, self.direction_ratio)
  mnfl_write_u32(buf, self.dominant_tokens.length())
  for token in self.dominant_tokens { mnfl_write_str(buf, token) }
  mnfl_write_u32(buf, self.streaming_score)
  mnfl_write_u32(buf, self.regularity_score)
  mnfl_write_u32(buf, self.vocab_score)
  mnfl_write_str(buf, self.grammar_root)
  // grammar_hash: always 4 bytes
  if self.grammar_hash.length() >= 4 {
    for j = 0; j < 4; j = j + 1 { buf.push(self.grammar_hash[j]) }
  } else {
    for _j = 0; _j < 4; _j = _j + 1 { buf.push(b'\x00') }
  }
  buf
}

///|
pub fn ManifoldFragment::from_bytes(data : Array[Byte]) -> ManifoldFragment? {
  let len = data.length()
  if len < 8 { return None }
  if data[0] != mnfl_magic[0] || data[1] != mnfl_magic[1] ||
     data[2] != mnfl_magic[2] || data[3] != mnfl_magic[3] { return None }
  let mut pos = 4
  let _ver = mnfl_read_u32(data, pos); pos = pos + 4

  let fragment_id = match mnfl_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  let source_tap = match mnfl_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  if pos + 28 > len { return None }
  let observation_epoch = mnfl_read_u32(data, pos); pos = pos + 4
  let tree_depth = mnfl_read_u32(data, pos); pos = pos + 4
  let tree_width = mnfl_read_u32(data, pos); pos = pos + 4
  let node_count = mnfl_read_u32(data, pos); pos = pos + 4
  let sealed_ratio = mnfl_read_u32(data, pos); pos = pos + 4
  let salience_mean = mnfl_read_i32(data, pos); pos = pos + 4
  let salience_spread = mnfl_read_i32(data, pos); pos = pos + 4

  // heat_profile: 8 u32s
  if pos + 32 > len { return None }
  let heat_profile : Array[Int] = []
  let mut i = 0
  while i < profile_buckets {
    heat_profile.push(mnfl_read_u32(data, pos)); pos = pos + 4
    i = i + 1
  }
  // mass_profile: 8 u32s
  if pos + 32 > len { return None }
  let mass_profile : Array[Int] = []
  i = 0
  while i < profile_buckets {
    mass_profile.push(mnfl_read_u32(data, pos)); pos = pos + 4
    i = i + 1
  }

  if pos + 4 > len { return None }
  let direction_ratio = mnfl_read_u32(data, pos); pos = pos + 4

  if pos + 4 > len { return None }
  let n_tokens = mnfl_read_u32(data, pos); pos = pos + 4
  let dominant_tokens : Array[String] = []
  i = 0
  while i < n_tokens {
    match mnfl_read_str(data, pos, len) {
      Some((s, p)) => { pos = p; dominant_tokens.push(s) }
      None => return None
    }
    i = i + 1
  }

  if pos + 12 > len { return None }
  let streaming_score = mnfl_read_u32(data, pos); pos = pos + 4
  let regularity_score = mnfl_read_u32(data, pos); pos = pos + 4
  let vocab_score = mnfl_read_u32(data, pos); pos = pos + 4

  let grammar_root = match mnfl_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }

  if pos + 4 > len { return None }
  let grammar_hash : Array[Byte] = [data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]

  Some({
    fragment_id, source_tap, observation_epoch,
    tree_depth, tree_width, node_count, sealed_ratio,
    salience_mean, salience_spread,
    heat_profile, mass_profile, direction_ratio, dominant_tokens,
    streaming_score, regularity_score, vocab_score,
    grammar_root, grammar_hash,
  })
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn mnfl_compute_depth(tree : @grammar.GrammarTree, root_key : String) -> Int {
  let mut max_d = 0
  let queue : Array[(String, Int)] = [(root_key, 0)]
  while queue.length() > 0 {
    match queue.pop() {
      Some((key, depth)) => {
        if depth > max_d { max_d = depth }
        match tree.get_node(key) {
          Some(node) =>
            for child_key in node.children {
              queue.push((child_key, depth + 1))
            }
          None => ()
        }
      }
      None => break
    }
  }
  max_d
}

///|
fn mnfl_histogram(values : Array[Int], buckets : Int) -> Array[Int] {
  let hist = Array::make(buckets, 0)
  if values.length() == 0 { return hist }
  // Find max for bucket boundaries
  let mut max_val = 0
  for v in values {
    if v > max_val { max_val = v }
  }
  if max_val == 0 {
    hist[0] = values.length()
    return hist
  }
  let bucket_size = max_val / buckets + 1
  for v in values {
    let idx = v / bucket_size
    let clamped = if idx >= buckets { buckets - 1 } else { idx }
    hist[clamped] = hist[clamped] + 1
  }
  hist
}

///|
fn mnfl_total_popcount(tree : @grammar.GrammarTree) -> Int {
  let mut total = 0
  tree.nodes.each(fn(_key, node) {
    total = total + node.routing_sketch.popcount()
  })
  total
}

///|
fn mnfl_fnv_hash(data : Array[Byte]) -> Array[Byte] {
  let mut h = 0x811C9DC5
  for b in data {
    h = h ^ (b.to_int() & 0xFF)
    h = h * 0x01000193
  }
  [
    (h & 0xFF).to_byte(),
    ((h >> 8) & 0xFF).to_byte(),
    ((h >> 16) & 0xFF).to_byte(),
    ((h >> 24) & 0xFF).to_byte(),
  ]
}

///|
fn mnfl_int_min(a : Int, b : Int) -> Int {
  if a <= b { a } else { b }
}

///|
fn mnfl_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn mnfl_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn mnfl_write_i32(buf : Array[Byte], v : Int) -> Unit {
  mnfl_write_u32(buf, v)
}

///|
fn mnfl_read_i32(data : Array[Byte], pos : Int) -> Int {
  mnfl_read_u32(data, pos)
}

///|
fn mnfl_write_str(buf : Array[Byte], s : String) -> Unit {
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
  mnfl_write_u32(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

///|
fn mnfl_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = mnfl_read_u32(data, pos)
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
