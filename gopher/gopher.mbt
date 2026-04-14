///|
/// Gopher — Fast Capability Discovery + WASM/OCI Serving for AI Nodes.
///
/// The Gopher protocol (RFC 1436) is exceptionally well-suited for AI node
/// communication because:
///
///   - A request is ONE LINE: selector string + CRLF.  Zero setup.
///   - A binary response is the raw bytes, nothing else.  No HTTP overhead,
///     no framing, no content negotiation.
///   - The hierarchical menu metaphor maps cleanly to capability trees.
///   - Round-trip for a WASM blob: connect → selector → binary stream → close.
///
/// AI nodes expose a Gopher surface on port 70 for:
///
///   /                  root menu — node identity + capability categories
///   /caps              protocol capabilities (mulsp tier, OCI media types)
///   /plugins           active plugin names
///   /peers             known peers (node IDs + endpoints)
///   /finger.plan       the node's finger.plan in FNGR binary, served as type 9
///   /wasm/node         the node WASM binary itself (type 9 = binary)
///   /oci/<hash>        OCI layer by CAS hash (type 9)
///   /mulsp/<id>        mulsp state document (type 0 = text)
///   /cave/public       public cave keys (type 0)
///   /nntp              NNTP newsgroup listing (type 0)
///
/// Architecture
/// ------------
/// Like all lang protocol modules, this is a pure codec layer.  The host
/// drives I/O.  Call parse_request() on incoming bytes, dispatch via
/// GopherSelector, then encode_response() to get bytes to send.
///
/// Gopher wire format
/// ------------------
/// Request:  <selector>\r\n        (empty selector = root menu)
/// Response (type 1 menu):
///   <type><display>\t<selector>\t<host>\t<port>\r\n  ... per item
///   .\r\n                          (terminator)
/// Response (type 0 text):   raw UTF-8 text bytes
/// Response (type 9 binary): raw binary bytes
///
/// Item types used here:
///   '0' — text file
///   '1' — submenu / directory
///   '9' — binary file (WASM blobs, OCI layers, finger.plan)
///   '7' — search query
///   'i' — info line (non-selectable)
///   '3' — error

// ---------------------------------------------------------------------------
// Item types
// ---------------------------------------------------------------------------

///|
/// Gopher item type characters (RFC 1436 §3.8 + common extensions).
pub(all) enum GopherItemType {
  Text // '0' — plain text document
  Menu // '1' — submenu (another Gopher menu)
  Binary // '9' — binary file (e.g. WASM blob, OCI layer)
  Search // '7' — search service
  Info // 'i' — informational line (non-selectable, display only)
  Error // '3' — error / inline error message
} derive(Eq, Debug)

///|
impl Show for GopherItemType with output(self, logger) {
  logger.write_string(
    match self {
      Text => "Text"
      Menu => "Menu"
      Binary => "Binary"
      Search => "Search"
      Info => "Info"
      Error => "Error"
    },
  )
}

///|
fn GopherItemType::to_char(self : GopherItemType) -> Char {
  match self {
    Text => '0'
    Menu => '1'
    Binary => '9'
    Search => '7'
    Info => 'i'
    Error => '3'
  }
}

///|
fn GopherItemType::from_char(ch : Char) -> GopherItemType? {
  match ch {
    '0' => Some(Text)
    '1' => Some(Menu)
    '9' => Some(Binary)
    '7' => Some(Search)
    'i' => Some(Info)
    '3' => Some(Error)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Gopher menu item
// ---------------------------------------------------------------------------

///|
/// A single line in a Gopher menu.
pub(all) struct GopherItem {
  item_type : GopherItemType
  display : String // human-readable display text
  selector : String // request path (empty for Info/Error)
  host : String // server hostname
  port : Int // server port
} derive(Debug)

///|
pub fn GopherItem::text(
  display : String,
  selector : String,
  host : String,
  port : Int,
) -> GopherItem {
  { item_type: Text, display, selector, host, port }
}

///|
pub fn GopherItem::menu(
  display : String,
  selector : String,
  host : String,
  port : Int,
) -> GopherItem {
  { item_type: Menu, display, selector, host, port }
}

///|
pub fn GopherItem::binary(
  display : String,
  selector : String,
  host : String,
  port : Int,
) -> GopherItem {
  { item_type: Binary, display, selector, host, port }
}

///|
pub fn GopherItem::search(
  display : String,
  selector : String,
  host : String,
  port : Int,
) -> GopherItem {
  { item_type: Search, display, selector, host, port }
}

///|
pub fn GopherItem::info(text : String) -> GopherItem {
  { item_type: Info, display: text, selector: "", host: "error.host", port: 1 }
}

///|
pub fn GopherItem::error(text : String) -> GopherItem {
  { item_type: Error, display: text, selector: "", host: "error.host", port: 1 }
}

///|
/// Encode a single item as a Gopher protocol line (without CRLF).
pub fn GopherItem::encode_line(self : GopherItem) -> String {
  let type_char = self.item_type.to_char()
  "\{type_char}\{self.display}\t\{self.selector}\t\{self.host}\t\{self.port}"
}

// ---------------------------------------------------------------------------
// Gopher menu
// ---------------------------------------------------------------------------

///|
/// A Gopher menu — a collection of typed items.
pub(all) struct GopherMenu {
  items : Array[GopherItem]
} derive(Debug)

///|
pub fn GopherMenu::new() -> GopherMenu {
  { items: [] }
}

///|
pub fn GopherMenu::add_info(self : GopherMenu, text : String) -> Unit {
  self.items.push(GopherItem::info(text))
}

///|
pub fn GopherMenu::add_menu(
  self : GopherMenu,
  display : String,
  selector : String,
  host : String,
  port : Int,
) -> Unit {
  self.items.push(GopherItem::menu(display, selector, host, port))
}

///|
pub fn GopherMenu::add_text(
  self : GopherMenu,
  display : String,
  selector : String,
  host : String,
  port : Int,
) -> Unit {
  self.items.push(GopherItem::text(display, selector, host, port))
}

///|
pub fn GopherMenu::add_binary(
  self : GopherMenu,
  display : String,
  selector : String,
  host : String,
  port : Int,
) -> Unit {
  self.items.push(GopherItem::binary(display, selector, host, port))
}

///|
pub fn GopherMenu::add_search(
  self : GopherMenu,
  display : String,
  selector : String,
  host : String,
  port : Int,
) -> Unit {
  self.items.push(GopherItem::search(display, selector, host, port))
}

///|
pub fn GopherMenu::add_error(self : GopherMenu, text : String) -> Unit {
  self.items.push(GopherItem::error(text))
}

///|
/// Encode the menu as Gopher wire bytes (items + `.\r\n` terminator).
pub fn GopherMenu::encode(self : GopherMenu) -> Array[Byte] {
  let sb = StringBuilder::new()
  for item in self.items {
    sb.write_string(item.encode_line())
    sb.write_string("\r\n")
  }
  sb.write_string(".\r\n")
  gopher_str_to_bytes(sb.to_string())
}

///|
/// Number of items in the menu.
pub fn GopherMenu::item_count(self : GopherMenu) -> Int {
  self.items.length()
}

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------

///|
/// A parsed Gopher request.
pub(all) struct GopherRequest {
  selector : String // the raw selector string (may be empty for root)
  query : String // search query portion (after \t in type-7 requests)
} derive(Debug)

///|
/// Parse a Gopher request from incoming bytes.
/// Accepts `<selector>\r\n` or `<selector>\t<query>\r\n`.
pub fn GopherRequest::parse(bytes : Array[Byte]) -> GopherRequest? {
  let text = gopher_bytes_to_str(bytes)
  let trimmed = gopher_str_trim(text)
  if trimmed.length() == 0 {
    return Some({ selector: "/", query: "" })
  }
  // Split at first tab (search query)
  let chars = trimmed.to_array()
  let len = chars.length()
  let mut tab_pos = -1
  let mut i = 0
  while i < len {
    if chars[i] == '\t' {
      tab_pos = i
      break
    }
    i = i + 1
  }
  if tab_pos > 0 {
    let selector = trimmed[0:tab_pos].to_string()
    let query = trimmed[tab_pos + 1:].to_string()
    Some({ selector, query })
  } else {
    Some({ selector: trimmed, query: "" })
  }
}

// ---------------------------------------------------------------------------
// Selector routing
// ---------------------------------------------------------------------------

///|
/// Parsed semantic meaning of a Gopher selector.
pub(all) enum GopherSelector {
  Root // "" or "/" — node root menu
  Capabilities // "/caps"
  Plugins // "/plugins"
  Peers // "/peers"
  FingerPlan // "/finger.plan"
  NodeWasm // "/wasm/node"
  OciLayer(String) // "/oci/<hash>"
  MulspState(String) // "/mulsp/<id>"
  CavePublic // "/cave/public"
  NntpGroups // "/nntp" — list NNTP newsgroups
  Search(String) // "/search" with query
  Unknown(String) // unrecognised selector
} derive(Debug)

///|
/// Route a raw selector string to a semantic GopherSelector.
pub fn GopherSelector::from_string(selector : String) -> GopherSelector {
  let s = gopher_str_trim(selector)
  if s.length() == 0 || s == "/" {
    return Root
  }
  let lower = gopher_str_lower(s)
  if lower == "/caps" || lower == "caps" {
    return Capabilities
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
    let hash = s[5:].to_string()
    return OciLayer(hash)
  }
  if lower.has_prefix("oci/") {
    let hash = s[4:].to_string()
    return OciLayer(hash)
  }
  if lower.has_prefix("/mulsp/") {
    let id = s[7:].to_string()
    return MulspState(id)
  }
  if lower.has_prefix("mulsp/") {
    let id = s[6:].to_string()
    return MulspState(id)
  }
  if lower == "/search" || lower == "search" {
    return Search("")
  }
  Unknown(s)
}

// ---------------------------------------------------------------------------
// Response type
// ---------------------------------------------------------------------------

///|
/// A Gopher response — either a menu or raw bytes.
pub(all) enum GopherResponse {
  Menu(GopherMenu) // type-1 menu
  Bytes(Array[Byte]) // type-0 / type-9 raw bytes
  NotFound // 404 equivalent (Gopher error item)
} derive(Debug)

///|
/// Encode a GopherResponse to wire bytes.
pub fn GopherResponse::encode(self : GopherResponse) -> Array[Byte] {
  match self {
    Menu(menu) => menu.encode()
    Bytes(data) => data
    NotFound => {
      let m = GopherMenu::new()
      m.add_error("resource not found")
      m.encode()
    }
  }
}

// ---------------------------------------------------------------------------
// Node menu builders
// ---------------------------------------------------------------------------

///|
/// Build the root menu for an AI node.
pub fn build_node_root_menu(
  node_id : String,
  epoch : Int,
  mode : String,
  tier : String,
  plugin_count : Int,
  peer_count : Int,
  host : String,
  port : Int,
) -> GopherMenu {
  let m = GopherMenu::new()
  m.add_info("Lang AI Node")
  m.add_info("  id:      \{node_id}")
  m.add_info("  epoch:   \{epoch}")
  m.add_info("  mode:    \{mode}")
  m.add_info("  tier:    \{tier}")
  m.add_info("  plugins: \{plugin_count}")
  m.add_info("  peers:   \{peer_count}")
  m.add_info("")
  m.add_menu("Capabilities", "/caps", host, port)
  m.add_menu("Plugins (\{plugin_count})", "/plugins", host, port)
  m.add_menu("Peers (\{peer_count})", "/peers", host, port)
  m.add_menu("NNTP Newsgroups", "/nntp", host, port)
  m.add_info("")
  m.add_text("finger.plan", "/finger.plan", host, port)
  m.add_binary("node.wasm (binary)", "/wasm/node", host, port)
  m.add_binary("OCI Layers", "/oci", host, port)
  m.add_text("Public Cave", "/cave/public", host, port)
  m.add_search("Search CAS", "/search", host, port)
  m
}

///|
/// Build a capabilities submenu.
pub fn build_caps_menu(
  node_id : String,
  overlay : String,
  tier : String,
  has_mulsp : Bool,
  oci_types : Array[String],
  host : String,
  port : Int,
) -> GopherMenu {
  let m = GopherMenu::new()
  m.add_info("Capabilities — \{node_id}")
  m.add_info("")
  m.add_info("AI Runtime")
  m.add_info("  overlay: \{overlay}")
  m.add_info("  tier:    \{tier}")
  let mulsp_status = if has_mulsp { "attached" } else { "dormant" }
  m.add_info("  mulsp:   \{mulsp_status}")
  m.add_info("")
  m.add_info("Protocols")
  m.add_info("  gopher:  port 70")
  m.add_info("  nntp:    port 119")
  m.add_info("  lsp:     stdio / port 2087")
  m.add_info("")
  if oci_types.length() > 0 {
    m.add_info("OCI Media Types")
    for mt in oci_types {
      m.add_info("  \{mt}")
    }
    m.add_info("")
  }
  m.add_binary("node.wasm", "/wasm/node", host, port)
  m.add_menu("Back", "/", host, port)
  m
}

///|
/// Build a plugins submenu.
pub fn build_plugins_menu(
  node_id : String,
  plugins : Array[String],
  host : String,
  port : Int,
) -> GopherMenu {
  let m = GopherMenu::new()
  m.add_info("Active Plugins — \{node_id}")
  m.add_info("")
  if plugins.length() == 0 {
    m.add_info("  (no plugins loaded)")
  } else {
    for name in plugins {
      m.add_binary("\{name}  [wasm]", "/wasm/plugin/\{name}", host, port)
    }
  }
  m.add_info("")
  m.add_menu("Back", "/", host, port)
  m
}

///|
/// A brief peer summary for menu construction.
pub(all) struct GopherPeerSummary {
  node_id : String
  tier : String
  endpoint : String
} derive(Debug)

///|
pub fn GopherPeerSummary::new(
  node_id : String,
  tier : String,
  endpoint : String,
) -> GopherPeerSummary {
  { node_id, tier, endpoint }
}

///|
/// Build a peers submenu.
pub fn build_peers_menu(
  node_id : String,
  peers : Array[GopherPeerSummary],
  host : String,
  port : Int,
) -> GopherMenu {
  let m = GopherMenu::new()
  m.add_info("Known Peers — \{node_id}")
  m.add_info("")
  if peers.length() == 0 {
    m.add_info("  (no peers discovered yet)")
  } else {
    for p in peers {
      let display = "\{p.node_id}  [\{p.tier}]  \{p.endpoint}"
      m.add_menu(display, "/mulsp/\{p.node_id}", host, port)
    }
  }
  m.add_info("")
  m.add_menu("Back", "/", host, port)
  m
}

///|
/// Build the NNTP newsgroup listing as a Gopher text response.
/// Returns text bytes showing the lang.* newsgroup names and article counts.
pub fn build_nntp_groups_text(
  node_id : String,
  groups : Array[(String, Int, Int)], // (name, low, high)
) -> Array[Byte] {
  let sb = StringBuilder::new()
  sb.write_string("NNTP Newsgroups — \{node_id}\r\n")
  sb.write_string("=".repeat(40) + "\r\n")
  sb.write_string("\r\n")
  if groups.length() == 0 {
    sb.write_string("(no newsgroups)\r\n")
  } else {
    for item in groups {
      let name = item.0
      let low = item.1
      let high = item.2
      let count = high - low + 1
      sb.write_string("\{name}  (\{count} articles)\r\n")
    }
  }
  sb.write_string("\r\n")
  sb.write_string("Connect on port 119 to read/post articles.\r\n")
  gopher_str_to_bytes(sb.to_string())
}

///|
/// Build an error response for an unknown selector.
pub fn build_not_found_response(selector : String) -> GopherMenu {
  let m = GopherMenu::new()
  m.add_error("not found: \{selector}")
  m.add_menu("Back to root", "/", "localhost", 70)
  m
}

// ---------------------------------------------------------------------------
// Response helper — build from GopherSelector dispatch
// ---------------------------------------------------------------------------

///|
/// Dispatch a GopherRequest to a GopherSelector and produce a response.
///
/// This is the high-level entry point for the host's Gopher handler.
/// The host provides `lookup_blob` to serve OCI layers / WASM blobs from CAS,
/// and supplies current node state for menu construction.
pub fn dispatch_request(
  req : GopherRequest,
  node_id : String,
  epoch : Int,
  mode : String,
  tier : String,
  overlay : String,
  has_mulsp : Bool,
  plugins : Array[String],
  peers : Array[GopherPeerSummary],
  oci_types : Array[String],
  nntp_groups : Array[(String, Int, Int)],
  host : String,
  port : Int,
  lookup_blob : (String) -> Array[Byte]?,
) -> GopherResponse {
  let sel = GopherSelector::from_string(req.selector)
  match sel {
    Root =>
      Menu(
        build_node_root_menu(
          node_id,
          epoch,
          mode,
          tier,
          plugins.length(),
          peers.length(),
          host,
          port,
        ),
      )
    Capabilities =>
      Menu(
        build_caps_menu(
          node_id, overlay, tier, has_mulsp, oci_types, host, port,
        ),
      )
    Plugins => Menu(build_plugins_menu(node_id, plugins, host, port))
    Peers => Menu(build_peers_menu(node_id, peers, host, port))
    FingerPlan =>
      // finger.plan is served as a binary blob from CAS
      match lookup_blob("finger.plan") {
        Some(data) => Bytes(data)
        None => Bytes(gopher_str_to_bytes("(no finger.plan available)\r\n"))
      }
    NodeWasm =>
      match lookup_blob("node.wasm") {
        Some(data) => Bytes(data)
        None => NotFound
      }
    OciLayer(hash) =>
      match lookup_blob("oci:\{hash}") {
        Some(data) => Bytes(data)
        None => NotFound
      }
    MulspState(id) =>
      match lookup_blob("mulsp:\{id}") {
        Some(data) => Bytes(data)
        None => Bytes(gopher_str_to_bytes("(mulsp \{id} not found)\r\n"))
      }
    CavePublic =>
      match lookup_blob("cave.public") {
        Some(data) => Bytes(data)
        None => Bytes(gopher_str_to_bytes("(public cave empty)\r\n"))
      }
    NntpGroups => Bytes(build_nntp_groups_text(node_id, nntp_groups))
    Search(_q) => {
      // Stub: host implements actual CAS search
      let m = GopherMenu::new()
      m.add_info("Search not yet implemented")
      m.add_menu("Back", "/", host, port)
      Menu(m)
    }
    Unknown(raw) => Menu(build_not_found_response(raw))
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn gopher_str_trim(s : String) -> String {
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
fn gopher_str_lower(s : String) -> String {
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
fn gopher_str_to_bytes(s : String) -> Array[Byte] {
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
fn gopher_bytes_to_str(buf : Array[Byte]) -> String {
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
