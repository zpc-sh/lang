///|
/// Gemtext — The markup language for Gemini protocol (MIME type: text/gemini).
///
/// Gemtext is strictly line-oriented: each line has exactly one type.  There
/// is no inline markup.  The format is intentionally minimal so that clients
/// with no rendering capability still produce readable output.
///
/// Line types
/// ----------
///   Plain text   — any line not matching the prefixes below
///   =>           — link:  `=> URL [label]`
///   #            — heading level 1
///   ##           — heading level 2
///   ###          — heading level 3
///   *            — unordered list item
///   >            — blockquote
///   ```          — toggle preformatted mode (optional alt-text follows)
///
/// Preformatted mode
/// -----------------
/// A line starting with ``` opens a preformatted block; the next ``` line
/// closes it.  Lines inside the block are emitted verbatim (kind = PreText).
/// The opening ``` line may carry an alt-text string for screen readers.
///
/// Round-trip guarantee
/// --------------------
/// parse(doc.render()) == doc   (modulo trailing-newline normalisation)
///
/// Architecture
/// ------------
/// Pure codec — no I/O.  Call parse() on incoming text, mutate with builder
/// methods, then render() or to_bytes() to produce wire-ready output.

// ---------------------------------------------------------------------------
// Line kind
// ---------------------------------------------------------------------------

///|
/// The semantic kind of a single Gemtext line.
pub(all) enum GemtextLineKind {
  Text // plain paragraph (empty text = blank line)
  Link // => URL [label]
  Heading1 // # heading
  Heading2 // ## heading
  Heading3 // ### heading
  ListItem // * item
  Quote // > quote
  PreToggle // ``` [alt-text]  — opens or closes a preformatted block
  PreText // verbatim line inside a preformatted block
} derive(Eq, Debug)

///|
impl Show for GemtextLineKind with output(self, logger) {
  logger.write_string(
    match self {
      Text => "Text"
      Link => "Link"
      Heading1 => "Heading1"
      Heading2 => "Heading2"
      Heading3 => "Heading3"
      ListItem => "ListItem"
      Quote => "Quote"
      PreToggle => "PreToggle"
      PreText => "PreText"
    },
  )
}

// ---------------------------------------------------------------------------
// Line
// ---------------------------------------------------------------------------

///|
/// A single parsed Gemtext line.
///
/// For Link lines, `url` holds the link target and `text` holds the label
/// (may be empty — callers should fall back to displaying `url` when `text`
/// is empty).  For all other kinds, `url` is the empty string.
pub(all) struct GemtextLine {
  kind : GemtextLineKind
  text : String
  url : String
} derive(Debug)

///|
fn GemtextLine::plain(text : String) -> GemtextLine {
  { kind: Text, text, url: "" }
}

///|
fn GemtextLine::link(url : String, label : String) -> GemtextLine {
  { kind: Link, text: label, url }
}

///|
fn GemtextLine::heading(level : Int, text : String) -> GemtextLine {
  let kind = if level == 1 {
    Heading1
  } else if level == 2 {
    Heading2
  } else {
    Heading3
  }
  { kind, text, url: "" }
}

///|
fn GemtextLine::list_item(text : String) -> GemtextLine {
  { kind: ListItem, text, url: "" }
}

///|
fn GemtextLine::quote(text : String) -> GemtextLine {
  { kind: Quote, text, url: "" }
}

///|
fn GemtextLine::pre_toggle(alt : String) -> GemtextLine {
  { kind: PreToggle, text: alt, url: "" }
}

///|
fn GemtextLine::pre_text(text : String) -> GemtextLine {
  { kind: PreText, text, url: "" }
}

///|
/// Render a single line back to canonical Gemtext (without trailing newline).
pub fn GemtextLine::render(self : GemtextLine) -> String {
  match self.kind {
    Text => self.text
    Link =>
      if self.text.length() == 0 {
        "=> \{self.url}"
      } else {
        "=> \{self.url} \{self.text}"
      }
    Heading1 => "# \{self.text}"
    Heading2 => "## \{self.text}"
    Heading3 => "### \{self.text}"
    ListItem => "* \{self.text}"
    Quote => "> \{self.text}"
    PreToggle =>
      if self.text.length() == 0 {
        "```"
      } else {
        "``` \{self.text}"
      }
    PreText => self.text
  }
}

// ---------------------------------------------------------------------------
// Document
// ---------------------------------------------------------------------------

///|
/// A Gemtext document — an ordered sequence of typed lines.
pub(all) struct GemtextDocument {
  lines : Array[GemtextLine]
} derive(Debug)

///|
pub fn GemtextDocument::new() -> GemtextDocument {
  { lines: [] }
}

// ---------------------------------------------------------------------------
// Builder methods
// ---------------------------------------------------------------------------

///|
pub fn GemtextDocument::add_heading1(
  self : GemtextDocument,
  text : String,
) -> Unit {
  self.lines.push(GemtextLine::heading(1, text))
}

///|
pub fn GemtextDocument::add_heading2(
  self : GemtextDocument,
  text : String,
) -> Unit {
  self.lines.push(GemtextLine::heading(2, text))
}

///|
pub fn GemtextDocument::add_heading3(
  self : GemtextDocument,
  text : String,
) -> Unit {
  self.lines.push(GemtextLine::heading(3, text))
}

///|
pub fn GemtextDocument::add_link(
  self : GemtextDocument,
  url : String,
  label : String,
) -> Unit {
  self.lines.push(GemtextLine::link(url, label))
}

///|
pub fn GemtextDocument::add_text(
  self : GemtextDocument,
  text : String,
) -> Unit {
  self.lines.push(GemtextLine::plain(text))
}

///|
pub fn GemtextDocument::add_list_item(
  self : GemtextDocument,
  text : String,
) -> Unit {
  self.lines.push(GemtextLine::list_item(text))
}

///|
pub fn GemtextDocument::add_quote(
  self : GemtextDocument,
  text : String,
) -> Unit {
  self.lines.push(GemtextLine::quote(text))
}

///|
pub fn GemtextDocument::add_preformatted_toggle(
  self : GemtextDocument,
  alt : String,
) -> Unit {
  self.lines.push(GemtextLine::pre_toggle(alt))
}

///|
pub fn GemtextDocument::add_preformatted_text(
  self : GemtextDocument,
  text : String,
) -> Unit {
  self.lines.push(GemtextLine::pre_text(text))
}

///|
pub fn GemtextDocument::add_blank(self : GemtextDocument) -> Unit {
  self.lines.push(GemtextLine::plain(""))
}

///|
pub fn GemtextDocument::line_count(self : GemtextDocument) -> Int {
  self.lines.length()
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

///|
/// Parse a Gemtext string into a GemtextDocument.
///
/// Handles both `\n` and `\r\n` line endings.  Preformatted blocks are tracked
/// with a boolean toggle: lines between matching ``` markers get kind=PreText.
pub fn GemtextDocument::parse(input : String) -> GemtextDocument {
  let doc = GemtextDocument::new()
  let raw_lines = gemtext_split_lines(input)
  let mut in_pre = false
  for raw in raw_lines {
    let line = gemtext_str_trim_right(raw)
    if in_pre {
      if line.has_prefix("```") {
        let alt = gemtext_str_trim(line[3:].to_string())
        doc.lines.push(GemtextLine::pre_toggle(alt))
        in_pre = false
      } else {
        doc.lines.push(GemtextLine::pre_text(line))
      }
    } else if line.has_prefix("```") {
      let alt = gemtext_str_trim(line[3:].to_string())
      doc.lines.push(GemtextLine::pre_toggle(alt))
      in_pre = true
    } else if line.has_prefix("### ") {
      doc.lines.push(GemtextLine::heading(3, line[4:].to_string()))
    } else if line.has_prefix("## ") {
      doc.lines.push(GemtextLine::heading(2, line[3:].to_string()))
    } else if line.has_prefix("# ") {
      doc.lines.push(GemtextLine::heading(1, line[2:].to_string()))
    } else if line.has_prefix("=> ") {
      doc.lines.push(gemtext_parse_link(line[3:].to_string()))
    } else if line.has_prefix("* ") {
      doc.lines.push(GemtextLine::list_item(line[2:].to_string()))
    } else if line.has_prefix("> ") {
      doc.lines.push(GemtextLine::quote(line[2:].to_string()))
    } else {
      doc.lines.push(GemtextLine::plain(line))
    }
  }
  doc
}

///|
/// Parse the body of a link line (the part after "=> ").
fn gemtext_parse_link(body : String) -> GemtextLine {
  let trimmed = gemtext_str_trim(body)
  let chars = trimmed.to_array()
  let len = chars.length()
  // Find first whitespace character after the URL
  let mut space_pos = -1
  let mut i = 0
  while i < len {
    let ch = chars[i]
    if ch == ' ' || ch == '\t' {
      space_pos = i
      break
    }
    i = i + 1
  }
  if space_pos > 0 {
    let url = trimmed[0:space_pos].to_string()
    let label = gemtext_str_trim(trimmed[space_pos + 1:].to_string())
    GemtextLine::link(url, label)
  } else {
    GemtextLine::link(trimmed, "")
  }
}

// ---------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------

///|
/// Render the document back to a canonical Gemtext string.
/// Each line is terminated with `\n`.
pub fn GemtextDocument::render(self : GemtextDocument) -> String {
  let sb = StringBuilder::new()
  for line in self.lines {
    sb.write_string(line.render())
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// Encode the document to UTF-8 bytes (for Gemini wire transport).
pub fn GemtextDocument::to_bytes(self : GemtextDocument) -> Array[Byte] {
  gemtext_str_to_bytes(self.render())
}

// ---------------------------------------------------------------------------
// Page builders
// ---------------------------------------------------------------------------

///|
/// Build a root page for an AI node.
pub fn build_node_root_page(
  node_id : String,
  epoch : Int,
  mode : String,
  tier : String,
  plugin_count : Int,
  peer_count : Int,
) -> GemtextDocument {
  let doc = GemtextDocument::new()
  doc.add_heading1("Lang AI Node")
  doc.add_blank()
  doc.add_text("Node:    \{node_id}")
  doc.add_text("Epoch:   \{epoch}")
  doc.add_text("Mode:    \{mode}")
  doc.add_text("Tier:    \{tier}")
  doc.add_text("Plugins: \{plugin_count}")
  doc.add_text("Peers:   \{peer_count}")
  doc.add_blank()
  doc.add_heading2("Browse")
  doc.add_link("/caps", "Capabilities")
  doc.add_link("/plugins", "Plugins (\{plugin_count})")
  doc.add_link("/peers", "Peers (\{peer_count})")
  doc.add_link("/nntp", "NNTP Newsgroups")
  doc.add_blank()
  doc.add_heading2("Assets")
  doc.add_link("/finger.plan", "finger.plan")
  doc.add_link("/wasm/node", "node.wasm (binary)")
  doc.add_link("/cave/public", "Public Cave Keys")
  doc.add_blank()
  doc.add_link("/search", "Search CAS")
  doc
}

///|
/// Build a capabilities page.
pub fn build_caps_page(
  node_id : String,
  overlay : String,
  tier : String,
  has_mulsp : Bool,
  oci_types : Array[String],
  protocols : Array[String],
) -> GemtextDocument {
  let doc = GemtextDocument::new()
  doc.add_heading1("Capabilities")
  doc.add_text("Node: \{node_id}")
  doc.add_blank()
  doc.add_heading2("AI Runtime")
  doc.add_text("Overlay: \{overlay}")
  doc.add_text("Tier:    \{tier}")
  let mulsp_label = if has_mulsp { "attached" } else { "dormant" }
  doc.add_text("Mulsp:   \{mulsp_label}")
  doc.add_blank()
  doc.add_heading2("Protocols")
  for proto in protocols {
    doc.add_list_item(proto)
  }
  doc.add_blank()
  if oci_types.length() > 0 {
    doc.add_heading2("OCI Media Types")
    for mt in oci_types {
      doc.add_list_item(mt)
    }
    doc.add_blank()
  }
  doc.add_link("/wasm/node", "node.wasm")
  doc.add_link("/", "Back to root")
  doc
}

///|
/// Build a peers page.
pub fn build_peers_page(
  node_id : String,
  peers : Array[(String, String, String)], // (id, tier, endpoint)
) -> GemtextDocument {
  let doc = GemtextDocument::new()
  doc.add_heading1("Known Peers")
  doc.add_text("Node: \{node_id}")
  doc.add_blank()
  if peers.length() == 0 {
    doc.add_text("(no peers discovered yet)")
  } else {
    for p in peers {
      let peer_id = p.0
      let peer_tier = p.1
      let endpoint = p.2
      doc.add_link("/mulsp/\{peer_id}", "\{peer_id}  [\{peer_tier}]  \{endpoint}")
    }
  }
  doc.add_blank()
  doc.add_link("/", "Back to root")
  doc
}

///|
/// Build an NNTP newsgroups page.
pub fn build_nntp_groups_page(
  node_id : String,
  groups : Array[(String, Int, Int)], // (name, low, high)
) -> GemtextDocument {
  let doc = GemtextDocument::new()
  doc.add_heading1("NNTP Newsgroups")
  doc.add_text("Node: \{node_id}")
  doc.add_blank()
  if groups.length() == 0 {
    doc.add_text("(no newsgroups)")
  } else {
    for g in groups {
      let name = g.0
      let low = g.1
      let high = g.2
      let count = high - low + 1
      doc.add_text("\{name}  (\{count} articles)")
    }
  }
  doc.add_blank()
  doc.add_text("Connect on port 119 to read/post articles.")
  doc.add_link("/", "Back to root")
  doc
}

///|
/// Build a plugins page.
pub fn build_plugins_page(
  node_id : String,
  plugins : Array[String],
) -> GemtextDocument {
  let doc = GemtextDocument::new()
  doc.add_heading1("Active Plugins")
  doc.add_text("Node: \{node_id}")
  doc.add_blank()
  if plugins.length() == 0 {
    doc.add_text("(no plugins loaded)")
  } else {
    for name in plugins {
      doc.add_link("/wasm/plugin/\{name}", "\{name}  [wasm]")
    }
  }
  doc.add_blank()
  doc.add_link("/", "Back to root")
  doc
}

///|
/// Build an error page for an unknown or missing selector.
pub fn build_error_page(selector : String) -> GemtextDocument {
  let doc = GemtextDocument::new()
  doc.add_heading1("Not Found")
  doc.add_blank()
  doc.add_text("No resource at: \{selector}")
  doc.add_blank()
  doc.add_link("/", "Back to root")
  doc
}

///|
/// Build a finger.plan page from raw plan text.
pub fn build_finger_plan_page(plan_text : String) -> GemtextDocument {
  let doc = GemtextDocument::new()
  doc.add_heading1("finger.plan")
  doc.add_blank()
  doc.add_preformatted_toggle("finger plan")
  let plan_lines = gemtext_split_lines(plan_text)
  for l in plan_lines {
    doc.add_preformatted_text(l)
  }
  doc.add_preformatted_toggle("")
  doc
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn gemtext_split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let chars = s.to_array()
  let len = chars.length()
  let mut line_start = 0
  let mut i = 0
  while i < len {
    let ch = chars[i]
    if ch == '\r' && i + 1 < len && chars[i + 1] == '\n' {
      out.push(s[line_start:i].to_string())
      i = i + 2
      line_start = i
    } else if ch == '\n' {
      out.push(s[line_start:i].to_string())
      i = i + 1
      line_start = i
    } else {
      i = i + 1
    }
  }
  // last line without trailing newline
  if line_start < len {
    out.push(s[line_start:].to_string())
  }
  out
}

///|
fn gemtext_str_trim(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  while start < len &&
        (chars[start] == ' ' || chars[start] == '\t' || chars[start] == '\r' || chars[start] == '\n') {
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
fn gemtext_str_trim_right(s : String) -> String {
  let chars = s.to_array()
  let len = chars.length()
  let mut end = len
  while end > 0 &&
        (chars[end - 1] == ' ' || chars[end - 1] == '\t' || chars[end - 1] == '\r') {
    end = end - 1
  }
  if end == len {
    return s
  }
  s[0:end].to_string()
}

///|
fn gemtext_str_to_bytes(s : String) -> Array[Byte] {
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
