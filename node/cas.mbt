///|
/// CAS Wrapper — content-addressed storage operations for the node.
///
/// The node's CAS is backed by the host bridge's blob_put/blob_get/blob_has.
/// This wrapper adds:
///   - Content hashing (blake3-style via FNV-1a for now)
///   - Envelope wrapping (content type + metadata)
///   - Ingest pipeline (hash → store → anchor)
///   - Query by hash key
///
/// In production, this delegates to Merkin's CAS store. In testing,
/// it uses the stub host bridge's in-memory map.
///
/// Wire format for envelopes:
///   [4]  magic      : 0x43 0x41 0x53 0x45  "CASE"
///   [4]  version    : u32 LE
///   [4]  content_type_len : u32 LE
///   [n]  content_type : utf8
///   [4]  data_len   : u32 LE
///   [n]  data       : raw bytes

let cas_magic : Array[Byte] = [b'\x43', b'\x41', b'\x53', b'\x45'] // "CASE"
let cas_version : Int = 1

// ---------------------------------------------------------------------------
// Hash key generation
// ---------------------------------------------------------------------------

///|
/// Generate a content hash key from raw bytes.
/// Uses FNV-1a (32-bit) as a lightweight stand-in for blake3.
/// Returns a hex string key.
pub fn cas_hash(data : Array[Byte]) -> String {
  let mut h = 0x811C9DC5
  for b in data {
    h = h ^ (b.to_int() & 0xFF)
    h = h * 0x01000193
  }
  // Produce 8-char hex
  cas_int_to_hex(h)
}

// ---------------------------------------------------------------------------
// Envelope
// ---------------------------------------------------------------------------

///|
/// A CAS envelope — content type + raw data.
pub(all) struct CasEnvelope {
  content_type : String     // MIME-like type tag
  data         : Array[Byte]
  hash_key     : String     // computed on construction
} derive(Debug)

///|
impl Show for CasEnvelope with output(self, logger) {
  logger.write_string("CasEnvelope(type=\{self.content_type}, key=\{self.hash_key}, size=\{self.data.length()})")
}

///|
/// Wrap raw data in a CAS envelope.
pub fn CasEnvelope::wrap(content_type : String, data : Array[Byte]) -> CasEnvelope {
  let hash_key = cas_hash(data)
  { content_type, data, hash_key }
}

///|
/// Serialize the envelope to wire bytes.
pub fn CasEnvelope::to_bytes(self : CasEnvelope) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in cas_magic { buf.push(b) }
  cas_write_u32(buf, cas_version)
  cas_write_str(buf, self.content_type)
  cas_write_u32(buf, self.data.length())
  for b in self.data { buf.push(b) }
  buf
}

///|
/// Deserialize an envelope from wire bytes.
pub fn CasEnvelope::from_bytes(raw : Array[Byte]) -> CasEnvelope? {
  let len = raw.length()
  if len < 12 { return None }
  if raw[0] != cas_magic[0] || raw[1] != cas_magic[1] ||
     raw[2] != cas_magic[2] || raw[3] != cas_magic[3] { return None }
  let mut pos = 4
  let _ver = cas_read_u32(raw, pos); pos = pos + 4
  let content_type = match cas_read_str(raw, pos, len) {
    Some((s, p)) => { pos = p; s }
    None => return None
  }
  if pos + 4 > len { return None }
  let data_len = cas_read_u32(raw, pos); pos = pos + 4
  if pos + data_len > len { return None }
  let data : Array[Byte] = []
  let mut i = 0
  while i < data_len {
    data.push(raw[pos + i])
    i = i + 1
  }
  let hash_key = cas_hash(data)
  Some({ content_type, data, hash_key })
}

// ---------------------------------------------------------------------------
// CAS Store
// ---------------------------------------------------------------------------

///|
/// The node's CAS — wraps the host bridge for content-addressed storage.
pub(all) struct CasStore {
  host           : HostBridge
  mut put_count  : Int
  mut get_count  : Int
  mut hit_count  : Int
  mut miss_count : Int
}

///|
pub fn CasStore::new(host : HostBridge) -> CasStore {
  { host, put_count: 0, get_count: 0, hit_count: 0, miss_count: 0 }
}

///|
/// Ingest raw bytes into the CAS. Returns the hash key.
pub fn CasStore::ingest(
  self : CasStore,
  content_type : String,
  data : Array[Byte],
) -> String {
  let envelope = CasEnvelope::wrap(content_type, data)
  let wire = envelope.to_bytes()
  ignore((self.host.blob_put)(envelope.hash_key, wire))
  self.put_count = self.put_count + 1
  (self.host.log_trace)("cas: ingest key=\{envelope.hash_key} type=\{content_type} size=\{data.length()}")
  envelope.hash_key
}

///|
/// Ingest raw bytes without envelope wrapping (for pre-enveloped data).
pub fn CasStore::ingest_raw(self : CasStore, key : String, data : Array[Byte]) -> Bool {
  let ok = (self.host.blob_put)(key, data)
  if ok { self.put_count = self.put_count + 1 }
  ok
}

///|
/// Query the CAS by hash key. Returns the envelope if found.
pub fn CasStore::query(self : CasStore, key : String) -> CasEnvelope? {
  self.get_count = self.get_count + 1
  match (self.host.blob_get)(key) {
    Some(wire) => {
      self.hit_count = self.hit_count + 1
      CasEnvelope::from_bytes(wire)
    }
    None => {
      self.miss_count = self.miss_count + 1
      None
    }
  }
}

///|
/// Check if a key exists in the CAS.
pub fn CasStore::has(self : CasStore, key : String) -> Bool {
  (self.host.blob_has)(key)
}

///|
/// Get raw bytes by key (no envelope unwrapping).
pub fn CasStore::get_raw(self : CasStore, key : String) -> Array[Byte]? {
  self.get_count = self.get_count + 1
  match (self.host.blob_get)(key) {
    Some(data) => { self.hit_count = self.hit_count + 1; Some(data) }
    None       => { self.miss_count = self.miss_count + 1; None }
  }
}

///|
/// CAS statistics.
pub(all) struct CasStats {
  put_count  : Int
  get_count  : Int
  hit_count  : Int
  miss_count : Int
  hit_rate   : Int    // percentage 0-100
} derive(Debug)

///|
pub fn CasStore::stats(self : CasStore) -> CasStats {
  let hit_rate = if self.get_count > 0 {
    (self.hit_count * 100) / self.get_count
  } else {
    0
  }
  {
    put_count: self.put_count,
    get_count: self.get_count,
    hit_count: self.hit_count,
    miss_count: self.miss_count,
    hit_rate,
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn cas_int_to_hex(v : Int) -> String {
  let hex = "0123456789abcdef"
  let hex_chars = hex.to_array()
  let sb = StringBuilder::new()
  let mut i = 28
  while i >= 0 {
    let nibble = (v >> i) & 0x0F
    sb.write_char(hex_chars[nibble])
    i = i - 4
  }
  sb.to_string()
}

///|
fn cas_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn cas_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF)
  | ((data[pos + 1].to_int() & 0xFF) << 8)
  | ((data[pos + 2].to_int() & 0xFF) << 16)
  | ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn cas_write_str(buf : Array[Byte], s : String) -> Unit {
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
  cas_write_u32(buf, encoded.length())
  for b in encoded { buf.push(b) }
}

///|
fn cas_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len { return None }
  let n = cas_read_u32(data, pos)
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
