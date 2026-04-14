// LSP message type discrimination.
//
// JSON-RPC 2.0 over Content-Length frames. We parse just enough of the
// envelope to route — full JSON parsing is left to the host or a future
// structured parser.
//
// Discrimination rules (JSON-RPC 2.0):
//   Request      — has "id" (number or string) + "method"
//   Response     — has "id" + "result" (success) or "error" (failure)
//   Notification — has "method" but NO "id"
//   Unknown      — anything else (malformed, partial)
//
// All operations on raw JSON strings (no AST). We extract fields with
// a minimal substring scanner — correct for well-formed LSP messages.

///|
/// Discriminated LSP message kind.
pub(all) enum MessageKind {
  Request // id + lsp_method present → host must send a Response
  Response // id present, result or error present
  Notification // lsp_method present, no id → fire-and-forget
  Unknown // cannot classify (malformed / unexpected shape)
} derive(Eq, Debug)

///|
impl Show for MessageKind with output(self, logger) {
  logger.write_string(
    match self {
      Request => "Request"
      Response => "Response"
      Notification => "Notification"
      Unknown => "Unknown"
    },
  )
}

///|
/// A lightly-parsed LSP message envelope.
pub(all) struct LspMessage {
  kind : MessageKind
  id : String? // raw JSON value: number, quoted string, or null
  lsp_method : String? // method name string (unquoted)
  raw : String // full original JSON for downstream use
} derive(Debug)

///|
/// Classify and partially parse a JSON-RPC body string.
pub fn parse_message(json : String) -> LspMessage {
  let id = extract_field(json, "id")
  let lsp_method = extract_string_field(json, "method")
  let has_result = has_field(json, "result")
  let has_error = has_field(json, "error")
  let kind = match (id, lsp_method, has_result || has_error) {
    (Some(_), Some(_), _) => Request
    (Some(_), None, true) => Response
    (None, Some(_), _) => Notification
    _ => Unknown
  }
  { kind, id, lsp_method, raw: json }
}

///|
/// Parse a Frame directly into an LspMessage.
pub fn parse_frame(frame : Frame) -> LspMessage {
  let sb = StringBuilder::new()
  let mut i = 0
  let len = frame.body.length()
  while i < len {
    let b0 = frame.body[i].to_int()
    if (b0 & 0x80) == 0 {
      sb.write_char(b0.to_char().unwrap())
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 && i + 1 < len {
      let b1 = frame.body[i + 1].to_int()
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      sb.write_char(cp.to_char().unwrap())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < len {
      let b1 = frame.body[i + 1].to_int()
      let b2 = frame.body[i + 2].to_int()
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      sb.write_char(cp.to_char().unwrap())
      i = i + 3
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  parse_message(sb.to_string())
}

// ---------------------------------------------------------------------------
// Minimal JSON field extractor (no allocations beyond String)
// ---------------------------------------------------------------------------

// Extract the raw JSON value for `key` (any type: string, number, object, null).

///|
fn extract_field(json : String, key : String) -> String? {
  let pat = "\"\{key}\":"
  match json.find(pat) {
    None => None
    Some(pos) => {
      let start = pos + pat.length()
      let mut i = start
      let chars = json.to_array()
      let len = chars.length()
      while i < len &&
            (
              chars[i] == ' ' ||
              chars[i] == '\t' ||
              chars[i] == '\n' ||
              chars[i] == '\r'
            ) {
        i = i + 1
      }
      if i >= len {
        return None
      }
      let val_end = scan_value(chars, i)
      Some(json[i:val_end].to_string())
    }
  }
}

// Like extract_field but additionally strips surrounding quotes.

///|
fn extract_string_field(json : String, key : String) -> String? {
  match extract_field(json, key) {
    None => None
    Some(raw) =>
      if raw.length() >= 2 && raw.has_prefix("\"") {
        Some(raw[1:raw.length() - 1].to_string())
      } else {
        None
      }
  }
}

// Return true if `key` appears anywhere as a JSON object key in `json`.

///|
fn has_field(json : String, key : String) -> Bool {
  match json.find("\"\{key}\":") {
    Some(_) => true
    None => false
  }
}

// Scan from position `i` and return the index one past the end of the
// JSON value starting at chars[i].

///|
fn scan_value(chars : Array[Char], start : Int) -> Int {
  let len = chars.length()
  if start >= len {
    return start
  }
  let c = chars[start]
  if c == '"' {
    let mut i = start + 1
    while i < len {
      if chars[i] == '\\' {
        i = i + 2
      } else if chars[i] == '"' {
        return i + 1
      } else {
        i = i + 1
      }
    }
    len
  } else if c == '{' || c == '[' {
    let close = if c == '{' { '}' } else { ']' }
    let mut depth = 1
    let mut i = start + 1
    while i < len && depth > 0 {
      if chars[i] == '"' {
        i = i + 1
        while i < len {
          if chars[i] == '\\' {
            i = i + 2
          } else if chars[i] == '"' {
            i = i + 1
            break
          } else {
            i = i + 1
          }
        }
      } else if chars[i] == c {
        depth = depth + 1
        i = i + 1
      } else if chars[i] == close {
        depth = depth - 1
        i = i + 1
      } else {
        i = i + 1
      }
    }
    i
  } else {
    let mut i = start
    while i < len {
      let ch = chars[i]
      if ch == ',' ||
        ch == '}' ||
        ch == ']' ||
        ch == ' ' ||
        ch == '\t' ||
        ch == '\n' ||
        ch == '\r' {
        break
      }
      i = i + 1
    }
    i
  }
}
