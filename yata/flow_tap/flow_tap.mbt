///|
/// FlowTap — protocol-agnostic observation surface.
///
/// Sits between any flow (Postgres, HTTP, gRPC, AI inference, raw TCP)
/// and accumulates structural grammar into a GrammarTree + Void.
///
/// The FlowTap receives pre-delimited frames from the host with a
/// type_tag byte. Protocol-specific adapters (PgTap, etc.) handle
/// frame delimiting and type extraction. The FlowTap only sees opaque
/// structural features.
///
/// Key principle: capture protocol grammar, not data. Extract structural
/// tokens (message type, direction, size class, n-gram sequences) and
/// insert them into the grammar tree. The tree shape IS the grammar.
///
/// Wire format (FTAP magic: 0x46 0x54 0x41 0x50):
///   [4]  magic          : "FTAP"
///   [4]  format_version : u32 LE (currently 1)
///   [4+n] tap_id        : utf8
///   [1]  flow_kind      : u8
///   [4]  frames_seen    : u32 LE
///   [4]  flushes        : u32 LE
///   [4]  c2s_count      : u32 LE
///   [4]  s2c_count      : u32 LE
///   [1]  is_ai_flow     : u8
///   [...] void bytes
///   [...] grammar tree bytes

let ftap_magic : Array[Byte] = [b'\x46', b'\x54', b'\x41', b'\x50'] // "FTAP"
let ftap_version : Int = 1

// ---------------------------------------------------------------------------
// Flow enums
// ---------------------------------------------------------------------------

///|
/// Protocol hint for the observed flow.
pub(all) enum FlowKind {
  Lsp           // existing LSP observation
  Database      // Postgres/MySQL wire protocols
  Http          // HTTP/1.1 or HTTP/2
  Grpc          // gRPC over HTTP/2
  AiInference   // AI model inference streams
  Raw           // unknown/raw TCP
} derive(Eq, Debug)

///|
impl Show for FlowKind with output(self, logger) {
  logger.write_string(match self {
    Lsp         => "Lsp"
    Database    => "Database"
    Http        => "Http"
    Grpc        => "Grpc"
    AiInference => "AiInference"
    Raw         => "Raw"
  })
}

///|
fn FlowKind::to_byte(self : FlowKind) -> Byte {
  match self {
    Lsp         => b'\x00'
    Database    => b'\x01'
    Http        => b'\x02'
    Grpc        => b'\x03'
    AiInference => b'\x04'
    Raw         => b'\x05'
  }
}

///|
fn FlowKind::from_byte(b : Byte) -> FlowKind {
  match b.to_int() {
    0 => Lsp
    1 => Database
    2 => Http
    3 => Grpc
    4 => AiInference
    _ => Raw
  }
}

///|
/// Which side of the pipe.
pub(all) enum FlowDirection {
  ClientToServer
  ServerToClient
  Unknown
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// FlowFrame — what the host gives us per frame boundary
// ---------------------------------------------------------------------------

///|
/// A single observed frame boundary. All values are bucketed/jittered
/// before storage.
pub(all) struct FlowFrame {
  direction    : FlowDirection
  size_bytes   : Int        // raw size (bucketed by caller)
  type_tag     : Int        // protocol-specific message type (opaque u8)
  has_body     : Bool
  timestamp_ms : Int        // raw wall clock (jittered by FlowTap)
} derive(Debug)

// ---------------------------------------------------------------------------
// FlowTapConfig
// ---------------------------------------------------------------------------

///|
pub(all) struct FlowTapConfig {
  tap_id         : String
  flow_kind      : FlowKind
  batch_size     : Int        // flush after N frames
  time_jitter_ms : Int        // ± temporal blur
  decoy_rate     : Int        // 1-in-N flushes emit decoy (0 = off)
  ngram_depth    : Int        // n-gram token depth (default 3)
} derive(Debug)

///|
pub fn FlowTapConfig::default(tap_id : String, flow_kind : FlowKind) -> FlowTapConfig {
  {
    tap_id,
    flow_kind,
    batch_size: 32,
    time_jitter_ms: 200,
    decoy_rate: 7,
    ngram_depth: 3,
  }
}

// ---------------------------------------------------------------------------
// Jitter (local lightweight reimplementation)
// ---------------------------------------------------------------------------

///|
struct TapJitter {
  mut state : Int
} derive(Debug)

///|
fn TapJitter::from_str(s : String) -> TapJitter {
  let mut h = 0x811C9DC5
  for ch in s {
    h = h ^ ch.to_int()
    h = h * 0x01000193
  }
  { state: h ^ 0x5DEECE66 }
}

///|
fn TapJitter::next(self : TapJitter) -> Int {
  self.state = self.state * 1664525 + 1013904223
  (self.state >> 16) & 0xFFFF
}

///|
fn TapJitter::blur_time(self : TapJitter, t_ms : Int, range_ms : Int) -> Int {
  if range_ms <= 0 { return t_ms }
  let n = self.next()
  let span = 2 * range_ms + 1
  let scaled = (n * span) >> 16
  let offset = scaled - range_ms
  let jittered = t_ms + offset
  if jittered < 0 { 0 } else { jittered }
}

///|
fn TapJitter::coin(self : TapJitter, one_in_n : Int) -> Bool {
  if one_in_n <= 0 { return false }
  self.next() < (65536 / one_in_n)
}

// ---------------------------------------------------------------------------
// FlowTap
// ---------------------------------------------------------------------------

///|
/// Protocol-agnostic observer. Feeds a GrammarTree + Void.
pub(all) struct FlowTap {
  config       : FlowTapConfig
  mut void_state   : @void.Void
  grammar_tree : @grammar.GrammarTree
  jitter       : TapJitter
  mut frames_seen  : Int
  mut flushes      : Int
  recent_tags  : Array[Int]     // ring buffer for n-gram computation
  mut recent_idx   : Int
  mut last_dir     : FlowDirection
  mut last_ts      : Int
  mut c2s_count    : Int
  mut s2c_count    : Int
  mut is_ai_flow   : Bool
  manifold     : @manifold.ManifoldFragment?
} derive(Debug)

///|
pub fn FlowTap::new(config : FlowTapConfig) -> FlowTap {
  let ngram_size = if config.ngram_depth > 0 { config.ngram_depth } else { 3 }
  {
    config,
    void_state: @void.Void::new(config.tap_id),
    grammar_tree: @grammar.GrammarTree::new(),
    jitter: TapJitter::from_str(config.tap_id),
    frames_seen: 0,
    flushes: 0,
    recent_tags: Array::make(ngram_size, -1),
    recent_idx: 0,
    last_dir: Unknown,
    last_ts: 0,
    c2s_count: 0,
    s2c_count: 0,
    is_ai_flow: false,
    manifold: None,
  }
}

///|
/// Observe a single frame. Extracts structural tokens and feeds them
/// into the grammar tree and void.
pub fn FlowTap::observe(self : FlowTap, frame : FlowFrame) -> Unit {
  self.frames_seen = self.frames_seen + 1

  // Track direction counts
  match frame.direction {
    ClientToServer => self.c2s_count = self.c2s_count + 1
    ServerToClient => self.s2c_count = self.s2c_count + 1
    Unknown => ()
  }

  // Jitter timestamp
  let jittered_ts = self.jitter.blur_time(frame.timestamp_ms, self.config.time_jitter_ms)

  // Bucket size
  let bucketed_size = ftap_bucket(frame.size_bytes, 512)

  // Build routing tokens
  let tokens : Array[String] = []

  // Unigram: message type
  let type_token = "t:" + frame.type_tag.to_string()
  tokens.push(type_token)

  // Direction token
  let dir_token = match frame.direction {
    ClientToServer => "dir:c2s"
    ServerToClient => "dir:s2c"
    Unknown => "dir:unk"
  }
  tokens.push(dir_token)

  // Size class token
  tokens.push("sz:" + ftap_size_label(bucketed_size))

  // Bigram: previous type → current type
  let ngram_size = self.recent_tags.length()
  if ngram_size > 0 {
    let prev_idx = (self.recent_idx + ngram_size - 1) % ngram_size
    let prev_tag = self.recent_tags[prev_idx]
    if prev_tag >= 0 {
      tokens.push("bg:" + prev_tag.to_string() + "->" + frame.type_tag.to_string())
    }
  }

  // Trigram: two-back → previous → current
  if ngram_size > 1 {
    let prev_idx = (self.recent_idx + ngram_size - 1) % ngram_size
    let prev2_idx = (self.recent_idx + ngram_size - 2) % ngram_size
    let prev_tag = self.recent_tags[prev_idx]
    let prev2_tag = self.recent_tags[prev2_idx]
    if prev_tag >= 0 && prev2_tag >= 0 {
      tokens.push("tg:" + prev2_tag.to_string() + "->" + prev_tag.to_string() + "->" + frame.type_tag.to_string())
    }
  }

  // Update ring buffer
  self.recent_tags[self.recent_idx] = frame.type_tag
  self.recent_idx = (self.recent_idx + 1) % ngram_size

  // Ingest into grammar tree with timing salience
  let _ = self.grammar_tree.ingest_with_salience(tokens, jittered_ts)

  // Accumulate into void
  self.void_state = self.void_state.observe_bytes(bucketed_size)
  self.void_state = self.void_state.attend(type_token)
  self.void_state = self.void_state.attend(dir_token)

  // Track direction changes
  self.last_dir = frame.direction
  self.last_ts = jittered_ts

  // Auto-flush if batch full
  if self.frames_seen % self.config.batch_size == 0 {
    self.flush()
  }
}

///|
/// Flush: seal void epoch, optionally inject decoy, check AI heuristic.
pub fn FlowTap::flush(self : FlowTap) -> Unit {
  self.void_state = self.void_state.tick()
  self.flushes = self.flushes + 1

  // Decoy injection
  if self.config.decoy_rate > 0 && self.jitter.coin(self.config.decoy_rate) {
    self.void_state = self.void_state.attend("decoy")
    self.void_state = self.void_state.observe_bytes(ftap_bucket(self.jitter.next() * 8, 512))
  }

  // AI-flow heuristic check
  self.is_ai_flow = self.detect_ai_flow()
}

///|
/// Direction ratio: c2s_count * 100 / total. 0 if no frames.
pub fn FlowTap::direction_ratio(self : FlowTap) -> Int {
  let total = self.c2s_count + self.s2c_count
  if total == 0 { 0 } else { self.c2s_count * 100 / total }
}

///|
/// Distill a ManifoldFragment from the current grammar tree state.
pub fn FlowTap::distill_manifold(self : FlowTap) -> @manifold.ManifoldFragment {
  @manifold.ManifoldFragment::distill(
    self.grammar_tree,
    self.config.tap_id + ":mnfl:" + self.flushes.to_string(),
    self.config.tap_id,
    self.direction_ratio(),
  )
}

///|
/// Snapshot of the current void state.
pub fn FlowTap::void_snapshot(self : FlowTap) -> @void.Void {
  self.void_state
}

///|
/// Reference to the grammar tree.
pub fn FlowTap::grammar(self : FlowTap) -> @grammar.GrammarTree {
  self.grammar_tree
}

// ---------------------------------------------------------------------------
// AI-flow heuristic
// ---------------------------------------------------------------------------

///|
/// Detect if this flow looks like AI traffic.
/// Heuristics:
///   1. Heavily one-directional (streaming responses)
///   2. High timing regularity (consistent token emission)
///   3. Flow kind hint is AiInference
fn FlowTap::detect_ai_flow(self : FlowTap) -> Bool {
  // Explicit hint
  if self.config.flow_kind == AiInference { return true }

  let total = self.c2s_count + self.s2c_count
  if total < 10 { return false }  // not enough data

  // Check direction imbalance (AI streams are heavily s2c)
  let ratio = self.s2c_count * 100 / total
  if ratio > 80 { return true }

  false
}

// ---------------------------------------------------------------------------
// Serialization
// ---------------------------------------------------------------------------

///|
pub fn FlowTap::to_bytes(self : FlowTap) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in ftap_magic { buf.push(b) }
  ftap_write_u32(buf, ftap_version)
  ftap_write_str(buf, self.config.tap_id)
  buf.push(self.config.flow_kind.to_byte())
  ftap_write_u32(buf, self.frames_seen)
  ftap_write_u32(buf, self.flushes)
  ftap_write_u32(buf, self.c2s_count)
  ftap_write_u32(buf, self.s2c_count)
  buf.push(if self.is_ai_flow { b'\x01' } else { b'\x00' })
  // Void bytes
  let void_bytes = self.void_state.to_bytes()
  ftap_write_u32(buf, void_bytes.length())
  for b in void_bytes { buf.push(b) }
  // Grammar tree bytes
  let gram_bytes = self.grammar_tree.to_bytes()
  ftap_write_u32(buf, gram_bytes.length())
  for b in gram_bytes { buf.push(b) }
  buf
}

///|
pub fn FlowTap::from_bytes(data : Array[Byte], config : FlowTapConfig) -> FlowTap? {
  let len = data.length()
  if len < 8 { return None }
  if data[0] != ftap_magic[0] || data[1] != ftap_magic[1] ||
     data[2] != ftap_magic[2] || data[3] != ftap_magic[3] { return None }
  let mut pos = 4
  let _ver = ftap_read_u32(data, pos); pos = pos + 4

  let _tap_id = match ftap_read_str(data, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  if pos >= len { return None }
  let _flow_kind = FlowKind::from_byte(data[pos]); pos = pos + 1

  if pos + 16 > len { return None }
  let frames_seen = ftap_read_u32(data, pos); pos = pos + 4
  let flushes = ftap_read_u32(data, pos); pos = pos + 4
  let c2s_count = ftap_read_u32(data, pos); pos = pos + 4
  let s2c_count = ftap_read_u32(data, pos); pos = pos + 4

  if pos >= len { return None }
  let is_ai_flow = data[pos] == b'\x01'; pos = pos + 1

  // Void bytes
  if pos + 4 > len { return None }
  let void_len = ftap_read_u32(data, pos); pos = pos + 4
  if pos + void_len > len { return None }
  let void_bytes : Array[Byte] = []
  let mut i = 0
  while i < void_len { void_bytes.push(data[pos + i]); i = i + 1 }
  pos = pos + void_len
  let void_state = match @void.Void::from_bytes(void_bytes) {
    Some(v) => v
    None => return None
  }

  // Grammar tree bytes
  if pos + 4 > len { return None }
  let gram_len = ftap_read_u32(data, pos); pos = pos + 4
  if pos + gram_len > len { return None }
  let gram_bytes : Array[Byte] = []
  i = 0
  while i < gram_len { gram_bytes.push(data[pos + i]); i = i + 1 }
  let grammar_tree = match @grammar.GrammarTree::from_bytes(gram_bytes) {
    Some(t) => t
    None => return None
  }

  let ngram_size = if config.ngram_depth > 0 { config.ngram_depth } else { 3 }
  Some({
    config,
    void_state,
    grammar_tree,
    jitter: TapJitter::from_str(config.tap_id),
    frames_seen,
    flushes,
    recent_tags: Array::make(ngram_size, -1),
    recent_idx: 0,
    last_dir: Unknown,
    last_ts: 0,
    c2s_count,
    s2c_count,
    is_ai_flow,
    manifold: None,
  })
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn ftap_bucket(n : Int, bucket_size : Int) -> Int {
  let b = if bucket_size > 0 { bucket_size } else { 512 }
  (n / b) * b
}

///|
fn ftap_size_label(n : Int) -> String {
  if n < 512 { "xs" }
  else if n < 2048 { "sm" }
  else if n < 8192 { "md" }
  else if n < 32768 { "lg" }
  else { "xl" }
}

///|
fn ftap_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn ftap_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn ftap_write_str(buf : Array[Byte], s : String) -> Unit {
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
  ftap_write_u32(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

///|
fn ftap_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = ftap_read_u32(data, pos)
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
