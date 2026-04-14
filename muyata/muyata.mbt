///|
/// muyata — AI-Shaped Yata Profile.
///
/// Per MUYATA_SPEC: the AI-specific wrapping around Yata work units.
///
/// A MuyataProfile describes what kind of AI agent is occupying a node:
///   - Which model overlay (claude, codex, chatgpt, gemini, etc.)
///   - Which tier/mode (haiku, sonnet, opus for Anthropic; mini, o3 for OpenAI)
///   - What work intent it carries (observation, compilation, delegation, etc.)
///   - What execution surface and handler it runs on
///
/// The tier hierarchy defines the cognitive compiler chain:
///   Haiku  — gut: fast, cheap, high-volume scouting
///   Sonnet — worker: balanced, can compile and produce artifacts
///   Opus   — architect: expensive, deliberate, strategic decisions
///
/// Wire format:
///   [4]  magic          : 0x4D 0x55 0x59 0x41  "MUYA"
///   [4]  version        : u32 LE (currently 1)
///   [4]  overlay_len    : u32 LE
///   [n]  overlay        : utf8
///   [4]  family_len     : u32 LE
///   [n]  family         : utf8
///   [4]  mode_len       : u32 LE
///   [n]  mode           : utf8
///   [1]  intent         : u8
///   [4]  exec_surface_len : u32 LE
///   [n]  execution_surface : utf8
///   [4]  handler_len    : u32 LE
///   [n]  handler        : utf8
///   [1]  has_procsi     : u8
///   (if has_procsi):
///     [4+n] locus, [4+n] project, [4+n] tier
///   [1]  has_fingerprint : u8
///   (if has_fingerprint):
///     [4+n] fingerprint_commitment
///   [4]  cap_class_len  : u32 LE
///   [n]  capability_class : utf8

let muyata_magic : Array[Byte] = [b'\x4D', b'\x55', b'\x59', b'\x41'] // "MUYA"
let muyata_version : Int = 1

// ---------------------------------------------------------------------------
// Work intent
// ---------------------------------------------------------------------------

///|
/// What kind of work this AI profile intends to perform.
pub(all) enum WorkIntent {
  Observation   // passive watching, void accumulation
  Compilation   // producing artifacts, merging code
  Delegation    // spawning child agents, routing work
  Resolution    // answering questions, completing tasks
  Audit         // reviewing, checking, validating
  Translation   // format conversion, protocol bridging
} derive(Eq, Debug)

///|
impl Show for WorkIntent with output(self, logger) {
  logger.write_string(match self {
    Observation => "Observation"
    Compilation => "Compilation"
    Delegation  => "Delegation"
    Resolution  => "Resolution"
    Audit       => "Audit"
    Translation => "Translation"
  })
}

///|
fn WorkIntent::to_byte(self : WorkIntent) -> Byte {
  match self {
    Observation => b'\x00'
    Compilation => b'\x01'
    Delegation  => b'\x02'
    Resolution  => b'\x03'
    Audit       => b'\x04'
    Translation => b'\x05'
  }
}

///|
fn WorkIntent::from_byte(b : Byte) -> WorkIntent {
  match b.to_int() {
    0 => Observation
    1 => Compilation
    2 => Delegation
    3 => Resolution
    4 => Audit
    _ => Translation
  }
}

// ---------------------------------------------------------------------------
// Tier
// ---------------------------------------------------------------------------

///|
/// The cognitive tier — position in the compilation hierarchy.
pub(all) enum CognitiveTier {
  Haiku    // gut: fast, cheap, exploratory
  Sonnet   // worker: balanced, productive
  Opus     // architect: expensive, strategic
  Custom(String)  // unknown/custom tier
} derive(Eq, Debug)

///|
impl Show for CognitiveTier with output(self, logger) {
  logger.write_string(match self {
    Haiku       => "Haiku"
    Sonnet      => "Sonnet"
    Opus        => "Opus"
    Custom(s)   => s
  })
}

///|
pub fn CognitiveTier::from_string(s : String) -> CognitiveTier {
  match s {
    "haiku"  => Haiku
    "sonnet" => Sonnet
    "opus"   => Opus
    other    => Custom(other)
  }
}

///|
pub fn CognitiveTier::to_string(self : CognitiveTier) -> String {
  match self {
    Haiku     => "haiku"
    Sonnet    => "sonnet"
    Opus      => "opus"
    Custom(s) => s
  }
}

// ---------------------------------------------------------------------------
// Procsi reference (local copy — same shape as mulsp's)
// ---------------------------------------------------------------------------

///|
/// Reference to a procsi identity for muyata binding.
pub(all) struct MuyataProcsiRef {
  locus   : String
  project : String
  tier    : String
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// MuyataProfile
// ---------------------------------------------------------------------------

///|
/// The AI-shaped Yata profile — describes the cognitive agent occupying a node.
pub(all) struct MuyataProfile {
  overlay              : String      // e.g., "claude", "codex", "chatgpt", "gemini"
  family               : String      // e.g., "anthropic", "openai", "google"
  mode                 : String      // e.g., "haiku", "sonnet", "opus", "o3-mini"
  intent               : WorkIntent
  execution_surface    : String      // e.g., "wasm-gc", "atomvm", "wasmedge"
  handler              : String      // e.g., "lsp-proxy", "emergent", "plugin"
  procsi_ref           : MuyataProcsiRef?
  fingerprint_commitment : String?   // 32-byte hex commitment
  capability_class     : String      // e.g., "full", "read-only", "scoped"
} derive(Debug)

///|
/// Create a new muyata profile.
pub fn MuyataProfile::new(
  overlay : String,
  family : String,
  mode : String,
  intent : WorkIntent,
  execution_surface : String,
  handler : String,
  capability_class : String,
) -> MuyataProfile {
  {
    overlay, family, mode, intent,
    execution_surface, handler,
    procsi_ref: None,
    fingerprint_commitment: None,
    capability_class,
  }
}

///|
/// Create an Anthropic Claude profile with the given tier.
pub fn MuyataProfile::claude(
  tier : CognitiveTier,
  intent : WorkIntent,
  execution_surface : String,
  handler : String,
) -> MuyataProfile {
  MuyataProfile::new(
    "claude", "anthropic", tier.to_string(), intent,
    execution_surface, handler, "full",
  )
}

///|
/// Create a Google Gemini profile.
pub fn MuyataProfile::gemini(
  mode : String,
  intent : WorkIntent,
  execution_surface : String,
  handler : String,
) -> MuyataProfile {
  MuyataProfile::new(
    "gemini", "google", mode, intent,
    execution_surface, handler, "full",
  )
}

// ---------------------------------------------------------------------------
// Mutation helpers (immutable update)
// ---------------------------------------------------------------------------

///|
/// Bind procsi identity.
pub fn MuyataProfile::bind_procsi(self : MuyataProfile, procsi : MuyataProcsiRef) -> MuyataProfile {
  { ..self, procsi_ref: Some(procsi) }
}

///|
/// Set fingerprint commitment.
pub fn MuyataProfile::set_fingerprint(self : MuyataProfile, commitment : String) -> MuyataProfile {
  { ..self, fingerprint_commitment: Some(commitment) }
}

///|
/// Change work intent.
pub fn MuyataProfile::set_intent(self : MuyataProfile, intent : WorkIntent) -> MuyataProfile {
  { ..self, intent }
}

///|
/// Change capability class.
pub fn MuyataProfile::set_capability_class(self : MuyataProfile, cls : String) -> MuyataProfile {
  { ..self, capability_class: cls }
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Get the cognitive tier from the mode string.
pub fn MuyataProfile::tier(self : MuyataProfile) -> CognitiveTier {
  CognitiveTier::from_string(self.mode)
}

///|
/// Is this a top-tier (Opus) agent?
pub fn MuyataProfile::is_architect(self : MuyataProfile) -> Bool {
  self.tier() == Opus
}

///|
/// Is this a worker-tier (Sonnet) agent?
pub fn MuyataProfile::is_worker(self : MuyataProfile) -> Bool {
  self.tier() == Sonnet
}

///|
/// Is this a scout-tier (Haiku) agent?
pub fn MuyataProfile::is_scout(self : MuyataProfile) -> Bool {
  self.tier() == Haiku
}

///|
/// Is this profile currently observing?
pub fn MuyataProfile::is_observing(self : MuyataProfile) -> Bool {
  self.intent == Observation
}

///|
/// Cost weight for scheduling (Haiku=1, Sonnet=4, Opus=16).
pub fn MuyataProfile::cost_weight(self : MuyataProfile) -> Int {
  match self.tier() {
    Haiku     => 1
    Sonnet    => 4
    Opus      => 16
    Custom(_) => 2
  }
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

///|
/// Serialize to bytes.
pub fn MuyataProfile::to_bytes(self : MuyataProfile) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in muyata_magic { buf.push(b) }
  muyata_write_u32(buf, muyata_version)
  muyata_write_str(buf, self.overlay)
  muyata_write_str(buf, self.family)
  muyata_write_str(buf, self.mode)
  buf.push(self.intent.to_byte())
  muyata_write_str(buf, self.execution_surface)
  muyata_write_str(buf, self.handler)
  // procsi_ref
  match self.procsi_ref {
    Some(p) => {
      buf.push(b'\x01')
      muyata_write_str(buf, p.locus)
      muyata_write_str(buf, p.project)
      muyata_write_str(buf, p.tier)
    }
    None => buf.push(b'\x00')
  }
  // fingerprint
  match self.fingerprint_commitment {
    Some(f) => { buf.push(b'\x01'); muyata_write_str(buf, f) }
    None    => buf.push(b'\x00')
  }
  muyata_write_str(buf, self.capability_class)
  buf
}

///|
/// Deserialize from bytes.
pub fn MuyataProfile::from_bytes(data : Array[Byte]) -> MuyataProfile? {
  let len = data.length()
  if len < 8 { return None }
  if data[0] != muyata_magic[0] || data[1] != muyata_magic[1] ||
     data[2] != muyata_magic[2] || data[3] != muyata_magic[3] { return None }
  let mut pos = 4
  let _ver = muyata_read_u32(data, pos); pos = pos + 4

  let overlay = match muyata_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  let family = match muyata_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  let mode = match muyata_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  if pos >= len { return None }
  let intent = WorkIntent::from_byte(data[pos]); pos = pos + 1
  let execution_surface = match muyata_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  let handler = match muyata_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  // procsi_ref
  if pos >= len { return None }
  let procsi_ref : MuyataProcsiRef? = if data[pos] == b'\x01' {
    pos = pos + 1
    let locus = match muyata_read_str(data, pos, len) {
      Some((s, p)) => { pos = p; s }
      None => return None
    }
    let project = match muyata_read_str(data, pos, len) {
      Some((s, p)) => { pos = p; s }
      None => return None
    }
    let tier = match muyata_read_str(data, pos, len) {
      Some((s, p)) => { pos = p; s }
      None => return None
    }
    Some({ locus, project, tier })
  } else {
    pos = pos + 1
    None
  }
  // fingerprint
  if pos >= len { return None }
  let fingerprint_commitment : String? = if data[pos] == b'\x01' {
    pos = pos + 1
    match muyata_read_str(data, pos, len) {
      Some((s, p)) => { pos = p; Some(s) }
      None => return None
    }
  } else {
    pos = pos + 1
    None
  }
  let capability_class = match muyata_read_str(data, pos, len) {
    Some((s, _p)) => s
    None => return None
  }

  Some({
    overlay, family, mode, intent, execution_surface, handler,
    procsi_ref, fingerprint_commitment, capability_class,
  })
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn muyata_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn muyata_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn muyata_write_str(buf : Array[Byte], s : String) -> Unit {
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
  muyata_write_u32(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

///|
fn muyata_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = muyata_read_u32(data, pos)
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
