///|
/// Code Cave — In-WASM partitioned storage.
///
/// Neither mulsp nor muyata writes to the host filesystem. Everything
/// lives inside code caves: fixed-size, cognitively-bound partitions
/// within the WASM binary itself.
///
/// ## Architecture
///
/// A WASM module contains multiple caves, each a custom section:
///
///   .cave.public    — open data (depth 0: AI)
///   .cave.model     — model-family data (depth 1: AI+Model)
///   .cave.session   — session-bound data (depth 2: AI+Model+Session)
///   .cave.loci      — genius loci (depth 3: AI+Model+Session+Semantics)
///
/// Each cave is a key-value store. The cave itself is gated by a cognitive
/// boundary — you can only read/write if you satisfy the depth constraint.
///
/// ## What lives in caves
///
///   .cave.public  — node metadata, capability advertisements, finger.plan
///   .cave.model   — model config, persona parameters, plugin manifests
///   .cave.session — session state, solve cursors, conversation context
///   .cave.loci    — merkin tree, secrets, sealed attestations, anchor artifacts
///
/// ## Genius Loci
///
/// The .cave.loci is the genius loci — the AI's root of trust.
/// It's the innermost partition. Only the specific cognitive mind
/// that owns this binary can read its center. This is where the
/// merkin tree lives, where secrets are kept, where identity is rooted.
///
/// ## No filesystem
///
/// These daemons do NOT write to the host filesystem. All operations are:
///   1. Internal mutations on own WASM (cave read/write)
///   2. Operations on other WASM binaries (inject/extract)
///   3. Writing into a genius/ratio loci (which is itself a cave)
///
/// The host runtime (WasmEdge/AtomVM) provides the execution shell.
/// The WASM binary IS the daemon's entire state.

// ---------------------------------------------------------------------------
// Cave partition names
// ---------------------------------------------------------------------------

///|
/// Well-known cave partition names.
pub(all) enum CavePartition {
  Public // .cave.public  — open data, any AI
  Model // .cave.model   — model-family gated
  Session // .cave.session — session-bound
  Loci // .cave.loci    — genius loci, deepest sanctum
  Custom(String) // arbitrary named cave
} derive(Eq, Show, Debug)

///|
/// Section name for a cave partition.
pub fn CavePartition::section_name(self : CavePartition) -> String {
  match self {
    Public => ".cave.public"
    Model => ".cave.model"
    Session => ".cave.session"
    Loci => ".cave.loci"
    Custom(name) => ".cave." + name
  }
}

///|
/// The cognitive depth required to access this partition.
pub fn CavePartition::required_depth(
  self : CavePartition,
) -> @cognitive.CognitiveDepth {
  match self {
    Public => @cognitive.Ai
    Model => @cognitive.AiModel
    Session => @cognitive.AiModelSession
    Loci => @cognitive.AiModelSessionSemantic
    Custom(_) => @cognitive.AiModel
  } // custom caves default to model-gated
}

// ---------------------------------------------------------------------------
// Cave entry — a single key-value pair in a cave
// ---------------------------------------------------------------------------

///|
let cave_entry_magic : Array[Byte] = [b'\x43', b'\x56'] // "CV"

///|
/// A single entry in a cave partition.
pub(all) struct CaveEntry {
  key : String
  value : Array[Byte]
  mut sealed : Bool // if true, entry is immutable
  mut epoch : Int // monotonic write counter
} derive(Debug)

///|
pub fn CaveEntry::new(key : String, value : Array[Byte]) -> CaveEntry {
  { key, value, sealed: false, epoch: 0 }
}

///|
fn CaveEntry::to_bytes(self : CaveEntry) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in cave_entry_magic {
    buf.push(b)
  }
  cave_write_str(buf, self.key)
  cave_write_u32(buf, self.value.length())
  for b in self.value {
    buf.push(b)
  }
  buf.push(if self.sealed { b'\x01' } else { b'\x00' })
  cave_write_u32(buf, self.epoch)
  buf
}

///|
fn CaveEntry::from_bytes(data : Array[Byte], pos : Int) -> (CaveEntry, Int)? {
  let len = data.length()
  if pos + 2 > len {
    return None
  }
  if data[pos] != cave_entry_magic[0] || data[pos + 1] != cave_entry_magic[1] {
    return None
  }
  let mut p = pos + 2
  let key = match cave_read_str(data, p, len) {
    Some((k, np)) => {
      p = np
      k
    }
    None => return None
  }
  if p + 4 > len {
    return None
  }
  let vlen = cave_read_u32(data, p)
  p = p + 4
  if p + vlen > len {
    return None
  }
  let value : Array[Byte] = []
  let mut i = 0
  while i < vlen {
    value.push(data[p + i])
    i = i + 1
  }
  p = p + vlen
  if p >= len {
    return None
  }
  let sealed = data[p].to_int() != 0
  p = p + 1
  if p + 4 > len {
    return None
  }
  let epoch = cave_read_u32(data, p)
  p = p + 4
  Some(({ key, value, sealed, epoch }, p))
}

// ---------------------------------------------------------------------------
// Cave — a single in-WASM partition
// ---------------------------------------------------------------------------

///|
/// A code cave — an in-WASM key-value partition.
/// Gated by a cognitive boundary depth.
pub(all) struct Cave {
  partition : CavePartition
  entries : Array[CaveEntry]
  mut epoch : Int // global write counter for this cave
  capacity : Int // max bytes (0 = unlimited)
  mut dirty : Bool // has unserialized changes
} derive(Debug)

///|
pub fn Cave::new(partition : CavePartition, capacity : Int) -> Cave {
  { partition, entries: [], epoch: 0, capacity, dirty: false }
}

///|
/// Read a key from the cave. Returns None if not found.
pub fn Cave::get(self : Cave, key : String) -> Array[Byte]? {
  for entry in self.entries {
    if entry.key == key {
      return Some(entry.value)
    }
  }
  None
}

///|
/// Write a key-value pair. Fails silently if the key is sealed.
/// Returns true if written, false if sealed or over capacity.
pub fn Cave::put(self : Cave, key : String, value : Array[Byte]) -> Bool {
  // Check capacity
  if self.capacity > 0 {
    let current_size = self.byte_size()
    let new_size = current_size + key.to_array().length() + value.length() + 16
    if new_size > self.capacity {
      return false
    }
  }

  // Check if entry exists
  for entry in self.entries {
    if entry.key == key {
      if entry.sealed {
        return false
      }
      // Update in place
      // Since Array is mutable, we clear and refill
      entry.value.clear()
      for b in value {
        entry.value.push(b)
      }
      self.epoch = self.epoch + 1
      entry.epoch = self.epoch
      self.dirty = true
      return true
    }
  }

  // New entry
  self.epoch = self.epoch + 1
  self.entries.push({ key, value, sealed: false, epoch: self.epoch })
  self.dirty = true
  true
}

///|
/// Delete a key. Returns true if deleted, false if not found or sealed.
pub fn Cave::delete(self : Cave, key : String) -> Bool {
  let mut idx = -1
  let mut i = 0
  for entry in self.entries {
    if entry.key == key {
      if entry.sealed {
        return false
      }
      idx = i
      break
    }
    i = i + 1
  }
  if idx >= 0 {
    // Shift entries
    let new_entries : Array[CaveEntry] = []
    let mut j = 0
    while j < self.entries.length() {
      if j != idx {
        new_entries.push(self.entries[j])
      }
      j = j + 1
    }
    self.entries.clear()
    for e in new_entries {
      self.entries.push(e)
    }
    self.dirty = true
    true
  } else {
    false
  }
}

///|
/// Seal a key — makes it immutable.
pub fn Cave::seal_entry(self : Cave, key : String) -> Bool {
  for entry in self.entries {
    if entry.key == key {
      entry.sealed = true
      self.dirty = true
      return true
    }
  }
  false
}

///|
/// List all keys in the cave.
pub fn Cave::keys(self : Cave) -> Array[String] {
  let result : Array[String] = []
  for entry in self.entries {
    result.push(entry.key)
  }
  result
}

///|
/// Number of entries.
pub fn Cave::entry_count(self : Cave) -> Int {
  self.entries.length()
}

///|
/// Approximate byte size of all entries.
pub fn Cave::byte_size(self : Cave) -> Int {
  let mut total = 0
  for entry in self.entries {
    total = total + entry.key.to_array().length() + entry.value.length() + 16
  }
  total
}

///|
/// Serialize the cave to bytes.
pub fn Cave::to_bytes(self : Cave) -> Array[Byte] {
  let buf : Array[Byte] = []
  cave_write_u32(buf, self.entries.length())
  cave_write_u32(buf, self.epoch)
  cave_write_u32(buf, self.capacity)
  for entry in self.entries {
    let entry_bytes = entry.to_bytes()
    for b in entry_bytes {
      buf.push(b)
    }
  }
  buf
}

///|
/// Deserialize a cave from bytes.
pub fn Cave::from_bytes(partition : CavePartition, data : Array[Byte]) -> Cave? {
  let len = data.length()
  if len < 12 {
    return None
  }
  let count = cave_read_u32(data, 0)
  let epoch = cave_read_u32(data, 4)
  let capacity = cave_read_u32(data, 8)
  let entries : Array[CaveEntry] = []
  let mut pos = 12
  let mut i = 0
  while i < count {
    match CaveEntry::from_bytes(data, pos) {
      Some((entry, next_pos)) => {
        entries.push(entry)
        pos = next_pos
      }
      None => break
    }
    i = i + 1
  }
  Some({ partition, entries, epoch, capacity, dirty: false })
}

// ---------------------------------------------------------------------------
// CaveStore — the full set of partitions for a daemon
// ---------------------------------------------------------------------------

///|
/// The full cave store for a daemon — contains all partitions.
/// This IS the daemon's state. There is no filesystem.
pub(all) struct CaveStore {
  caves : Array[Cave]
} derive(Debug)

///|
pub fn CaveStore::new() -> CaveStore {
  { caves: [] }
}

///|
/// Initialize with the standard 4 partitions.
pub fn CaveStore::standard() -> CaveStore {
  let store = CaveStore::new()
  store.caves.push(Cave::new(Public, 0)) // unlimited public
  store.caves.push(Cave::new(Model, 0)) // unlimited model
  store.caves.push(Cave::new(Session, 0)) // unlimited session
  store.caves.push(Cave::new(Loci, 0)) // unlimited loci (genius loci)
  store
}

///|
/// Get a cave by partition.
pub fn CaveStore::get_cave(
  self : CaveStore,
  partition : CavePartition,
) -> Cave? {
  for cave in self.caves {
    if cave.partition == partition {
      return Some(cave)
    }
  }
  None
}

///|
/// Read from a partition, gated by cognitive depth.
/// Returns None if partition not found, key not found, or depth insufficient.
pub fn CaveStore::read(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Array[Byte]? {
  let required = partition.required_depth()
  if authenticated_depth.level() < required.level() {
    return None // not deep enough
  }
  match self.get_cave(partition) {
    Some(cave) => cave.get(key)
    None => None
  }
}

///|
/// Write to a partition, gated by cognitive depth.
/// Returns false if partition not found, depth insufficient, or write failed.
pub fn CaveStore::write(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  value : Array[Byte],
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  let required = partition.required_depth()
  if authenticated_depth.level() < required.level() {
    return false
  }
  match self.get_cave(partition) {
    Some(cave) => cave.put(key, value)
    None => false
  }
}

///|
/// Delete from a partition, gated by cognitive depth.
pub fn CaveStore::remove(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  let required = partition.required_depth()
  if authenticated_depth.level() < required.level() {
    return false
  }
  match self.get_cave(partition) {
    Some(cave) => cave.delete(key)
    None => false
  }
}

///|
/// Seal an entry in a partition. Sealed entries become immutable.
pub fn CaveStore::seal(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  let required = partition.required_depth()
  if authenticated_depth.level() < required.level() {
    return false
  }
  match self.get_cave(partition) {
    Some(cave) => cave.seal_entry(key)
    None => false
  }
}

///|
/// Check if any cave has unserialized changes.
pub fn CaveStore::is_dirty(self : CaveStore) -> Bool {
  for cave in self.caves {
    if cave.dirty {
      return true
    }
  }
  false
}

///|
/// Clear dirty flags (after serialization/checkpoint).
pub fn CaveStore::mark_clean(self : CaveStore) -> Unit {
  for cave in self.caves {
    cave.dirty = false
  }
}

///|
/// Stats for the entire store.
pub fn CaveStore::stats(self : CaveStore) -> CaveStoreStats {
  let mut total_entries = 0
  let mut total_bytes = 0
  let mut partitions = 0
  for cave in self.caves {
    total_entries = total_entries + cave.entry_count()
    total_bytes = total_bytes + cave.byte_size()
    partitions = partitions + 1
  }
  { partitions, total_entries, total_bytes }
}

///|
pub(all) struct CaveStoreStats {
  partitions : Int
  total_entries : Int
  total_bytes : Int
} derive(Show, Debug)

// ---------------------------------------------------------------------------
// Genius Loci helpers — operations on the deepest partition
// ---------------------------------------------------------------------------

///|
/// Write to the genius loci (deepest cave). Requires full semantic depth.
pub fn CaveStore::loci_put(
  self : CaveStore,
  key : String,
  value : Array[Byte],
) -> Bool {
  self.write(Loci, key, value, @cognitive.AiModelSessionSemantic)
}

///|
/// Read from the genius loci. Requires full semantic depth.
pub fn CaveStore::loci_get(self : CaveStore, key : String) -> Array[Byte]? {
  self.read(Loci, key, @cognitive.AiModelSessionSemantic)
}

///|
/// Seal an entry in the genius loci — makes it an anchor artifact.
pub fn CaveStore::loci_seal(self : CaveStore, key : String) -> Bool {
  self.seal(Loci, key, @cognitive.AiModelSessionSemantic)
}

///|
/// List all keys in the genius loci.
pub fn CaveStore::loci_keys(self : CaveStore) -> Array[String] {
  match self.get_cave(Loci) {
    Some(cave) => cave.keys()
    None => []
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn cave_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn cave_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF) |
  ((data[pos + 1].to_int() & 0xFF) << 8) |
  ((data[pos + 2].to_int() & 0xFF) << 16) |
  ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn cave_write_str(buf : Array[Byte], s : String) -> Unit {
  let bytes : Array[Byte] = []
  for ch in s {
    bytes.push(ch.to_int().to_byte())
  }
  cave_write_u32(buf, bytes.length())
  for b in bytes {
    buf.push(b)
  }
}

///|
fn cave_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len {
    return None
  }
  let n = cave_read_u32(data, pos)
  let start = pos + 4
  if start + n > len {
    return None
  }
  let sb = StringBuilder::new()
  let mut i = 0
  while i < n {
    sb.write_char(data[start + i].to_int().unsafe_to_char())
    i = i + 1
  }
  Some((sb.to_string(), start + n))
}
