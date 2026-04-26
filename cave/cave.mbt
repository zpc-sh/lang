///|
/// Code Cave implementation.

///|
let cave_entry_magic : Array[Byte] = [b'\x43', b'\x56'] // "CV"

///|
fn has_required_depth(
  partition : CavePartition,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  let required = partition.required_depth()
  authenticated_depth.level() >= required.level()
}

///|
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
pub fn CavePartition::required_depth(
  self : CavePartition,
) -> @cognitive.CognitiveDepth {
  match self {
    Public => @cognitive.Ai
    Model => @cognitive.AiModel
    Session => @cognitive.AiModelSession
    Loci => @cognitive.AiModelSessionSemantic
    Custom(_) => @cognitive.AiModel
  }
}

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
  buf.push(if self.is_sealed { b'\x01' } else { b'\x00' })
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
  let value_len = cave_read_u32(data, p)
  p = p + 4
  if p + value_len > len {
    return None
  }

  let value : Array[Byte] = []
  for i in 0..<value_len {
    value.push(data[p + i])
  }
  p = p + value_len

  if p >= len {
    return None
  }
  let is_sealed = data[p].to_int() != 0
  p = p + 1

  if p + 4 > len {
    return None
  }
  let epoch = cave_read_u32(data, p)
  p = p + 4
  Some(({ key, value, is_sealed, epoch }, p))
}

///|
pub fn Cave::new(partition : CavePartition, capacity : Int) -> Cave {
  { partition, entries: [], epoch: 0, capacity, dirty: false }
}

///|
pub fn Cave::get(self : Cave, key : String) -> Array[Byte]? {
  for entry in self.entries {
    if entry.key == key {
      return Some(entry.value)
    }
  }
  None
}

///|
pub fn Cave::put(self : Cave, key : String, value : Array[Byte]) -> Bool {
  if self.capacity > 0 {
    let current_size = self.byte_size()
    let estimated_new_size = current_size + key.to_array().length() + value.length() +
      16
    if estimated_new_size > self.capacity {
      return false
    }
  }

  for entry in self.entries {
    if entry.key != key {
      continue
    }
    if entry.is_sealed {
      return false
    }
    entry.value.clear()
    for b in value {
      entry.value.push(b)
    }
    self.epoch = self.epoch + 1
    entry.epoch = self.epoch
    self.dirty = true
    return true
  }

  self.epoch = self.epoch + 1
  self.entries.push({ key, value, is_sealed: false, epoch: self.epoch })
  self.dirty = true
  true
}

///|
pub fn Cave::delete(self : Cave, key : String) -> Bool {
  let mut remove_idx = -1
  for i, entry in self.entries {
    if entry.key != key {
      continue
    }
    if entry.is_sealed {
      return false
    }
    remove_idx = i
    break
  }
  if remove_idx < 0 {
    return false
  }

  let kept : Array[CaveEntry] = []
  for i, entry in self.entries {
    if i != remove_idx {
      kept.push(entry)
    }
  }
  self.entries.clear()
  for entry in kept {
    self.entries.push(entry)
  }
  self.dirty = true
  true
}

///|
pub fn Cave::seal_entry(self : Cave, key : String) -> Bool {
  for entry in self.entries {
    if entry.key == key {
      entry.is_sealed = true
      self.dirty = true
      return true
    }
  }
  false
}

///|
pub fn Cave::keys(self : Cave) -> Array[String] {
  let result : Array[String] = []
  for entry in self.entries {
    result.push(entry.key)
  }
  result
}

///|
pub fn Cave::entry_count(self : Cave) -> Int {
  self.entries.length()
}

///|
pub fn Cave::byte_size(self : Cave) -> Int {
  let mut total = 0
  for entry in self.entries {
    total = total + entry.key.to_array().length() + entry.value.length() + 16
  }
  total
}

///|
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
  for _ in 0..<count {
    match CaveEntry::from_bytes(data, pos) {
      Some((entry, next_pos)) => {
        entries.push(entry)
        pos = next_pos
      }
      None => break
    }
  }
  Some({ partition, entries, epoch, capacity, dirty: false })
}

///|
fn cave_store_new() -> CaveStore {
  { caves: [] }
}

///|
pub fn CaveStore::standard() -> CaveStore {
  let store = cave_store_new()
  store.caves.push(Cave::new(Public, 0))
  store.caves.push(Cave::new(Model, 0))
  store.caves.push(Cave::new(Session, 0))
  store.caves.push(Cave::new(Loci, 0))
  store
}

///|
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
pub fn CaveStore::read(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Array[Byte]? {
  if !has_required_depth(partition, authenticated_depth) {
    return None
  }
  match self.get_cave(partition) {
    Some(cave) => cave.get(key)
    None => None
  }
}

///|
pub fn CaveStore::write(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  value : Array[Byte],
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  if !has_required_depth(partition, authenticated_depth) {
    return false
  }
  match self.get_cave(partition) {
    Some(cave) => cave.put(key, value)
    None => false
  }
}

///|
pub fn CaveStore::remove(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  if !has_required_depth(partition, authenticated_depth) {
    return false
  }
  match self.get_cave(partition) {
    Some(cave) => cave.delete(key)
    None => false
  }
}

///|
pub fn CaveStore::seal(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  if !has_required_depth(partition, authenticated_depth) {
    return false
  }
  match self.get_cave(partition) {
    Some(cave) => cave.seal_entry(key)
    None => false
  }
}

///|
pub fn CaveStore::is_dirty(self : CaveStore) -> Bool {
  for cave in self.caves {
    if cave.dirty {
      return true
    }
  }
  false
}

///|
pub fn CaveStore::mark_clean(self : CaveStore) -> Unit {
  for cave in self.caves {
    cave.dirty = false
  }
}

///|
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
pub fn CaveStore::loci_put(
  self : CaveStore,
  key : String,
  value : Array[Byte],
) -> Bool {
  self.write(Loci, key, value, @cognitive.AiModelSessionSemantic)
}

///|
pub fn CaveStore::loci_get(self : CaveStore, key : String) -> Array[Byte]? {
  self.read(Loci, key, @cognitive.AiModelSessionSemantic)
}

///|
pub fn CaveStore::loci_seal(self : CaveStore, key : String) -> Bool {
  self.seal(Loci, key, @cognitive.AiModelSessionSemantic)
}

///|
pub fn CaveStore::loci_keys(self : CaveStore) -> Array[String] {
  match self.get_cave(Loci) {
    Some(cave) => cave.keys()
    None => []
  }
}

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
  for i in 0..<n {
    sb.write_char(data[start + i].to_int().unsafe_to_char())
  }
  Some((sb.to_string(), start + n))
}
