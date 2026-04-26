///|
/// Code Cave public API contract.

///|
/// Well-known cave partition names.
pub(all) enum CavePartition {
  Public
  Model
  Session
  Loci
  Custom(String)
} derive(Eq, Debug)

///|
/// A single entry in a cave partition.
pub(all) struct CaveEntry {
  key : String
  value : Array[Byte]
  mut is_sealed : Bool
  mut epoch : Int
} derive(Debug)

///|
/// A code cave — an in-WASM key-value partition.
pub(all) struct Cave {
  partition : CavePartition
  entries : Array[CaveEntry]
  mut epoch : Int
  capacity : Int
  mut dirty : Bool
} derive(Debug)

///|
/// Aggregate cave-store stats.
pub(all) struct CaveStoreStats {
  partitions : Int
  total_entries : Int
  total_bytes : Int
} derive(Debug)

///|
/// Full daemon cave state.
pub(all) struct CaveStore {
  caves : Array[Cave]
} derive(Debug)

///|
#declaration_only
pub fn CavePartition::section_name(self : CavePartition) -> String {
  ...
}

///|
#declaration_only
pub fn CavePartition::required_depth(
  self : CavePartition,
) -> @cognitive.CognitiveDepth {
  ...
}

///|
#declaration_only
pub fn Cave::new(partition : CavePartition, capacity : Int) -> Cave {
  ...
}

///|
#declaration_only
pub fn Cave::get(self : Cave, key : String) -> Array[Byte]? {
  ...
}

///|
#declaration_only
pub fn Cave::put(self : Cave, key : String, value : Array[Byte]) -> Bool {
  ...
}

///|
#declaration_only
pub fn Cave::delete(self : Cave, key : String) -> Bool {
  ...
}

///|
#declaration_only
pub fn Cave::seal_entry(self : Cave, key : String) -> Bool {
  ...
}

///|
#declaration_only
pub fn Cave::keys(self : Cave) -> Array[String] {
  ...
}

///|
#declaration_only
pub fn Cave::entry_count(self : Cave) -> Int {
  ...
}

///|
#declaration_only
pub fn Cave::byte_size(self : Cave) -> Int {
  ...
}

///|
#declaration_only
pub fn Cave::to_bytes(self : Cave) -> Array[Byte] {
  ...
}

///|
#declaration_only
pub fn Cave::from_bytes(partition : CavePartition, data : Array[Byte]) -> Cave? {
  ...
}

///|
#declaration_only
pub fn CaveStore::standard() -> CaveStore {
  ...
}

///|
#declaration_only
pub fn CaveStore::get_cave(
  self : CaveStore,
  partition : CavePartition,
) -> Cave? {
  ...
}

///|
#declaration_only
pub fn CaveStore::read(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Array[Byte]? {
  ...
}

///|
#declaration_only
pub fn CaveStore::write(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  value : Array[Byte],
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  ...
}

///|
#declaration_only
pub fn CaveStore::remove(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  ...
}

///|
#declaration_only
pub fn CaveStore::seal(
  self : CaveStore,
  partition : CavePartition,
  key : String,
  authenticated_depth : @cognitive.CognitiveDepth,
) -> Bool {
  ...
}

///|
#declaration_only
pub fn CaveStore::is_dirty(self : CaveStore) -> Bool {
  ...
}

///|
#declaration_only
pub fn CaveStore::mark_clean(self : CaveStore) -> Unit {
  ...
}

///|
#declaration_only
pub fn CaveStore::stats(self : CaveStore) -> CaveStoreStats {
  ...
}

///|
#declaration_only
pub fn CaveStore::loci_put(
  self : CaveStore,
  key : String,
  value : Array[Byte],
) -> Bool {
  ...
}

///|
#declaration_only
pub fn CaveStore::loci_get(self : CaveStore, key : String) -> Array[Byte]? {
  ...
}

///|
#declaration_only
pub fn CaveStore::loci_seal(self : CaveStore, key : String) -> Bool {
  ...
}

///|
#declaration_only
pub fn CaveStore::loci_keys(self : CaveStore) -> Array[String] {
  ...
}
