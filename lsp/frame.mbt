// LSP Content-Length framing.
//
// The Language Server Protocol wraps every JSON message in an HTTP-style
// header:
//
//   Content-Length: <n>\r\n
//   \r\n
//   <n bytes of UTF-8 JSON>
//
// This module operates on Array[Byte] throughout — no filesystem, no sockets.
// The host drives the loop; these functions handle the framing layer only.
//
// Streaming parse pattern (for a host accumulating TCP bytes):
//
//   let mut buf : Array[Byte] = []
//   // on each recv:
//   append_all(buf, incoming)
//   while true {
//     match frame_read(buf) {
//       Some((msg_bytes, rest)) => { handle(msg_bytes); buf = rest }
//       None => break   // incomplete — wait for more bytes
//     }
//   }

///|
/// A fully-framed LSP message, ready for JSON parsing.
pub(all) struct Frame {
  content_length : Int
  body : Array[Byte] // exactly content_length bytes of UTF-8 JSON
} derive(Debug)

///|
impl Show for Frame with output(self, logger) {
  logger.write_string("Frame(content_length=\{self.content_length})")
}

///|
/// Attempt to parse one complete LSP frame from the front of `buf`.
///
/// Returns `Some((frame, remainder))` when a complete frame is available,
/// `None` when the buffer does not yet contain a complete frame.
///
/// Does not consume partial frames — `buf` is not mutated.
pub fn frame_read(buf : Array[Byte]) -> (Frame, Array[Byte])? {
  // Find the double CRLF that separates headers from body.
  let sep = find_header_end(buf)
  match sep {
    None => None
    Some(body_start) => {
      // Extract the header block and parse Content-Length.
      let header_bytes = slice(buf, 0, body_start)
      let header_str = bytes_to_str(header_bytes)
      match parse_content_length(header_str) {
        None => None // malformed header — drop until next frame sync
        Some(n) => {
          let total = body_start + n
          if buf.length() < total {
            None // body not yet fully arrived
          } else {
            let body = slice(buf, body_start, total)
            let rest = slice(buf, total, buf.length())
            Some(({ content_length: n, body }, rest))
          }
        }
      }
    }
  }
}

///|
/// Encode a JSON body as a framed LSP message (Content-Length header + body).
///
/// `json` must be a valid UTF-8 string. Returns the wire bytes to send.
pub fn frame_write(json : String) -> Array[Byte] {
  let body = str_to_bytes(json)
  let n = body.length()
  let header = str_to_bytes("Content-Length: \{n}\r\n\r\n")
  let out = Array::make(header.length() + n, b'\x00')
  let mut i = 0
  for b in header {
    out[i] = b
    i = i + 1
  }
  for b in body {
    out[i] = b
    i = i + 1
  }
  out
}

///|
/// Drain all complete frames from `buf`.
///
/// Returns a list of parsed frames and the unconsumed remainder.
pub fn frame_drain(buf : Array[Byte]) -> (Array[Frame], Array[Byte]) {
  let frames : Array[Frame] = []
  let mut rest = buf
  while true {
    match frame_read(rest) {
      None => break
      Some((f, r)) => {
        frames.push(f)
        rest = r
      }
    }
  }
  (frames, rest)
}

// ---------------------------------------------------------------------------
// Test-visible helpers
// ---------------------------------------------------------------------------

///|
/// Exposed for tests only.
pub fn bytes_to_str_pub(buf : Array[Byte]) -> String {
  bytes_to_str(buf)
}

///|
/// Exposed for tests only.
pub fn slice_pub(buf : Array[Byte], start : Int, end : Int) -> Array[Byte] {
  slice(buf, start, end)
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Find the index of the byte immediately after \r\n\r\n in `buf`.

///|
fn find_header_end(buf : Array[Byte]) -> Int? {
  let len = buf.length()
  let mut i = 0
  while i + 3 < len {
    if buf[i] == b'\r' &&
      buf[i + 1] == b'\n' &&
      buf[i + 2] == b'\r' &&
      buf[i + 3] == b'\n' {
      return Some(i + 4)
    }
    i = i + 1
  }
  None
}

// Parse "Content-Length: N" from a header block.

///|
fn parse_content_length(header : String) -> Int? {
  let lines = split_lines(header)
  for line in lines {
    let lower = str_lower(line)
    if lower.has_prefix("content-length:") {
      let rest = line[15:].to_string()
      match str_trim_int(rest) {
        Some(n) => return Some(n)
        None => ()
      }
    }
  }
  None
}

///|
fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  let mut i = 0
  let chars = s.to_array()
  let len = chars.length()
  while i < len {
    if chars[i] == '\r' && i + 1 < len && chars[i + 1] == '\n' {
      out.push(s[start:i].to_string())
      i = i + 2
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
fn str_lower(s : String) -> String {
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
fn str_trim_int(s : String) -> Int? {
  let mut i = 0
  let chars = s.to_array()
  let len = chars.length()
  while i < len && (chars[i] == ' ' || chars[i] == '\t') {
    i = i + 1
  }
  if i == len {
    return None
  }
  let mut n = 0
  let mut found = false
  while i < len {
    let cp = chars[i].to_int()
    if cp >= 48 && cp <= 57 {
      n = n * 10 + (cp - 48)
      found = true
      i = i + 1
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
fn slice(buf : Array[Byte], start : Int, end : Int) -> Array[Byte] {
  let len = end - start
  if len <= 0 {
    return []
  }
  let out = Array::make(len, b'\x00')
  let mut i = 0
  while i < len {
    out[i] = buf[start + i]
    i = i + 1
  }
  out
}

///|
fn str_to_bytes(s : String) -> Array[Byte] {
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
fn bytes_to_str(buf : Array[Byte]) -> String {
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
      let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      sb.write_char(cp.to_char().unwrap())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < len {
      let b1 = buf[i + 1].to_int()
      let b2 = buf[i + 2].to_int()
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      sb.write_char(cp.to_char().unwrap())
      i = i + 3
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  sb.to_string()
}
