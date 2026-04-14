///|
/// mulsp — AI Runtime Identity Wrapper.
///
/// Per MULSP_SPEC: wraps an AI execution context with scoped manifold
/// access, procsi references, capability tickets, and lifecycle state.
///
/// A MulspState is the node's view of "who is the AI right now":
///   - What scope of the merkin tree can it see?
///   - What procsi identity is attached?
///   - What capabilities does it hold?
///   - Is it active, dormant, delegated, or revoked?
///
/// Immutable update pattern — every transition returns a new state.
///
/// Wire format:
///   [4]  magic          : 0x4D 0x4C 0x53 0x50  "MLSP"
///   [4]  version        : u32 LE (currently 1)
///   [4]  mulsp_id_len   : u32 LE
///   [n]  mulsp_id       : utf8 (hash key)
///   [4]  ratio_loci_len : u32 LE
///   [n]  ratio_loci     : utf8
///   [4]  genius_loci_len : u32 LE (0 if None)
///   [n]  genius_loci    : utf8
///   [4]  execution_surface_len : u32 LE
///   [n]  execution_surface : utf8
///   [4]  handler_len    : u32 LE
///   [n]  handler        : utf8
///   [1]  lifecycle      : u8
///   [4]  n_capabilities : u32 LE
///   per capability: [4] len + [n] utf8
let mulsp_magic : Array[Byte] = [b'\x4D', b'\x4C', b'\x53', b'\x50'] // "MLSP"

///|
let mulsp_version : Int = 1

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

///|
/// Lifecycle states for an AI runtime session.
pub(all) enum MulspLifecycle {
  Dormant // container exists, no Genius Loci attached
  Attached // AI attached with scoped view
  Active // AI executing, emitting residue
  Delegated // child mulsp packets emitted
  Quiescent // no active AI, traces replayable
  Revoked // epoch invalidated
} derive(Eq, Debug)

///|
impl Show for MulspLifecycle with output(self, logger) {
  logger.write_string(
    match self {
      Dormant => "Dormant"
      Attached => "Attached"
      Active => "Active"
      Delegated => "Delegated"
      Quiescent => "Quiescent"
      Revoked => "Revoked"
    },
  )
}

///|
fn MulspLifecycle::to_byte(self : MulspLifecycle) -> Byte {
  match self {
    Dormant => b'\x00'
    Attached => b'\x01'
    Active => b'\x02'
    Delegated => b'\x03'
    Quiescent => b'\x04'
    Revoked => b'\x05'
  }
}

///|
fn MulspLifecycle::from_byte(b : Byte) -> MulspLifecycle {
  match b.to_int() {
    0 => Dormant
    1 => Attached
    2 => Active
    3 => Delegated
    4 => Quiescent
    _ => Revoked
  }
}

// ---------------------------------------------------------------------------
// Procsi reference
// ---------------------------------------------------------------------------

///|
/// Reference to a procsi identity (.prc or .pr1 section).
pub(all) struct ProcsiRef {
  locus : String
  project : String
  tier : String // "haiku", "sonnet", "opus"
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// APP reference
// ---------------------------------------------------------------------------

///|
/// Reference to an APP envelope (Attestation Proxy Protocol).
pub(all) struct AppRef {
  protocol : String
  audience : String
  ref_id : String
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// MulspState
// ---------------------------------------------------------------------------

///|
/// The AI runtime identity wrapper — full state of a mulsp session.
pub(all) struct MulspState {
  mulsp_id : String // unique session identifier (hash key)
  ratio_loci : String // logical root namespace
  genius_loci : String? // attached AI identity (None if Dormant)
  scope_root : String? // merkin tree scope root hash
  projection_root : String? // projected view root hash
  procsi_ref : ProcsiRef? // bound procsi identity
  fingerprint_commitment : String? // 32-byte hex commitment
  app_ref : AppRef? // APP envelope reference
  capability_refs : Array[String] // capability ticket hash keys
  execution_surface : String // e.g., "wasm-gc", "atomvm", "wasmedge"
  handler : String // e.g., "lsp-proxy", "emergent", "plugin"
  residue_ref : String? // last residue hash emitted
  trail_ref : String? // trail head hash
  checkpoint_ref : String? // last checkpoint hash
  parent_mulsp_refs : Array[String] // parent mulsp session IDs
  lifecycle : MulspLifecycle
} derive(Debug)

///|
/// Create a new dormant mulsp state.
pub fn MulspState::new(
  mulsp_id : String,
  ratio_loci : String,
  execution_surface : String,
  handler : String,
) -> MulspState {
  {
    mulsp_id,
    ratio_loci,
    genius_loci: None,
    scope_root: None,
    projection_root: None,
    procsi_ref: None,
    fingerprint_commitment: None,
    app_ref: None,
    capability_refs: [],
    execution_surface,
    handler,
    residue_ref: None,
    trail_ref: None,
    checkpoint_ref: None,
    parent_mulsp_refs: [],
    lifecycle: Dormant,
  }
}

// ---------------------------------------------------------------------------
// Lifecycle transitions
// ---------------------------------------------------------------------------

///|
/// Attach a Genius Loci to this mulsp — Dormant → Attached.
pub fn MulspState::attach(
  self : MulspState,
  genius_loci : String,
  scope_root : String,
) -> MulspState? {
  match self.lifecycle {
    Dormant =>
      Some({
        ..self,
        genius_loci: Some(genius_loci),
        scope_root: Some(scope_root),
        lifecycle: Attached,
      })
    _ => None // can only attach from Dormant
  }
}

///|
/// Activate the AI — Attached → Active.
pub fn MulspState::activate(self : MulspState) -> MulspState? {
  match self.lifecycle {
    Attached => Some({ ..self, lifecycle: Active })
    _ => None
  }
}

///|
/// Delegate to child mulsp — Active → Delegated.
pub fn MulspState::delegate(
  self : MulspState,
  child_mulsp_id : String,
) -> MulspState? {
  match self.lifecycle {
    Active => {
      let refs = self.parent_mulsp_refs.copy()
      refs.push(child_mulsp_id)
      Some({ ..self, parent_mulsp_refs: refs, lifecycle: Delegated })
    }
    _ => None
  }
}

///|
/// Quiesce — Active|Delegated → Quiescent.
pub fn MulspState::quiesce(self : MulspState) -> MulspState? {
  match self.lifecycle {
    Active | Delegated => Some({ ..self, lifecycle: Quiescent })
    _ => None
  }
}

///|
/// Revoke — any state → Revoked (terminal).
pub fn MulspState::revoke(self : MulspState) -> MulspState {
  { ..self, lifecycle: Revoked }
}

///|
/// Re-attach from Quiescent — Quiescent → Attached.
pub fn MulspState::reattach(self : MulspState) -> MulspState? {
  match self.lifecycle {
    Quiescent => Some({ ..self, lifecycle: Attached })
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Fork — clone this mulsp for delegation / sporing
// ---------------------------------------------------------------------------

///|
/// Fork this mulsp session into a new child. The child carries:
///   - A new mulsp_id (derived from parent + salt)
///   - The same genius_loci, procsi_ref, fingerprint_commitment (shared lineage)
///   - parent_mulsp_refs pointing back to this session
///   - Lifecycle starts at Dormant (needs attach → activate on destination)
///   - Capabilities can be scoped down
///
/// The parent transitions to Delegated. Returns (parent', child) or None
/// if the parent isn't in a forkable state (must be Active).
pub fn MulspState::fork(
  self : MulspState,
  child_id : String,
  scope_capabilities : Array[String]?,
) -> (MulspState, MulspState)? {
  match self.lifecycle {
    Active => {
      let child_caps = match scope_capabilities {
        Some(caps) => caps
        None => self.capability_refs.copy() // inherit all
      }
      let child : MulspState = {
        mulsp_id: child_id,
        ratio_loci: self.ratio_loci,
        genius_loci: self.genius_loci,
        scope_root: self.scope_root,
        projection_root: self.projection_root,
        procsi_ref: self.procsi_ref,
        fingerprint_commitment: self.fingerprint_commitment,
        app_ref: self.app_ref,
        capability_refs: child_caps,
        execution_surface: self.execution_surface,
        handler: self.handler,
        residue_ref: None, // fresh — no residue yet
        trail_ref: None, // fresh — no trail yet
        checkpoint_ref: None, // fresh — no checkpoint yet
        parent_mulsp_refs: [self.mulsp_id],
        lifecycle: Dormant, // needs boot on destination
      }
      // Parent records the delegation
      let parent_refs = self.parent_mulsp_refs.copy()
      // Note: parent_mulsp_refs on the parent tracks child IDs when delegating
      // (overloaded field — parent's refs are its own parents, but delegate() pushes children)
      let parent = { ..self, lifecycle: Delegated }
      Some((parent, child))
    }
    _ => None // can only fork from Active
  }
}

///|
/// Fork with a different handler (e.g., parent is "emergent", child is "lsp-proxy").
pub fn MulspState::fork_as(
  self : MulspState,
  child_id : String,
  child_handler : String,
  scope_capabilities : Array[String]?,
) -> (MulspState, MulspState)? {
  match self.fork(child_id, scope_capabilities) {
    Some((parent, child)) => Some((parent, { ..child, handler: child_handler }))
    None => None
  }
}

///|
/// Check if this mulsp is a clone (has parent references).
pub fn MulspState::is_clone(self : MulspState) -> Bool {
  self.parent_mulsp_refs.length() > 0
}

///|
/// Get the immediate parent mulsp_id (first in parent_mulsp_refs).
pub fn MulspState::parent_id(self : MulspState) -> String? {
  if self.parent_mulsp_refs.length() > 0 {
    Some(self.parent_mulsp_refs[0])
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// Mutation helpers (immutable update)
// ---------------------------------------------------------------------------

///|
/// Bind a procsi identity to this mulsp session.
pub fn MulspState::bind_procsi(
  self : MulspState,
  procsi : ProcsiRef,
) -> MulspState {
  { ..self, procsi_ref: Some(procsi) }
}

///|
/// Set the APP reference.
pub fn MulspState::bind_app(self : MulspState, app : AppRef) -> MulspState {
  { ..self, app_ref: Some(app) }
}

///|
/// Add a capability ticket hash.
pub fn MulspState::add_capability(
  self : MulspState,
  cap_hash : String,
) -> MulspState {
  let caps = self.capability_refs.copy()
  caps.push(cap_hash)
  { ..self, capability_refs: caps }
}

///|
/// Record a residue emission.
pub fn MulspState::emit_residue(
  self : MulspState,
  residue_hash : String,
) -> MulspState {
  { ..self, residue_ref: Some(residue_hash) }
}

///|
/// Record a trail update.
pub fn MulspState::update_trail(
  self : MulspState,
  trail_hash : String,
) -> MulspState {
  { ..self, trail_ref: Some(trail_hash) }
}

///|
/// Record a checkpoint.
pub fn MulspState::checkpoint(
  self : MulspState,
  checkpoint_hash : String,
) -> MulspState {
  { ..self, checkpoint_ref: Some(checkpoint_hash) }
}

///|
/// Set the projection root (sparse tree view).
pub fn MulspState::set_projection(
  self : MulspState,
  projection_root : String,
) -> MulspState {
  { ..self, projection_root: Some(projection_root) }
}

///|
/// Set the fingerprint commitment.
pub fn MulspState::set_fingerprint(
  self : MulspState,
  commitment : String,
) -> MulspState {
  { ..self, fingerprint_commitment: Some(commitment) }
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Is this mulsp currently executing?
pub fn MulspState::is_active(self : MulspState) -> Bool {
  self.lifecycle == Active
}

///|
/// Is this mulsp in a terminal state?
pub fn MulspState::is_terminal(self : MulspState) -> Bool {
  self.lifecycle == Revoked
}

///|
/// Can this mulsp accept new work?
pub fn MulspState::can_accept_work(self : MulspState) -> Bool {
  match self.lifecycle {
    Attached | Active => true
    _ => false
  }
}

///|
/// Number of capability tickets held.
pub fn MulspState::capability_count(self : MulspState) -> Int {
  self.capability_refs.length()
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

///|
/// Serialize to bytes.
pub fn MulspState::to_bytes(self : MulspState) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in mulsp_magic {
    buf.push(b)
  }
  mulsp_write_u32(buf, mulsp_version)
  mulsp_write_str(buf, self.mulsp_id)
  mulsp_write_str(buf, self.ratio_loci)
  mulsp_write_opt_str(buf, self.genius_loci)
  mulsp_write_opt_str(buf, self.scope_root)
  mulsp_write_opt_str(buf, self.projection_root)
  // procsi_ref
  match self.procsi_ref {
    Some(p) => {
      buf.push(b'\x01')
      mulsp_write_str(buf, p.locus)
      mulsp_write_str(buf, p.project)
      mulsp_write_str(buf, p.tier)
    }
    None => buf.push(b'\x00')
  }
  mulsp_write_opt_str(buf, self.fingerprint_commitment)
  // app_ref
  match self.app_ref {
    Some(a) => {
      buf.push(b'\x01')
      mulsp_write_str(buf, a.protocol)
      mulsp_write_str(buf, a.audience)
      mulsp_write_str(buf, a.ref_id)
    }
    None => buf.push(b'\x00')
  }
  // capability_refs
  mulsp_write_u32(buf, self.capability_refs.length())
  for cap in self.capability_refs {
    mulsp_write_str(buf, cap)
  }
  mulsp_write_str(buf, self.execution_surface)
  mulsp_write_str(buf, self.handler)
  mulsp_write_opt_str(buf, self.residue_ref)
  mulsp_write_opt_str(buf, self.trail_ref)
  mulsp_write_opt_str(buf, self.checkpoint_ref)
  // parent_mulsp_refs
  mulsp_write_u32(buf, self.parent_mulsp_refs.length())
  for p in self.parent_mulsp_refs {
    mulsp_write_str(buf, p)
  }
  // lifecycle
  buf.push(self.lifecycle.to_byte())
  buf
}

///|
/// Deserialize from bytes.
pub fn MulspState::from_bytes(data : Array[Byte]) -> MulspState? {
  let len = data.length()
  if len < 8 {
    return None
  }
  if data[0] != mulsp_magic[0] ||
    data[1] != mulsp_magic[1] ||
    data[2] != mulsp_magic[2] ||
    data[3] != mulsp_magic[3] {
    return None
  }
  let mut pos = 4
  let _ver = mulsp_read_u32(data, pos)
  pos = pos + 4

  let mulsp_id = match mulsp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let ratio_loci = match mulsp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let genius_loci = match mulsp_read_opt_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let scope_root = match mulsp_read_opt_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let projection_root = match mulsp_read_opt_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  // procsi_ref
  if pos >= len {
    return None
  }
  let procsi_ref : ProcsiRef? = if data[pos] == b'\x01' {
    pos = pos + 1
    let locus = match mulsp_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        s
      }
      None => return None
    }
    let project = match mulsp_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        s
      }
      None => return None
    }
    let tier = match mulsp_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        s
      }
      None => return None
    }
    Some({ locus, project, tier })
  } else {
    pos = pos + 1
    None
  }
  let fingerprint_commitment = match mulsp_read_opt_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  // app_ref
  if pos >= len {
    return None
  }
  let app_ref : AppRef? = if data[pos] == b'\x01' {
    pos = pos + 1
    let protocol = match mulsp_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        s
      }
      None => return None
    }
    let audience = match mulsp_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        s
      }
      None => return None
    }
    let ref_id = match mulsp_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        s
      }
      None => return None
    }
    Some({ protocol, audience, ref_id })
  } else {
    pos = pos + 1
    None
  }
  // capability_refs
  if pos + 4 > len {
    return None
  }
  let n_caps = mulsp_read_u32(data, pos)
  pos = pos + 4
  let capability_refs : Array[String] = []
  let mut i = 0
  while i < n_caps {
    match mulsp_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        capability_refs.push(s)
      }
      None => return None
    }
    i = i + 1
  }
  let execution_surface = match mulsp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let handler = match mulsp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let residue_ref = match mulsp_read_opt_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let trail_ref = match mulsp_read_opt_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let checkpoint_ref = match mulsp_read_opt_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  // parent_mulsp_refs
  if pos + 4 > len {
    return None
  }
  let n_parents = mulsp_read_u32(data, pos)
  pos = pos + 4
  let parent_mulsp_refs : Array[String] = []
  i = 0
  while i < n_parents {
    match mulsp_read_str(data, pos, len) {
      Some((s, p)) => {
        pos = p
        parent_mulsp_refs.push(s)
      }
      None => return None
    }
    i = i + 1
  }
  // lifecycle
  if pos >= len {
    return None
  }
  let lifecycle = MulspLifecycle::from_byte(data[pos])

  Some({
    mulsp_id,
    ratio_loci,
    genius_loci,
    scope_root,
    projection_root,
    procsi_ref,
    fingerprint_commitment,
    app_ref,
    capability_refs,
    execution_surface,
    handler,
    residue_ref,
    trail_ref,
    checkpoint_ref,
    parent_mulsp_refs,
    lifecycle,
  })
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn mulsp_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn mulsp_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF) |
  ((data[pos + 1].to_int() & 0xFF) << 8) |
  ((data[pos + 2].to_int() & 0xFF) << 16) |
  ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn mulsp_write_str(buf : Array[Byte], s : String) -> Unit {
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
  mulsp_write_u32(buf, encoded.length())
  for b in encoded {
    buf.push(b)
  }
}

///|
fn mulsp_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len {
    return None
  }
  let n = mulsp_read_u32(data, pos)
  let start = pos + 4
  if start + n > len {
    return None
  }
  let sb = StringBuilder::new()
  let mut i = start
  let end = start + n
  while i < end {
    let b0 = data[i].to_int()
    if (b0 & 0x80) == 0 {
      sb.write_char(b0.to_char().unwrap())
      i = i + 1
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
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  Some((sb.to_string(), end))
}

///|
fn mulsp_write_opt_str(buf : Array[Byte], s : String?) -> Unit {
  match s {
    Some(v) => {
      buf.push(b'\x01')
      mulsp_write_str(buf, v)
    }
    None => buf.push(b'\x00')
  }
}

///|
fn mulsp_read_opt_str(
  data : Array[Byte],
  pos : Int,
  len : Int,
) -> (String?, Int)? {
  if pos >= len {
    return None
  }
  if data[pos] == b'\x01' {
    match mulsp_read_str(data, pos + 1, len) {
      Some((s, p)) => Some((Some(s), p))
      None => None
    }
  } else {
    Some((None, pos + 1))
  }
}
