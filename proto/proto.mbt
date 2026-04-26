///|
/// Protocol Registry — catalog of all codec surfaces this node can speak.
///
/// The registry answers two questions:
///
///   1. What protocols exist?  (static — the built-in table seeded at init)
///   2. Which are active here? (dynamic — ProtoStatus tracks bundle/availability)
///
/// This feeds the dynamic compile/distribute pipeline: at build time the host
/// walks the registry to decide which protocol codecs to bundle into a given
/// WASM distribution.  At runtime, external protocols can be registered from
/// CAS once their codec blobs are fetched.
///
/// Relationship to PluginRegistry
/// --------------------------------
/// PluginRegistry tracks wasm *plugins* (application logic with bus topics).
/// ProtoRegistry tracks *protocol codecs* (wire format + dispatch surfaces).
/// A plugin may *use* a protocol codec; the codec itself is not a plugin.
///
/// Built-in protocols (seeded from all_builtin_protos()):
///
///   Gopher   port 70    RFC 1436  Browse    — capability menus + WASM serving
///   Finger   port 79    RFC 1288  Discovery — node self-description (FNGR binary)
///   GmuOne   —          GMU/1     Transport — peer-to-peer binary framing
///   Nntp     port 119   RFC 3977  Gossip    — distributed newsgroup transport
///   Gemini   port 1965  Gemini    Browse    — TLS-first content serving
///   Gemtext  —          Gemini    Markup    — text/gemini line-oriented markup
///   Lsp      stdio/2087 LSP spec  Runtime   — language server proxy framing

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

///|
/// Functional grouping for a protocol codec.
pub(all) enum ProtoCategory {
  Browse // client-visible content surfaces (Gopher, Gemini)
  Discovery // node/service advertisement (Finger, GMU/1 plan exchange)
  Gossip // distributed message propagation (NNTP)
  Markup // content encoding formats (Gemtext)
  Runtime // node-local operational protocols (LSP)
  Transport // low-level peer framing (GMU/1 wire)
} derive(Eq, Debug)

///|
impl Show for ProtoCategory with output(self, logger) {
  logger.write_string(
    match self {
      Browse => "Browse"
      Discovery => "Discovery"
      Gossip => "Gossip"
      Markup => "Markup"
      Runtime => "Runtime"
      Transport => "Transport"
    },
  )
}

// ---------------------------------------------------------------------------
// Kind
// ---------------------------------------------------------------------------

///|
/// Canonical identifier for each known protocol codec.
pub(all) enum ProtoKind {
  GopherProtocol // RFC 1436 Gopher
  FingerProtocol // RFC 1288 Finger + FNGR binary
  GmuOneTransport // GMU/1 peer framing + plan exchange
  NntpProtocol // RFC 3977 NNTP
  GeminiProtocol // Project Gemini
  GemtextMarkup // text/gemini markup codec
  LspProtocol // Language Server Protocol framing
  Custom(String) // host-registered extension protocol
} derive(Eq, Debug)

///|
impl Show for ProtoKind with output(self, logger) {
  logger.write_string(
    match self {
      GopherProtocol => "GopherProtocol"
      FingerProtocol => "FingerProtocol"
      GmuOneTransport => "GmuOneTransport"
      NntpProtocol => "NntpProtocol"
      GeminiProtocol => "GeminiProtocol"
      GemtextMarkup => "GemtextMarkup"
      LspProtocol => "LspProtocol"
      Custom(id) => "Custom(\{id})"
    },
  )
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

///|
/// Compilation / availability status of a protocol codec in this node.
pub(all) enum ProtoStatus {
  Bundled // codec is compiled into the current node binary
  Available // codec wasm is in CAS but not yet linked
  External(String) // codec is reachable at a remote endpoint (URL/address)
  Disabled // excluded from this distribution intentionally
  Unknown // location not yet determined
} derive(Eq, Debug)

///|
impl Show for ProtoStatus with output(self, logger) {
  logger.write_string(
    match self {
      Bundled => "Bundled"
      Available => "Available"
      External(addr) => "External(\{addr})"
      Disabled => "Disabled"
      Unknown => "Unknown"
    },
  )
}

///|
pub fn ProtoStatus::is_usable(self : ProtoStatus) -> Bool {
  match self {
    Bundled | Available => true
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Meta
// ---------------------------------------------------------------------------

///|
/// Static metadata describing a protocol codec.
pub(all) struct ProtoMeta {
  kind : ProtoKind
  name : String // human-readable full name
  shortname : String // short identifier used in configs / selectors
  port : Int // well-known port, 0 if not applicable (codec-only)
  category : ProtoCategory
  spec : String // RFC number, spec name, or internal identifier
  description : String // one-line description
} derive(Debug)

///|
pub fn ProtoMeta::new(
  kind : ProtoKind,
  name : String,
  shortname : String,
  port : Int,
  category : ProtoCategory,
  spec : String,
  description : String,
) -> ProtoMeta {
  { kind, name, shortname, port, category, spec, description }
}

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

///|
/// A registry entry — metadata plus runtime status and optional CAS key.
pub(all) struct ProtoEntry {
  meta : ProtoMeta
  mut status : ProtoStatus
  mut cas_key : String // CAS hash of the codec wasm blob, empty if bundled
} derive(Debug)

///|
pub fn ProtoEntry::new(meta : ProtoMeta, status : ProtoStatus) -> ProtoEntry {
  { meta, status, cas_key: "" }
}

///|
pub fn ProtoEntry::with_cas(
  meta : ProtoMeta,
  status : ProtoStatus,
  cas_key : String,
) -> ProtoEntry {
  { meta, status, cas_key }
}

///|
pub fn ProtoEntry::mark_bundled(self : ProtoEntry) -> Unit {
  self.status = Bundled
  self.cas_key = ""
}

///|
pub fn ProtoEntry::mark_available(self : ProtoEntry, cas_key : String) -> Unit {
  self.status = Available
  self.cas_key = cas_key
}

///|
pub fn ProtoEntry::mark_disabled(self : ProtoEntry) -> Unit {
  self.status = Disabled
}

///|
pub fn ProtoEntry::is_usable(self : ProtoEntry) -> Bool {
  self.status.is_usable()
}

// ---------------------------------------------------------------------------
// Built-in protocol table
// ---------------------------------------------------------------------------

///|
/// The canonical list of all protocol codecs known to this codebase.
/// This is the seed table used to initialise a ProtoRegistry.
pub fn all_builtin_protos() -> Array[ProtoMeta] {
  [
    ProtoMeta::new(
      GopherProtocol,
      "Gopher",
      "gopher",
      70,
      Browse,
      "RFC 1436",
      "Hierarchical menu browsing + WASM/OCI blob serving",
    ),
    ProtoMeta::new(
      FingerProtocol,
      "Finger",
      "finger",
      79,
      Discovery,
      "RFC 1288 + FNGR",
      "Node self-description via FingerPlan and FNGR binary format",
    ),
    ProtoMeta::new(
      GmuOneTransport,
      "GMU/1",
      "gmu1",
      0,
      Transport,
      "GMU/1",
      "Peer-to-peer framing: Ping/Pong, PlanRequest, CasSync, Residue",
    ),
    ProtoMeta::new(
      NntpProtocol,
      "NNTP",
      "nntp",
      119,
      Gossip,
      "RFC 3977 + NTPA",
      "Distributed newsgroup transport for gossip, spores, and OCI layers",
    ),
    ProtoMeta::new(
      GeminiProtocol,
      "Gemini",
      "gemini",
      1965,
      Browse,
      "Gemini spec",
      "TLS-first minimalist content protocol with Gemtext pages",
    ),
    ProtoMeta::new(
      GemtextMarkup,
      "Gemtext",
      "gemtext",
      0,
      Markup,
      "Gemini spec",
      "Line-oriented text/gemini markup: links, headings, preformatted blocks",
    ),
    ProtoMeta::new(
      LspProtocol,
      "LSP",
      "lsp",
      0,
      Runtime,
      "LSP 3.17",
      "Language Server Protocol framing (Content-Length header + JSON body)",
    ),
  ]
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

///|
/// The node's protocol registry — catalog of codec surfaces with status.
///
/// Initialise with new() to get all built-in protocols pre-seeded as Bundled.
/// Call register() to add externally-loaded or Custom protocol entries.
pub(all) struct ProtoRegistry {
  entries : Array[ProtoEntry]
  mut custom_count : Int
} derive(Debug)

///|
/// Create a registry pre-seeded with all built-in protocols marked Bundled.
pub fn ProtoRegistry::new() -> ProtoRegistry {
  let reg = { entries: [], custom_count: 0 }
  for meta in all_builtin_protos() {
    reg.entries.push(ProtoEntry::new(meta, Bundled))
  }
  reg
}

///|
/// Create an empty registry (no built-ins seeded).
/// Useful when building a minimal distribution that cherry-picks protocols.
pub fn ProtoRegistry::empty() -> ProtoRegistry {
  { entries: [], custom_count: 0 }
}

///|
/// Register a protocol entry. Returns its index.
pub fn ProtoRegistry::register(
  self : ProtoRegistry,
  meta : ProtoMeta,
  status : ProtoStatus,
) -> Int {
  let idx = self.entries.length()
  self.entries.push(ProtoEntry::new(meta, status))
  match meta.kind {
    Custom(_) => self.custom_count = self.custom_count + 1
    _ => ()
  }
  idx
}

///|
/// Register with an explicit CAS key (for Available codecs fetched from CAS).
pub fn ProtoRegistry::register_with_cas(
  self : ProtoRegistry,
  meta : ProtoMeta,
  cas_key : String,
) -> Int {
  let idx = self.entries.length()
  self.entries.push(ProtoEntry::with_cas(meta, Available, cas_key))
  idx
}

///|
/// Look up by ProtoKind.
pub fn ProtoRegistry::find_by_kind(
  self : ProtoRegistry,
  kind : ProtoKind,
) -> ProtoEntry? {
  for e in self.entries {
    if e.meta.kind == kind {
      return Some(e)
    }
  }
  None
}

///|
/// Look up by well-known port (0 = not applicable; skipped in lookup).
pub fn ProtoRegistry::find_by_port(
  self : ProtoRegistry,
  port : Int,
) -> ProtoEntry? {
  if port == 0 {
    return None
  }
  for e in self.entries {
    if e.meta.port == port {
      return Some(e)
    }
  }
  None
}

///|
/// Look up by shortname (e.g. "gopher", "nntp", "gemini").
pub fn ProtoRegistry::find_by_name(
  self : ProtoRegistry,
  name : String,
) -> ProtoEntry? {
  for e in self.entries {
    if e.meta.shortname == name || e.meta.name == name {
      return Some(e)
    }
  }
  None
}

///|
/// All entries in a given category.
pub fn ProtoRegistry::by_category(
  self : ProtoRegistry,
  cat : ProtoCategory,
) -> Array[ProtoEntry] {
  let out : Array[ProtoEntry] = []
  for e in self.entries {
    if e.meta.category == cat {
      out.push(e)
    }
  }
  out
}

///|
/// All usable entries (Bundled or Available).
pub fn ProtoRegistry::usable(self : ProtoRegistry) -> Array[ProtoEntry] {
  let out : Array[ProtoEntry] = []
  for e in self.entries {
    if e.is_usable() {
      out.push(e)
    }
  }
  out
}

///|
/// All entries regardless of status.
pub fn ProtoRegistry::all(self : ProtoRegistry) -> Array[ProtoEntry] {
  self.entries.copy()
}

///|
/// Entries with a listening port (port > 0).
pub fn ProtoRegistry::with_port(self : ProtoRegistry) -> Array[ProtoEntry] {
  let out : Array[ProtoEntry] = []
  for e in self.entries {
    if e.meta.port > 0 {
      out.push(e)
    }
  }
  out
}

///|
pub fn ProtoRegistry::count(self : ProtoRegistry) -> Int {
  self.entries.length()
}

///|
pub fn ProtoRegistry::bundled_count(self : ProtoRegistry) -> Int {
  let mut n = 0
  for e in self.entries {
    if e.status == Bundled {
      n = n + 1
    }
  }
  n
}

// ---------------------------------------------------------------------------
// Summary / stats
// ---------------------------------------------------------------------------

///|
pub(all) struct ProtoRegistryStats {
  total : Int
  bundled : Int
  available : Int
  external : Int
  disabled : Int
  unknown : Int
  custom : Int
} derive(Debug)

///|
pub fn ProtoRegistry::stats(self : ProtoRegistry) -> ProtoRegistryStats {
  let mut bundled = 0
  let mut available = 0
  let mut external = 0
  let mut disabled = 0
  let mut unknown = 0
  for e in self.entries {
    match e.status {
      Bundled => bundled = bundled + 1
      Available => available = available + 1
      External(_) => external = external + 1
      Disabled => disabled = disabled + 1
      Unknown => unknown = unknown + 1
    }
  }
  {
    total: self.entries.length(),
    bundled,
    available,
    external,
    disabled,
    unknown,
    custom: self.custom_count,
  }
}

///|
/// Render a compact ASCII summary table for finger/Gopher/Gemini menus.
pub fn ProtoRegistry::summary_table(self : ProtoRegistry) -> String {
  let sb = StringBuilder::new()
  sb.write_string("Protocol Registry\n")
  sb.write_string("=================\n")
  sb.write_string("\n")
  let categories = [Browse, Discovery, Gossip, Transport, Markup, Runtime]
  for cat in categories {
    let group = self.by_category(cat)
    if group.length() == 0 {
      continue
    }
    sb.write_string("[\{cat}]\n")
    for e in group {
      let port_str = if e.meta.port > 0 {
        "port \{e.meta.port}"
      } else {
        "codec   "
      }
      let status_str = match e.status {
        Bundled => "bundled"
        Available => "available"
        External(_) => "external"
        Disabled => "disabled"
        Unknown => "unknown"
      }
      sb.write_string(
        "  \{e.meta.shortname}  \{port_str}  \{e.meta.spec}  [\{status_str}]\n",
      )
    }
    sb.write_string("\n")
  }
  sb.to_string()
}
