///|
/// WASM Interface — direct WASM manipulation surface.
///
/// This package exposes the node's WASM manipulation capabilities
/// as a clean API surface. It wraps Mu's module parser and section
/// operations for use by the node kernel and plugins.
///
/// Operations:
///   - Parse a wasm binary into a navigable module descriptor
///   - Extract custom sections (.mks, .prc, .pr1)
///   - Inject/strip/patch sections
///   - Compose modules (wire exports to imports)
///   - Query module stats (size, exports, code sections)
///
/// This is the "direct WASM interface for external manipulation" from
/// the architecture specs. The node exposes these as bus operations or
/// host-callable exports.

// ---------------------------------------------------------------------------
// Module descriptor (local mirror of Mu's Module structure)
// ---------------------------------------------------------------------------

///|
/// A parsed WASM module descriptor — the node's view of a wasm binary.
pub(all) struct ModuleDesc {
  total_size     : Int
  section_count  : Int
  export_count   : Int
  function_count : Int
  type_count     : Int
  code_size      : Int
  exports        : Array[ExportDesc]
  custom_sections : Array[CustomSectionDesc]
} derive(Debug)

///|
/// An export from a wasm module.
pub(all) struct ExportDesc {
  name : String
  kind : ExportKindDesc    // func, table, memory, global
  index : Int
} derive(Debug)

///|
/// Export kind.
pub(all) enum ExportKindDesc {
  Func
  Table
  Memory
  Global
} derive(Eq, Debug)

///|
impl Show for ExportKindDesc with output(self, logger) {
  logger.write_string(match self {
    Func   => "Func"
    Table  => "Table"
    Memory => "Memory"
    Global => "Global"
  })
}

///|
/// A custom section found in a wasm module.
pub(all) struct CustomSectionDesc {
  name         : String
  payload_size : Int
} derive(Debug)

// ---------------------------------------------------------------------------
// Parse
// ---------------------------------------------------------------------------

///|
/// Parse a wasm binary into a module descriptor.
/// Returns None if the binary is not valid wasm.
pub fn parse_module(wasm : Array[Byte]) -> ModuleDesc? {
  // Verify wasm magic: \0asm
  if wasm.length() < 8 { return None }
  if wasm[0] != b'\x00' || wasm[1] != b'\x61' ||
     wasm[2] != b'\x73' || wasm[3] != b'\x6D' { return None }
  // Verify version 1
  if wasm[4] != b'\x01' || wasm[5] != b'\x00' ||
     wasm[6] != b'\x00' || wasm[7] != b'\x00' { return None }

  // Walk sections
  let mut pos = 8
  let len = wasm.length()
  let mut section_count = 0
  let mut export_count = 0
  let mut function_count = 0
  let mut type_count = 0
  let mut code_size = 0
  let exports : Array[ExportDesc] = []
  let custom_sections : Array[CustomSectionDesc] = []

  while pos < len {
    let section_id = wasm[pos].to_int()
    pos = pos + 1

    // Read LEB128 size
    let (size, new_pos) = iface_read_leb128(wasm, pos)
    pos = new_pos
    let payload_end = if pos + size <= len { pos + size } else { len }

    section_count = section_count + 1

    match section_id {
      0 => {
        // Custom section — parse name
        let (name_len, name_pos) = iface_read_leb128(wasm, pos)
        let sb = StringBuilder::new()
        let mut i = 0
        while i < name_len && name_pos + i < payload_end {
          sb.write_char(wasm[name_pos + i].to_int().unsafe_to_char())
          i = i + 1
        }
        let payload_data_size = payload_end - (name_pos + name_len)
        custom_sections.push({ name: sb.to_string(), payload_size: payload_data_size })
      }
      1 => {
        // Type section — count entries
        let (count, _) = iface_read_leb128(wasm, pos)
        type_count = count
      }
      7 => {
        // Export section — count + parse names
        let r = iface_read_leb128(wasm, pos)
        let count = r.0
        let mut epos = r.1
        export_count = count
        let mut j = 0
        while j < count && epos < payload_end {
          let r2 = iface_read_leb128(wasm, epos)
          let name_len = r2.0
          epos = r2.1
          let sb = StringBuilder::new()
          let mut k = 0
          while k < name_len && epos + k < payload_end {
            sb.write_char(wasm[epos + k].to_int().unsafe_to_char())
            k = k + 1
          }
          epos = epos + name_len
          let kind : ExportKindDesc = if epos < payload_end {
            match wasm[epos].to_int() {
              0 => Func
              1 => Table
              2 => Memory
              3 => Global
              _ => Func
            }
          } else { Func }
          epos = epos + 1
          let r3 = iface_read_leb128(wasm, epos)
          let index = r3.0
          epos = r3.1
          exports.push({ name: sb.to_string(), kind, index })
          j = j + 1
        }
      }
      10 => {
        // Code section — count + total size
        let (count, _) = iface_read_leb128(wasm, pos)
        function_count = count
        code_size = size
      }
      _ => ()
    }

    pos = payload_end
  }

  Some({
    total_size: wasm.length(),
    section_count,
    export_count,
    function_count,
    type_count,
    code_size,
    exports,
    custom_sections,
  })
}

// ---------------------------------------------------------------------------
// Section operations
// ---------------------------------------------------------------------------

///|
/// Inject a named custom section into a wasm binary.
/// Appends the section after all existing sections.
pub fn inject_section(
  wasm : Array[Byte],
  name : String,
  payload : Array[Byte],
) -> Array[Byte] {
  let out : Array[Byte] = []
  for b in wasm { out.push(b) }

  // Custom section id = 0x00
  out.push(b'\x00')

  // Name as UTF-8 bytes
  let name_bytes : Array[Byte] = []
  for ch in name {
    name_bytes.push(ch.to_int().to_byte())
  }

  let body_size = iface_leb128_size(name_bytes.length()) + name_bytes.length() + payload.length()

  // Section size as LEB128
  iface_write_leb128(out, body_size)
  // Name length as LEB128
  iface_write_leb128(out, name_bytes.length())
  // Name bytes
  for b in name_bytes { out.push(b) }
  // Payload
  for b in payload { out.push(b) }

  out
}

///|
/// Strip all custom sections with a given name from a wasm binary.
pub fn strip_section(wasm : Array[Byte], name : String) -> Array[Byte] {
  let out : Array[Byte] = []
  // Copy header
  let mut i = 0
  while i < 8 && i < wasm.length() {
    out.push(wasm[i]); i = i + 1
  }

  let mut pos = 8
  let len = wasm.length()
  while pos < len {
    let id_pos = pos
    let section_id = wasm[pos].to_int()
    pos = pos + 1
    let (size, new_pos) = iface_read_leb128(wasm, pos)
    pos = new_pos
    let payload_end = if pos + size <= len { pos + size } else { len }

    let mut skip = false
    if section_id == 0 {
      let (name_len, name_pos) = iface_read_leb128(wasm, pos)
      if name_pos + name_len <= payload_end {
        let sb = StringBuilder::new()
        let mut j = 0
        while j < name_len {
          sb.write_char(wasm[name_pos + j].to_int().unsafe_to_char())
          j = j + 1
        }
        if sb.to_string() == name { skip = true }
      }
    }

    if !skip {
      let mut j = id_pos
      while j < payload_end { out.push(wasm[j]); j = j + 1 }
    }

    pos = payload_end
  }

  out
}

///|
/// Check if a wasm binary has a custom section with the given name.
pub fn has_section(wasm : Array[Byte], name : String) -> Bool {
  match parse_module(wasm) {
    Some(desc) => {
      for cs in desc.custom_sections {
        if cs.name == name { return true }
      }
      false
    }
    None => false
  }
}

///|
/// Find an export by name in a module descriptor.
pub fn find_export(desc : ModuleDesc, name : String) -> ExportDesc? {
  for e in desc.exports {
    if e.name == name { return Some(e) }
  }
  None
}

///|
/// Validate that a wasm module meets the plugin ABI requirements.
pub fn validate_plugin_abi(desc : ModuleDesc) -> @plugin.PluginAbi {
  let mut has_init = false
  let mut has_handle = false
  let mut has_query = false
  let mut has_tick = false
  let mut has_dispose = false
  for e in desc.exports {
    match e.name {
      "plugin_init"    => has_init = true
      "plugin_handle"  => has_handle = true
      "plugin_query"   => has_query = true
      "plugin_tick"    => has_tick = true
      "plugin_dispose" => has_dispose = true
      _ => ()
    }
  }
  { has_init, has_handle, has_query, has_tick, has_dispose }
}

// ---------------------------------------------------------------------------
// Cognitive boundary WASM operations
// ---------------------------------------------------------------------------

///|
/// Inject a full cognitive identity into a wasm binary.
/// Each layer becomes a custom section: .cb0, .cb1, .cb2, .cb3.
pub fn inject_cognitive_identity(
  wasm : Array[Byte],
  identity : @cognitive.CognitiveIdentity,
) -> Array[Byte] {
  let mut result = wasm
  for layer in identity.layers {
    let section_name = layer.depth.section_name()
    let payload = layer.to_bytes()
    result = inject_section(result, section_name, payload)
  }
  result
}

///|
/// Extract a cognitive identity from a wasm binary's custom sections.
/// Reads .cb0, .cb1, .cb2, .cb3 sections and deserializes the boundaries.
pub fn extract_cognitive_identity(wasm : Array[Byte]) -> @cognitive.CognitiveIdentity {
  let identity = @cognitive.CognitiveIdentity::new()
  let desc = parse_module(wasm)
  match desc {
    None => identity
    Some(d) => {
      // Walk custom sections looking for .cb0-.cb3
      // We need to re-parse to get actual payload bytes
      let sections = extract_cognitive_sections(wasm, d)
      for section in sections {
        let boundary = @cognitive.CognitiveBoundary::from_bytes(section.1)
        match boundary {
          Some(b) => identity.add_layer(b)
          None => ()
        }
      }
      identity
    }
  }
}

///|
/// Strip all cognitive boundary sections (.cb0-.cb3) from a wasm binary.
pub fn strip_cognitive_identity(wasm : Array[Byte]) -> Array[Byte] {
  let mut result = wasm
  result = strip_section(result, ".cb0")
  result = strip_section(result, ".cb1")
  result = strip_section(result, ".cb2")
  result = strip_section(result, ".cb3")
  result
}

///|
/// Check what cognitive depth a wasm binary carries.
pub fn cognitive_depth(wasm : Array[Byte]) -> @cognitive.CognitiveDepth {
  let identity = extract_cognitive_identity(wasm)
  identity.max_depth()
}

///|
/// Internal: extract raw payload bytes for cognitive sections.
fn extract_cognitive_sections(
  wasm : Array[Byte],
  _desc : ModuleDesc,
) -> Array[(String, Array[Byte])] {
  let results : Array[(String, Array[Byte])] = []
  let len = wasm.length()
  if len < 8 { return results }
  let mut pos = 8
  while pos < len {
    let section_id = wasm[pos].to_int()
    pos = pos + 1
    let r = iface_read_leb128(wasm, pos)
    let size = r.0
    pos = r.1
    let payload_end = if pos + size <= len { pos + size } else { len }

    if section_id == 0 {
      // Custom section — check name
      let r2 = iface_read_leb128(wasm, pos)
      let name_len = r2.0
      let name_pos = r2.1
      if name_pos + name_len <= payload_end {
        let sb = StringBuilder::new()
        let mut j = 0
        while j < name_len {
          sb.write_char(wasm[name_pos + j].to_int().unsafe_to_char())
          j = j + 1
        }
        let name = sb.to_string()
        if name == ".cb0" || name == ".cb1" || name == ".cb2" || name == ".cb3" {
          // Extract payload after the name
          let data_start = name_pos + name_len
          let payload : Array[Byte] = []
          let mut k = data_start
          while k < payload_end {
            payload.push(wasm[k])
            k = k + 1
          }
          results.push((name, payload))
        }
      }
    }

    pos = payload_end
  }
  results
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn iface_read_leb128(bytes : Array[Byte], start : Int) -> (Int, Int) {
  let mut result = 0
  let mut shift = 0
  let mut pos = start
  while pos < bytes.length() {
    let b = bytes[pos].to_int()
    result = result | ((b & 0x7F) << shift)
    pos = pos + 1
    if (b & 0x80) == 0 { break }
    shift = shift + 7
  }
  (result, pos)
}

///|
fn iface_write_leb128(buf : Array[Byte], value : Int) -> Unit {
  let mut v = value
  while true {
    let b = v & 0x7F
    v = v >> 7
    if v == 0 {
      buf.push(b.to_byte())
      break
    } else {
      buf.push((b | 0x80).to_byte())
    }
  }
}

///|
fn iface_leb128_size(value : Int) -> Int {
  let mut v = value
  let mut size = 0
  while true {
    v = v >> 7
    size = size + 1
    if v == 0 { break }
  }
  size
}
