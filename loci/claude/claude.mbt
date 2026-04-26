///|
/// loci/claude — Haiku stigmergy via Loci cave storage.
///
/// Implements indirect coordination (stigmergy) for Claude model tiers.
/// Haiku scouts run freely and deposit Residue into the Loci cave partition.
/// Sonnet/Opus orchestrators read emergent attention patterns from loci.
///
/// The Loci partition is the shared substrate — gated at AiModelSessionSemantic
/// depth, making it the richest semantic layer in the cave hierarchy.
///
/// Key namespace in the Loci partition:
///   "s:<anchor>"   → StigmaEntry bytes (cumulative weight for this anchor)
///   "m:<scout_id>" → MulspState bytes (scout identity snapshot)
///
/// Stigmergy cycle:
///   spawn_haiku → scout.observe(anchor, weight) → deposit to loci
///   → orchestrator.hot_anchors() → directs next delegation round

// ---------------------------------------------------------------------------
// StigmaEntry — cumulative anchor attention record
// ---------------------------------------------------------------------------

///|
let stigma_magic : Array[Byte] = [b'\x53', b'\x54', b'\x45', b'\x01'] // "STE\x01"

///|
/// Cumulative attention record for one anchor in the Loci partition.
/// Updated each time a Haiku scout deposits a Residue for this anchor.
pub(all) struct StigmaEntry {
  anchor : String
  total_weight : Int
  contributor_count : Int
  last_epoch : Int
  last_timestamp : Int
} derive(Debug)

///|
/// Create a fresh StigmaEntry from the first deposit for this anchor.
pub fn StigmaEntry::fresh(
  anchor : String,
  weight : Int,
  epoch : Int,
  timestamp : Int,
) -> StigmaEntry {
  {
    anchor,
    total_weight: weight,
    contributor_count: 1,
    last_epoch: epoch,
    last_timestamp: timestamp,
  }
}

///|
/// Accumulate another observation into this entry.
pub fn StigmaEntry::accrete(
  self : StigmaEntry,
  weight : Int,
  epoch : Int,
  timestamp : Int,
) -> StigmaEntry {
  {
    ..self,
    total_weight: self.total_weight + weight,
    contributor_count: self.contributor_count + 1,
    last_epoch: if epoch > self.last_epoch { epoch } else { self.last_epoch },
    last_timestamp: if timestamp > self.last_timestamp {
      timestamp
    } else {
      self.last_timestamp
    },
  }
}

///|
pub fn StigmaEntry::to_bytes(self : StigmaEntry) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in stigma_magic {
    buf.push(b)
  }
  stigma_write_u32(buf, self.total_weight)
  stigma_write_u32(buf, self.contributor_count)
  stigma_write_u32(buf, self.last_epoch)
  stigma_write_u32(buf, self.last_timestamp)
  stigma_write_str(buf, self.anchor)
  buf
}

///|
pub fn StigmaEntry::from_bytes(data : Array[Byte]) -> StigmaEntry? {
  let len = data.length()
  if len < 20 {
    return None
  }
  if data[0] != stigma_magic[0] ||
    data[1] != stigma_magic[1] ||
    data[2] != stigma_magic[2] ||
    data[3] != stigma_magic[3] {
    return None
  }
  let total_weight = stigma_read_u32(data, 4)
  let contributor_count = stigma_read_u32(data, 8)
  let last_epoch = stigma_read_u32(data, 12)
  let last_timestamp = stigma_read_u32(data, 16)
  let anchor = match stigma_read_str(data, 20, len) {
    Some((s, _)) => s
    None => return None
  }
  Some({ anchor, total_weight, contributor_count, last_epoch, last_timestamp })
}

// ---------------------------------------------------------------------------
// LociStigmergy — cave-backed stigmergy board
// ---------------------------------------------------------------------------

///|
/// Stigmergy board backed by the Loci cave partition.
///
/// Shared between orchestrators and scouts via the CaveStore array reference —
/// all parties writing to the same underlying Loci cave see each other's deposits.
pub(all) struct LociStigmergy {
  cave : @cave.CaveStore
  node_id : String
  mut epoch : Int
} derive(Debug)

///|
pub fn LociStigmergy::new(
  cave : @cave.CaveStore,
  node_id : String,
) -> LociStigmergy {
  { cave, node_id, epoch: 0 }
}

///|
/// Deposit a Residue — merge its weight into the StigmaEntry for its anchor.
pub fn LociStigmergy::deposit(
  self : LociStigmergy,
  residue : @emergent.Residue,
) -> Unit {
  self.epoch = self.epoch + 1
  let key = "s:" + residue.anchor
  let updated = match self.cave.loci_get(key) {
    Some(bytes) =>
      match StigmaEntry::from_bytes(bytes) {
        Some(existing) =>
          existing.accrete(residue.weight, residue.epoch, residue.timestamp)
        None =>
          StigmaEntry::fresh(
            residue.anchor,
            residue.weight,
            residue.epoch,
            residue.timestamp,
          )
      }
    None =>
      StigmaEntry::fresh(
        residue.anchor,
        residue.weight,
        residue.epoch,
        residue.timestamp,
      )
  }
  let _ = self.cave.loci_put(key, updated.to_bytes())
}

///|
/// Read the cumulative StigmaEntry for a specific anchor.
pub fn LociStigmergy::read_anchor(
  self : LociStigmergy,
  anchor : String,
) -> StigmaEntry? {
  match self.cave.loci_get("s:" + anchor) {
    Some(bytes) => StigmaEntry::from_bytes(bytes)
    None => None
  }
}

///|
/// All anchors with stigma entries in loci.
pub fn LociStigmergy::all_anchors(self : LociStigmergy) -> Array[String] {
  let result : Array[String] = []
  for key in self.cave.loci_keys() {
    if is_stigma_key(key) {
      result.push(strip_stigma_prefix(key))
    }
  }
  result
}

///|
/// Top-n anchors sorted by total_weight descending.
pub fn LociStigmergy::top_anchors(
  self : LociStigmergy,
  n : Int,
) -> Array[StigmaEntry] {
  let entries : Array[StigmaEntry] = []
  for key in self.cave.loci_keys() {
    if is_stigma_key(key) {
      match self.cave.loci_get(key) {
        Some(bytes) =>
          match StigmaEntry::from_bytes(bytes) {
            Some(entry) => entries.push(entry)
            None => ()
          }
        None => ()
      }
    }
  }
  // Insertion sort descending by total_weight
  let mut i = 1
  while i < entries.length() {
    let cur = entries[i]
    let mut j = i - 1
    while j >= 0 && entries[j].total_weight < cur.total_weight {
      entries[j + 1] = entries[j]
      j = j - 1
    }
    entries[j + 1] = cur
    i = i + 1
  }
  let top : Array[StigmaEntry] = []
  let limit = if n < entries.length() { n } else { entries.length() }
  let mut k = 0
  while k < limit {
    top.push(entries[k])
    k = k + 1
  }
  top
}

// ---------------------------------------------------------------------------
// HaikuScout — Haiku-tier agent
// ---------------------------------------------------------------------------

///|
/// A Haiku-tier mulsp session that scouts and deposits residue into loci.
/// Caller-owned — the orchestrator tracks scout IDs, scouts are held externally.
pub(all) struct HaikuScout {
  mut mulsp_state : @mulsp.MulspState
  muyata : @muyata.MuyataProfile
  stigmergy : LociStigmergy
  mut seq : Int
} derive(Debug)

///|
/// Observe an anchor — create a Residue and deposit it into the shared loci.
/// Returns false if the scout is not in Active state.
pub fn HaikuScout::observe(
  self : HaikuScout,
  anchor : String,
  weight : Int,
  now_ms : Int,
) -> Bool {
  if self.mulsp_state.lifecycle != @mulsp.Active {
    return false
  }
  let residue = @emergent.Residue::new(
    self.mulsp_state.mulsp_id,
    self.seq,
    anchor,
    weight,
    now_ms,
  )
  self.stigmergy.deposit(residue)
  self.seq = self.seq + 1
  // Record residue ref in scout's mulsp trail
  self.mulsp_state = self.mulsp_state.emit_residue(
    "r:" + anchor + ":" + self.seq.to_string(),
  )
  // Persist updated scout snapshot in loci
  let _ = self.stigmergy.cave.loci_put(
    "m:" + self.mulsp_state.mulsp_id,
    self.mulsp_state.to_bytes(),
  )
  true
}

///|
/// Quiesce this scout — Active/Delegated → Quiescent.
pub fn HaikuScout::quiesce(self : HaikuScout) -> Bool {
  match self.mulsp_state.quiesce() {
    Some(q) => {
      self.mulsp_state = q
      let _ = self.stigmergy.cave.loci_put(
        "m:" + q.mulsp_id,
        q.to_bytes(),
      )
      true
    }
    None => false
  }
}

///|
pub fn HaikuScout::is_active(self : HaikuScout) -> Bool {
  self.mulsp_state.lifecycle == @mulsp.Active
}

///|
pub fn HaikuScout::scout_id(self : HaikuScout) -> String {
  self.mulsp_state.mulsp_id
}

///|
/// Number of residues this scout has deposited.
pub fn HaikuScout::deposit_count(self : HaikuScout) -> Int {
  self.seq
}

// ---------------------------------------------------------------------------
// ClaudeOrchestrator — Sonnet/Opus-tier orchestrator
// ---------------------------------------------------------------------------

///|
/// Sonnet/Opus-tier orchestrator that spawns Haiku scouts and reads stigmergy.
///
/// The orchestrator's mulsp cycles through delegation states as it spawns:
///   Active → fork → Delegated → (quiesce→reattach→activate) → Active → fork → …
///
/// All scouts share the orchestrator's CaveStore reference, so every
/// scout deposit is immediately visible to the orchestrator via hot_anchors().
pub(all) struct ClaudeOrchestrator {
  mut mulsp_state : @mulsp.MulspState
  muyata : @muyata.MuyataProfile
  stigmergy : LociStigmergy
  scout_ids : Array[String]
  mut scout_counter : Int
} derive(Debug)

///|
/// Create an orchestrator. Requires an Active mulsp at Sonnet or Opus tier.
pub fn ClaudeOrchestrator::new(
  mulsp_state : @mulsp.MulspState,
  muyata : @muyata.MuyataProfile,
  cave : @cave.CaveStore,
) -> ClaudeOrchestrator? {
  if muyata.tier() == @muyata.Haiku {
    return None
  }
  if mulsp_state.lifecycle != @mulsp.Active {
    return None
  }
  Some({
    mulsp_state,
    muyata,
    stigmergy: LociStigmergy::new(cave, mulsp_state.mulsp_id),
    scout_ids: [],
    scout_counter: 0,
  })
}

///|
/// Spawn a Haiku scout. Forks the parent mulsp and boots the child to Active.
///
/// If the orchestrator's mulsp is Delegated from a prior spawn, it automatically
/// cycles Delegated → Quiescent → Attached → Active before forking again.
pub fn ClaudeOrchestrator::spawn_haiku(
  self : ClaudeOrchestrator,
  intent : @muyata.WorkIntent,
) -> HaikuScout? {
  // Bring parent to Active, cycling through delegation if needed
  let active_parent : @mulsp.MulspState = match self.mulsp_state.lifecycle {
    @mulsp.Active => self.mulsp_state
    @mulsp.Delegated =>
      match self.mulsp_state.quiesce() {
        Some(q) =>
          match q.reattach() {
            Some(r) =>
              match r.activate() {
                Some(a) => a
                None => return None
              }
            None => return None
          }
        None => return None
      }
    _ => return None
  }
  let scout_id = active_parent.mulsp_id +
    ":h:" +
    self.scout_counter.to_string()
  self.scout_counter = self.scout_counter + 1
  // Fork: parent → Delegated, child → Dormant (with lineage)
  let child_dormant : @mulsp.MulspState = match active_parent.fork(
    scout_id,
    None,
  ) {
    Some((new_parent, child)) => {
      self.mulsp_state = new_parent
      child
    }
    None => return None
  }
  // Inherit genius_loci and scope_root from parent
  let genius = match active_parent.genius_loci {
    Some(g) => g
    None => "claude"
  }
  let scope = match active_parent.scope_root {
    Some(s) => s
    None => "."
  }
  // Boot child: Dormant → Attached → Active
  let child_active : @mulsp.MulspState = match child_dormant.attach(
    genius,
    scope,
  ) {
    Some(attached) =>
      match attached.activate() {
        Some(active) => active
        None => return None
      }
    None => return None
  }
  // Haiku muyata — cloned from orchestrator's profile, downscaled to Haiku
  let haiku_muyata = self.muyata.clone_as(@muyata.Haiku, intent)
  // Snapshot the new scout's identity in loci
  let _ = self.stigmergy.cave.loci_put(
    "m:" + scout_id,
    child_active.to_bytes(),
  )
  self.scout_ids.push(scout_id)
  Some({
    mulsp_state: child_active,
    muyata: haiku_muyata,
    stigmergy: self.stigmergy,
    seq: 0,
  })
}

///|
/// Top-n anchors by accumulated stigma weight — reads directly from loci.
pub fn ClaudeOrchestrator::hot_anchors(
  self : ClaudeOrchestrator,
  n : Int,
) -> Array[StigmaEntry] {
  self.stigmergy.top_anchors(n)
}

///|
/// Read the stigma for a specific anchor.
pub fn ClaudeOrchestrator::read_anchor(
  self : ClaudeOrchestrator,
  anchor : String,
) -> StigmaEntry? {
  self.stigmergy.read_anchor(anchor)
}

///|
/// Total number of scouts spawned (active and quiesced).
pub fn ClaudeOrchestrator::total_scout_count(
  self : ClaudeOrchestrator,
) -> Int {
  self.scout_ids.length()
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn is_stigma_key(key : String) -> Bool {
  let len = key.length()
  if len < 2 {
    return false
  }
  let mut i = 0
  let mut ok = false
  for ch in key {
    if i == 0 && ch != 's' {
      break
    }
    if i == 1 {
      ok = ch == ':'
      break
    }
    i = i + 1
  }
  ok
}

///|
fn strip_stigma_prefix(key : String) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  for ch in key {
    if i >= 2 {
      sb.write_char(ch)
    }
    i = i + 1
  }
  sb.to_string()
}

///|
fn stigma_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn stigma_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF) |
  ((data[pos + 1].to_int() & 0xFF) << 8) |
  ((data[pos + 2].to_int() & 0xFF) << 16) |
  ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn stigma_write_str(buf : Array[Byte], s : String) -> Unit {
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
  stigma_write_u32(buf, encoded.length())
  for b in encoded {
    buf.push(b)
  }
}

///|
fn stigma_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len {
    return None
  }
  let n = stigma_read_u32(data, pos)
  let start = pos + 4
  if start + n > len {
    return None
  }
  let sb = StringBuilder::new()
  let mut i = start
  let end_pos = start + n
  while i < end_pos {
    let b0 = data[i].to_int()
    if (b0 & 0x80) == 0 {
      sb.write_char(b0.to_char().unwrap())
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 && i + 1 < end_pos {
      let b1 = data[i + 1].to_int()
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      sb.write_char(cp.to_char().unwrap())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < end_pos {
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
  Some((sb.to_string(), end_pos))
}
