///|
/// Gemini Protocol Codec — gemini.circumlunar.space / Project Gemini spec.
///
/// Gemini is a modern minimalist application protocol that sits between Gopher
/// and HTTP in complexity.  Key properties:
///
///   - TLS required (mandatory encryption, no plaintext fallback).
///   - ONE request per connection: URL + CRLF, then response header + body.
///   - Response header is a single line: `<STATUS> <META>\r\n`.
///   - Body is only present for 2x (SUCCESS) responses.
///   - Default content type is text/gemini (Gemtext markup).
///
/// AI nodes expose a Gemini surface on port 1965 for:
///
///   /                  root page — node identity + navigation links
///   /caps              protocol capabilities
///   /plugins           active plugin names
///   /peers             known peers
///   /finger.plan       node's finger.plan rendered as Gemtext
///   /wasm/node         node WASM binary (binary response)
///   /oci/<hash>        OCI layer by CAS hash (binary response)
///   /mulsp/<id>        mulsp state document
///   /cave/public       public cave keys
///   /nntp              NNTP newsgroup listing
///
/// Wire format
/// -----------
/// Request:   `gemini://host/path?query\r\n`   (max 1024 bytes including CRLF)
/// Response:  `<STATUS_CODE> <META>\r\n[BODY]`
///
/// Status codes (2-digit):
///   1x  INPUT           — server needs user input; META is the prompt
///   2x  SUCCESS         — META is the MIME type; body follows
///   3x  REDIRECT        — META is the redirect URL
///   4x  TEMP FAILURE    — transient error; META is the human-readable message
///   5x  PERM FAILURE    — permanent error; META is the message
///   6x  CERT REQUIRED   — client certificate required; META is the message
///
/// Architecture
/// ------------
/// Pure codec layer — no I/O.  The host drives networking.  Call
/// GeminiRequest::parse() on incoming bytes, dispatch via GeminiSelector,
/// then GeminiResponse::encode() to get bytes to send.

// ---------------------------------------------------------------------------
// Status codes
// ---------------------------------------------------------------------------

///|
/// Gemini response status codes.
pub(all) enum GeminiStatus {
  Input // 10 — server requires user input
  SensitiveInput // 11 — as Input but client must not display what is typed
  Success // 20 — request successful; body follows
  RedirectTemp // 30 — temporary redirect
  RedirectPerm // 31 — permanent redirect
  TempFailure // 40 — temporary failure
  ServerUnavail // 41 — server temporarily unavailable
  CgiError // 42 — CGI error
  ProxyError // 43 — proxy error
  SlowDown // 44 — rate limited; META is seconds to wait
  PermFailure // 50 — permanent failure
  NotFound // 51 — resource not found
  Gone // 52 — resource gone permanently
  ProxyRefused // 53 — proxy refused request
  BadRequest // 59 — bad request
  CertRequired // 60 — client certificate required
  CertNotAuth // 61 — certificate not authorised
  CertNotValid // 62 — certificate not valid
} derive(Eq, Debug)

///|
impl Show for GeminiStatus with output(self, logger) {
  logger.write_string(
    match self {
      Input => "Input"
      SensitiveInput => "SensitiveInput"
      Success => "Success"
      RedirectTemp => "RedirectTemp"
      RedirectPerm => "RedirectPerm"
      TempFailure => "TempFailure"
      ServerUnavail => "ServerUnavail"
      CgiError => "CgiError"
      ProxyError => "ProxyError"
      SlowDown => "SlowDown"
      PermFailure => "PermFailure"
      NotFound => "NotFound"
      Gone => "Gone"
      ProxyRefused => "ProxyRefused"
      BadRequest => "BadRequest"
      CertRequired => "CertRequired"
      CertNotAuth => "CertNotAuth"
      CertNotValid => "CertNotValid"
    },
  )
}

///|
pub fn GeminiStatus::to_code(self : GeminiStatus) -> Int {
  match self {
    Input => 10
    SensitiveInput => 11
    Success => 20
    RedirectTemp => 30
    RedirectPerm => 31
    TempFailure => 40
    ServerUnavail => 41
    CgiError => 42
    ProxyError => 43
    SlowDown => 44
    PermFailure => 50
    NotFound => 51
    Gone => 52
    ProxyRefused => 53
    BadRequest => 59
    CertRequired => 60
    CertNotAuth => 61
    CertNotValid => 62
  }
}

///|
pub fn GeminiStatus::from_code(code : Int) -> GeminiStatus {
  match code {
    10 => Input
    11 => SensitiveInput
    20 => Success
    30 => RedirectTemp
    31 => RedirectPerm
    40 => TempFailure
    41 => ServerUnavail
    42 => CgiError
    43 => ProxyError
    44 => SlowDown
    50 => PermFailure
    51 => NotFound
    52 => Gone
    53 => ProxyRefused
    59 => BadRequest
    60 => CertRequired
    61 => CertNotAuth
    62 => CertNotValid
    _ => TempFailure
  }
}

///|
/// True for status codes whose first digit is 2.
pub fn GeminiStatus::is_success(self : GeminiStatus) -> Bool {
  self == Success
}

///|
/// True for status codes whose first digit is 1.
pub fn GeminiStatus::needs_input(self : GeminiStatus) -> Bool {
  self == Input || self == SensitiveInput
}

///|
/// True for status codes whose first digit is 3.
pub fn GeminiStatus::is_redirect(self : GeminiStatus) -> Bool {
  self == RedirectTemp || self == RedirectPerm
}

// ---------------------------------------------------------------------------
// URL
// ---------------------------------------------------------------------------

///|
/// A parsed Gemini URL.
pub(all) struct GeminiUrl {
  host : String
  path : String
  query : String
} derive(Debug)

///|
/// Parse a Gemini URL string.  Accepts with or without the `gemini://` scheme.
/// Returns None if the string is empty after stripping the scheme.
pub fn GeminiUrl::parse(s : String) -> GeminiUrl? {
  let stripped = if s.has_prefix("gemini://") {
    s[9:].to_string()
  } else if s.has_prefix("//") {
    s[2:].to_string()
  } else {
    s
  }
  if stripped.length() == 0 {
    return None
  }
  let chars = stripped.to_array()
  let len = chars.length()
  // Find end of host (first '/' or '?' or end)
  let mut host_end = len
  let mut i = 0
  while i < len {
    if chars[i] == '/' || chars[i] == '?' {
      host_end = i
      break
    }
    i = i + 1
  }
  let host = stripped[0:host_end].to_string()
  let rest = if host_end < len { stripped[host_end:].to_string() } else { "/" }
  // Split path and query
  let rest_chars = rest.to_array()
  let rest_len = rest_chars.length()
  let mut q_pos = -1
  let mut j = 0
  while j < rest_len {
    if rest_chars[j] == '?' {
      q_pos = j
      break
    }
    j = j + 1
  }
  if q_pos >= 0 {
    let path = rest[0:q_pos].to_string()
    let query = rest[q_pos + 1:].to_string()
    Some({ host, path, query })
  } else {
    Some({ host, path: rest, query: "" })
  }
}

// ---------------------------------------------------------------------------
// Request
// ---------------------------------------------------------------------------

///|
/// A parsed Gemini request.
pub(all) struct GeminiRequest {
  url : GeminiUrl
  raw : String
} derive(Debug)

///|
/// Parse a Gemini request from raw bytes (max 1024 per spec).
/// Returns None if the bytes are not a valid Gemini request.
pub fn GeminiRequest::parse(data : Array[Byte]) -> GeminiRequest? {
  if data.length() > 1024 {
    return None
  }
  let raw = gemini_bytes_to_str(data)
  let trimmed = gemini_str_trim(raw)
  if trimmed.length() == 0 {
    return None
  }
  match GeminiUrl::parse(trimmed) {
    Some(url) => Some({ url, raw: trimmed })
    None => None
  }
}

// ---------------------------------------------------------------------------
// Selector routing
// ---------------------------------------------------------------------------

///|
/// Semantic meaning of a Gemini request path.
pub(all) enum GeminiSelector {
  Root // "/" or ""
  Caps // "/caps"
  Plugins // "/plugins"
  Peers // "/peers"
  FingerPlan // "/finger.plan"
  NodeWasm // "/wasm/node"
  OciLayer(String) // "/oci/<hash>"
  MulspState(String) // "/mulsp/<id>"
  CavePublic // "/cave/public"
  NntpGroups // "/nntp"
  Search(String) // "/search" with query
  Unknown(String) // unrecognised path
} derive(Debug)

///|
/// Route a GeminiRequest path to a semantic GeminiSelector.
pub fn GeminiRequest::selector(self : GeminiRequest) -> GeminiSelector {
  let path = gemini_str_trim(self.url.path)
  let lower = gemini_str_lower(path)
  if lower.length() == 0 || lower == "/" {
    return Root
  }
  if lower == "/caps" || lower == "caps" {
    return Caps
  }
  if lower == "/plugins" || lower == "plugins" {
    return Plugins
  }
  if lower == "/peers" || lower == "peers" {
    return Peers
  }
  if lower == "/finger.plan" || lower == "finger.plan" {
    return FingerPlan
  }
  if lower == "/wasm/node" || lower == "wasm/node" {
    return NodeWasm
  }
  if lower == "/cave/public" || lower == "cave/public" {
    return CavePublic
  }
  if lower == "/nntp" || lower == "nntp" {
    return NntpGroups
  }
  if lower.has_prefix("/oci/") {
    let hash = path[5:].to_string()
    return OciLayer(hash)
  }
  if lower.has_prefix("oci/") {
    let hash = path[4:].to_string()
    return OciLayer(hash)
  }
  if lower.has_prefix("/mulsp/") {
    let id = path[7:].to_string()
    return MulspState(id)
  }
  if lower.has_prefix("mulsp/") {
    let id = path[6:].to_string()
    return MulspState(id)
  }
  if lower == "/search" || lower == "search" {
    return Search(self.url.query)
  }
  Unknown(path)
}

// ---------------------------------------------------------------------------
// Response
// ---------------------------------------------------------------------------

///|
/// A Gemini response ready for wire encoding.
pub(all) struct GeminiResponse {
  status : GeminiStatus
  meta : String
  body : Array[Byte]
} derive(Debug)

///|
/// Successful response with explicit MIME type and body.
pub fn GeminiResponse::success(
  mime : String,
  body : Array[Byte],
) -> GeminiResponse {
  { status: Success, meta: mime, body }
}

///|
/// Successful Gemtext response (most common case).
pub fn GeminiResponse::gemtext(body : Array[Byte]) -> GeminiResponse {
  { status: Success, meta: "text/gemini; charset=utf-8", body }
}

///|
/// Successful binary response (WASM, OCI layers, etc.).
pub fn GeminiResponse::binary(body : Array[Byte]) -> GeminiResponse {
  { status: Success, meta: "application/octet-stream", body }
}

///|
/// Prompt the user for input.
pub fn GeminiResponse::input(prompt : String) -> GeminiResponse {
  { status: Input, meta: prompt, body: [] }
}

///|
/// Sensitive input (password-like; client must not echo characters).
pub fn GeminiResponse::sensitive_input(prompt : String) -> GeminiResponse {
  { status: SensitiveInput, meta: prompt, body: [] }
}

///|
/// Temporary redirect.
pub fn GeminiResponse::redirect_temp(url : String) -> GeminiResponse {
  { status: RedirectTemp, meta: url, body: [] }
}

///|
/// Permanent redirect.
pub fn GeminiResponse::redirect_perm(url : String) -> GeminiResponse {
  { status: RedirectPerm, meta: url, body: [] }
}

///|
/// Resource not found (51).
pub fn GeminiResponse::not_found(msg : String) -> GeminiResponse {
  { status: NotFound, meta: msg, body: [] }
}

///|
/// Temporary failure with human-readable message.
pub fn GeminiResponse::temp_failure(msg : String) -> GeminiResponse {
  { status: TempFailure, meta: msg, body: [] }
}

///|
/// Permanent failure with human-readable message.
pub fn GeminiResponse::perm_failure(msg : String) -> GeminiResponse {
  { status: PermFailure, meta: msg, body: [] }
}

///|
/// Rate limiting response.  `seconds` is the retry-after hint.
pub fn GeminiResponse::slow_down(seconds : Int) -> GeminiResponse {
  { status: SlowDown, meta: "\{seconds}", body: [] }
}

///|
/// Client certificate required.
pub fn GeminiResponse::cert_required(msg : String) -> GeminiResponse {
  { status: CertRequired, meta: msg, body: [] }
}

///|
/// Encode a GeminiResponse to wire bytes.
/// Format: `<CODE> <META>\r\n[BODY]`
pub fn GeminiResponse::encode(self : GeminiResponse) -> Array[Byte] {
  let code = self.status.to_code()
  let header = "\{code} \{self.meta}\r\n"
  let out : Array[Byte] = []
  for b in gemini_str_to_bytes(header) {
    out.push(b)
  }
  for b in self.body {
    out.push(b)
  }
  out
}

///|
/// Decode a Gemini response header line from bytes.
/// Returns (status, meta) or None on parse failure.
pub fn GeminiResponse::decode_header(
  data : Array[Byte],
) -> (GeminiStatus, String)? {
  let s = gemini_str_trim(gemini_bytes_to_str(data))
  if s.length() < 2 {
    return None
  }
  let chars = s.to_array()
  // First two chars must be ASCII digits
  let d0 = chars[0].to_int() - 48
  let d1 = chars[1].to_int() - 48
  if d0 < 0 || d0 > 9 || d1 < 0 || d1 > 9 {
    return None
  }
  let code = d0 * 10 + d1
  let status = GeminiStatus::from_code(code)
  let meta = if s.length() > 3 {
    gemini_str_trim(s[3:].to_string())
  } else {
    ""
  }
  Some((status, meta))
}

// ---------------------------------------------------------------------------
// High-level dispatch
// ---------------------------------------------------------------------------

///|
/// Dispatch a parsed GeminiRequest to a GeminiResponse.
///
/// The host provides:
///   - Current node state (node_id, epoch, mode, tier, overlay, has_mulsp)
///   - Plugin and peer lists for menu construction
///   - `lookup_blob` callback for serving CAS content (WASM, OCI layers, etc.)
///   - `nntp_groups` for the newsgroup listing
pub fn dispatch_request(
  req : GeminiRequest,
  node_id : String,
  epoch : Int,
  mode : String,
  tier : String,
  overlay : String,
  has_mulsp : Bool,
  plugins : Array[String],
  peers : Array[(String, String, String)], // (id, tier, endpoint)
  oci_types : Array[String],
  nntp_groups : Array[(String, Int, Int)], // (name, low, high)
  lookup_blob : (String) -> Array[Byte]?,
) -> GeminiResponse {
  let sel = req.selector()
  match sel {
    Root => {
      let doc = @gemtext.build_node_root_page(
        node_id,
        epoch,
        mode,
        tier,
        plugins.length(),
        peers.length(),
      )
      GeminiResponse::gemtext(doc.to_bytes())
    }
    Caps => {
      let protocols = [
        "gemini  port 1965",
        "gopher  port 70",
        "nntp    port 119",
        "lsp     stdio / port 2087",
      ]
      let doc = @gemtext.build_caps_page(
        node_id, overlay, tier, has_mulsp, oci_types, protocols,
      )
      GeminiResponse::gemtext(doc.to_bytes())
    }
    Plugins => {
      let doc = @gemtext.build_plugins_page(node_id, plugins)
      GeminiResponse::gemtext(doc.to_bytes())
    }
    Peers => {
      let doc = @gemtext.build_peers_page(node_id, peers)
      GeminiResponse::gemtext(doc.to_bytes())
    }
    FingerPlan =>
      match lookup_blob("finger.plan") {
        Some(data) => {
          let plan_text = gemini_bytes_to_str(data)
          let doc = @gemtext.build_finger_plan_page(plan_text)
          GeminiResponse::gemtext(doc.to_bytes())
        }
        None =>
          GeminiResponse::gemtext(
            @gemtext.build_finger_plan_page("(no finger.plan available)").to_bytes(),
          )
      }
    NodeWasm =>
      match lookup_blob("node.wasm") {
        Some(data) => GeminiResponse::binary(data)
        None => GeminiResponse::not_found("node.wasm not available")
      }
    OciLayer(hash) =>
      match lookup_blob("oci:\{hash}") {
        Some(data) => GeminiResponse::binary(data)
        None => GeminiResponse::not_found("OCI layer \{hash} not found")
      }
    MulspState(id) =>
      match lookup_blob("mulsp:\{id}") {
        Some(data) =>
          GeminiResponse::success("text/plain; charset=utf-8", data)
        None =>
          GeminiResponse::gemtext(
            @gemtext.build_error_page("/mulsp/\{id}").to_bytes(),
          )
      }
    CavePublic =>
      match lookup_blob("cave.public") {
        Some(data) =>
          GeminiResponse::success("text/plain; charset=utf-8", data)
        None =>
          GeminiResponse::gemtext(
            @gemtext.build_error_page("/cave/public").to_bytes(),
          )
      }
    NntpGroups => {
      let doc = @gemtext.build_nntp_groups_page(node_id, nntp_groups)
      GeminiResponse::gemtext(doc.to_bytes())
    }
    Search(_q) =>
      GeminiResponse::input("Enter search query for CAS:")
    Unknown(path) =>
      GeminiResponse::not_found("not found: \{path}")
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn gemini_str_trim(s : String) -> String {
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
fn gemini_str_lower(s : String) -> String {
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
fn gemini_str_to_bytes(s : String) -> Array[Byte] {
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
fn gemini_bytes_to_str(buf : Array[Byte]) -> String {
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
