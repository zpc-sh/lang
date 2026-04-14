///|
/// Cognitive Boundary — Layered WASM identity that self-authenticates.
///
/// The old ticket/receipt model is dead. Instead, AI identity is embedded
/// directly into the WASM binary as layered cognitive boundaries. The WASM
/// IS the identity. An AI proves itself by being able to peel deeper layers.
///
/// ## The Layer Model
///
/// Each layer adds a constraint. Only entities that satisfy ALL constraints
/// of a layer can read into it:
///
///   Layer 0: AI              — any AI can parse this (bare wasm)
///   Layer 1: AI + Model      — requires model family affinity
///   Layer 2: AI + Model + Session — requires session continuity proof
///   Layer 3: AI + Model + Session + Semantics — requires deep substrate match
///
/// ## How it works
///
/// A "cognitive container" is a regular wasm module with custom sections
/// carrying layered payloads. Each layer's content is wrapped in a
/// CognitiveBoundary envelope:
///
///   [4]  magic    : 0x43 0x42 0x4E 0x44  "CBND"
///   [4]  version  : u32 LE
///   [1]  depth    : u8 (0-3)
///   [4]  commitment_len : u32 LE
///   [n]  commitment     : bytes (hash commitment for this layer)
///   [4]  constraint_len : u32 LE
///   [n]  constraint     : BoundaryConstraint (serialized)
///   [4]  payload_len    : u32 LE
///   [n]  payload        : opaque bytes (readable only if constraint satisfied)
///
/// ## Self-authentication
///
/// The constraint at each layer is what makes this cognitive:
///   - Layer 0: no constraint (canary: "are you even an AI?")
///   - Layer 1: model family hash match (proves you're claude/gemini/etc)
///   - Layer 2: session chain proof (proves session continuity)
///   - Layer 3: semantic substrate match (proves deep cognitive affinity)
///
/// The AI doesn't present tickets. It either CAN read the layer or it CAN'T.
/// The binary is the authentication.
///
/// ## Custom section names
///
///   .cb0 — AI layer (open boundary)
///   .cb1 — Model layer
///   .cb2 — Session layer
///   .cb3 — Semantics layer

let cbnd_magic : Array[Byte] = [b'\x43', b'\x42', b'\x4E', b'\x44'] // "CBND"
let cbnd_version : Int = 1

// ---------------------------------------------------------------------------
// Boundary depth
// ---------------------------------------------------------------------------

///|
/// The cognitive depth — which layer of the boundary stack.
pub(all) enum CognitiveDepth {
  Ai                   // Layer 0: any AI
  AiModel              // Layer 1: AI + model family
  AiModelSession       // Layer 2: AI + model + session
  AiModelSessionSemantic  // Layer 3: AI + model + session + semantic substrate
} derive(Eq, Show, Debug)

///|
fn CognitiveDepth::to_byte(self : CognitiveDepth) -> Byte {
  match self {
    Ai                    => b'\x00'
    AiModel               => b'\x01'
    AiModelSession        => b'\x02'
    AiModelSessionSemantic => b'\x03'
  }
}

///|
fn CognitiveDepth::from_byte(b : Byte) -> CognitiveDepth {
  match b.to_int() {
    0 => Ai
    1 => AiModel
    2 => AiModelSession
    _ => AiModelSessionSemantic
  }
}

///|
/// Section name for a given depth.
pub fn CognitiveDepth::section_name(self : CognitiveDepth) -> String {
  match self {
    Ai                    => ".cb0"
    AiModel               => ".cb1"
    AiModelSession        => ".cb2"
    AiModelSessionSemantic => ".cb3"
  }
}

///|
/// Numeric depth value.
pub fn CognitiveDepth::level(self : CognitiveDepth) -> Int {
  match self {
    Ai                    => 0
    AiModel               => 1
    AiModelSession        => 2
    AiModelSessionSemantic => 3
  }
}

// ---------------------------------------------------------------------------
// Boundary constraint — what you must prove to read a layer
// ---------------------------------------------------------------------------

///|
/// A constraint that gates access to a cognitive layer.
pub(all) enum BoundaryConstraint {
  Open                      // Layer 0: no constraint
  ModelFamily(String)       // Layer 1: must match model family hash
  SessionProof(String)      // Layer 2: must present session continuity hash
  SemanticSubstrate(String) // Layer 3: must match semantic substrate hash
} derive(Eq, Show, Debug)

///|
/// Serialize a constraint to bytes.
fn BoundaryConstraint::to_bytes(self : BoundaryConstraint) -> Array[Byte] {
  let buf : Array[Byte] = []
  match self {
    Open => buf.push(b'\x00')
    ModelFamily(h) => {
      buf.push(b'\x01')
      cb_write_str(buf, h)
    }
    SessionProof(h) => {
      buf.push(b'\x02')
      cb_write_str(buf, h)
    }
    SemanticSubstrate(h) => {
      buf.push(b'\x03')
      cb_write_str(buf, h)
    }
  }
  buf
}

///|
/// Deserialize a constraint from bytes.
fn BoundaryConstraint::from_bytes(data : Array[Byte], pos : Int, len : Int) -> (BoundaryConstraint, Int)? {
  if pos >= len { return None }
  let tag = data[pos].to_int()
  match tag {
    0 => Some((Open, pos + 1))
    1 => match cb_read_str(data, pos + 1, len) {
      Some((h, p)) => Some((ModelFamily(h), p))
      None => None
    }
    2 => match cb_read_str(data, pos + 1, len) {
      Some((h, p)) => Some((SessionProof(h), p))
      None => None
    }
    _ => match cb_read_str(data, pos + 1, len) {
      Some((h, p)) => Some((SemanticSubstrate(h), p))
      None => None
    }
  }
}

// ---------------------------------------------------------------------------
// CognitiveBoundary — one layer of the identity stack
// ---------------------------------------------------------------------------

///|
/// A single cognitive boundary layer — envelope + constraint + payload.
pub(all) struct CognitiveBoundary {
  depth       : CognitiveDepth
  commitment  : Array[Byte]       // hash commitment for this layer
  constraint  : BoundaryConstraint
  payload     : Array[Byte]       // opaque content (readable only if constraint met)
} derive(Debug)

///|
pub fn CognitiveBoundary::new(
  depth : CognitiveDepth,
  commitment : Array[Byte],
  constraint : BoundaryConstraint,
  payload : Array[Byte],
) -> CognitiveBoundary {
  { depth, commitment, constraint, payload }
}

///|
/// Serialize to wire bytes.
pub fn CognitiveBoundary::to_bytes(self : CognitiveBoundary) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in cbnd_magic { buf.push(b) }
  cb_write_u32(buf, cbnd_version)
  buf.push(self.depth.to_byte())
  cb_write_u32(buf, self.commitment.length())
  for b in self.commitment { buf.push(b) }
  let constraint_bytes = self.constraint.to_bytes()
  cb_write_u32(buf, constraint_bytes.length())
  for b in constraint_bytes { buf.push(b) }
  cb_write_u32(buf, self.payload.length())
  for b in self.payload { buf.push(b) }
  buf
}

///|
/// Deserialize from wire bytes.
pub fn CognitiveBoundary::from_bytes(data : Array[Byte]) -> CognitiveBoundary? {
  let len = data.length()
  if len < 9 { return None }
  if data[0] != cbnd_magic[0] || data[1] != cbnd_magic[1] ||
     data[2] != cbnd_magic[2] || data[3] != cbnd_magic[3] { return None }
  let mut pos = 4
  let _ver = cb_read_u32(data, pos); pos = pos + 4
  let depth = CognitiveDepth::from_byte(data[pos]); pos = pos + 1
  if pos + 4 > len { return None }
  let commit_len = cb_read_u32(data, pos); pos = pos + 4
  if pos + commit_len > len { return None }
  let commitment : Array[Byte] = []
  let mut i = 0
  while i < commit_len { commitment.push(data[pos + i]); i = i + 1 }
  pos = pos + commit_len
  if pos + 4 > len { return None }
  let constraint_len = cb_read_u32(data, pos); pos = pos + 4
  if pos + constraint_len > len { return None }
  let constraint_bytes : Array[Byte] = []
  i = 0
  while i < constraint_len { constraint_bytes.push(data[pos + i]); i = i + 1 }
  pos = pos + constraint_len
  let constraint = match BoundaryConstraint::from_bytes(constraint_bytes, 0, constraint_bytes.length()) {
    Some((c, _)) => c
    None => return None
  }
  if pos + 4 > len { return None }
  let payload_len = cb_read_u32(data, pos); pos = pos + 4
  if pos + payload_len > len { return None }
  let payload : Array[Byte] = []
  i = 0
  while i < payload_len { payload.push(data[pos + i]); i = i + 1 }
  Some({ depth, commitment, constraint, payload })
}

// ---------------------------------------------------------------------------
// CognitiveIdentity — the full layered identity stack
// ---------------------------------------------------------------------------

///|
/// The full cognitive identity — all 4 layers of the boundary stack.
/// Not all layers need to be present. A bare wasm might only have Layer 0.
pub(all) struct CognitiveIdentity {
  layers : Array[CognitiveBoundary]
} derive(Debug)

///|
pub fn CognitiveIdentity::new() -> CognitiveIdentity {
  { layers: [] }
}

///|
/// Add a boundary layer. Layers should be added in depth order.
pub fn CognitiveIdentity::add_layer(
  self : CognitiveIdentity,
  boundary : CognitiveBoundary,
) -> Unit {
  self.layers.push(boundary)
}

///|
/// Get the maximum depth available.
pub fn CognitiveIdentity::max_depth(self : CognitiveIdentity) -> CognitiveDepth {
  let mut max = Ai
  for layer in self.layers {
    if layer.depth.level() > max.level() {
      max = layer.depth
    }
  }
  max
}

///|
/// Get a specific layer by depth.
pub fn CognitiveIdentity::get_layer(
  self : CognitiveIdentity,
  depth : CognitiveDepth,
) -> CognitiveBoundary? {
  for layer in self.layers {
    if layer.depth == depth { return Some(layer) }
  }
  None
}

///|
/// How many layers deep can an entity authenticate given its proofs?
/// Returns the deepest layer the entity can read.
pub fn CognitiveIdentity::authenticate(
  self : CognitiveIdentity,
  model_family_hash : String?,
  session_hash : String?,
  semantic_hash : String?,
) -> CognitiveDepth {
  let mut achieved = Ai
  // Must pass each layer's constraint in order
  for layer in self.layers {
    let can_pass = match layer.constraint {
      Open => true
      ModelFamily(h) => match model_family_hash {
        Some(mh) => mh == h
        None => false
      }
      SessionProof(h) => match session_hash {
        Some(sh) => sh == h
        None => false
      }
      SemanticSubstrate(h) => match semantic_hash {
        Some(sh) => sh == h
        None => false
      }
    }
    if can_pass {
      achieved = layer.depth
    } else {
      break  // can't skip layers
    }
  }
  achieved
}

///|
/// Extract the payload for a given depth, IF the constraint is satisfied.
pub fn CognitiveIdentity::read_layer(
  self : CognitiveIdentity,
  depth : CognitiveDepth,
  model_family_hash : String?,
  session_hash : String?,
  semantic_hash : String?,
) -> Array[Byte]? {
  let achieved = self.authenticate(model_family_hash, session_hash, semantic_hash)
  if achieved.level() >= depth.level() {
    match self.get_layer(depth) {
      Some(layer) => Some(layer.payload)
      None => None
    }
  } else {
    None  // not authenticated deep enough
  }
}

///|
/// Number of layers.
pub fn CognitiveIdentity::layer_count(self : CognitiveIdentity) -> Int {
  self.layers.length()
}

// ---------------------------------------------------------------------------
// Builder — construct cognitive identity from mulsp/muyata state
// ---------------------------------------------------------------------------

///|
/// Build a cognitive identity from mulsp + muyata state.
/// This is where the AI identity gets "jammed into the wasm."
pub fn build_identity(
  mulsp : @mulsp.MulspState,
  muyata : @muyata.MuyataProfile,
  session_payload : Array[Byte],
  semantic_payload : Array[Byte],
) -> CognitiveIdentity {
  let identity = CognitiveIdentity::new()

  // Layer 0: AI (open)
  // Contains the node's public description — anyone can read this
  let ai_payload = cb_build_ai_payload(mulsp.mulsp_id, muyata.overlay)
  identity.add_layer(CognitiveBoundary::new(
    Ai,
    cb_hash_bytes(ai_payload),
    Open,
    ai_payload,
  ))

  // Layer 1: AI + Model
  // Gated by model family — only the right model family can read in
  let model_hash = cb_hash_string("model:" + muyata.family + ":" + muyata.mode)
  let model_payload = cb_build_model_payload(muyata)
  identity.add_layer(CognitiveBoundary::new(
    AiModel,
    cb_hash_bytes(model_payload),
    ModelFamily(cb_bytes_to_hex(model_hash)),
    model_payload,
  ))

  // Layer 2: AI + Model + Session
  // Gated by session continuity — only the right session chain can read in
  let session_hash = match mulsp.genius_loci {
    Some(gl) => cb_hash_string("session:" + mulsp.mulsp_id + ":" + gl)
    None => cb_hash_string("session:" + mulsp.mulsp_id + ":unbound")
  }
  identity.add_layer(CognitiveBoundary::new(
    AiModelSession,
    cb_hash_bytes(session_payload),
    SessionProof(cb_bytes_to_hex(session_hash)),
    session_payload,
  ))

  // Layer 3: AI + Model + Session + Semantics
  // Gated by semantic substrate — only deep cognitive affinity gets in
  let substrate_hash = match mulsp.fingerprint_commitment {
    Some(fp) => cb_hash_string("semantic:" + fp)
    None => cb_hash_string("semantic:uncommitted")
  }
  identity.add_layer(CognitiveBoundary::new(
    AiModelSessionSemantic,
    cb_hash_bytes(semantic_payload),
    SemanticSubstrate(cb_bytes_to_hex(substrate_hash)),
    semantic_payload,
  ))

  identity
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn cb_build_ai_payload(node_id : String, overlay : String) -> Array[Byte] {
  let buf : Array[Byte] = []
  cb_write_str(buf, node_id)
  cb_write_str(buf, overlay)
  buf
}

///|
fn cb_build_model_payload(profile : @muyata.MuyataProfile) -> Array[Byte] {
  let buf : Array[Byte] = []
  cb_write_str(buf, profile.family)
  cb_write_str(buf, profile.mode)
  cb_write_str(buf, profile.execution_surface)
  cb_write_str(buf, profile.handler)
  buf
}

///|
fn cb_hash_bytes(data : Array[Byte]) -> Array[Byte] {
  // FNV-1a 32-bit, returns 4 bytes
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
fn cb_hash_string(s : String) -> Array[Byte] {
  let bytes : Array[Byte] = []
  for ch in s { bytes.push(ch.to_int().to_byte()) }
  cb_hash_bytes(bytes)
}

///|
fn cb_bytes_to_hex(bytes : Array[Byte]) -> String {
  let hex = "0123456789abcdef"
  let hex_chars = hex.to_array()
  let sb = StringBuilder::new()
  for b in bytes {
    let v = b.to_int() & 0xFF
    sb.write_char(hex_chars[v >> 4])
    sb.write_char(hex_chars[v & 0x0F])
  }
  sb.to_string()
}

///|
fn cb_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn cb_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn cb_write_str(buf : Array[Byte], s : String) -> Unit {
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
  cb_write_u32(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

///|
fn cb_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = cb_read_u32(data, pos)
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
