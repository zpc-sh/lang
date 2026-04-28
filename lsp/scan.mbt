// Encoding anomaly scanner.
//
// scan_bytes() walks a byte buffer once, detecting:
//   - Mixed newlines  (\r\n vs \n vs bare \r)
//   - Non-ASCII quote characters (smart quotes, fullwidth, primes)
//   - BiDi control / isolate codepoints (Trojan Source vectors)
//   - Zero-width and invisible codepoints
//   - Non-standard line separators (U+2028/2029)
//   - Invalid UTF-8 sequences
//   - Mid-stream BOM
//
// All detection is codepoint-level after a minimal UTF-8 decoder.
// No allocations beyond the hits array. O(n) in input length.
//
// ---------------------------------------------------------------------------
// FUTURE: distill() — root-cause signal from a set of ScanReports
// ---------------------------------------------------------------------------
//
// Pattern we keep finding: a large set of observations collapses to a single
// root point (21 files, 1 missing byte each — one cause) OR the whole
// picture is visible at once and every hit is meaningful simultaneously.
//
// distill(reports: Array[(String, ScanReport)]) -> DistillResult
//
// DistillResult either:
//   SinglePoint(file, kind, offset) — one file/offset explains all reports
//   FullPicture(Array[(String, ScanKind, Int)]) — every hit is load-bearing
//
// The function looks for:
//   - A kind that appears in every report (systematic, same origin)
//   - A single file whose anomalies predict the others (causal root)
//   - Reports where every hit is a different kind (no redundancy — full picture)
//
// This becomes an LSP workspace diagnostic request:
//   method: "lang/distill"
//   params: { uris: [...] }
//   result: DistillResult
//
// Build when: we have enough scan data across sessions to know what
// "systematic" looks like vs. "targeted at one spot."

// ---------------------------------------------------------------------------
// ScanKind
// ---------------------------------------------------------------------------

///|
/// Category of encoding anomaly.
pub(all) enum ScanKind {
  CrlfNewline    // \r\n Windows line ending
  BareCarriage   // \r not followed by \n
  CurlyQuote     // U+2018–U+201F typographic quotes
  FullwidthQuote // U+FF02/FF07/FF40 fullwidth lookalikes
  PrimeQuote     // U+2032/2033 primes used as quotes
  ZeroWidth      // U+200B/C/D, U+2060 invisible/zero-width chars
  BiDiControl    // U+202A–U+202E embedding/override (Trojan Source)
  BiDiIsolate    // U+2066–U+2069, U+061C, U+200E/F directional marks
  LineSeparator  // U+2028/2029 non-standard line separators
  SoftHyphen     // U+00AD invisible conditional hyphen
  InvalidUtf8    // byte sequence that cannot be decoded as UTF-8
  BomMidstream   // U+FEFF BOM outside byte 0
} derive(Eq, Debug)

///|
impl Show for ScanKind with output(self, logger) {
  logger.write_string(
    match self {
      CrlfNewline => "CrlfNewline"
      BareCarriage => "BareCarriage"
      CurlyQuote => "CurlyQuote"
      FullwidthQuote => "FullwidthQuote"
      PrimeQuote => "PrimeQuote"
      ZeroWidth => "ZeroWidth"
      BiDiControl => "BiDiControl"
      BiDiIsolate => "BiDiIsolate"
      LineSeparator => "LineSeparator"
      SoftHyphen => "SoftHyphen"
      InvalidUtf8 => "InvalidUtf8"
      BomMidstream => "BomMidstream"
    },
  )
}

// ---------------------------------------------------------------------------
// ScanHit
// ---------------------------------------------------------------------------

///|
/// A single anomaly occurrence.
pub(all) struct ScanHit {
  kind : ScanKind
  offset : Int // byte offset of the first byte of the anomaly
  cp : Int // Unicode codepoint (0 for byte-level anomalies like InvalidUtf8)
} derive(Debug)

///|
impl Show for ScanHit with output(self, logger) {
  logger.write_string("ScanHit(\{self.kind} @\{self.offset} cp=U+\{cp_hex(self.cp)})")
}

// ---------------------------------------------------------------------------
// ScanReport
// ---------------------------------------------------------------------------

///|
/// Full result of a scan_bytes() call.
pub(all) struct ScanReport {
  hits : Array[ScanHit]
  clean : Bool // true iff hits is empty
  newline_mixed : Bool // file uses more than one newline convention
  quote_mixed : Bool // ASCII quotes and non-ASCII quotes both present
  has_bidi : Bool // any BiDi control or isolate codepoints found
} derive(Debug)

///|
pub fn ScanReport::summary(self : ScanReport) -> String {
  if self.clean {
    return "clean"
  }
  let sb = StringBuilder::new()
  sb.write_string("\{self.hits.length()} hit(s)")
  if self.newline_mixed {
    sb.write_string(" [newline-mixed]")
  }
  if self.quote_mixed {
    sb.write_string(" [quote-mixed]")
  }
  if self.has_bidi {
    sb.write_string(" [bidi!]")
  }
  sb.to_string()
}

///|
/// Group hits by kind — how many of each anomaly type.
pub fn ScanReport::counts(self : ScanReport) -> Array[(ScanKind, Int)] {
  let kinds : Array[ScanKind] = [
    CrlfNewline, BareCarriage, CurlyQuote, FullwidthQuote, PrimeQuote, ZeroWidth,
    BiDiControl, BiDiIsolate, LineSeparator, SoftHyphen, InvalidUtf8, BomMidstream,
  ]
  let out : Array[(ScanKind, Int)] = []
  for k in kinds {
    let mut n = 0
    for h in self.hits {
      if h.kind == k {
        n = n + 1
      }
    }
    if n > 0 {
      out.push((k, n))
    }
  }
  out
}

// ---------------------------------------------------------------------------
// Main scanner
// ---------------------------------------------------------------------------

///|
/// Scan a byte buffer for encoding anomalies. Single pass, O(n).
pub fn scan_bytes(data : Array[Byte]) -> ScanReport {
  let hits : Array[ScanHit] = []
  let mut i = 0
  let n = data.length()
  // Newline tracking
  let mut seen_lf = false
  let mut seen_crlf = false
  let mut seen_bare_cr = false
  // Quote tracking
  let mut seen_ascii_quote = false
  let mut seen_unicode_quote = false
  while i < n {
    let b0 = data[i].to_int()
    // --- Newline handling (byte level, before UTF-8 decode) ---
    if b0 == 0x0D {
      // CR
      if i + 1 < n && data[i + 1].to_int() == 0x0A {
        // CRLF
        hits.push({ kind: CrlfNewline, offset: i, cp: 0 })
        seen_crlf = true
        i = i + 2
        continue
      } else {
        // bare CR
        hits.push({ kind: BareCarriage, offset: i, cp: 0 })
        seen_bare_cr = true
        i = i + 1
        continue
      }
    }
    if b0 == 0x0A {
      seen_lf = true
      i = i + 1
      continue
    }
    // --- ASCII quote tracking ---
    if b0 == 0x22 || b0 == 0x27 || b0 == 0x60 {
      seen_ascii_quote = true
      i = i + 1
      continue
    }
    // --- Pure ASCII fast path (avoids UTF-8 decode cost) ---
    if b0 < 0x80 {
      i = i + 1
      continue
    }
    // --- UTF-8 decode ---
    let (cp, consumed) = utf8_decode_at(data, i)
    if cp < 0 {
      hits.push({ kind: InvalidUtf8, offset: i, cp: 0 })
      i = i + consumed
      continue
    }
    // --- Classify codepoint ---
    let kind_opt = classify_cp(cp)
    match kind_opt {
      Some(kind) => {
        // BOM: only flag if not at byte 0
        if kind == BomMidstream && i == 0 {
          () // leading BOM is allowed (though unusual)
        } else {
          hits.push({ kind, offset: i, cp })
        }
        // Quote mixing tracking
        if kind == CurlyQuote || kind == FullwidthQuote || kind == PrimeQuote {
          seen_unicode_quote = true
        }
      }
      None => ()
    }
    // Soft hyphen has no effect on quote mixing
    i = i + consumed
  }
  let newline_mixed = (seen_lf && seen_crlf) ||
    (seen_lf && seen_bare_cr) ||
    (seen_crlf && seen_bare_cr)
  let quote_mixed = seen_ascii_quote && seen_unicode_quote
  let mut has_bidi = false
  for h in hits {
    if h.kind == BiDiControl || h.kind == BiDiIsolate {
      has_bidi = true
      break
    }
  }
  {
    hits,
    clean: hits.length() == 0,
    newline_mixed,
    quote_mixed,
    has_bidi,
  }
}

///|
/// Convenience: scan a String (UTF-8 encode then scan).
pub fn scan_str(s : String) -> ScanReport {
  scan_bytes(str_to_bytes_scan(s))
}

// ---------------------------------------------------------------------------
// UTF-8 decoder
// ---------------------------------------------------------------------------

///|
/// Decode one codepoint at offset `off` in `data`.
/// Returns (codepoint, bytes_consumed). cp=-1 means invalid sequence,
/// consumed is always >= 1 so the caller can advance past the bad byte.
fn utf8_decode_at(data : Array[Byte], off : Int) -> (Int, Int) {
  let n = data.length()
  let b0 = data[off].to_int()
  if (b0 & 0x80) == 0 {
    (b0, 1)
  } else if (b0 & 0xE0) == 0xC0 {
    if off + 1 >= n {
      return (-1, 1)
    }
    let b1 = data[off + 1].to_int()
    if (b1 & 0xC0) != 0x80 {
      return (-1, 1)
    }
    let cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
    if cp < 0x80 {
      return (-1, 2) // overlong
    }
    (cp, 2)
  } else if (b0 & 0xF0) == 0xE0 {
    if off + 2 >= n {
      return (-1, 1)
    }
    let b1 = data[off + 1].to_int()
    let b2 = data[off + 2].to_int()
    if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 {
      return (-1, 1)
    }
    let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
    if cp < 0x800 {
      return (-1, 3) // overlong
    }
    (cp, 3)
  } else if (b0 & 0xF8) == 0xF0 {
    if off + 3 >= n {
      return (-1, 1)
    }
    let b1 = data[off + 1].to_int()
    let b2 = data[off + 2].to_int()
    let b3 = data[off + 3].to_int()
    if (b1 & 0xC0) != 0x80 ||
      (b2 & 0xC0) != 0x80 ||
      (b3 & 0xC0) != 0x80 {
      return (-1, 1)
    }
    let cp = ((b0 & 0x07) << 18) |
      ((b1 & 0x3F) << 12) |
      ((b2 & 0x3F) << 6) |
      (b3 & 0x3F)
    if cp < 0x10000 {
      return (-1, 4) // overlong
    }
    (cp, 4)
  } else {
    (-1, 1)
  }
}

// ---------------------------------------------------------------------------
// Codepoint classifier
// ---------------------------------------------------------------------------

///|
fn classify_cp(cp : Int) -> ScanKind? {
  // Curly / typographic quotes: U+2018–U+201F
  if cp >= 0x2018 && cp <= 0x201F {
    return Some(CurlyQuote)
  }
  // BiDi embedding/override: U+202A–U+202E
  if cp >= 0x202A && cp <= 0x202E {
    return Some(BiDiControl)
  }
  // BiDi isolates: U+2066–U+2069
  if cp >= 0x2066 && cp <= 0x2069 {
    return Some(BiDiIsolate)
  }
  // Fullwidth quotes
  if cp == 0xFF02 || cp == 0xFF07 || cp == 0xFF40 {
    return Some(FullwidthQuote)
  }
  // Prime characters used as quotes
  if cp == 0x2032 || cp == 0x2033 {
    return Some(PrimeQuote)
  }
  // Zero-width / invisible
  if cp == 0x200B || cp == 0x200C || cp == 0x200D || cp == 0x2060 {
    return Some(ZeroWidth)
  }
  // BOM / ZWNBSP — mid-stream is suspicious
  if cp == 0xFEFF {
    return Some(BomMidstream)
  }
  // Directional marks: LTR mark U+200E, RTL mark U+200F, Arabic letter mark U+061C
  if cp == 0x200E || cp == 0x200F || cp == 0x061C {
    return Some(BiDiIsolate)
  }
  // Non-standard line separators
  if cp == 0x2028 || cp == 0x2029 {
    return Some(LineSeparator)
  }
  // Soft hyphen
  if cp == 0x00AD {
    return Some(SoftHyphen)
  }
  None
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
fn str_to_bytes_scan(s : String) -> Array[Byte] {
  let chars = s.to_array()
  let out : Array[Byte] = []
  let mut i = 0
  while i < chars.length() {
    let cp = chars[i].to_int()
    if cp < 0x80 {
      out.push(cp.to_byte())
    } else if cp < 0x800 {
      out.push((0xC0 | (cp >> 6)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      out.push((0xE0 | (cp >> 12)).to_byte())
      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      out.push((0xF0 | (cp >> 18)).to_byte())
      out.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    }
    i = i + 1
  }
  out
}

///|
fn cp_hex(cp : Int) -> String {
  if cp == 0 {
    return "0000"
  }
  let sb = StringBuilder::new()
  let mut v = cp
  let nibbles : Array[Int] = []
  while v > 0 {
    nibbles.push(v & 0xF)
    v = v >> 4
  }
  while nibbles.length() < 4 {
    nibbles.push(0)
  }
  let mut j = nibbles.length() - 1
  while j >= 0 {
    let n = nibbles[j]
    let ch = if n < 10 {
      (48 + n).to_char().unwrap() // '0'..'9'
    } else {
      (55 + n).to_char().unwrap() // 'A'..'F'  (65 - 10 = 55)
    }
    sb.write_char(ch)
    j = j - 1
  }
  sb.to_string()
}
