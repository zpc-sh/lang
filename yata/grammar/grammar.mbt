///|
/// GrammarTree — protocol grammar accumulator as a merkin-shaped tree.
///
/// Mirrors the structure of zpc/merkin's MerkinTree/MerkinNode but is
/// self-contained in the lang layer. Each node carries:
///   - A bloom sketch for probabilistic routing (which tokens pass through)
///   - A gaussian salience pair (timing confidence in integer arithmetic)
///   - Mass (observation count) and heat (activity counter)
///
/// The tree accumulates protocol grammar by ingesting routing tokens
/// extracted from observed frames. The tree shape IS the grammar:
///   - Bloom filters say which message types appear at each tree position
///   - Gaussian salience tracks timing confidence per grammar path
///   - Sparse projections give filtered views of the grammar
///   - Tree diff detects grammar evolution between epochs
///
/// Wire format (for .gram section / envelope integration):
///   [4]  magic          : 0x47 0x52 0x41 0x4D  "GRAM"
///   [4]  format_version : u32 LE (currently 1)
///   [4]  epoch          : u32 LE
///   [4]  total_tokens   : u32 LE
///   [1]  has_hot_root   : u8
///   (if has_hot_root):
///     [4+n] hot_root    : utf8
///   [4]  n_nodes        : u32 LE
///   per node:
///     [4+n] node_id     : utf8
///     [4]   n_children  : u32 LE
///     per child: [4+n] child_key : utf8
///     [BLOOM_SIZE] routing_sketch bits
///     [12] salience: mu(i32) + sigma(i32) + n(i32)
///     [4]  mass          : u32 LE
///     [4]  heat          : u32 LE
///     [1]  state         : u8

let gram_magic : Array[Byte] = [b'\x47', b'\x52', b'\x41', b'\x4D'] // "GRAM"
let gram_version : Int = 1

// ---------------------------------------------------------------------------
// GaussianPair — integer-scaled gaussian salience
// ---------------------------------------------------------------------------

///|
/// Integer-scaled gaussian for timing salience. Avoids floating point.
/// Values are in milliunits (multiply by 1000).
pub(all) struct GaussianPair {
  mu    : Int    // mean * 1000
  sigma : Int    // stddev * 1000 (always >= 0)
  n     : Int    // observation count
} derive(Eq, Debug)

///|
pub fn GaussianPair::new() -> GaussianPair {
  { mu: 0, sigma: 1000, n: 0 }  // uninformative prior: mu=0, sigma=1.0
}

///|
/// Update with a new observation using Welford's algorithm in integer arithmetic.
/// `observation_milli` is the observed value * 1000.
pub fn GaussianPair::update(self : GaussianPair, observation_milli : Int) -> GaussianPair {
  let count = self.n + 1
  let delta = observation_milli - self.mu
  let new_mu = self.mu + delta / count
  let new_sigma = if count < 2 {
    self.sigma
  } else {
    // EMA estimate of sigma
    let alpha_inv = count  // 1/alpha = count
    let diff = if observation_milli > new_mu {
      observation_milli - new_mu
    } else {
      new_mu - observation_milli
    }
    // sigma = sigma * (1 - 1/count) + diff * (1/count)
    // = (sigma * (count - 1) + diff) / count
    (self.sigma * (alpha_inv - 1) + diff) / alpha_inv
  }
  { mu: new_mu, sigma: new_sigma, n: count }
}

///|
/// Scheduling decision: should expensive work be executed?
/// True if mu - k*sigma/1000 >= threshold (all in milliunits).
pub fn GaussianPair::should_execute(
  self : GaussianPair,
  k_milli : Int,
  threshold_milli : Int,
) -> Bool {
  self.mu - k_milli * self.sigma / 1000 >= threshold_milli
}

///|
/// Merge two gaussian pairs (take the one with more observations,
/// or combine if both have observations).
pub fn GaussianPair::merge(self : GaussianPair, other : GaussianPair) -> GaussianPair {
  if self.n == 0 { return other }
  if other.n == 0 { return self }
  let total = self.n + other.n
  let new_mu = (self.mu * self.n + other.mu * other.n) / total
  let new_sigma = gram_int_max(self.sigma, other.sigma)
  { mu: new_mu, sigma: new_sigma, n: total }
}

// ---------------------------------------------------------------------------
// BloomSketch — local implementation compatible with merkin's
// ---------------------------------------------------------------------------

///|
pub let gram_bloom_size : Int = 256  // bits (same as merkin default)
let gram_bloom_hashes : Int = 3

///|
/// Bloom filter for probabilistic routing token membership.
pub(all) struct GrammarBloom {
  bits       : Array[Bool]
  mut count  : Int          // insertions (not distinct)
} derive(Debug)

///|
pub fn GrammarBloom::new() -> GrammarBloom {
  { bits: Array::make(gram_bloom_size, false), count: 0 }
}

///|
/// Insert a routing token.
pub fn GrammarBloom::add(self : GrammarBloom, token : String) -> Unit {
  let positions = gram_bloom_positions(token)
  for pos in positions {
    self.bits[pos] = true
  }
  self.count = self.count + 1
}

///|
/// Probabilistic membership test.
pub fn GrammarBloom::maybe_contains(self : GrammarBloom, token : String) -> Bool {
  let positions = gram_bloom_positions(token)
  for pos in positions {
    if !self.bits[pos] { return false }
  }
  true
}

///|
/// Merge two blooms (OR of bits).
pub fn GrammarBloom::merge(self : GrammarBloom, other : GrammarBloom) -> GrammarBloom {
  let merged = Array::make(gram_bloom_size, false)
  let mut i = 0
  while i < gram_bloom_size {
    merged[i] = self.bits[i] || other.bits[i]
    i = i + 1
  }
  { bits: merged, count: self.count + other.count }
}

///|
/// Count bits set (population count).
pub fn GrammarBloom::popcount(self : GrammarBloom) -> Int {
  let mut c = 0
  for b in self.bits {
    if b { c = c + 1 }
  }
  c
}

///|
/// Overlap count between two blooms (bits both set).
pub fn GrammarBloom::overlap(self : GrammarBloom, other : GrammarBloom) -> Int {
  let mut c = 0
  let mut i = 0
  while i < gram_bloom_size {
    if self.bits[i] && other.bits[i] { c = c + 1 }
    i = i + 1
  }
  c
}

///|
fn gram_bloom_positions(token : String) -> Array[Int] {
  let positions : Array[Int] = []
  let mut k = 0
  while k < gram_bloom_hashes {
    let offset_basis = 14695981039346656037UL
    let prime = 1099511628211UL
    let mut h = offset_basis ^ k.to_uint64()
    for ch in token {
      h = h ^ ch.to_uint().to_uint64()
      h = h * prime
    }
    let pos = (h % gram_bloom_size.to_uint64()).to_int()
    positions.push(pos)
    k = k + 1
  }
  positions
}

// ---------------------------------------------------------------------------
// NodeState
// ---------------------------------------------------------------------------

///|
pub(all) enum GrammarNodeState {
  Fresh
  Dirty
  Sealed
} derive(Eq, Debug)

///|
fn GrammarNodeState::to_byte(self : GrammarNodeState) -> Byte {
  match self {
    Fresh  => b'\x00'
    Dirty  => b'\x01'
    Sealed => b'\x02'
  }
}

///|
fn GrammarNodeState::from_byte(b : Byte) -> GrammarNodeState {
  match b.to_int() {
    0 => Fresh
    1 => Dirty
    _ => Sealed
  }
}

// ---------------------------------------------------------------------------
// GrammarNode — mirrors merkin's MerkinNode
// ---------------------------------------------------------------------------

///|
/// A grammar tree node with bloom routing, gaussian salience, and mass/heat.
pub(all) struct GrammarNode {
  node_id        : String
  children       : Array[String]      // child node keys
  routing_sketch : GrammarBloom
  salience       : GaussianPair
  mass           : Int                // observation count at this node
  heat           : Int                // activity counter
  state          : GrammarNodeState
} derive(Debug)

///|
pub fn GrammarNode::leaf(node_id : String) -> GrammarNode {
  {
    node_id,
    children: [],
    routing_sketch: GrammarBloom::new(),
    salience: GaussianPair::new(),
    mass: 0,
    heat: 0,
    state: Fresh,
  }
}

///|
/// Ingest routing tokens into this node. Marks Dirty.
pub fn GrammarNode::ingest_tokens(
  self : GrammarNode,
  tokens : Array[String],
) -> GrammarNode {
  for token in tokens {
    self.routing_sketch.add(token)
  }
  { ..self, mass: self.mass + 1, heat: self.heat + 1, state: Dirty }
}

///|
/// Add a child edge. Marks Dirty.
pub fn GrammarNode::add_child(
  self : GrammarNode,
  child_key : String,
) -> GrammarNode {
  let kids = self.children.copy()
  kids.push(child_key)
  { ..self, children: kids, state: Dirty }
}

///|
/// Update salience with a timing observation (in milliunits).
pub fn GrammarNode::observe_salience(
  self : GrammarNode,
  observation_milli : Int,
) -> GrammarNode {
  { ..self, salience: self.salience.update(observation_milli) }
}

///|
/// Seal this node: merge child bloom sketches upward, mark Sealed.
pub fn GrammarNode::seal(
  self : GrammarNode,
  child_sketches : Array[GrammarBloom],
) -> GrammarNode {
  let mut merged = GrammarBloom::new()
  for sketch in child_sketches {
    merged = merged.merge(sketch)
  }
  merged = merged.merge(self.routing_sketch)
  { ..self, routing_sketch: merged, state: Sealed }
}

///|
/// Check if a token might route through this node.
pub fn GrammarNode::maybe_routes(self : GrammarNode, token : String) -> Bool {
  self.routing_sketch.maybe_contains(token)
}

// ---------------------------------------------------------------------------
// GrammarTree — mirrors merkin's MerkinTree
// ---------------------------------------------------------------------------

///|
/// Protocol grammar accumulated as a probabilistic tree.
pub(all) struct GrammarTree {
  nodes        : Map[String, GrammarNode]
  mut hot_root : String?
  mut epoch    : Int
  mut total_tokens : Int    // lifetime routing token insertions
} derive(Debug)

///|
pub fn GrammarTree::new() -> GrammarTree {
  { nodes: {}, hot_root: None, epoch: 0, total_tokens: 0 }
}

///|
fn gram_default_root_key() -> String {
  "gram:root:00000001"
}

///|
/// Ingest routing tokens into the tree. Creates root if needed.
/// Returns the root key.
pub fn GrammarTree::ingest(
  self : GrammarTree,
  tokens : Array[String],
) -> String {
  let root_key = match self.hot_root {
    Some(key) => key
    None => {
      let key = gram_default_root_key()
      self.nodes[key] = GrammarNode::leaf(key)
      self.hot_root = Some(key)
      key
    }
  }
  match self.nodes.get(root_key) {
    Some(node) => {
      let updated = node.ingest_tokens(tokens)
      self.nodes[root_key] = updated
    }
    None => ()
  }
  self.total_tokens = self.total_tokens + tokens.length()
  root_key
}

///|
/// Ingest tokens and also update salience on the root node.
pub fn GrammarTree::ingest_with_salience(
  self : GrammarTree,
  tokens : Array[String],
  timing_milli : Int,
) -> String {
  let root_key = self.ingest(tokens)
  match self.nodes.get(root_key) {
    Some(node) => {
      let updated = node.observe_salience(timing_milli)
      self.nodes[root_key] = updated
    }
    None => ()
  }
  root_key
}

///|
/// Add a child node under the root.
pub fn GrammarTree::add_child(
  self : GrammarTree,
  child_key : String,
) -> Bool {
  match self.hot_root {
    None => false
    Some(root_key) =>
      match self.nodes.get(root_key) {
        Some(root) => {
          self.nodes[root_key] = root.add_child(child_key)
          if self.nodes.get(child_key) is None {
            self.nodes[child_key] = GrammarNode::leaf(child_key)
          }
          true
        }
        None => false
      }
  }
}

///|
/// Seal the current epoch: freeze all nodes, merge child bloom sketches
/// upward, increment epoch. Returns sealed root key.
pub fn GrammarTree::seal(self : GrammarTree) -> String? {
  match self.hot_root {
    None => None
    Some(root_key) =>
      match self.nodes.get(root_key) {
        Some(root_node) => {
          let child_sketches : Array[GrammarBloom] = []
          for child_key in root_node.children {
            match self.nodes.get(child_key) {
              Some(child_node) => child_sketches.push(child_node.routing_sketch)
              None => ()
            }
          }
          let sealed_node = root_node.seal(child_sketches)
          self.nodes[root_key] = sealed_node
          self.epoch = self.epoch + 1
          self.hot_root = None
          Some(root_key)
        }
        None => None
      }
  }
}

///|
/// Get a node by key.
pub fn GrammarTree::get_node(self : GrammarTree, key : String) -> GrammarNode? {
  self.nodes.get(key)
}

///|
/// Number of nodes in the tree.
pub fn GrammarTree::node_count(self : GrammarTree) -> Int {
  self.nodes.length()
}

///|
/// Current epoch.
pub fn GrammarTree::current_epoch(self : GrammarTree) -> Int {
  self.epoch
}

///|
/// Total mass across all nodes.
pub fn GrammarTree::total_mass(self : GrammarTree) -> Int {
  let mut total = 0
  self.nodes.each(fn(_k, v) { total = total + v.mass })
  total
}

///|
/// Total heat across all nodes.
pub fn GrammarTree::total_heat(self : GrammarTree) -> Int {
  let mut total = 0
  self.nodes.each(fn(_k, v) { total = total + v.heat })
  total
}

///|
/// Active root key (hot root or default).
pub fn GrammarTree::active_root_key(self : GrammarTree) -> String? {
  match self.hot_root {
    Some(key) => Some(key)
    None => {
      let key = gram_default_root_key()
      if self.nodes.get(key) is None { None } else { Some(key) }
    }
  }
}

// ---------------------------------------------------------------------------
// Sparse projection
// ---------------------------------------------------------------------------

///|
/// A filtered projection of the grammar tree.
pub(all) struct SparseGrammar {
  root_key : String?
  nodes    : Map[String, GrammarNode]
} derive(Debug)

///|
pub fn SparseGrammar::node_count(self : SparseGrammar) -> Int {
  self.nodes.length()
}

///|
pub fn SparseGrammar::has_node(self : SparseGrammar, key : String) -> Bool {
  self.nodes.get(key) is Some(_)
}

///|
/// Build a sparse projection by token filter. Include ancestor chain to root.
pub fn GrammarTree::sparse(
  self : GrammarTree,
  tokens : Array[String],
) -> SparseGrammar {
  let include_all = tokens.length() == 0
  let included : Map[String, Bool] = {}

  // Find matching nodes
  self.nodes.each(fn(key, node) {
    if include_all || gram_node_matches(node, tokens) {
      included[key] = true
    }
  })

  // Always include root
  let root_key = self.active_root_key()
  match root_key {
    Some(key) => included[key] = true
    None => ()
  }

  // Build child→parents map
  let parent_map : Map[String, Array[String]] = {}
  self.nodes.each(fn(parent_key, parent) {
    for child_key in parent.children {
      match parent_map.get(child_key) {
        Some(parents) => parents.push(parent_key)
        None => parent_map[child_key] = [parent_key]
      }
    }
  })

  // BFS lift matched nodes to root
  let queue : Array[String] = []
  included.each(fn(key, _) { queue.push(key) })
  while queue.length() > 0 {
    match queue.pop() {
      Some(child_key) =>
        match parent_map.get(child_key) {
          Some(parents) =>
            for parent_key in parents {
              if included.get(parent_key) is None {
                included[parent_key] = true
                queue.push(parent_key)
              }
            }
          None => ()
        }
      None => break
    }
  }

  // Collect
  let result_nodes : Map[String, GrammarNode] = {}
  included.each(fn(key, _) {
    match self.nodes.get(key) {
      Some(node) => result_nodes[key] = node
      None => ()
    }
  })

  { root_key, nodes: result_nodes }
}

///|
fn gram_node_matches(node : GrammarNode, tokens : Array[String]) -> Bool {
  for token in tokens {
    if !node.maybe_routes(token) { return false }
  }
  true
}

// ---------------------------------------------------------------------------
// Tree diff
// ---------------------------------------------------------------------------

///|
/// Diff between two grammar trees.
pub(all) struct GrammarDiff {
  added     : Array[String]
  removed   : Array[String]
  changed   : Array[String]
  unchanged : Int
} derive(Debug)

///|
pub fn GrammarDiff::is_empty(self : GrammarDiff) -> Bool {
  self.added.length() == 0 &&
  self.removed.length() == 0 &&
  self.changed.length() == 0
}

///|
/// Diff two grammar trees.
pub fn GrammarTree::diff(self : GrammarTree, other : GrammarTree) -> GrammarDiff {
  gram_diff_maps(self.nodes, other.nodes)
}

///|
fn gram_diff_maps(
  lhs : Map[String, GrammarNode],
  rhs : Map[String, GrammarNode],
) -> GrammarDiff {
  let added : Array[String] = []
  let removed : Array[String] = []
  let changed : Array[String] = []
  let mut unchanged = 0

  // Check all keys in lhs
  lhs.each(fn(key, left) {
    match rhs.get(key) {
      Some(right) =>
        if gram_node_sig(left) == gram_node_sig(right) {
          unchanged = unchanged + 1
        } else {
          changed.push(key)
        }
      None => removed.push(key)
    }
  })

  // Check keys only in rhs
  rhs.each(fn(key, _right) {
    if lhs.get(key) is None {
      added.push(key)
    }
  })

  { added, removed, changed, unchanged }
}

///|
fn gram_node_sig(node : GrammarNode) -> String {
  let sb = StringBuilder::new()
  sb.write_string(node.node_id)
  sb.write_string("|")
  sb.write_string(match node.state {
    Fresh  => "fresh"
    Dirty  => "dirty"
    Sealed => "sealed"
  })
  sb.write_string("|")
  sb.write_string(node.mass.to_string())
  sb.write_string("|")
  sb.write_string(node.heat.to_string())
  sb.write_string("|")
  let mut first = true
  for child in node.children {
    if !first { sb.write_string(",") }
    sb.write_string(child)
    first = false
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Tree merge
// ---------------------------------------------------------------------------

///|
/// Merge two grammar trees. Combines nodes by key:
///   - Bloom sketches are OR-merged
///   - Gaussian salience is combined
///   - Mass/heat take max
///   - Children are unioned
/// `self` epoch and hot_root take precedence.
pub fn GrammarTree::merge(self : GrammarTree, other : GrammarTree) -> GrammarTree {
  let merged_nodes : Map[String, GrammarNode] = {}

  // Copy all from self
  self.nodes.each(fn(key, node) { merged_nodes[key] = node })

  // Merge from other
  other.nodes.each(fn(key, other_node) {
    match merged_nodes.get(key) {
      Some(existing) => {
        // Merge bloom sketches
        let merged_bloom = existing.routing_sketch.merge(other_node.routing_sketch)
        // Merge salience
        let merged_salience = existing.salience.merge(other_node.salience)
        // Union children
        let merged_children = existing.children.copy()
        for child in other_node.children {
          let mut found = false
          for existing_child in merged_children {
            if existing_child == child { found = true; break }
          }
          if !found { merged_children.push(child) }
        }
        merged_nodes[key] = {
          ..existing,
          routing_sketch: merged_bloom,
          salience: merged_salience,
          mass: gram_int_max(existing.mass, other_node.mass),
          heat: gram_int_max(existing.heat, other_node.heat),
          children: merged_children,
        }
      }
      None => merged_nodes[key] = other_node
    }
  })

  {
    nodes: merged_nodes,
    hot_root: self.hot_root,
    epoch: gram_int_max(self.epoch, other.epoch),
    total_tokens: self.total_tokens + other.total_tokens,
  }
}

// ---------------------------------------------------------------------------
// Grammar similarity (bloom overlap based)
// ---------------------------------------------------------------------------

///|
/// Compute similarity score between two trees (0-100).
/// Based on bloom filter overlap of all nodes.
pub fn GrammarTree::similarity(self : GrammarTree, other : GrammarTree) -> Int {
  // Build aggregate bloom for each tree
  let self_bloom = gram_aggregate_bloom(self)
  let other_bloom = gram_aggregate_bloom(other)

  let overlap = self_bloom.overlap(other_bloom)
  let union_count = self_bloom.popcount() + other_bloom.popcount() - overlap
  if union_count == 0 { return 100 }  // both empty
  overlap * 100 / union_count
}

///|
fn gram_aggregate_bloom(tree : GrammarTree) -> GrammarBloom {
  let agg = GrammarBloom::new()
  tree.nodes.each(fn(_key, node) {
    let mut i = 0
    while i < gram_bloom_size {
      if node.routing_sketch.bits[i] { agg.bits[i] = true }
      i = i + 1
    }
  })
  agg
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

///|
pub fn GrammarTree::to_bytes(self : GrammarTree) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in gram_magic { buf.push(b) }
  gram_write_u32(buf, gram_version)
  gram_write_u32(buf, self.epoch)
  gram_write_u32(buf, self.total_tokens)

  // hot_root
  match self.hot_root {
    Some(key) => { buf.push(b'\x01'); gram_write_str(buf, key) }
    None => buf.push(b'\x00')
  }

  // nodes
  let node_keys : Array[String] = []
  self.nodes.each(fn(key, _) { node_keys.push(key) })
  gram_write_u32(buf, node_keys.length())

  for key in node_keys {
    match self.nodes.get(key) {
      Some(node) => gram_write_node(buf, node)
      None => ()
    }
  }
  buf
}

///|
pub fn GrammarTree::from_bytes(data : Array[Byte]) -> GrammarTree? {
  let len = data.length()
  if len < 8 { return None }
  if data[0] != gram_magic[0] || data[1] != gram_magic[1] ||
     data[2] != gram_magic[2] || data[3] != gram_magic[3] { return None }
  let mut pos = 4
  let _ver = gram_read_u32(data, pos); pos = pos + 4
  if pos + 8 > len { return None }
  let epoch = gram_read_u32(data, pos); pos = pos + 4
  let total_tokens = gram_read_u32(data, pos); pos = pos + 4

  // hot_root
  if pos >= len { return None }
  let hot_root : String? = if data[pos] == b'\x01' {
    pos = pos + 1
    match gram_read_str(data, pos, len) {
      Some((s, p)) => { pos = p; Some(s) }
      None => return None
    }
  } else {
    pos = pos + 1
    None
  }

  // nodes
  if pos + 4 > len { return None }
  let n_nodes = gram_read_u32(data, pos); pos = pos + 4
  let nodes : Map[String, GrammarNode] = {}
  let mut i = 0
  while i < n_nodes {
    match gram_read_node(data, pos, len) {
      Some((node, p)) => {
        pos = p
        nodes[node.node_id] = node
      }
      None => return None
    }
    i = i + 1
  }

  Some({ nodes, hot_root, epoch, total_tokens })
}

// ---------------------------------------------------------------------------
// Private serialization helpers
// ---------------------------------------------------------------------------

///|
fn gram_write_node(buf : Array[Byte], node : GrammarNode) -> Unit {
  gram_write_str(buf, node.node_id)
  // children
  gram_write_u32(buf, node.children.length())
  for child in node.children {
    gram_write_str(buf, child)
  }
  // bloom bits (as packed bytes — 256 bits = 32 bytes)
  let bloom_bytes = gram_bloom_size / 8
  let mut i = 0
  while i < bloom_bytes {
    let mut byte_val = 0
    let mut bit = 0
    while bit < 8 {
      let idx = i * 8 + bit
      if idx < gram_bloom_size && node.routing_sketch.bits[idx] {
        byte_val = byte_val | (1 << bit)
      }
      bit = bit + 1
    }
    buf.push(byte_val.to_byte())
    i = i + 1
  }
  // salience
  gram_write_i32(buf, node.salience.mu)
  gram_write_i32(buf, node.salience.sigma)
  gram_write_i32(buf, node.salience.n)
  // mass, heat, state
  gram_write_u32(buf, node.mass)
  gram_write_u32(buf, node.heat)
  buf.push(node.state.to_byte())
}

///|
fn gram_read_node(data : Array[Byte], pos : Int, len : Int) -> (GrammarNode, Int)? {
  let mut p = pos
  let node_id = match gram_read_str(data, p, len) {
    Some((s, p2)) => { p = p2; s }
    None => return None
  }
  // children
  if p + 4 > len { return None }
  let n_children = gram_read_u32(data, p); p = p + 4
  let children : Array[String] = []
  let mut i = 0
  while i < n_children {
    match gram_read_str(data, p, len) {
      Some((s, p2)) => { p = p2; children.push(s) }
      None => return None
    }
    i = i + 1
  }
  // bloom bits
  let bloom_bytes = gram_bloom_size / 8
  if p + bloom_bytes > len { return None }
  let bits = Array::make(gram_bloom_size, false)
  i = 0
  while i < bloom_bytes {
    let byte_val = data[p + i].to_int()
    let mut bit = 0
    while bit < 8 {
      let idx = i * 8 + bit
      if idx < gram_bloom_size && (byte_val & (1 << bit)) != 0 {
        bits[idx] = true
      }
      bit = bit + 1
    }
    i = i + 1
  }
  p = p + bloom_bytes
  let routing_sketch : GrammarBloom = { bits, count: 0 }
  // salience
  if p + 12 > len { return None }
  let mu = gram_read_i32(data, p); p = p + 4
  let sigma = gram_read_i32(data, p); p = p + 4
  let n = gram_read_i32(data, p); p = p + 4
  let salience : GaussianPair = { mu, sigma, n }
  // mass, heat, state
  if p + 9 > len { return None }
  let mass = gram_read_u32(data, p); p = p + 4
  let heat = gram_read_u32(data, p); p = p + 4
  let state = GrammarNodeState::from_byte(data[p]); p = p + 1

  Some(({ node_id, children, routing_sketch, salience, mass, heat, state }, p))
}

///|
fn gram_int_max(a : Int, b : Int) -> Int {
  if a >= b { a } else { b }
}

///|
fn gram_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn gram_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn gram_write_i32(buf : Array[Byte], v : Int) -> Unit {
  gram_write_u32(buf, v)
}

///|
fn gram_read_i32(data : Array[Byte], pos : Int) -> Int {
  gram_read_u32(data, pos)
}

///|
fn gram_write_str(buf : Array[Byte], s : String) -> Unit {
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
  gram_write_u32(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

///|
fn gram_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = gram_read_u32(data, pos)
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
