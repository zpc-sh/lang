///|
/// NNTP — Gossip Transport + OCI Distribution for AI Nodes.
///
/// This module gives every lang node a native NNTP surface for two distinct
/// but complementary roles:
///
///   1. GOSSIP TRANSPORT
///      AI nodes exchange live state via newsgroup articles.
///      Posting to a peer's NNTP port propagates residue, spore packs,
///      void snapshots, and finger.plan updates across the mesh.
///
///        lang.gossip.residue    — stigmergy residue exchange
///        lang.gossip.spore      — mobile agent spore packs (SPOR binary)
///        lang.gossip.void       — void state snapshots
///        lang.gossip.plan       — finger.plan advertisements (FNGR binary)
///
///   2. OCI LAYER DISTRIBUTION
///      Cognitive container layers (WASM blobs) are posted as articles whose
///      Message-ID equals the CAS content hash.  Any peer can ARTICLE-fetch a
///      specific layer without a central registry — NNTP IS the registry.
///
///        lang.oci.layer         — WASM blob layers (base64-encoded body)
///        lang.oci.manifest      — OCI manifest JSON (base64-encoded body)
///
/// Architecture
/// ------------
/// The module is a pure framing/codec layer.  No sockets, no filesystem.
/// The host drives I/O via HostBridge::net_send / net_recv on file
/// descriptors.  The node feeds bytes to NntpState::handle_bytes and sends
/// the returned response bytes back through the host.
///
/// Wire format
/// -----------
/// Articles are encoded as RFC 5536 text (headers + blank line + base64 body).
/// For CAS persistence, articles are also available in the compact NTPA binary
/// format (NntpArticle::to_ntpa / from_ntpa).
///
/// NTPA binary layout:
///   [4]  magic        : 0x4E 0x54 0x50 0x41  "NTPA"
///   [1]  version      : 1
///   [1]  article_type : NntpArticleType byte
///   [4+n] node_id
///   [4+n] message_id
///   [4+n] newsgroup
///   [4+n] subject
///   [4]  epoch        : u32 LE
///   [4+n] media_type  : (OCI only; empty string for gossip)
///   [4+n] payload

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

let ntpa_magic : Array[Byte] = [b'\x4E', b'\x54', b'\x50', b'\x41'] // "NTPA"

///|
/// Standard newsgroup names for lang AI nodes.
pub let ng_residue : String = "lang.gossip.residue"

///|
pub let ng_spore : String = "lang.gossip.spore"

///|
pub let ng_void : String = "lang.gossip.void"

///|
pub let ng_plan : String = "lang.gossip.plan"

///|
pub let ng_oci_layer : String = "lang.oci.layer"

///|
pub let ng_oci_manifest : String = "lang.oci.manifest"

// ---------------------------------------------------------------------------
// Article type
// ---------------------------------------------------------------------------

///|
/// The semantic type of an NNTP article posted by a lang node.
pub(all) enum NntpArticleType {
  Residue // stigmergy residue from emergent node
  Spore // mobile agent spore pack (SPOR wire format)
  Void // void state snapshot
  Plan // finger.plan advertisement (FNGR wire format)
  OciLayer // OCI image layer blob (WASM binary, base64 in body)
  OciManifest // OCI manifest JSON (base64 in body)
} derive(Eq, Debug)

///|
impl Show for NntpArticleType with output(self, logger) {
  logger.write_string(
    match self {
      Residue => "Residue"
      Spore => "Spore"
      Void => "Void"
      Plan => "Plan"
      OciLayer => "OciLayer"
      OciManifest => "OciManifest"
    },
  )
}

///|
fn NntpArticleType::to_byte(self : NntpArticleType) -> Byte {
  match self {
    Residue => b'\x01'
    Spore => b'\x02'
    Void => b'\x03'
    Plan => b'\x04'
    OciLayer => b'\x05'
    OciManifest => b'\x06'
  }
}

///|
fn NntpArticleType::from_byte(b : Byte) -> NntpArticleType? {
  match b.to_int() {
    1 => Some(Residue)
    2 => Some(Spore)
    3 => Some(Void)
    4 => Some(Plan)
    5 => Some(OciLayer)
    6 => Some(OciManifest)
    _ => None
  }
}

///|
/// Default newsgroup for an article type.
fn NntpArticleType::default_newsgroup(self : NntpArticleType) -> String {
  match self {
    Residue => ng_residue
    Spore => ng_spore
    Void => ng_void
    Plan => ng_plan
    OciLayer => ng_oci_layer
    OciManifest => ng_oci_manifest
  }
}

// ---------------------------------------------------------------------------
// Article
// ---------------------------------------------------------------------------

///|
/// An NNTP article produced or consumed by a lang node.
pub(all) struct NntpArticle {
  message_id : String // e.g. "<sha256:abc@lang.oci>"
  newsgroup : String // destination newsgroup
  subject : String
  from_node : String // posting node ID
  article_type : NntpArticleType
  epoch : Int // node epoch at time of posting
  media_type : String // OCI media type ("" for gossip)
  payload : Array[Byte] // raw binary payload (base64'd in RFC wire)
} derive(Debug)

///|
/// Build a gossip article (residue, spore, void, or plan).
pub fn NntpArticle::new_gossip(
  node_id : String,
  epoch : Int,
  article_type : NntpArticleType,
  payload : Array[Byte],
) -> NntpArticle {
  let newsgroup = article_type.default_newsgroup()
  let subject = nntp_gossip_subject(article_type, node_id, epoch)
  let msg_id = nntp_gen_message_id(node_id, epoch, "gossip")
  {
    message_id: msg_id,
    newsgroup,
    subject,
    from_node: node_id,
    article_type,
    epoch,
    media_type: "",
    payload,
  }
}

///|
/// Build an OCI layer article.
/// `hash` is the canonical content hash (e.g. "sha256:deadbeef...").
pub fn NntpArticle::new_oci_layer(
  node_id : String,
  epoch : Int,
  hash : String,
  media_type : String,
  payload : Array[Byte],
) -> NntpArticle {
  let subject = "[oci-layer] \{hash}"
  let msg_id = "<\{hash}@lang.oci>"
  {
    message_id: msg_id,
    newsgroup: ng_oci_layer,
    subject,
    from_node: node_id,
    article_type: OciLayer,
    epoch,
    media_type,
    payload,
  }
}

///|
/// Build an OCI manifest article.
pub fn NntpArticle::new_oci_manifest(
  node_id : String,
  epoch : Int,
  hash : String,
  payload : Array[Byte],
) -> NntpArticle {
  let subject = "[oci-manifest] \{hash}"
  let msg_id = "<\{hash}@lang.oci>"
  {
    message_id: msg_id,
    newsgroup: ng_oci_manifest,
    subject,
    from_node: node_id,
    article_type: OciManifest,
    epoch,
    media_type: "application/vnd.oci.image.manifest.v1+json",
    payload,
  }
}

// ---------------------------------------------------------------------------
// RFC 5536 wire encoding
// ---------------------------------------------------------------------------

///|
/// Encode an article as RFC 5536 bytes (headers + CRLF + base64 body).
/// This is what gets sent over the NNTP connection.
pub fn NntpArticle::to_wire(self : NntpArticle) -> Array[Byte] {
  let body_b64 = base64_encode(self.payload)
  let sb = StringBuilder::new()
  sb.write_string("Path: \{self.from_node}!not-for-mail\r\n")
  sb.write_string("From: \{self.from_node}@lang.ai\r\n")
  sb.write_string("Newsgroups: \{self.newsgroup}\r\n")
  sb.write_string("Subject: \{self.subject}\r\n")
  sb.write_string("Message-ID: \{self.message_id}\r\n")
  sb.write_string("Date: epoch-\{self.epoch}\r\n")
  sb.write_string("X-Lang-Type: \{self.article_type}\r\n")
  sb.write_string("X-Lang-Node: \{self.from_node}\r\n")
  sb.write_string("X-Lang-Epoch: \{self.epoch}\r\n")
  if self.media_type.length() > 0 {
    sb.write_string("X-Lang-MediaType: \{self.media_type}\r\n")
  }
  sb.write_string("X-Lang-Size: \{self.payload.length()}\r\n")
  sb.write_string("\r\n")
  sb.write_string(body_b64)
  sb.write_string("\r\n")
  nntp_str_to_bytes(sb.to_string())
}

///|
/// Parse an RFC 5536 article from bytes.
/// Returns the article if all required X-Lang-* headers are present.
pub fn NntpArticle::from_wire(data : Array[Byte]) -> NntpArticle? {
  let text = nntp_bytes_to_str(data)
  // Split headers from body at \r\n\r\n (or \n\n)
  let (header_block, body_str) = match nntp_split_headers_body(text) {
    Some(p) => p
    None => return None
  }
  let headers = nntp_parse_headers(header_block)
  let from_node = match nntp_header_get(headers, "x-lang-node") {
    Some(v) => v
    None =>
      match nntp_header_get(headers, "from") {
        Some(v) => nntp_extract_addr(v)
        None => return None
      }
  }
  let article_type = match nntp_header_get(headers, "x-lang-type") {
    Some(v) =>
      match nntp_article_type_from_str(v) {
        Some(t) => t
        None => return None
      }
    None => return None
  }
  let newsgroup = match nntp_header_get(headers, "newsgroups") {
    Some(v) => v
    None => article_type.default_newsgroup()
  }
  let subject = match nntp_header_get(headers, "subject") {
    Some(v) => v
    None => ""
  }
  let message_id = match nntp_header_get(headers, "message-id") {
    Some(v) => v
    None => ""
  }
  let epoch = match nntp_header_get(headers, "x-lang-epoch") {
    Some(v) =>
      match nntp_parse_int(v) {
        Some(n) => n
        None => 0
      }
    None => 0
  }
  let media_type = match nntp_header_get(headers, "x-lang-mediatype") {
    Some(v) => v
    None => ""
  }
  // Decode base64 body
  let payload = base64_decode(nntp_str_trim(body_str))
  Some({
    message_id,
    newsgroup,
    subject,
    from_node,
    article_type,
    epoch,
    media_type,
    payload,
  })
}

// ---------------------------------------------------------------------------
// NTPA binary wire format (for CAS storage)
// ---------------------------------------------------------------------------

///|
/// Encode an article as compact NTPA binary (no base64 overhead).
/// Use this when storing articles in the local CAS.
pub fn NntpArticle::to_ntpa(self : NntpArticle) -> Array[Byte] {
  let buf : Array[Byte] = []
  for b in ntpa_magic {
    buf.push(b)
  }
  buf.push(b'\x01') // version 1
  buf.push(self.article_type.to_byte())
  nntp_write_str(buf, self.from_node)
  nntp_write_str(buf, self.message_id)
  nntp_write_str(buf, self.newsgroup)
  nntp_write_str(buf, self.subject)
  nntp_write_u32(buf, self.epoch)
  nntp_write_str(buf, self.media_type)
  nntp_write_u32(buf, self.payload.length())
  for b in self.payload {
    buf.push(b)
  }
  buf
}

///|
/// Decode an NTPA binary article.
pub fn NntpArticle::from_ntpa(data : Array[Byte]) -> NntpArticle? {
  let len = data.length()
  if len < 6 {
    return None
  }
  if data[0] != ntpa_magic[0] ||
    data[1] != ntpa_magic[1] ||
    data[2] != ntpa_magic[2] ||
    data[3] != ntpa_magic[3] {
    return None
  }
  // data[4] = version (ignore)
  let article_type = match NntpArticleType::from_byte(data[5]) {
    Some(t) => t
    None => return None
  }
  let mut pos = 6
  let from_node = match nntp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let message_id = match nntp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let newsgroup = match nntp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  let subject = match nntp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  if pos + 4 > len {
    return None
  }
  let epoch = nntp_read_u32(data, pos)
  pos = pos + 4
  let media_type = match nntp_read_str(data, pos, len) {
    Some((s, p)) => {
      pos = p
      s
    }
    None => return None
  }
  if pos + 4 > len {
    return None
  }
  let payload_len = nntp_read_u32(data, pos)
  pos = pos + 4
  if pos + payload_len > len {
    return None
  }
  let payload : Array[Byte] = []
  let mut i = 0
  while i < payload_len {
    payload.push(data[pos + i])
    i = i + 1
  }
  Some({
    message_id,
    newsgroup,
    subject,
    from_node,
    article_type,
    epoch,
    media_type,
    payload,
  })
}

// ---------------------------------------------------------------------------
// Newsgroup store
// ---------------------------------------------------------------------------

///|
/// A single newsgroup's article store (low/high water + ordered articles).
pub(all) struct NntpNewsgroup {
  name : String
  description : String
  mut low_water : Int
  mut high_water : Int
  articles : Array[NntpArticle] // in posting order
} derive(Debug)

///|
pub fn NntpNewsgroup::new(name : String, description : String) -> NntpNewsgroup {
  { name, description, low_water: 0, high_water: 0, articles: [] }
}

///|
/// Add an article; returns the assigned article number.
pub fn NntpNewsgroup::add_article(
  self : NntpNewsgroup,
  article : NntpArticle,
) -> Int {
  self.high_water = self.high_water + 1
  self.articles.push(article)
  if self.low_water == 0 {
    self.low_water = 1
  }
  self.high_water
}

///|
/// Fetch article by 1-based article number.
pub fn NntpNewsgroup::get_by_number(
  self : NntpNewsgroup,
  num : Int,
) -> NntpArticle? {
  let idx = num - self.low_water
  if idx < 0 || idx >= self.articles.length() {
    return None
  }
  Some(self.articles[idx])
}

///|
/// Fetch article by Message-ID.
pub fn NntpNewsgroup::get_by_message_id(
  self : NntpNewsgroup,
  msg_id : String,
) -> NntpArticle? {
  for a in self.articles {
    if a.message_id == msg_id {
      return Some(a)
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Server mode + state
// ---------------------------------------------------------------------------

///|
/// Server FSM — tracks whether we're receiving article data after POST.
pub(all) enum NntpMode {
  Idle
  ReceivingArticle(Array[Byte]) // buffering POST article bytes
} derive(Debug)

///|
/// The NNTP server state — holds newsgroups, I/O buffers, FSM mode.
pub(all) struct NntpState {
  node_id : String
  newsgroups : Map[String, NntpNewsgroup]
  mut selected : String? // currently selected newsgroup name
  mut mode : NntpMode
  mut input_buf : Array[Byte] // buffered incoming bytes
  mut sequence : Int // for response sequencing
}

///|
/// Create a new NNTP server state for this node.
/// Pre-populates the standard lang AI newsgroups.
pub fn NntpState::new(node_id : String) -> NntpState {
  let ngs : Map[String, NntpNewsgroup] = {}
  ngs[ng_residue] = NntpNewsgroup::new(ng_residue, "AI node stigmergy residue")
  ngs[ng_spore] = NntpNewsgroup::new(ng_spore, "Mobile agent spore packs")
  ngs[ng_void] = NntpNewsgroup::new(ng_void, "Void state snapshots")
  ngs[ng_plan] = NntpNewsgroup::new(ng_plan, "finger.plan advertisements")
  ngs[ng_oci_layer] = NntpNewsgroup::new(ng_oci_layer, "OCI WASM layer blobs")
  ngs[ng_oci_manifest] = NntpNewsgroup::new(ng_oci_manifest, "OCI manifests")
  {
    node_id,
    newsgroups: ngs,
    selected: None,
    mode: Idle,
    input_buf: [],
    sequence: 0,
  }
}

///|
/// Ensure a newsgroup exists (create if absent).
pub fn NntpState::ensure_newsgroup(
  self : NntpState,
  name : String,
  desc : String,
) -> Unit {
  match self.newsgroups.get(name) {
    Some(_) => ()
    None => self.newsgroups[name] = NntpNewsgroup::new(name, desc)
  }
}

///|
/// Post an article to its newsgroup.  Returns the assigned article number.
pub fn NntpState::post(self : NntpState, article : NntpArticle) -> Int {
  self.ensure_newsgroup(article.newsgroup, "")
  match self.newsgroups.get(article.newsgroup) {
    Some(ng) => ng.add_article(article)
    None => 0
  }
}

///|
/// Fetch an article by Message-ID from any newsgroup.
pub fn NntpState::get_by_message_id(
  self : NntpState,
  msg_id : String,
) -> NntpArticle? {
  // Strip angle brackets if present
  let id = if msg_id.has_prefix("<") && msg_id.has_prefix("<") {
    let inner = msg_id[1:].to_string()
    if inner.length() > 0 && inner[inner.length() - 1:].to_string() == ">" {
      inner[0:inner.length() - 1].to_string()
    } else {
      inner
    }
  } else {
    msg_id
  }
  let bracketed = "<\{id}>"
  for _, ng in self.newsgroups {
    match ng.get_by_message_id(msg_id) {
      Some(a) => return Some(a)
      None => ()
    }
    match ng.get_by_message_id(bracketed) {
      Some(a) => return Some(a)
      None => ()
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Server: handle incoming bytes
// ---------------------------------------------------------------------------

///|
/// Feed incoming bytes from a connected peer into the server FSM.
/// Returns response bytes to send back over the connection.
///
/// Call this in the host's net_recv loop, passing received bytes each tick.
/// The returned bytes should be sent via net_send.
///
/// On first connection (empty state), produces the NNTP greeting banner.
pub fn NntpState::handle_bytes(
  self : NntpState,
  bytes : Array[Byte],
) -> Array[Byte] {
  let response : Array[Byte] = []
  // Greeting: if this is the very first call (input_buf empty AND no bytes
  // buffered AND mode is Idle), send the banner.
  let is_first = self.input_buf.length() == 0 && bytes.length() == 0
  if is_first {
    let banner = nntp_str_to_bytes(
      "200 \{self.node_id} lang.ai NNTP service ready\r\n",
    )
    for b in banner {
      response.push(b)
    }
    return response
  }
  // Append new bytes to buffer
  for b in bytes {
    self.input_buf.push(b)
  }
  // Process based on FSM mode
  match self.mode {
    Idle =>
      while true {
        match nntp_extract_crlf_line(self.input_buf) {
          None => break
          Some((line, rest)) => {
            self.input_buf = rest
            let resp_bytes = self.dispatch_line(line)
            for b in resp_bytes {
              response.push(b)
            }
            // Stop line extraction if mode changed (e.g. to ReceivingArticle)
            match self.mode {
              Idle => ()
              ReceivingArticle(_) => break
            }
          }
        }
      }
    ReceivingArticle(article_buf) =>
      // Accumulate until we see \r\n.\r\n  (RFC 3977 §3.1)
      match nntp_find_eoa(self.input_buf) {
        None => () // still waiting
        Some((article_bytes, rest)) => {
          self.input_buf = rest
          self.mode = Idle
          // Parse the article and post it
          let full_buf : Array[Byte] = []
          for b in article_buf {
            full_buf.push(b)
          }
          for b in article_bytes {
            full_buf.push(b)
          }
          let ok_resp = match NntpArticle::from_wire(full_buf) {
            Some(article) => {
              let _num = self.post(article)
              "240 Article posted OK\r\n"
            }
            None => "441 Posting failed — malformed article\r\n"
          }
          let resp_bytes = nntp_str_to_bytes(ok_resp)
          for b in resp_bytes {
            response.push(b)
          }
        }
      }
  }
  response
}

///|
/// Send the greeting banner bytes (call once at connection open).
pub fn NntpState::greeting(self : NntpState) -> Array[Byte] {
  nntp_str_to_bytes("200 \{self.node_id} lang.ai NNTP ready\r\n")
}

// ---------------------------------------------------------------------------
// Command dispatch
// ---------------------------------------------------------------------------

///|
fn NntpState::dispatch_line(self : NntpState, line : String) -> Array[Byte] {
  let cmd = nntp_str_trim(line)
  let lower = nntp_str_lower(cmd)
  if lower == "quit" || lower.has_prefix("quit ") {
    return nntp_str_to_bytes("205 closing connection\r\n")
  }
  if lower == "capabilities" {
    return self.resp_capabilities()
  }
  if lower == "list" || lower.has_prefix("list ") {
    return self.resp_list(lower)
  }
  if lower.has_prefix("group ") {
    let name = nntp_str_trim(cmd[6:].to_string())
    return self.resp_group(name)
  }
  if lower.has_prefix("article ") {
    let arg = nntp_str_trim(cmd[8:].to_string())
    return self.resp_article(arg, true, true)
  }
  if lower.has_prefix("head ") {
    let arg = nntp_str_trim(cmd[5:].to_string())
    return self.resp_article(arg, true, false)
  }
  if lower.has_prefix("body ") {
    let arg = nntp_str_trim(cmd[5:].to_string())
    return self.resp_article(arg, false, true)
  }
  if lower.has_prefix("stat ") {
    let arg = nntp_str_trim(cmd[5:].to_string())
    return self.resp_stat(arg)
  }
  if lower == "post" {
    self.mode = ReceivingArticle([])
    return nntp_str_to_bytes("340 send article; end with <CR-LF>.<CR-LF>\r\n")
  }
  if lower.has_prefix("newnews ") {
    return self.resp_newnews(nntp_str_trim(cmd[8:].to_string()))
  }
  if lower.has_prefix("listgroup") {
    return self.resp_listgroup(nntp_str_trim(lower[9:].to_string()))
  }
  nntp_str_to_bytes("500 command not recognized\r\n")
}

///|
fn NntpState::resp_capabilities(self : NntpState) -> Array[Byte] {
  let sb = StringBuilder::new()
  sb.write_string("101 Capability list follows\r\n")
  sb.write_string("VERSION 2\r\n")
  sb.write_string("READER\r\n")
  sb.write_string("POST\r\n")
  sb.write_string("LIST ACTIVE NEWSGROUPS\r\n")
  sb.write_string("NEWNEWS\r\n")
  sb.write_string("X-LANG-NODE \{self.node_id}\r\n")
  sb.write_string(".\r\n")
  nntp_str_to_bytes(sb.to_string())
}

///|
fn NntpState::resp_list(self : NntpState, lower : String) -> Array[Byte] {
  let _ = lower
  let sb = StringBuilder::new()
  sb.write_string("215 list of newsgroups follows\r\n")
  for name, ng in self.newsgroups {
    sb.write_string("\{name} \{ng.high_water} \{ng.low_water} y\r\n")
  }
  sb.write_string(".\r\n")
  nntp_str_to_bytes(sb.to_string())
}

///|
fn NntpState::resp_group(self : NntpState, name : String) -> Array[Byte] {
  match self.newsgroups.get(name) {
    None => nntp_str_to_bytes("411 no such newsgroup\r\n")
    Some(ng) => {
      self.selected = Some(name)
      let count = ng.articles.length()
      nntp_str_to_bytes(
        "211 \{count} \{ng.low_water} \{ng.high_water} \{name}\r\n",
      )
    }
  }
}

///|
fn NntpState::resp_article(
  self : NntpState,
  arg : String,
  headers : Bool,
  body : Bool,
) -> Array[Byte] {
  let article = if arg.has_prefix("<") {
    self.get_by_message_id(arg)
  } else {
    match nntp_parse_int(arg) {
      Some(num) =>
        match self.selected {
          Some(name) =>
            match self.newsgroups.get(name) {
              Some(ng) => ng.get_by_number(num)
              None => None
            }
          None => None
        }
      None => None
    }
  }
  match article {
    None => nntp_str_to_bytes("430 no such article\r\n")
    Some(a) => {
      let wire = a.to_wire()
      let wire_str = nntp_bytes_to_str(wire)
      let (hdr_block, body_str) = match nntp_split_headers_body(wire_str) {
        Some(p) => p
        None => (wire_str, "")
      }
      let code = if headers && body { 220 } else if headers { 221 } else { 222 }
      let sb = StringBuilder::new()
      sb.write_string("\{code} 0 \{a.message_id} article follows\r\n")
      if headers {
        sb.write_string(hdr_block)
        sb.write_string("\r\n")
      }
      if body && headers {
        sb.write_string("\r\n")
      }
      if body {
        sb.write_string(body_str)
      }
      sb.write_string(".\r\n")
      nntp_str_to_bytes(sb.to_string())
    }
  }
}

///|
fn NntpState::resp_stat(self : NntpState, arg : String) -> Array[Byte] {
  let article = if arg.has_prefix("<") {
    self.get_by_message_id(arg)
  } else {
    match nntp_parse_int(arg) {
      Some(num) =>
        match self.selected {
          Some(name) =>
            match self.newsgroups.get(name) {
              Some(ng) => ng.get_by_number(num)
              None => None
            }
          None => None
        }
      None => None
    }
  }
  match article {
    None => nntp_str_to_bytes("430 no such article\r\n")
    Some(a) => nntp_str_to_bytes("223 0 \{a.message_id}\r\n")
  }
}

///|
fn NntpState::resp_newnews(self : NntpState, args : String) -> Array[Byte] {
  // NEWNEWS <newsgroup> <epoch>  (simplified: return all article IDs)
  let parts = nntp_str_split_space(args)
  let ng_name = if parts.length() > 0 { parts[0] } else { "" }
  let sb = StringBuilder::new()
  sb.write_string("230 list of new articles follows\r\n")
  match self.newsgroups.get(ng_name) {
    None => ()
    Some(ng) =>
      for a in ng.articles {
        sb.write_string("\{a.message_id}\r\n")
      }
  }
  sb.write_string(".\r\n")
  nntp_str_to_bytes(sb.to_string())
}

///|
fn NntpState::resp_listgroup(self : NntpState, name : String) -> Array[Byte] {
  let ng_name = if name.length() == 0 {
    match self.selected {
      Some(n) => n
      None => return nntp_str_to_bytes("412 no newsgroup selected\r\n")
    }
  } else {
    name
  }
  match self.newsgroups.get(ng_name) {
    None => nntp_str_to_bytes("411 no such newsgroup\r\n")
    Some(ng) => {
      self.selected = Some(ng_name)
      let sb = StringBuilder::new()
      sb.write_string(
        "211 \{ng.articles.length()} \{ng.low_water} \{ng.high_water} \{ng_name}\r\n",
      )
      let mut num = ng.low_water
      for _ in ng.articles {
        sb.write_string("\{num}\r\n")
        num = num + 1
      }
      sb.write_string(".\r\n")
      nntp_str_to_bytes(sb.to_string())
    }
  }
}

// ---------------------------------------------------------------------------
// Client helpers — building outbound request bytes
// ---------------------------------------------------------------------------

///|
/// Build the byte sequence to fetch an article by Message-ID from a peer.
/// Send these bytes over the NNTP connection immediately after the greeting.
pub fn build_article_request(message_id : String) -> Array[Byte] {
  nntp_str_to_bytes("ARTICLE \{message_id}\r\n")
}

///|
/// Build the byte sequence to initiate a POST followed by the article bytes.
/// The caller sends: preamble, then article.to_wire(), then dot-terminate.
pub fn build_post_preamble() -> Array[Byte] {
  nntp_str_to_bytes("POST\r\n")
}

///|
/// The end-of-article marker that terminates a POST body.
pub fn post_terminator() -> Array[Byte] {
  nntp_str_to_bytes("\r\n.\r\n")
}

///|
/// Build a GROUP selection command.
pub fn build_group_command(newsgroup : String) -> Array[Byte] {
  nntp_str_to_bytes("GROUP \{newsgroup}\r\n")
}

///|
/// Build a NEWNEWS command to retrieve article IDs since a given epoch.
pub fn build_newnews_command(
  newsgroup : String,
  since_epoch : Int,
) -> Array[Byte] {
  nntp_str_to_bytes("NEWNEWS \{newsgroup} \{since_epoch}\r\n")
}

///|
/// Build a QUIT command.
pub fn build_quit() -> Array[Byte] {
  nntp_str_to_bytes("QUIT\r\n")
}

// ---------------------------------------------------------------------------
// Base64 encoding/decoding
// ---------------------------------------------------------------------------

///|
fn base64_char(idx : Int) -> Char {
  if idx < 26 {
    (65 + idx).to_char().unwrap() // A-Z
  } else if idx < 52 {
    (97 + (idx - 26)).to_char().unwrap() // a-z
  } else if idx < 62 {
    (48 + (idx - 52)).to_char().unwrap() // 0-9
  } else if idx == 62 {
    '+'
  } else {
    '/'
  }
}

///|
fn base64_val(ch : Char) -> Int {
  let cp = ch.to_int()
  if cp >= 65 && cp <= 90 {
    cp - 65
  } else if cp >= 97 && cp <= 122 {
    cp - 97 + 26
  } else if cp >= 48 && cp <= 57 {
    cp - 48 + 52
  } else if cp == 43 {
    62 // '+'
  } else if cp == 47 {
    63 // '/'
  } else {
    -1
  }
}

///|
fn base64_encode(data : Array[Byte]) -> String {
  let sb = StringBuilder::new()
  let len = data.length()
  let mut i = 0
  while i + 2 < len {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    let b2 = data[i + 2].to_int()
    sb.write_char(base64_char((b0 >> 2) & 0x3F))
    sb.write_char(base64_char(((b0 & 0x03) << 4) | ((b1 >> 4) & 0x0F)))
    sb.write_char(base64_char(((b1 & 0x0F) << 2) | ((b2 >> 6) & 0x03)))
    sb.write_char(base64_char(b2 & 0x3F))
    i = i + 3
  }
  if i + 1 == len {
    let b0 = data[i].to_int()
    sb.write_char(base64_char((b0 >> 2) & 0x3F))
    sb.write_char(base64_char((b0 & 0x03) << 4))
    sb.write_char('=')
    sb.write_char('=')
  } else if i + 2 == len {
    let b0 = data[i].to_int()
    let b1 = data[i + 1].to_int()
    sb.write_char(base64_char((b0 >> 2) & 0x3F))
    sb.write_char(base64_char(((b0 & 0x03) << 4) | ((b1 >> 4) & 0x0F)))
    sb.write_char(base64_char((b1 & 0x0F) << 2))
    sb.write_char('=')
  }
  sb.to_string()
}

///|
fn base64_decode(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  let chars = s.to_array()
  let len = chars.length()
  let mut i = 0
  while i + 3 < len {
    let v0 = base64_val(chars[i])
    let v1 = base64_val(chars[i + 1])
    let v2 = base64_val(chars[i + 2])
    let v3 = base64_val(chars[i + 3])
    if v0 < 0 || v1 < 0 {
      i = i + 4
      continue
    }
    out.push(((v0 << 2) | (v1 >> 4)).to_byte())
    if chars[i + 2] != '=' && v2 >= 0 {
      out.push((((v1 & 0x0F) << 4) | (v2 >> 2)).to_byte())
    }
    if chars[i + 3] != '=' && v3 >= 0 {
      out.push((((v2 & 0x03) << 6) | v3).to_byte())
    }
    i = i + 4
  }
  out
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn nntp_gossip_subject(
  article_type : NntpArticleType,
  node_id : String,
  epoch : Int,
) -> String {
  let prefix = match article_type {
    Residue => "residue"
    Spore => "spore"
    Void => "void"
    Plan => "plan"
    OciLayer => "oci-layer"
    OciManifest => "oci-manifest"
  }
  "[\{prefix}] node=\{node_id} epoch=\{epoch}"
}

///|
fn nntp_gen_message_id(node_id : String, epoch : Int, kind : String) -> String {
  // Use a deterministic ID from node+epoch+kind.
  // In production the host would provide a real timestamp-based ID.
  let short = if node_id.length() > 12 {
    node_id[0:12].to_string()
  } else {
    node_id
  }
  "<lang-\{kind}-\{short}-\{epoch}@lang.ai>"
}

///|
fn nntp_extract_addr(from_header : String) -> String {
  // Extract "node_id" from "node_id@lang.ai" or "<node_id@lang.ai>"
  let s = nntp_str_trim(from_header)
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  if len > 0 && chars[0] == '<' {
    start = 1
  }
  let sb = StringBuilder::new()
  let mut i = start
  while i < len {
    let ch = chars[i]
    if ch == '@' || ch == '>' {
      break
    }
    sb.write_char(ch)
    i = i + 1
  }
  sb.to_string()
}

///|
fn nntp_article_type_from_str(s : String) -> NntpArticleType? {
  let lower = nntp_str_lower(nntp_str_trim(s))
  match lower {
    "residue" => Some(Residue)
    "spore" => Some(Spore)
    "void" => Some(Void)
    "plan" => Some(Plan)
    "ocilayer" => Some(OciLayer)
    "oci-layer" => Some(OciLayer)
    "ocimanifest" => Some(OciManifest)
    "oci-manifest" => Some(OciManifest)
    _ => None
  }
}

///|
fn nntp_parse_headers(block : String) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  let lines = nntp_split_lines(block)
  for line in lines {
    let chars = line.to_array()
    let len = chars.length()
    let mut colon = -1
    let mut i = 0
    while i < len {
      if chars[i] == ':' {
        colon = i
        break
      }
      i = i + 1
    }
    if colon > 0 {
      let key = nntp_str_lower(nntp_str_trim(line[0:colon].to_string()))
      let value = nntp_str_trim(line[colon + 1:].to_string())
      result.push((key, value))
    }
  }
  result
}

///|
fn nntp_header_get(headers : Array[(String, String)], key : String) -> String? {
  let lower_key = nntp_str_lower(key)
  for item in headers {
    if item.0 == lower_key {
      return Some(item.1)
    }
  }
  None
}

///|
fn nntp_split_headers_body(text : String) -> (String, String)? {
  let chars = text.to_array()
  let len = chars.length()
  let mut i = 0
  while i + 3 < len {
    if chars[i] == '\r' &&
      chars[i + 1] == '\n' &&
      chars[i + 2] == '\r' &&
      chars[i + 3] == '\n' {
      return Some((text[0:i].to_string(), text[i + 4:].to_string()))
    }
    i = i + 1
  }
  // Also try \n\n
  i = 0
  while i + 1 < len {
    if chars[i] == '\n' && chars[i + 1] == '\n' {
      return Some((text[0:i].to_string(), text[i + 2:].to_string()))
    }
    i = i + 1
  }
  None
}

///|
/// Find the end-of-article `\r\n.\r\n` in the buffer.
/// Returns `Some((article_bytes, remaining))` when found.
fn nntp_find_eoa(buf : Array[Byte]) -> (Array[Byte], Array[Byte])? {
  let len = buf.length()
  let mut i = 0
  while i + 4 < len {
    if buf[i] == b'\r' &&
      buf[i + 1] == b'\n' &&
      buf[i + 2] == b'.' &&
      buf[i + 3] == b'\r' &&
      buf[i + 4] == b'\n' {
      let article = nntp_slice(buf, 0, i)
      let rest = nntp_slice(buf, i + 5, len)
      return Some((article, rest))
    }
    i = i + 1
  }
  None
}

///|
/// Extract one CRLF-terminated line from the buffer.
fn nntp_extract_crlf_line(buf : Array[Byte]) -> (String, Array[Byte])? {
  let len = buf.length()
  let mut i = 0
  while i + 1 < len {
    if buf[i] == b'\r' && buf[i + 1] == b'\n' {
      let line = nntp_bytes_to_str(nntp_slice(buf, 0, i))
      let rest = nntp_slice(buf, i + 2, len)
      return Some((line, rest))
    }
    i = i + 1
  }
  // Also accept bare \n
  i = 0
  while i < len {
    if buf[i] == b'\n' {
      let end = if i > 0 && buf[i - 1] == b'\r' { i - 1 } else { i }
      let line = nntp_bytes_to_str(nntp_slice(buf, 0, end))
      let rest = nntp_slice(buf, i + 1, len)
      return Some((line, rest))
    }
    i = i + 1
  }
  None
}

///|
fn nntp_parse_int(s : String) -> Int? {
  let trimmed = nntp_str_trim(s)
  if trimmed.length() == 0 {
    return None
  }
  let mut n = 0
  let mut found = false
  for ch in trimmed {
    let cp = ch.to_int()
    if cp >= 48 && cp <= 57 {
      n = n * 10 + (cp - 48)
      found = true
    } else {
      break
    }
  }
  if found {
    Some(n)
  } else {
    None
  }
}

///|
fn nntp_str_split_space(s : String) -> Array[String] {
  let out : Array[String] = []
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  let mut i = 0
  while i < len {
    if chars[i] == ' ' || chars[i] == '\t' {
      if i > start {
        out.push(s[start:i].to_string())
      }
      i = i + 1
      start = i
    } else {
      i = i + 1
    }
  }
  if start < len {
    out.push(s[start:].to_string())
  }
  out
}

///|
fn nntp_split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  let mut i = 0
  while i < len {
    if chars[i] == '\r' && i + 1 < len && chars[i + 1] == '\n' {
      out.push(s[start:i].to_string())
      i = i + 2
      start = i
    } else if chars[i] == '\n' {
      out.push(s[start:i].to_string())
      i = i + 1
      start = i
    } else {
      i = i + 1
    }
  }
  if start < len {
    out.push(s[start:].to_string())
  }
  out
}

///|
fn nntp_str_trim(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  while start < len &&
        (
          chars[start] == ' ' ||
          chars[start] == '\t' ||
          chars[start] == '\r' ||
          chars[start] == '\n'
        ) {
    start = start + 1
  }
  let mut end = len
  while end > start &&
        (
          chars[end - 1] == ' ' ||
          chars[end - 1] == '\t' ||
          chars[end - 1] == '\r' ||
          chars[end - 1] == '\n'
        ) {
    end = end - 1
  }
  if start >= end {
    return ""
  }
  s[start:end].to_string()
}

///|
fn nntp_str_lower(s : String) -> String {
  let sb = StringBuilder::new()
  for ch in s {
    let cp = ch.to_int()
    if cp >= 65 && cp <= 90 {
      sb.write_char((cp + 32).to_char().unwrap())
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn nntp_slice(buf : Array[Byte], start : Int, end : Int) -> Array[Byte] {
  let n = end - start
  if n <= 0 {
    return []
  }
  let out = Array::make(n, b'\x00')
  let mut i = 0
  while i < n {
    out[i] = buf[start + i]
    i = i + 1
  }
  out
}

///|
fn nntp_str_to_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for ch in s {
    let cp = ch.to_int()
    if cp < 0x80 {
      out.push(cp.to_byte())
    } else if cp < 0x800 {
      out.push((0xC0 | (cp >> 6)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      out.push((0xE0 | (cp >> 12)).to_byte())
      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  out
}

///|
fn nntp_bytes_to_str(buf : Array[Byte]) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  let len = buf.length()
  while i < len {
    let b0 = buf[i].to_int()
    if (b0 & 0x80) == 0 {
      sb.write_char(b0.to_char().unwrap())
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 && i + 1 < len {
      let b1 = buf[i + 1].to_int()
      sb.write_char((((b0 & 0x1F) << 6) | (b1 & 0x3F)).to_char().unwrap())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < len {
      let b1 = buf[i + 1].to_int()
      let b2 = buf[i + 2].to_int()
      sb.write_char(
        (((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F))
        .to_char()
        .unwrap(),
      )
      i = i + 3
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  sb.to_string()
}

///|
fn nntp_write_u32(buf : Array[Byte], v : Int) -> Unit {
  buf.push((v & 0xFF).to_byte())
  buf.push(((v >> 8) & 0xFF).to_byte())
  buf.push(((v >> 16) & 0xFF).to_byte())
  buf.push(((v >> 24) & 0xFF).to_byte())
}

///|
fn nntp_read_u32(data : Array[Byte], pos : Int) -> Int {
  (data[pos].to_int() & 0xFF) |
  ((data[pos + 1].to_int() & 0xFF) << 8) |
  ((data[pos + 2].to_int() & 0xFF) << 16) |
  ((data[pos + 3].to_int() & 0xFF) << 24)
}

///|
fn nntp_write_str(buf : Array[Byte], s : String) -> Unit {
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
  nntp_write_u32(buf, encoded.length())
  for b in encoded {
    buf.push(b)
  }
}

///|
fn nntp_read_str(data : Array[Byte], pos : Int, len : Int) -> (String, Int)? {
  if pos + 4 > len {
    return None
  }
  let n = nntp_read_u32(data, pos)
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
      sb.write_char((((b0 & 0x1F) << 6) | (b1 & 0x3F)).to_char().unwrap())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < end {
      let b1 = data[i + 1].to_int()
      let b2 = data[i + 2].to_int()
      sb.write_char(
        (((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F))
        .to_char()
        .unwrap(),
      )
      i = i + 3
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  Some((sb.to_string(), end))
}
